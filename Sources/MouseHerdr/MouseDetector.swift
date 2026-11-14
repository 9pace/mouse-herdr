import Foundation
import IOKit
import IOKit.hid

/// A pointing device as it describes itself to macOS.
struct MouseDevice: Equatable, Identifiable {
    var vendorID = 0
    var productID = 0
    /// The product name it reports. A Bluetooth mouse can carry its owner's name here.
    var name = ""
    var maker = ""
    /// "USB", "Bluetooth", "Bluetooth Low Energy" and so on.
    var transport = ""
    var builtIn = false
    /// How many buttons its HID descriptor declares; 0 when it doesn't say. A USB receiver
    /// declares as many as any mouse behind it might have.
    var buttons = 0
    /// It also describes itself as a touch pad, or as a keyboard.
    var touchPad = false
    var keyboard = false
    /// The first thing it describes itself as is a mouse. A mouse can also be a keyboard of
    /// sorts, for a button that types a shortcut; a keyboard that can move the pointer says
    /// keyboard first.
    var mouseFirst = true
    /// When it connected, counting up. Everything already there at start shares 0.
    var order = 0

    enum Kind {
        case mouse
        /// A USB receiver, or something else a mouse may be hiding behind.
        case receiver
        /// A trackpad, a tablet, a virtual device: not a mouse to give buttons to.
        case ignored
    }

    var id: String { key }

    /// What choices about this device are remembered under. Two mice of the same model share it.
    var key: String {
        vendorID > 0 ? String(format: "%04x:%04x", vendorID, productID) : "name:" + name.lowercased()
    }

    var isBluetooth: Bool { transport.localizedCaseInsensitiveContains("bluetooth") }

    /// How it is connected, in a word.
    var connection: String {
        if isBluetooth { return "Bluetooth" }
        return transport.isEmpty ? "connected" : transport
    }

    /// The model in the list this is, if it is one.
    var recognised: MouseProfile? { MouseProfile.matching(vendor: vendorID, product: productID, name: name) }

    private static let notMice = ["trackpad", "touchpad", "touch pad", "virtualhid", "virtual hid", "virtual mouse",
                                  "tablet", "digitizer", "touchscreen", "touch screen", "stylus"]

    var kind: Kind {
        let lower = name.lowercased()
        if builtIn || touchPad || MouseDevice.notMice.contains(where: lower.contains) { return .ignored }
        // A model in the list is what the list says it is, whatever else it declares. Several of
        // Logitech's Bluetooth mice are keyboards too, for a thumb button that types a shortcut.
        if let known = recognised { return known.kind == .receiver ? .receiver : .mouse }
        // A keyboard that can also move the pointer is not a mouse to give buttons to.
        let keyboardFirst = keyboard && !mouseFirst
        if keyboardFirst && (lower.contains("keyboard") || lower.contains("kbd")) { return .ignored }
        if keyboardFirst || ["receiver", "transceiver", "dongle"].contains(where: lower.contains) { return .receiver }
        return .mouse
    }

    /// Some fixed order for devices that are otherwise equal, so that what is read first never decides anything.
    fileprivate var sortKey: String {
        "\(key)|\(name)|\(transport)|\(buttons)|\(keyboard)|\(mouseFirst)|\(order)"
    }
}

/// Which of the connected devices to follow, and which profile to give it. No IOKit in here, so
/// it can be tested with made-up devices.
enum MouseChooser {
    /// What choices are remembered under while no mouse is connected.
    static let noDevice = ""

    /// How good a guess a device is: the tested MX Master 4, a mouse in the list, an unknown mouse,
    /// then a receiver, which may have no mouse behind it at all.
    static func tier(_ device: MouseDevice) -> Int {
        switch device.kind {
        case .ignored: return -1
        case .receiver: return 0
        case .mouse:
            guard let profile = device.recognised else { return 1 }
            return profile.tested ? 3 : 2
        }
    }

    /// The devices worth showing, best guess first, each mouse once. Among equals the one that
    /// connected last comes first.
    static func candidates(_ devices: [MouseDevice]) -> [MouseDevice] {
        var seen: [String: MouseDevice] = [:]
        for device in devices.sorted(by: { $0.sortKey < $1.sortKey }) where device.kind != .ignored {
            guard var merged = seen[device.key] else { seen[device.key] = device; continue }
            // One mouse can show up as several HID devices. Keep what tells the most. If one of
            // them is a plain mouse, so is the whole, whichever of them is read first.
            merged.buttons = max(merged.buttons, device.buttons)
            merged.order = max(merged.order, device.order)
            if merged.name.isEmpty { merged.name = device.name }
            merged.keyboard = merged.keyboard && device.keyboard
            merged.mouseFirst = merged.mouseFirst || device.mouseFirst
            seen[device.key] = merged
        }
        return seen.values.sorted { a, b in
            let (ta, tb) = (tier(a), tier(b))
            if ta != tb { return ta > tb }
            if a.order != b.order { return a.order > b.order }
            return (a.name.lowercased(), a.key) < (b.name.lowercased(), b.key)
        }
    }

    /// The device to follow: the one that was picked by hand if it is connected, or else the best guess.
    static func active(among candidates: [MouseDevice], pinned: String?) -> MouseDevice? {
        if let pinned, let device = candidates.first(where: { $0.key == pinned }) { return device }
        return candidates.first
    }

    /// The profile for the device being followed. A model picked by hand for this device comes
    /// first, then the list, then a plain layout that fits its number of buttons. With no mouse
    /// connected it is the one that was in use last.
    static func profile(for device: MouseDevice?, memory: MouseMemory, firstRun: Bool) -> MouseProfile {
        if let id = memory.chosen[device?.key ?? noDevice], let chosen = MouseProfile.named(id) { return chosen }
        guard let device else {
            if let id = memory.last, let last = MouseProfile.named(id) { return last }
            // Until now every MouseHerdr owner had an MX Master 4, so that is what an earlier install shows.
            return firstRun ? .generic : .initial
        }
        let known = device.recognised
        // Before other mice were recognised, every mouse was taken for an MX Master 4, and one on
        // its Bolt receiver worked that way: its picture, its settings and the buttons macOS
        // reports. On a Mac that goes back that far, the mouse behind a Bolt receiver still is.
        // (An MX Master 4 pairs with no other kind of receiver.)
        if memory.boltCarriesMXMaster4, device.vendorID == MouseProfile.logitech, device.productID == MouseProfile.boltReceiver {
            return .mxMaster4
        }
        return known ?? .fallback(buttons: device.buttons)
    }

    /// The HID++ controls to hand back to the mouse on the direct link.
    ///
    /// `captured` is what was last captured on it for a profile. That outlives a dropped link,
    /// because the mouse is told its captures again as it reconnects. While it is the mouse being
    /// followed, what the profile no longer wants goes back. While another mouse is followed,
    /// everything captured for it goes back; and when it has just connected it may also hold
    /// captures this run knows nothing of, from a run that was killed before it could hand them
    /// back, so everything it could be holding goes back too. A control left captured with
    /// nobody listening is a dead button.
    static func handBack(captured: Set<UInt16>, wanted: Set<UInt16>, followed: Bool, arrived: Bool,
                         reported: [HIDPP.Control]) -> Set<UInt16> {
        if followed { return captured.subtracting(wanted) }
        let couldHold = arrived ? reported.filter { $0.divertable && !$0.isVirtual }.map(\.cid) : []
        return captured.union(couldHold)
    }
}

/// Watches which mice are connected to the Mac, whatever their make. It only reads what each
/// device says about itself and never opens one, so it needs no permission.
final class MouseDetector {
    /// Called on the main thread with every pointing device connected now, after each change.
    var onChange: (([MouseDevice]) -> Void)?

    private var manager: IOHIDManager?
    private var live: [(ref: IOHIDDevice, info: MouseDevice)] = []
    private var arrivals = 0
    private var notifying = false

    var devices: [MouseDevice] { live.map(\.info) }

    deinit {
        // The callbacks hold this object without keeping it alive, so they must not outlast it.
        guard let mgr = manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    /// Start watching, on the main thread. `onChange` is called once straight away with what is there.
    func start() {
        guard manager == nil else { return }
        let mgr = MouseDetector.makeManager()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, dev in
            Unmanaged<MouseDetector>.fromOpaque(ctx!).takeUnretainedValue().arrived(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, dev in
            Unmanaged<MouseDetector>.fromOpaque(ctx!).takeUnretainedValue().left(dev)
        }, ctx)
        manager = mgr
        // What is already connected, before the callbacks start, so the first answer is complete.
        for dev in MouseDetector.copyDevices(mgr) { live.append((dev, MouseDetector.describe(dev, order: 0))) }
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        onChange?(devices)
    }

    /// Read everything again from scratch, for when someone asks to detect their mouse. The
    /// caller reads `devices` afterwards; `onChange` is for changes nobody asked about.
    func rescan() {
        guard let mgr = manager else { return }
        var next: [(ref: IOHIDDevice, info: MouseDevice)] = []
        for dev in MouseDetector.copyDevices(mgr) {
            let order = live.first { $0.ref === dev }?.info.order ?? { arrivals += 1; return arrivals }()
            next.append((dev, MouseDetector.describe(dev, order: order)))
        }
        live = next
    }

    private func arrived(_ dev: IOHIDDevice) {
        guard !live.contains(where: { $0.ref === dev }) else { return }
        arrivals += 1
        live.append((dev, MouseDetector.describe(dev, order: arrivals)))
        changed()
    }

    private func left(_ dev: IOHIDDevice) {
        guard live.contains(where: { $0.ref === dev }) else { return }
        live.removeAll { $0.ref === dev }
        changed()
    }

    /// A mouse with several HID interfaces arrives in pieces; report once they are all here.
    private func changed() {
        guard !notifying else { return }
        notifying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.notifying = false
            self.onChange?(self.devices)
        }
    }

    // MARK: Reading IOKit

    /// Everything connected right now, read once. For the `--detect-mice` developer command.
    static func connected() -> [MouseDevice] {
        copyDevices(makeManager()).map { describe($0, order: 0) }
    }

    private static func makeManager() -> IOHIDManager {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Anything that calls itself a mouse. The manager is never opened: matching and reading
        // properties need no permission, opening a device does.
        let match: [String: Any] = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        return mgr
    }

    private static func copyDevices(_ mgr: IOHIDManager) -> [IOHIDDevice] {
        guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return [] }
        return Array(set)
    }

    private static func describe(_ dev: IOHIDDevice, order: Int) -> MouseDevice {
        func value<T>(_ key: String) -> T? { IOHIDDeviceGetProperty(dev, key as CFString) as? T }
        var device = MouseDevice()
        device.vendorID = max(0, value(kIOHIDVendorIDKey) ?? 0)
        device.productID = max(0, value(kIOHIDProductIDKey) ?? 0)
        device.name = (value(kIOHIDProductKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        device.maker = (value(kIOHIDManufacturerKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        device.transport = value(kIOHIDTransportKey) ?? ""
        device.builtIn = value(kIOHIDBuiltInKey) ?? false
        device.order = order
        if let page: Int = value(kIOHIDPrimaryUsagePageKey), let usage: Int = value(kIOHIDPrimaryUsageKey) {
            device.mouseFirst = page == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer)
        }
        for pair in (value(kIOHIDDeviceUsagePairsKey) as [[String: Any]]?) ?? [] {
            let page = pair[kIOHIDDeviceUsagePageKey] as? Int ?? 0, usage = pair[kIOHIDDeviceUsageKey] as? Int ?? 0
            if page == kHIDPage_Digitizer && usage == kHIDUsage_Dig_TouchPad { device.touchPad = true }
            if page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Keyboard { device.keyboard = true }
        }
        let match = [kIOHIDElementUsagePageKey: kHIDPage_Button] as CFDictionary
        if let elements = IOHIDDeviceCopyMatchingElements(dev, match, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            device.buttons = Set(elements.map { IOHIDElementGetUsage($0) }).count
        }
        return device
    }
}

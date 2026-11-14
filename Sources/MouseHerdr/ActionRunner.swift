import AppKit
import CoreGraphics

/// Turns an Action into something that actually happens on the Mac.
enum ActionRunner {
    /// Stamped on events we create so our own button tap ignores them.
    static let marker: Int64 = 0x4D4D_4F55

    static func run(_ action: Action) {
        switch action.kind {
        case "shortcut":
            guard let code = action.keyCode else { return }
            key(code, NSEvent.ModifierFlags(rawValue: action.modifiers ?? 0))
        case "app":
            if let p = action.appPath { open(p) }
        default:
            guard let preset = Catalog.byID[action.kind] else { return }
            switch preset.effect {
            case .passthrough, .nothing, .dragWindow: break
            case .key(let code, let flags): key(code, flags)
            case .media(let k): media(k)
            case .dock(let name): dock(name)
            case .middleClick: middleClick()
            case .open(let path): open(path)
            }
        }
    }

    // MARK: Keyboard

    static func key(_ code: Int, _ flags: NSEvent.ModifierFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let mods: [(NSEvent.ModifierFlags, CGKeyCode, CGEventFlags)] = [
            (.control, 59, .maskControl), (.option, 58, .maskAlternate),
            (.shift, 56, .maskShift), (.command, 55, .maskCommand),
        ]
        let active = mods.filter { flags.contains($0.0) }
        var current: CGEventFlags = []
        func post(_ vk: CGKeyCode, _ down: Bool) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: down) else { return }
            e.flags = current
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
        }
        // Press the modifiers for real, then the key, then let go — the most widely accepted form.
        for m in active { current.insert(m.2); post(m.1, true) }
        post(CGKeyCode(code), true)
        post(CGKeyCode(code), false)
        for m in active.reversed() { current.remove(m.2); post(m.1, false) }
    }

    // MARK: Media keys

    static func media(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let ev = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int((key << 16) | (state << 8)), data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Mission Control and friends

    private typealias DockNotify = @convention(c) (CFString, UnsafeRawPointer?) -> Void
    private static let dockNotify: DockNotify? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: DockNotify.self)
    }()

    static func dock(_ name: String) {
        if let f = dockNotify { f(name as CFString, nil); return }
        // Fallback: the Mission Control app accepts a mode argument.
        let args: [String]
        switch name {
        case "com.apple.expose.front.awake": args = ["2"]
        case "com.apple.showdesktop.awake": args = ["1"]
        default: args = []
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        p.arguments = args
        do { try p.run() } catch { Log.write("mission control launch failed: \(error)") }
    }

    // MARK: Mouse

    static func middleClick() {
        let pos = CGEvent(source: nil)?.location ?? .zero
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: .center) else { continue }
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
        }
    }

    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

/// Watches the standard extra mouse buttons (wheel click, back, forward) and lets us replace them.
final class ButtonTap {
    /// Called on button-down. Return true to swallow the click.
    var onPress: ((Int) -> Bool)?
    /// Whether a button is currently remapped (so its release and drags are swallowed too).
    var isMapped: ((Int) -> Bool)?
    /// Called when a remapped button is let go.
    var onRelease: ((Int) -> Void)?
    /// Called for ordinary left/right clicks. Return true to swallow the click.
    /// An ordinary left or right click; return true to keep it from the app under the pointer.
    var onPlainClick: ((_ right: Bool) -> Bool)?
    private var swallowUp = false
    /// Called when the thumb wheel is rolled (amount in lines). Return true to swallow the scroll.
    var onThumbWheel: ((Double) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, ctx in
                let me = Unmanaged<ButtonTap>.fromOpaque(ctx!).takeUnretainedValue()
                return me.handle(type, event)
            }, userInfo: ctx)
        else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        Log.write("button tap started")
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionRunner.marker {
            return Unmanaged.passUnretained(event)
        }
        if type == .scrollWheel {
            // A wheel (not a trackpad) scrolling purely sideways is the thumb wheel.
            let sideways = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let vertical = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0, sideways != 0, vertical == 0,
               !event.flags.contains(.maskShift), onThumbWheel?(sideways) ?? false {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            swallowUp = onPlainClick?(type == .rightMouseDown) ?? false
            return swallowUp ? nil : Unmanaged.passUnretained(event)
        }
        if type == .leftMouseUp || type == .rightMouseUp {
            if swallowUp { swallowUp = false; return nil }
            return Unmanaged.passUnretained(event)
        }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if type == .otherMouseDown {
            return (onPress?(button) ?? false) ? nil : Unmanaged.passUnretained(event)
        }
        guard isMapped?(button) ?? false else { return Unmanaged.passUnretained(event) }
        if type == .otherMouseUp { onRelease?(button) }
        return nil
    }

    // MARK: Escape

    /// Called when Escape is pressed while it is being watched for. Return true if it was used,
    /// which keeps it from the app in front.
    var onEscape: (() -> Bool)?
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var escape = EscapeKey()
    private static let escapeKey: Int64 = 53

    /// Watch for the Escape key, or stop. Keys are looked at only while something of ours is
    /// showing that Escape should put away. The rest of the time this tap is switched off, and
    /// no key press comes near the app.
    func watchEscape(_ on: Bool) {
        escape.watching = on
        if on, keyTap == nil {
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, ctx in
                    Unmanaged<ButtonTap>.fromOpaque(ctx!).takeUnretainedValue().handleKey(type, event)
                }, userInfo: ctx)
            else {
                Log.write("escape: the keyboard can't be watched, so Escape will not close the wheel")
                return
            }
            keyTap = port
            keySource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), keySource, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            escape.tapIs(on: true)
        }
        syncKeyTap()
    }

    /// The tap is on exactly while Escape is wanted, or one that was used has yet to be let go.
    /// The system is asked only when that changes: each asking is a round trip to the window
    /// server, made from the main thread.
    private func syncKeyTap() {
        guard let keyTap, let on = escape.tapChange() else { return }
        CGEvent.tapEnable(tap: keyTap, enable: on)
    }

    private func handleKey(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Every switching-off is reported here, our own included. Switching it off again in
            // answer would be reported again, and so on without end, with the main thread and the
            // window server doing nothing else. So note that it is off, and turn it back on only
            // if it is wanted.
            escape.tapIs(on: false)
            syncKeyTap()
            return pass
        }
        // Every other key goes straight on, and so do key presses MouseHerdr makes itself.
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKey,
              event.getIntegerValueField(.eventSourceUserData) != ActionRunner.marker else { return pass }
        if type == .keyUp {
            let ours = escape.released()
            syncKeyTap()
            return ours ? nil : pass
        }
        // Only a plain Escape is ours. ⌥⌘⎋ and the like belong to the system.
        let plain = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        switch escape.pressed(repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, plain: plain) {
        case .keep: return nil
        case .pass: return pass
        case .ask:
            // Using it closes the wheel, which stops the watching: the key is already marked as
            // held, so the tap stays on for its release.
            if onEscape?() ?? false { return nil }
            escape.notUsed()
            syncKeyTap()
            return pass
        }
    }
}

/// What becomes of the Escape key while something of ours can be put away with it. It is kept
/// apart from the event tap so that it can be tested.
struct EscapeKey {
    enum Verdict {
        /// Keep it from the app in front.
        case keep
        /// Let it through untouched.
        case pass
        /// Ask whether there is something to close; if so keep it, if not call `notUsed`.
        case ask
    }

    /// Something that Escape should close is showing.
    var watching = false
    /// An Escape that was used is still down, so its repeats and its release are kept as well:
    /// the app in front must not get the tail end of a key press it never saw begin.
    private(set) var held = false

    /// Keys have to be looked at: Escape is wanted, or one that was used has yet to be let go.
    var needsTap: Bool { watching || held }

    /// Whether the tap is on, as far as is known.
    private(set) var tapOn = false

    /// The tap was just made, which leaves it on, or the system says it has been switched off.
    mutating func tapIs(on: Bool) { tapOn = on }

    /// What to do to the tap: true to switch it on, false to switch it off, nil to leave it as
    /// it is. Asking twice gives nil the second time, so being told of a switching-off that was
    /// asked for does not lead to asking for it again.
    mutating func tapChange() -> Bool? {
        guard tapOn != needsTap else { return nil }
        tapOn = needsTap
        return tapOn
    }

    /// Escape went down.
    mutating func pressed(repeating: Bool, plain: Bool) -> Verdict {
        if held && repeating { return .keep }
        held = false            // a fresh press: whatever release was missed, start over
        guard watching, plain else { return .pass }
        held = true
        return .ask
    }

    /// Nothing wanted the Escape that `pressed` asked about.
    mutating func notUsed() { held = false }

    /// Escape was let go. True if it is ours to keep.
    mutating func released() -> Bool {
        guard held else { return false }
        held = false
        return true
    }
}

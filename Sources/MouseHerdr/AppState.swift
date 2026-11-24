import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement
import SwiftUI

/// Moves the active window along with the cursor while a button is held.
final class WindowDragger {
    private var window: AXUIElement?
    private var startOrigin = CGPoint.zero
    private var startMouse = CGPoint.zero
    private var last = CGPoint.zero
    private var timer: Timer?

    var isDragging: Bool { timer != nil }

    var snapEnabled = true
    /// Called when the cursor reaches a screen edge that the window would snap to.
    var onZone: (() -> Void)?
    private var zone: CGRect?
    private let overlay = SnapOverlay()

    /// The window an on-screen element belongs to.
    private func window(containing element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<25 {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
            if (role as? String) == (kAXWindowRole as String) { return current }
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &win) == .success,
               let win, CFGetTypeID(win) == AXUIElementGetTypeID() {
                return (win as! AXUIElement)
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func windowUnderCursor(_ p: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success, let hit else { return nil }
        return window(containing: hit)
    }

    private func activeWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.25)
        var ref: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &ref)
        if err != .success || ref == nil {
            err = AXUIElementCopyAttributeValue(ax, kAXMainWindowAttribute as CFString, &ref)
        }
        guard err == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    func begin() {
        end()
        let mouse = CGEvent(source: nil)?.location ?? .zero
        // Prefer the window under the cursor (active or not); fall back to the active window.
        let under = windowUnderCursor(mouse)
        guard let win = under ?? activeWindow() else {
            Log.write("drag: no window found")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let owner = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
        loggedFailure = false
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              let posRef, CFGetTypeID(posRef) == AXValueGetTypeID() else { return }
        var origin = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        window = win
        startOrigin = origin
        last = origin
        startMouse = mouse
        Log.write("drag: grabbed \(under != nil ? "window under cursor" : "active window") of \(owner) at \(Int(origin.x)),\(Int(origin.y))")
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func update() {
        guard let window, let mouse = CGEvent(source: nil)?.location else { return }
        var target = CGPoint(x: startOrigin.x + mouse.x - startMouse.x, y: startOrigin.y + mouse.y - startMouse.y)
        let z = snapEnabled ? Snap.zone(for: mouse) : nil
        if z != zone {
            zone = z
            overlay.show(z)
            if z != nil { onZone?() }
        }
        guard target != last else { return }
        last = target
        if let v = AXValueCreate(.cgPoint, &target) {
            let err = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            if err != .success && !loggedFailure {
                loggedFailure = true
                Log.write("drag: window refused to move (\(err.rawValue))")
            }
        }
    }

    private var loggedFailure = false

    func end(snap: Bool = true) {
        if !snap { zone = nil }
        if timer != nil { Log.write("drag: dropped at \(Int(last.x)),\(Int(last.y))\(zone != nil ? " (snapped)" : "")") }
        if let window, var origin = zone?.origin, var size = zone?.size {
            // Position, size, then position again — some apps clamp the first move.
            if let p = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
            }
        }
        zone = nil
        overlay.hide()
        timer?.invalidate()
        timer = nil
        window = nil
    }
}

final class AppState: ObservableObject {
    /// The mouse being followed: its controls, picture and defaults.
    @Published private(set) var profile: MouseProfile
    @Published var assignments: [Slot: Action]
    @Published var selected: Slot
    /// The mice connected now, best guess first, and the one of them being followed.
    @Published private(set) var mice: [MouseDevice] = []
    @Published private(set) var mouse: MouseDevice?
    /// Something to say about a mouse that was just found. The window shows it, or the menu bar when the window is closed.
    @Published var mouseNotice: MouseNotice?
    /// The Buttons page is showing the list of mice instead of a button's actions.
    @Published var choosingMouse = false
    @Published var mouseSearch = ""
    /// What the last "Detect again" found, in words.
    @Published private(set) var detectResult: String?
    @Published var gesturePart: Slot = .gesture
    @Published var recording = false

    @Published var hidStatus: HIDPP.Status = .searching
    @Published var battery: Int?
    @Published var charging = false
    @Published var accessibilityOK = false
    @Published var inputMonitoringOK = false
    @Published var needsRelaunch = false
    @Published var launchAtLogin = false
    @Published var available: Set<Slot> = []
    @Published var hapticsAvailable = false
    @Published var hapticsOn = UserDefaults.standard.object(forKey: "hapticsOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticsOn, forKey: "hapticsOn"); applyFeel() }
    }
    @Published var hapticStrength = UserDefaults.standard.object(forKey: "hapticStrength") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(hapticStrength, forKey: "hapticStrength"); applyFeel() }
    }
    @Published var feelHover = UserDefaults.standard.object(forKey: "feelHover") as? Bool ?? true {
        didSet { UserDefaults.standard.set(feelHover, forKey: "feelHover"); applyFeel() }
    }
    @Published var feelEdges = UserDefaults.standard.object(forKey: "feelEdges") as? Bool ?? true {
        didSet { UserDefaults.standard.set(feelEdges, forKey: "feelEdges"); applyFeel() }
    }
    @Published var ringOnTap = UserDefaults.standard.object(forKey: "ringOnTap") as? Bool ?? true {
        didSet { UserDefaults.standard.set(ringOnTap, forKey: "ringOnTap") }
    }
    @Published var ringOrder = RingOrder(rawValue: UserDefaults.standard.string(forKey: "ringOrder") ?? "") ?? .recent {
        didSet { UserDefaults.standard.set(ringOrder.rawValue, forKey: "ringOrder") }
    }
    /// Agents kept near the front of the wheel at full size, by terminal address.
    @Published var pinnedAgents = Set(UserDefaults.standard.stringArray(forKey: "pinnedAgents") ?? []) {
        didSet {
            UserDefaults.standard.set(pinnedAgents.sorted(), forKey: "pinnedAgents")
            ring.setPinned(pinnedAgents)
        }
    }
    @Published var feelAgents = UserDefaults.standard.object(forKey: "feelAgents") as? Bool ?? true {
        didSet { UserDefaults.standard.set(feelAgents, forKey: "feelAgents") }
    }
    /// Whether herdr-core and the Herdr app are there; both are optional and re-checked as the app runs.
    /// The window's three pages. Agents comes first: it is what the app is for.
    enum Tab: String, CaseIterable { case agents, buttons, feel, settings }
    let updates = UpdateManager()
    @Published var tab: Tab = .agents
    /// The agents as last seen, with their questions, for the Agents page.
    @Published var agentList: [AgentInfo] = []
    /// Set by the window; the Agents page only keeps itself fresh while someone can see it.
    var windowVisible = false {
        didSet {
            guard windowVisible else { return }
            refreshAgentList()
            noticeSeen()        // a notice that was waiting is now a banner in the window
        }
    }
    private var listFetching = false
    @Published var herdr = HerdrStatus.unknown
    @Published var herdrApp = true
    @Published var snapWindows = UserDefaults.standard.object(forKey: "snapWindows") as? Bool ?? true {
        didSet { UserDefaults.standard.set(snapWindows, forKey: "snapWindows"); applyFeel() }
    }
    @Published var directLink = false   // true when the mouse reports real press/hold/release

    let hid = HIDPP()
    let tap = ButtonTap()
    let detector = MouseDetector()
    /// Set by the app: opens the window, for a notice's button that leads into it.
    var openWindow: (() -> Void)?
    private var memory: MouseMemory
    /// Whether this Mac has never run MouseHerdr before; decides what is shown before any mouse is found.
    private let firstRun: Bool
    private var started = false
    /// Every pointing device the detector reports, before trackpads and the like are left out.
    private var detected: [MouseDevice] = []
    /// What the direct link is talking to, once it has introduced itself.
    private var link: (name: String, productID: Int, controls: [HIDPP.Control])?
    /// The link has only just come up, so what its mouse is holding from before is not known yet.
    private var linkArrived = false
    /// The controls last captured on the link's mouse. Kept while the link is down: the mouse is
    /// told its captures again as it reconnects, whoever is being followed by then.
    private var captured: Set<UInt16> = []
    /// The profile the link's controls were last tied to.
    private var boundProfile: String?
    /// When the mouse being followed took over, how the one before it ranked, and whether this
    /// one ranks below it and so may only be standing in while that one reconnects.
    private var followedSince = Date()
    private var previousTier: Int
    private var standIn = false
    let dragger = WindowDragger()
    let feeler = HoverFeeler()
    let agents = AgentWatcher()
    let ring = AgentRing()
    /// The agent in front in the Herdr app, and the one that was in front before it. Kept up by
    /// looking now and then, and whenever the wheel switches agents.
    private var fronts = FrontHistory()
    let replyBox = ReplyBox()
    private var agentStatus: [String: String] = [:]
    private var agentsSeen = false
    private var ticks = 0
    private var ringPress = false
    private var ringTimer: Timer?
    private var ringFetching = false
    private var agentsFetching = false
    private var dragStartMouse = CGPoint.zero
    private var wheelAcc = 0.0
    private var wheelLast = Date.distantPast
    private var wheelReady = Date.distantPast
    private var timer: Timer?
    private var keyMonitor: Any?

    // HID++ control ids
    private var cidForSlot: [Slot: UInt16] = [:]
    private var slotForCID: [UInt16: Slot] = [:]
    private var rawXYCapable: Set<UInt16> = []
    private var pressed: Set<UInt16> = []
    private var hidHaptics = false      // the connected mouse offers the haptics feature
    private var gestureSlot = Slot.gesture
    private var gestureHeld = false
    private var gestureFired = false
    private var gestureAcc = CGPoint.zero
    private var grantRestarts = 0
    private var stickyDrag = false
    private var pulseSource = false
    private var dragPressed = Date.distantPast
    private var gestureStart = CGPoint.zero
    private var gestureTimer: Timer?

    init() {
        var memory = MouseMemory.load()
        let firstRun = !UserDefaults.standard.bool(forKey: "didFirstRun")
        // A Mac that ran MouseHerdr before it knew other mice: there, every mouse was an MX Master 4.
        if !firstRun && !MouseMemory.exists() { memory.boltCarriesMXMaster4 = true }
        // Until a mouse is found, show the one that was in use last.
        let profile = MouseChooser.profile(for: nil, memory: memory, firstRun: firstRun)
        self.memory = memory
        self.firstRun = firstRun
        self.profile = profile
        // The mouse this Mac had last is the one to expect back; a Mac new to MouseHerdr expects none.
        previousTier = firstRun && memory.last == nil ? -1 : MouseSetup.tier(of: profile)
        assignments = ConfigStore.load(for: profile)
        selected = profile.firstSelected
    }

    /// The slot the right-hand panel is editing.
    var editing: Slot { hasGestures(selected) && gesturePart.isSwipe ? gesturePart : selected }

    func hasGestures(_ slot: Slot) -> Bool { profile.control(slot)?.gestures ?? false }

    /// Switch to another mouse: its picture, controls and defaults.
    func use(_ p: MouseProfile) {
        guard p.id != profile.id else { return }
        Log.write("profile: \(p.fullName)")
        // Whatever was being held or recorded belonged to the other mouse.
        recording = false
        gestureTimer?.invalidate(); gestureTimer = nil
        gestureHeld = false
        ringPress = false
        stickyDrag = false
        if dragger.isDragging { dragger.end(snap: false) }
        profile = p
        assignments = ConfigStore.load(for: p)
        if p.control(selected) == nil { selected = p.firstSelected }
        gesturePart = .gesture
    }

    // MARK: Which mouse

    /// What to call the mouse being followed, and a few words on how it was found.
    var mouseTitle: String { MouseSetup.title(device: mouse, profile: profile) }
    var mouseSubtitle: String { MouseSetup.subtitle(device: mouse, profile: profile, pickedByHand: modelPickedByHand) }

    /// The model was picked from the list, not worked out from the device.
    var modelPickedByHand: Bool { memory.chosen[mouse?.key ?? MouseChooser.noDevice] != nil }

    /// The direct link is talking to the mouse being followed.
    var linkFollowed: Bool {
        guard let link, let mouse else { return false }
        return mouse.vendorID == MouseProfile.logitech && mouse.productID == link.productID
    }

    /// This mouse has controls that only answer over the direct link, and it is connected in a way that can carry it.
    var wantsDirectLink: Bool {
        guard profile.usesDirectLink else { return false }
        guard let mouse else { return true }
        return mouse.vendorID == MouseProfile.logitech && mouse.isBluetooth
    }

    /// The connected mice changed, or the direct link found out what it is talking to.
    private func miceChanged() {
        var all = detected
        if let link {
            let isLinked: (MouseDevice) -> Bool = { $0.vendorID == MouseProfile.logitech && $0.productID == link.productID }
            if let i = all.firstIndex(where: isLinked) {
                // The name the mouse gives over the link is its model, even if it was renamed in
                // Bluetooth settings. Go by that when the name macOS has says nothing.
                if all[i].recognised == nil, MouseProfile.matching(vendor: MouseProfile.logitech, product: link.productID, name: link.name) != nil {
                    all[i].name = link.name
                }
            } else {
                // The mouse on the direct link counts even if the scan missed it.
                all.append(MouseDevice(vendorID: MouseProfile.logitech, productID: link.productID, name: link.name,
                                       maker: "Logitech", transport: "Bluetooth Low Energy"))
            }
        }
        let list = MouseChooser.candidates(all)
        if list != mice {
            mice = list
            Log.write("mice: " + (list.isEmpty ? "none" : list.map { "\($0.name) [\($0.key), \($0.connection), \($0.buttons) buttons]" }.joined(separator: "; ")))
        }
        follow()
    }

    /// Work out which mouse to follow and switch to its profile.
    private func follow() {
        let next = MouseChooser.active(among: mice, pinned: memory.pinned)
        if next?.key != mouse?.key {
            // One that ranks below the mouse before it may only be filling in while that one reconnects.
            if let old = mouse { previousTier = MouseChooser.tier(old) }
            standIn = next.map { $0.key != memory.pinned && MouseSetup.isStandIn($0, after: previousTier) } ?? false
            followedSince = Date()
            Log.write("following: \(next.map { "\($0.name) [\($0.key)]" } ?? "no mouse")\(standIn ? " (standing in)" : "")")
        }
        if next != mouse { mouse = next }
        let p = MouseChooser.profile(for: next, memory: memory, firstRun: firstRun)
        use(p)
        if next != nil {
            if memory.last != p.id { memory.last = p.id; saveMemory() }
            // From its first turn a mouse has a file of its own, so later changes to the MX Master 4 don't reach it.
            if started { ConfigStore.settle(p) }
        }
        bindLink()
        // A notice about a mouse that has gone, or that is no longer the one it describes, is withdrawn.
        if let notice = mouseNotice, !MouseSetup.stillTrue(notice, following: next, among: mice) { mouseNotice = nil }
        introduce()
    }

    private func saveMemory() {
        // Snapshots and other developer commands look but never write.
        if started { memory.save() }
    }

    /// Point out a mouse that hasn't been seen before: what it is and what opens the agent wheel on it.
    private func introduce() {
        // One notice at a time, and "press it to try" only once presses reach us.
        guard started, mouseNotice == nil, accessibilityOK, tap.isRunning else { return }
        // Not while the mouse being followed may be about to give way again.
        guard Date().timeIntervalSince(followedSince) >= MouseSetup.settleTime(standIn: standIn) else { return }
        guard let notice = MouseSetup.nextNotice(following: mouse, profile: profile, among: mice, triggers: wheelTriggers,
                                                 memory: memory, byChoice: followingByChoice) else { return }
        mouseNotice = notice
        Log.write("mouse notice: \(notice.title) [\(notice.device.key)]")
        // In the window it is a banner nobody can miss. Under the menu bar icon it has to stay up a while first.
        if windowVisible { noticeSeen() }
    }

    /// The notice that is showing has been seen, so it need not be shown again another day.
    func noticeSeen() {
        guard let notice = mouseNotice else { return }
        let before = memory
        MouseSetup.acknowledge(notice, in: &memory)
        if memory != before { saveMemory() }
    }

    /// Follow one of the connected mice from now on, by the person's choice.
    func follow(_ device: MouseDevice) {
        memory.pinned = device.key
        saveMemory()
        mouseNotice = nil
        follow()
        // Asked for, so there is nothing to wait for before saying what it does.
        standIn = false
        followedSince = .distantPast
        introduce()
    }

    /// Go back to following whichever mouse MouseHerdr thinks best.
    func followAutomatically() {
        memory.pinned = nil
        saveMemory()
        follow()
    }

    /// The mouse being followed was picked from the connected ones, not chosen by MouseHerdr.
    var followingByChoice: Bool { mouse != nil && mouse?.key == memory.pinned }

    /// Use a model from the list for the mouse being followed, whatever it says about itself.
    func choose(_ model: MouseProfile) {
        memory.chosen[mouse?.key ?? MouseChooser.noDevice] = model.id
        saveMemory()
        detectResult = nil
        follow()
    }

    /// Forget what was picked by hand and look at what is connected again.
    func detectMouse() {
        memory.pinned = nil
        memory.chosen[MouseChooser.noDevice] = nil
        for device in mice { memory.chosen[device.key] = nil }
        saveMemory()
        detector.rescan()
        detected = detector.devices
        miceChanged()
        detectResult = mouse.map { _ in "Found your \(mouseTitle)." }
            ?? "No mouse found. Trackpads don't count. Switch your mouse on or plug it in: it is picked up the moment it connects."
    }

    /// The notice's main button, or its other one.
    func answerNotice(primary: Bool) {
        guard let notice = mouseNotice else { return }
        noticeSeen()
        mouseNotice = nil
        switch (notice.kind, primary) {
        case (.alsoConnected, true): follow(notice.device)
        case (.chooseButton, true), (.ready, false):
            // Open the Buttons page on the button in question.
            tab = .buttons
            choosingMouse = false
            if let control = profile.wheelControl ?? profile.controls.first { selected = control.slot }
            openWindow?()
        default: break
        }
    }

    /// Developer aid: stand in for a connected mouse when drawing the window to a picture.
    func pose(_ p: MouseProfile, as device: MouseDevice?, among others: [MouseDevice] = []) {
        use(p)
        mouse = device
        mice = MouseChooser.candidates((device.map { [$0] } ?? []) + others)
        // A mouse with a direct link is shown as if it were up, so its battery level appears.
        link = device.flatMap { $0.vendorID == MouseProfile.logitech && p.usesDirectLink ? ($0.name, $0.productID, []) : nil }
    }

    /// The control behind a button number macOS reports.
    private func control(forButton button: Int) -> MouseControl? {
        profile.controls.first { $0.button == button }
    }

    // MARK: Start

    func start() {
        started = true
        // Written at the first start, so that whether this Mac goes back to before other mice is settled once.
        if !MouseMemory.exists() { memory.save() }
        refreshPermissions()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let defaults = UserDefaults.standard
        let path = Bundle.main.bundlePath
        if !defaults.bool(forKey: "didSetupLogin") {
            defaults.set(true, forKey: "didSetupLogin")
            setLaunchAtLogin(true)
        } else if defaults.string(forKey: "loginItemPath") != path, defaults.string(forKey: "loginItemPath") == nil || launchAtLogin {
            // The app was moved or renamed: point the login item at where it is now.
            try? SMAppService.mainApp.unregister()
            setLaunchAtLogin(true)
        }
        defaults.set(path, forKey: "loginItemPath")

        tap.onPress = { [weak self] button in
            guard let self, let control = self.control(forButton: button) else {
                Log.write("unmapped mouse button \(button) pressed")
                return false
            }
            let slot = control.slot
            Log.write("mouse button \(button) pressed → \(slot.rawValue)")
            guard self.isRemapped(slot) else { return false }
            // Without the direct connection some controls only send a short pulse, so they can't be "held".
            self.press(slot, pulseOnly: control.pulsesOverTap)
            return true
        }
        tap.isMapped = { [weak self] button in
            guard let self, let slot = self.control(forButton: button)?.slot else { return false }
            return self.isRemapped(slot)
        }
        tap.onRelease = { [weak self] button in
            guard let self, let slot = self.control(forButton: button)?.slot else { return }
            Log.write("mouse button \(button) released")
            self.release(slot)
        }
        tap.onPlainClick = { [weak self] right in
            guard let self else { return false }
            // With the agent ring open, a click picks the agent being aimed at and a right-click pins it.
            if self.ring.isOpen {
                if right { self.ring.pinAimed() } else { self.ring.choose() }
                return true
            }
            if self.replyBox.isOpen { return false }
            // A normal click drops a window that is being carried.
            guard self.stickyDrag else { return false }
            self.stickyDrag = false
            self.dragger.end()
            return true
        }
        tap.onThumbWheel = { [weak self] delta in self?.thumbWheel(delta) ?? false }
        dragger.onZone = { [weak self] in self?.buzz(.edge) }
        feeler.onLand = { [weak self] in
            guard let self, !self.dragger.isDragging else { return }
            self.buzz(.hover)
        }
        feeler.onCrossWindow = { [weak self] in
            guard let self, !self.dragger.isDragging else { return }
            self.buzz(.tick)
        }
        if accessibilityOK { tap.start() }
        watchAgents()
        // While the wheel is up, Escape puts it away, and the app in front never hears of it.
        ring.onOpenChange = { [weak self] open in self?.tap.watchEscape(open) }
        tap.onEscape = { [weak self] in
            guard let self, self.ring.isOpen else { return false }
            Log.write("agents: wheel closed with Escape")
            self.ring.dismiss()
            return true
        }
        ring.onAim = { [weak self] in self?.buzz(.tick) }
        ring.onChoose = { [weak self] agent in
            self?.fronts.note(agent.id)
            self?.agents.focus(agent)
        }
        ring.onPin = { [weak self] agent in
            self?.togglePin(agent)
            self?.buzz(.tick)
        }
        ring.onType = { [weak self] agent, spot in
            guard let self else { return }
            self.replyBox.show(for: agent, at: spot) { text in self.agents.answer(agent, typed: text) }
        }
        // An answer picked earlier may still be on its way to an agent; the wheel shows that it is.
        ring.answerOnItsWay = { [weak self] id in self?.agents.answering[id] }
        ring.onAnswer = { [weak self] agent, option in
            guard let self else { return }
            self.agents.answer(agent, option: option) { outcome in
                // Only now is it known whether the agent got it: herdr-core may hold a key back.
                self.ring.answered(agent, option: option, outcome)
                guard case .delivered = outcome else { return }
                // The agent may ask its next question; refresh so it can be answered straight away.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.ring.isOpen { self.refreshRing() }
                }
            }
            self.buzz(.tick)
        }

        hid.onStatus = { [weak self] s in
            guard let self else { return }
            self.hidStatus = s
            if s != .connected {
                self.hidHaptics = false; self.hapticsAvailable = false; self.applyFeel(); self.directLink = false; self.stickyDrag = false; self.pressed = []; self.cidForSlot = [:]; self.slotForCID = [:]; self.updateAvailability()
                // The link is gone, and with it what it said about itself.
                if self.link != nil { self.link = nil; self.miceChanged() }
            }
            if s == .connected { self.needsRelaunch = false }
        }
        hid.onDevice = { [weak self] name, productID, controls in self?.deviceReady(name, productID, controls) }
        hid.onButtons = { [weak self] cids in self?.buttons(cids) }
        hid.onRawXY = { [weak self] dx, dy in self?.rawXY(dx, dy) }
        hid.onHaptics = { [weak self] ok in
            guard let self else { return }
            self.hidHaptics = ok
            self.hapticsAvailable = self.hapticsReachable
            self.applyFeel()
        }
        hid.onBattery = { [weak self] p, c in self?.battery = p; self?.charging = c }
        // Find out which mouse is connected before the direct link starts, so the right picture is there from the start.
        detector.onChange = { [weak self] devices in
            guard let self else { return }
            self.detected = devices
            self.miceChanged()
        }
        detector.start()
        hid.start()
        updateAvailability()

        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.hid.reapply() }
        }
    }

    private func tick() {
        refreshPermissions()
        ticks += 1
        if ticks % 2 == 0 { watchAgents() }
        refreshAgentList()
        if accessibilityOK && !tap.isRunning { tap.start(); updateAvailability(); applyFeel() }
        introduce()     // a new mouse is pointed out once its presses can reach us
        if hidStatus == .notPermitted {
            // macOS sometimes refuses the first attempt right after launch, so keep trying quietly.
            grantRestarts += 1
            if grantRestarts <= 6 || grantRestarts % 5 == 0 { hid.restart() }
            if inputMonitoringOK && grantRestarts > 4 { needsRelaunch = true }
        } else {
            grantRestarts = 0
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        let ax = AXIsProcessTrusted()
        let im = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if ax != accessibilityOK { accessibilityOK = ax }
        if im != inputMonitoringOK { inputMonitoringOK = im }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
    }

    func relaunch() {
        hid.releaseAll()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\" --args --show", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Log.write("launch at login: \(launchAtLogin)")
    }

    // MARK: Agents

    /// Notice agents that start waiting on you or finish, and say so through the thumb pad.
    /// This is also what notices Herdr being installed, started or stopped while MouseHerdr runs.
    private func watchAgents() {
        // Nothing to ask for when neither agent feature is in use.
        guard ringOnTap || (feelAgents && hapticsOn && hapticsAvailable) || ring.isOpen else { return }
        // One question at a time, so a herdr-core that is slow to answer can't build up a queue.
        guard !agentsFetching else { return }
        agentsFetching = true
        // Which agent is in front, so that the wheel knows which one to go back to.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let front = AgentWatcher.frontTerminal()
            DispatchQueue.main.async { self?.fronts.note(front) }
        }
        // What a waiting agent is asking is read too, so that the wheel has its question to hand
        // the moment it opens.
        agents.fetch(details: .waiting) { [weak self] list in
            guard let self else { return }
            self.agentsFetching = false
            self.noteHerdr()
            var next: [String: String] = [:]
            var nowWaiting = false, nowDone = false
            for a in list {
                next[a.id] = a.status
                guard self.agentsSeen, let before = self.agentStatus[a.id], before != a.status else { continue }
                if a.needsYou { nowWaiting = true }
                else if a.status == "done" && before == "working" { nowDone = true }
            }
            self.agentStatus = next
            self.agentsSeen = true
            guard self.feelAgents else { return }
            if nowWaiting { Log.write("agents: one needs you"); self.buzz(.knock) }
            else if nowDone { Log.write("agents: one finished"); self.buzz(.finished) }
        }
    }

    /// Copy what the last fetch learned about Herdr to where the window can see it.
    private func noteHerdr() {
        if herdr != agents.status { herdr = agents.status }
        if herdrApp != agents.appInstalled { herdrApp = agents.appInstalled }
    }

    /// Refresh the Agents page: every agent with what it is asking.
    func refreshAgentList() {
        guard windowVisible, tab == .agents, !listFetching else { return }
        listFetching = true
        agents.fetch(details: .all) { [weak self] list in
            guard let self else { return }
            self.listFetching = false
            self.noteHerdr()
            if self.agentList != list { self.agentList = list }
        }
    }

    /// Open the wheel at the pointer, or pick from it if it is already open.
    func toggleWheel() {
        // Pressed again while the wheel is open, it picks the wedge aimed at, or puts the wheel away.
        if ring.isOpen { ring.choose(fromTrigger: true) } else { openRing() }
    }

    func focus(_ agent: AgentInfo) { agents.focus(agent) }

    /// Pin an agent to the front of the wheel, or let it go again.
    func togglePin(_ agent: AgentInfo) {
        if pinnedAgents.contains(agent.id) { pinnedAgents.remove(agent.id) } else { pinnedAgents.insert(agent.id) }
        Log.write("agents: \(pinnedAgents.contains(agent.id) ? "pinned" : "unpinned") \(agent.id) (\(agent.space) / \(agent.tab))")
    }

    /// Answer an agent's question from the window with one of its offered choices.
    func answer(_ agent: AgentInfo, option: Int) {
        agents.answer(agent, option: option) { [weak self] _ in
            // Once herdr-core has pressed the key, which can be a few seconds after the click.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refreshAgentList() }
        }
    }

    /// Plain-language list of what opens the wheel on this mouse right now.
    var wheelTriggers: [String] {
        MouseSetup.triggers(profile: profile, assignments: assignments, ringOnTap: ringOnTap)
    }

    /// Run an action; the agent wheel is ours, everything else is a key press or similar.
    private func perform(_ a: Action) {
        guard a.kind == "agentWheel" else { ActionRunner.run(a); return }
        // Trying the button is what the notice asked for, so it has done its job.
        if mouseNotice?.kind == .ready { noticeSeen(); mouseNotice = nil }
        toggleWheel()
    }

    /// Look again now; the settings popover asks for this when it opens.
    func checkHerdr() {
        agents.fetch { [weak self] _ in self?.noteHerdr() }
    }

    private func openRing() {
        ring.model.order = ringOrder
        ring.model.pinned = pinnedAgents
        // Which agent is in front may have changed in Herdr itself since the last look.
        fronts.note(AgentWatcher.frontTerminal())
        ring.model.back = fronts.back
        ring.show(agents.latest, herdr: agents.status, appInstalled: agents.appInstalled)
        refreshRing()
        // Keep the wheel live while it is showing: agents change state, ask new questions, finish.
        ringTimer?.invalidate()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self, self.ring.isOpen else { timer.invalidate(); return }
            self.refreshRing()
        }
        RunLoop.main.add(t, forMode: .common)
        ringTimer = t
    }

    private func refreshRing() {
        guard !ringFetching else { return }
        ringFetching = true
        agents.fetch(details: .all) { [weak self] list in
            guard let self else { return }
            self.ringFetching = false
            self.noteHerdr()
            self.ring.update(list, herdr: self.agents.status, appInstalled: self.agents.appInstalled)
        }
    }

    // MARK: Haptics and extras

    /// Push the "feel" settings to wherever they take effect.
    func applyFeel() {
        dragger.snapEnabled = snapWindows
        if hapticsOn && hapticsAvailable { hid.setHapticLevel(hapticStrength) }
        feeler.configure(controls: feelHover, windows: feelEdges)
        if hapticsOn && hapticsAvailable && (feelHover || feelEdges) && accessibilityOK { feeler.start() } else { feeler.stop() }
    }

    func buzz(_ wave: Wave) {
        guard hapticsOn, hapticsAvailable else { return }
        hid.haptic(wave.rawValue)
    }

    /// The thumb wheel was rolled. Returns true if we used the movement.
    private func thumbWheel(_ delta: Double) -> Bool {
        guard let wheel = profile.controls.first(where: { $0.source == .thumbWheel }) else { return false }
        let mode = action(wheel.slot).kind
        let step: Double, pause: Double
        switch mode {
        case "wheelVolume": (step, pause) = (1.0, 0.0)
        case "wheelZoom": (step, pause) = (2.0, 0.05)
        case "wheelTabs": (step, pause) = (2.5, 0.12)
        case "wheelUndo": (step, pause) = (2.5, 0.10)
        case "wheelDesktops": (step, pause) = (4.0, 0.6)
        default: return false
        }
        let now = Date()
        if now.timeIntervalSince(wheelLast) > 0.35 { wheelAcc = 0 }
        wheelLast = now
        wheelAcc += delta
        guard abs(wheelAcc) >= step, now >= wheelReady else { return true }
        let forward = wheelAcc < 0
        wheelAcc = 0
        wheelReady = now.addingTimeInterval(pause)
        switch mode {
        case "wheelVolume": ActionRunner.media(forward ? 0 : 1)
        case "wheelZoom": ActionRunner.key(forward ? 24 : 27, .command)
        case "wheelTabs": ActionRunner.key(48, forward ? .control : [.control, .shift]); buzz(.tick)
        case "wheelUndo": ActionRunner.key(6, forward ? [.command, .shift] : .command); buzz(.tick)
        default: ActionRunner.key(forward ? 124 : 123, .control); buzz(.swipe)
        }
        return true
    }

    // MARK: Assignments

    func action(_ slot: Slot) -> Action { assignments[slot] ?? .standard }

    func assign(_ action: Action, to slot: Slot) {
        assignments[slot] = action
        ConfigStore.save(assignments, for: profile)
        pushDiversions()
    }

    func resetAll() {
        assignments = profile.defaults
        ConfigStore.save(assignments, for: profile)
        pushDiversions()
    }

    private func isRemapped(_ slot: Slot) -> Bool {
        hasGestures(slot) ? gestureWanted(slot) : !action(slot).isDefault
    }

    /// A gesture control is in use if its click or any of the four directions does something.
    private func gestureWanted(_ slot: Slot) -> Bool {
        !action(slot).isDefault || Slot.swipes.contains { !action($0).isNothing && !action($0).isDefault }
    }

    /// Tell the mouse which controls to send our way. `releasing` holds controls that are handed
    /// back: captured for another profile, or held by a mouse that is no longer being followed.
    private func pushDiversions(releasing: Set<UInt16> = []) {
        var diverts: [UInt16: Bool] = [:]
        for control in profile.controls {
            guard let cid = cidForSlot[control.slot], isRemapped(control.slot) else { continue }
            diverts[cid] = control.gestures && rawXYCapable.contains(cid)   // raw XY only where movement matters
        }
        hid.setDiversions(diverts, managed: Array(releasing.union(cidForSlot.values)))
        captured = Set(cidForSlot.values)
    }

    // MARK: Device

    /// The direct link has learned what it is talking to.
    private func deviceReady(_ name: String, _ productID: Int, _ controls: [HIDPP.Control]) {
        link = (name, productID, controls)
        linkArrived = true
        miceChanged()       // follows the best mouse, then ties the link to it if it is that mouse
    }

    /// The haptic motor can be used: the mouse on the direct link has one, and it is the mouse being followed.
    private var hapticsReachable: Bool { hidHaptics && profile.hasHaptics && (link == nil || linkFollowed) }

    /// The mouse the direct link is talking to, when that is not the one being followed. The link reaches one mouse at a time.
    var linkElsewhere: String? { link != nil && !linkFollowed ? link?.name : nil }

    /// Tie the profile's HID++ controls to what the mouse on the direct link reports, if that is the
    /// mouse being followed. If it is another mouse, hand back whatever it is holding for us.
    private func bindLink() {
        let before = cidForSlot
        let followed = linkFollowed
        let arrived = linkArrived
        linkArrived = false
        cidForSlot = [:]
        rawXYCapable = []
        if let link, followed {
            rawXYCapable = Set(link.controls.filter { $0.rawXY }.map { $0.cid })
            cidForSlot = profile.captures(among: link.controls)
        }
        slotForCID = Dictionary(cidForSlot.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        if cidForSlot != before {
            Log.write("slots: " + (cidForSlot.isEmpty ? "none" : cidForSlot.map { "\($0.key.rawValue)=\(String(format: "0x%04x", $0.value))" }.sorted().joined(separator: " ")))
        }
        let haptics = hapticsReachable
        if haptics != hapticsAvailable { hapticsAvailable = haptics; applyFeel() }
        updateAvailability()
        if let link {
            let release = MouseChooser.handBack(captured: captured, wanted: Set(cidForSlot.values),
                                                followed: followed, arrived: arrived, reported: link.controls)
            // The mouse being followed is told what to capture when it has just connected or when
            // that has changed. Any other mouse on the link is only told to let go.
            let changed = arrived || cidForSlot != before || boundProfile != profile.id
            if !release.isEmpty || (followed && changed) {
                if !release.isEmpty {
                    Log.write("handing back to \(link.name): " + release.sorted().map { String(format: "0x%04x", $0) }.joined(separator: " "))
                }
                pushDiversions(releasing: release)
            }
            boundProfile = followed ? profile.id : nil
        }
        directLink = profile.controls.contains { $0.pulsesOverTap && cidForSlot[$0.slot] != nil }
    }

    private func updateAvailability() {
        var s = Set<Slot>()
        if tap.isRunning {
            s.formUnion(profile.controls.filter { $0.button != nil || $0.source == .thumbWheel }.map { $0.slot })
        }
        if hidStatus == .connected && accessibilityOK { s.formUnion(cidForSlot.keys) }
        available = s
    }

    // MARK: Button handling

    private func press(_ slot: Slot, pulseOnly: Bool = false) {
        pulseSource = pulseOnly
        if hasGestures(slot) { gestureDown(slot); return }
        let a = action(slot)
        guard a.isDrag else { perform(a); return }
        if ring.isOpen {                // pressing the pad again picks from the ring
            ringPress = true
            return
        }
        dragStartMouse = CGEvent(source: nil)?.location ?? .zero
        if stickyDrag {                 // second press drops the window
            stickyDrag = false
            dragger.end()
        } else {
            dragPressed = Date()
            dragger.begin()
        }
    }

    private func release(_ slot: Slot) {
        if hasGestures(slot) { gestureUp(); return }
        guard action(slot).isDrag else { return }
        if ringPress { ringPress = false; ring.choose(fromTrigger: true); return }
        guard !stickyDrag else { return }
        if pulseSource {
            // A button that can't be held: carry the window until the next click.
            guard dragger.isDragging else { return }
            stickyDrag = true
            Log.write("drag: carrying until next click")
            return
        }
        // A quick press without moving is a tap, not a drag.
        let now = CGEvent(source: nil)?.location ?? dragStartMouse
        let moved = hypot(now.x - dragStartMouse.x, now.y - dragStartMouse.y)
        let quick = Date().timeIntervalSince(dragPressed) < 0.30 && moved < 6
        dragger.end(snap: !quick)
        // The wheel opens even without Herdr, to say what is missing rather than do nothing.
        if quick && ringOnTap { openRing() }
    }

    private func gestureDown(_ slot: Slot) {
        gestureSlot = slot
        gestureHeld = true; gestureFired = false; gestureAcc = .zero
        gestureStart = CGEvent(source: nil)?.location ?? .zero
        gestureTimer?.invalidate()
        // Watch how far the cursor travels while the button is held.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, self.gestureHeld, !self.gestureFired, let m = CGEvent(source: nil)?.location else { return }
            self.swipe(m.x - self.gestureStart.x, m.y - self.gestureStart.y, threshold: 70)
        }
        RunLoop.main.add(t, forMode: .common)
        gestureTimer = t
    }

    private func gestureUp() {
        gestureTimer?.invalidate(); gestureTimer = nil
        guard gestureHeld else { return }
        gestureHeld = false
        if !gestureFired { perform(action(gestureSlot)) }
    }

    private func swipe(_ dx: CGFloat, _ dy: CGFloat, threshold: CGFloat) {
        guard max(abs(dx), abs(dy)) > threshold else { return }
        let slot: Slot = abs(dx) > abs(dy) ? (dx > 0 ? .gestureRight : .gestureLeft) : (dy > 0 ? .gestureDown : .gestureUp)
        gestureFired = true
        perform(action(slot))
        buzz(.swipe)
    }

    private func buttons(_ cids: Set<UInt16>) {
        let newly = cids.subtracting(pressed), released = pressed.subtracting(cids)
        pressed = cids
        for cid in newly {
            if let slot = slotForCID[cid] { press(slot) }
        }
        for cid in released {
            if let slot = slotForCID[cid] { release(slot) }
        }
    }

    private func rawXY(_ dx: Int, _ dy: Int) {
        guard gestureHeld, !gestureFired else { return }
        gestureAcc.x += CGFloat(dx); gestureAcc.y += CGFloat(dy)
        swipe(gestureAcc.x, gestureAcc.y, threshold: 140)
    }

    // MARK: Shortcut recording

    func beginRecording() {
        recording = true
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
                guard let self, self.recording else { return ev }
                self.recording = false
                if ev.keyCode == 53 { return nil }   // Esc cancels
                let flags = ev.modifierFlags.intersection([.command, .shift, .option, .control])
                let label = Catalog.shortcutLabel(keyCode: Int(ev.keyCode), flags: flags, characters: ev.charactersIgnoringModifiers)
                self.assign(Action(kind: "shortcut", keyCode: Int(ev.keyCode), modifiers: flags.rawValue, label: label), to: self.editing)
                return nil
            }
        }
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            assign(Action(kind: "app", appPath: url.path), to: editing)
        }
    }

    func shutdown() {
        ring.close()
        feeler.stop()
        dragger.end()
        hid.releaseAll()
    }
}

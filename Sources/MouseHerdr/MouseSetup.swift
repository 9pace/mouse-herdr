import Foundation

/// Something to tell the person about a mouse: that it was found and what opens the agent wheel
/// on it, or that another mouse could be followed instead.
struct MouseNotice: Equatable, Identifiable {
    enum Kind: Equatable {
        /// The mouse is in use and something on it opens the agent wheel.
        case ready
        /// The mouse is in use, but nothing on it opens the wheel yet.
        case chooseButton
        /// The mouse has no spare button to open the wheel with.
        case noButton
        /// Another mouse is being followed; this one could be instead.
        case alsoConnected
    }

    let kind: Kind
    /// The mouse it is about.
    let device: MouseDevice
    let title: String
    let text: String

    var id: String { "\(device.key) \(kind)" }

    /// The button that does what the notice suggests, and the one that doesn't.
    var primary: String {
        switch kind {
        case .ready, .noButton: return "Got it"
        case .chooseButton: return "Choose a button…"
        case .alsoConnected: return "Use this mouse"
        }
    }

    var secondary: String? {
        switch kind {
        case .ready: return "Choose another button…"
        case .chooseButton: return "Later"
        case .noButton: return nil
        case .alsoConnected: return "Not now"
        }
    }
}

/// What to say about a mouse. Kept apart from the app's state so it can be tested.
enum MouseSetup {
    /// What to call a mouse: its model if it is one in the list, or else what it calls itself.
    static func title(device: MouseDevice?, profile: MouseProfile) -> String {
        guard let device, profile.kind != .mouse else { return profile.fullName }
        if profile.kind == .receiver { return "\(profile.brand) USB receiver" }
        return device.name.isEmpty ? profile.name : device.name
    }

    /// How it was found and how it is connected, in a few words.
    static func subtitle(device: MouseDevice?, profile: MouseProfile, pickedByHand: Bool) -> String {
        guard let device else { return "Not connected" }
        if pickedByHand { return "\(device.connection) · model picked by you" }
        // A mouse hiding behind a receiver, taken for the one this Mac has always had.
        if profile.kind == .mouse && device.kind == .receiver { return "\(device.connection) receiver · assumed to be this mouse" }
        switch profile.kind {
        case .mouse: return "\(device.connection) · recognised"
        case .receiver: return "\(device.connection) · mouse model unknown"
        case .fallback: return "\(device.connection) · not in the list yet"
        }
    }

    /// Plain-language list of what opens the agent wheel on this mouse with these choices.
    static func triggers(profile: MouseProfile, assignments: [Slot: Action], ringOnTap: Bool) -> [String] {
        var out: [String] = []
        if ringOnTap, let pad = profile.control(.thumbPanel), (assignments[.thumbPanel] ?? .standard).isDrag {
            out.append("A quick tap on the \(pad.title.lowercased())")
        }
        for c in profile.controls {
            if assignments[c.slot]?.kind == "agentWheel" { out.append("The \(c.title.lowercased())") }
            if c.gestures {
                for s in Slot.swipes where assignments[s]?.kind == "agentWheel" {
                    out.append("\(c.title): \(s.swipeTitle.lowercased())")
                }
            }
        }
        return out
    }

    /// What to point out now, if anything: the mouse being followed, the first time it is, or else
    /// a mouse that could be followed instead.
    ///
    /// Nothing is noted here. A notice counts as said only once somebody has seen it
    /// (`acknowledge`), so one that was withdrawn before anyone could, because its mouse left
    /// again, comes back when there is reason to.
    static func nextNotice(following mouse: MouseDevice?, profile: MouseProfile, among connected: [MouseDevice],
                           triggers: [String], memory: MouseMemory, byChoice: Bool = false) -> MouseNotice? {
        // The MX Master 4 needs no introduction: the Agents page already says how its pad opens the wheel.
        if let mouse, !profile.tested, !memory.wasIntroduced(mouse) {
            return notice(for: mouse, profile: profile, triggers: triggers)
        }
        // A mouse that could be followed instead of the one that is. It is offered once. Taking the
        // offer follows it, and it is then introduced like any other. A receiver is never offered:
        // there may be no mouse behind it. And nothing is offered to someone who has just picked
        // the mouse to follow by hand.
        if !byChoice, let other = connected.first(where: { $0.key != mouse?.key && $0.kind == .mouse && !memory.wasOffered($0) }) {
            return notice(alsoConnected: other, following: title(device: mouse, profile: profile))
        }
        return nil
    }

    /// Note that a notice has been seen, so that it is not shown again, not even after a restart.
    static func acknowledge(_ notice: MouseNotice, in memory: inout MouseMemory) {
        if notice.kind == .alsoConnected { memory.offer(notice.device) } else { memory.introduce(notice.device) }
    }

    /// How long a mouse has to have been followed before anything is said about it.
    ///
    /// A Bluetooth mouse drops its link when it naps and takes a few seconds to come back after
    /// the Mac wakes or starts. A lesser mouse that takes over meanwhile is only standing in, and
    /// a notice about it would flash by and go. So a stand-in is given time to turn out to be
    /// one; any other mouse is spoken of almost at once.
    static func settleTime(standIn: Bool) -> TimeInterval { standIn ? 10 : 2 }

    /// Whether a mouse that takes over is ranked below the one followed before it (by `MouseChooser.tier`).
    static func isStandIn(_ device: MouseDevice, after previousTier: Int) -> Bool {
        MouseChooser.tier(device) < previousTier
    }

    /// The rank of the mouse a profile describes, for a profile that was in use when no device is to hand.
    static func tier(of profile: MouseProfile) -> Int {
        switch profile.kind {
        case .mouse: return profile.tested ? 3 : 2
        case .fallback: return 1
        case .receiver: return 0
        }
    }

    /// Whether a notice that is showing still describes things as they are. One about a mouse that
    /// has been unplugged, or that is no longer the one being followed, has nothing left to say.
    static func stillTrue(_ notice: MouseNotice, following mouse: MouseDevice?, among connected: [MouseDevice]) -> Bool {
        let about = notice.device.key
        if notice.kind == .alsoConnected { return about != mouse?.key && connected.contains { $0.key == about } }
        return about == mouse?.key
    }

    /// The notice for a mouse that has just been followed for the first time.
    static func notice(for device: MouseDevice, profile: MouseProfile, triggers: [String]) -> MouseNotice {
        let name = title(device: device, profile: profile)
        let found = "\(name) detected"
        // Nothing on it that macOS reports beyond left and right.
        if profile.controls.allSatisfy({ $0.virtual }) {
            return MouseNotice(kind: .noButton, device: device, title: found,
                               text: profile.note ?? "This mouse has no spare button. Open the agent wheel from the MouseHerdr menu bar icon instead.")
        }
        guard let trigger = triggers.first else {
            return MouseNotice(kind: .chooseButton, device: device, title: found,
                               text: "Nothing on it opens the agent wheel yet, because its buttons already have other jobs. Choose one for the wheel.")
        }
        let through = profile.kind == .receiver ? "If a mouse is connected through it: " : ""
        let subject = through.isEmpty ? trigger : trigger.prefix(1).lowercased() + trigger.dropFirst()
        // Say what was given up for it, so a middle click that stops working is no surprise.
        let isMiddleClick = profile.control(.middle).map { "The \($0.title.lowercased())" == trigger } ?? false
        let cost = isMiddleClick ? ", in place of a middle click" : ""
        return MouseNotice(kind: .ready, device: device, title: found,
                           text: "\(through)\(subject) now opens the agent wheel around the pointer\(cost). Press it to try, then click an agent or anywhere else.")
    }

    /// The notice for a mouse that connected while another one is being followed.
    static func notice(alsoConnected device: MouseDevice, following: String) -> MouseNotice {
        let name = title(device: device, profile: device.recognised ?? .fallback(buttons: device.buttons))
        return MouseNotice(kind: .alsoConnected, device: device, title: "\(name) is connected too",
                           text: "MouseHerdr follows one mouse at a time and is set up for your \(following). Switch to set this one up.")
    }
}

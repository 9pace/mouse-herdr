import SwiftUI

/// One thing on a mouse that can be given an action.
struct MouseControl: Identifiable {
    /// Where its presses come from.
    enum Source: Equatable {
        /// An ordinary button macOS reports by number (2 is the wheel click, 3 back, 4 forward), caught by the event tap.
        /// With `cid` set, the mouse can also report it over HID++, which is used instead when the direct link is up.
        case button(Int, cid: UInt16? = nil)
        /// A control macOS never sees. It only works once it is diverted over HID++.
        case hidpp(cid: UInt16)
        /// The sideways scroll wheel. Use it with the `.thumbWheel` slot, which has its own list of actions.
        case thumbWheel
    }

    /// How it is drawn on the picture.
    enum Shape {
        case button             // small capsule
        case wheel              // ridged capsule
        case pad(tilt: Double)  // large rounded panel, turned by `tilt` degrees
    }

    /// The key its action is saved under. Slots are shared between mice so settings carry over.
    let slot: Slot
    let title: String
    let blurb: String
    let source: Source
    /// Hold it and move the mouse for four more actions (the `.gestureUp` … `.gestureRight` slots).
    /// Those four slots are shared, so give this to at most one control per mouse.
    var gestures = false
    /// Through the event tap it only sends a short pulse, so it can be held only over HID++.
    var pulsesOverTap = false
    /// If the mouse doesn't report this control's `cid`, take the first capturable control nothing else accounts for.
    var orAnyUnlistedControl = false
    /// Not something this mouse can do by itself: it only happens with a helper app. Drawn as an outline.
    var virtual = false

    // Artwork, in the profile's canvas coordinates.
    let rect: CGRect
    var shape: Shape = .button
    /// Centre of its label, and whether the label sits left of the mouse.
    let chip: CGPoint
    let chipOnLeft: Bool

    var id: String { slot.rawValue }

    var button: Int? {
        if case .button(let n, _) = source { return n }
        return nil
    }

    var cid: UInt16? {
        switch source {
        case .button(_, let cid): return cid
        case .hidpp(let cid): return cid
        case .thumbWheel: return nil
        }
    }
}

/// The colours a mouse is drawn in.
enum Finish {
    case graphite, black, silver, white

    /// The body, from its lit corner to its far one.
    var body: [Color] {
        switch self {
        case .graphite: return [Color(white: 0.34), Color(white: 0.15)]
        case .black: return [Color(white: 0.29), Color(white: 0.09)]
        case .silver: return [Color(white: 0.80), Color(white: 0.58)]
        case .white: return [Color(white: 0.99), Color(white: 0.84)]
        }
    }

    /// A second shape behind the body, such as a thumb rest.
    var wing: [Color] {
        switch self {
        case .graphite: return [Color(white: 0.23), Color(white: 0.12)]
        case .black: return [Color(white: 0.16), Color(white: 0.05)]
        case .silver: return [Color(white: 0.68), Color(white: 0.50)]
        case .white: return [Color(white: 0.90), Color(white: 0.76)]
        }
    }

    var isLight: Bool { self == .silver || self == .white }
    /// The lines between the buttons.
    var seam: Color { isLight ? Color.black.opacity(0.26) : self == .black ? Color.white.opacity(0.16) : Color.black.opacity(0.45) }
    /// The body's outline.
    var edge: Color { isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.10) }
    /// A control that is not selected.
    var part: Color { isLight ? Color(white: 0.38) : Color(white: 0.56) }
    /// A large pad that is not selected.
    var pad: Color { isLight ? Color(white: 0.62) : self == .black ? Color(white: 0.22) : Color(white: 0.30) }
}

/// The picture of a mouse, nose pointing up.
struct MouseArt {
    let size: CGSize
    let body: Path
    /// An optional second shape drawn behind the body, such as a thumb rest.
    var wing: Path? = nil
    /// Lines on the body: the split between the main buttons, the palm seam.
    let seams: Path
    /// The oval of the soft shadow under the mouse.
    let shadow: CGRect
    /// The ball of a trackball, and whether a scroll ring goes around it.
    var ball: CGRect? = nil
    var ballColor = Color(red: 0.78, green: 0.16, blue: 0.18)
    var ring = false
    var finish = Finish.graphite

    static let chipSize = CGSize(width: 172, height: 52)

    /// The part of the canvas the mouse itself covers, for small pictures of it.
    var bounds: CGRect {
        var box = body.boundingRect
        if let wing { box = box.union(wing.boundingRect) }
        if let ball { box = box.union(ball.insetBy(dx: ring ? -16 : 0, dy: ring ? -16 : 0)) }
        return box
    }
}

/// Everything the app needs to know about one mouse model. A mouse with its own shape and its own
/// controls gets a file of its own (see Profiles/MXMaster4.swift). A mouse that looks and works like
/// many others is one line in Profiles/Catalog.swift, drawn from a shared body in Profiles/Bodies.swift.
struct MouseProfile: Identifiable {
    enum Kind {
        case mouse
        /// A USB receiver: the mouse behind it does not say what it is.
        case receiver
        /// A plain layout for a mouse that is not in the list.
        case fallback
    }

    let id: String
    let name: String
    var brand = "Logitech"
    var kind = Kind.mouse

    // How to recognise it: a product id from one of the vendors, or part of the name it reports.
    var vendorIDs: Set<Int> = [MouseProfile.logitech]   // HID vendor ids
    var productIDs: Set<Int> = []                       // HID product ids
    var nameContains: [String] = []                     // parts of the name the mouse reports

    /// In the order they are drawn.
    let controls: [MouseControl]
    /// The control selected when the window first opens.
    let firstSelected: Slot
    let hasHaptics: Bool
    let defaults: [Slot: Action]
    /// Shown next to the Input Monitoring permission: what the direct link adds for this mouse.
    let directLinkWhy: String
    let art: MouseArt
    /// Checked on the real device. Everything else is recognised from published device ids and
    /// uses only what macOS or HID++ reports for any mouse.
    var tested = false
    /// Something the owner of this mouse should know, shown in the window.
    var note: String? = nil

    static let logitech = 0x046D
    /// The product id of Logitech's Bolt receiver, the only kind an MX Master 4 pairs with.
    static let boltReceiver = 0xC548

    func control(_ slot: Slot) -> MouseControl? { controls.first { $0.slot == slot } }

    /// Every key this mouse's choices are saved under.
    var slots: [Slot] {
        controls.map(\.slot) + (controls.contains { $0.gestures } ? Slot.swipes : [])
    }

    /// Some of its controls only answer over the direct (HID++) link.
    var usesDirectLink: Bool { controls.contains { $0.cid != nil } }

    /// The control that opens the agent wheel out of the box, if this mouse has a spare one.
    var wheelControl: MouseControl? { controls.first { defaults[$0.slot]?.kind == "agentWheel" } }

    /// "Logitech MX Master 4", without saying a brand twice.
    var fullName: String {
        kind == .fallback || name.localizedCaseInsensitiveContains(brand) ? name : "\(brand) \(name)"
    }

    // MARK: Registry

    /// The mice we know.
    static let all: [MouseProfile] = [.mxMaster4] + MouseCatalog.mice

    /// Plain layouts for mice that are not in `all`.
    static let fallbacks: [MouseProfile] = [.generic, .generic3, .generic2]

    /// Assumed on a Mac that has run MouseHerdr before, so the picture doesn't change under an MX Master 4 owner at every start.
    static let initial = mxMaster4

    /// The profile for a device that says this about itself, or nil if it is not one we know.
    ///
    /// A product id counts only with its vendor. A name counts when the vendor fits or is unknown
    /// (some Bluetooth mice report none), and the longest matching name wins, so an "MX Master 3S"
    /// is not taken for an "MX Master 3".
    static func matching(vendor: Int, product: Int, name: String) -> MouseProfile? {
        let known = vendor > 0
        if known, let hit = all.first(where: { $0.vendorIDs.contains(vendor) && $0.productIDs.contains(product) }) {
            return hit
        }
        var best: (profile: MouseProfile, length: Int)?
        for p in all where !known || p.vendorIDs.isEmpty || p.vendorIDs.contains(vendor) {
            for pattern in p.nameContains where name.localizedCaseInsensitiveContains(pattern) {
                if pattern.count > (best?.length ?? 0) { best = (p, pattern.count) }
            }
        }
        return best?.profile
    }

    /// The profile for a Logitech mouse on the direct link, which reports no vendor of its own.
    static func matching(productID: Int, name: String) -> MouseProfile {
        matching(vendor: logitech, product: productID, name: name) ?? .generic
    }

    /// A plain layout for a mouse that is not in the list, going by how many buttons it says it has.
    static func fallback(buttons: Int) -> MouseProfile {
        switch buttons {
        case 1...2: return .generic2
        case 3: return .generic3
        default: return .generic      // unknown, or more than three: assume side buttons
        }
    }

    static func named(_ id: String) -> MouseProfile? { (all + fallbacks).first { $0.id == id } }

    // MARK: The direct link

    /// Controls every Logitech mouse reports (left, right, middle, back, forward, virtual gesture button).
    static let standardCIDs: Set<UInt16> = [0x0050, 0x0051, 0x0052, 0x0053, 0x0056, 0x00D7]

    /// Which of the controls a mouse reports over HID++ this profile captures, by slot.
    func captures(among reported: [HIDPP.Control]) -> [Slot: UInt16] {
        var found: [Slot: UInt16] = [:]
        let usable = reported.filter { $0.divertable && !$0.isVirtual }
        let ids = Set(usable.map { $0.cid })
        for control in controls {
            if let cid = control.cid, ids.contains(cid) { found[control.slot] = cid }
        }
        // A control that asked for it gets whichever capturable control is left once the known ones are accounted for.
        let known = MouseProfile.standardCIDs.union(controls.compactMap { $0.cid })
        if let orphan = controls.first(where: { $0.orAnyUnlistedControl && found[$0.slot] == nil }),
           let extra = usable.first(where: { !known.contains($0.cid) }) {
            found[orphan.slot] = extra.cid
        }
        return found
    }
}

import AppKit
import Foundation

// MARK: - Logging

enum Log {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("MouseHerdr.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int, size > 1_000_000 {
            try? FileManager.default.removeItem(at: u)
        }
        return u
    }()
    private static let queue = DispatchQueue(label: "mm.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    static func write(_ s: String) {
        let line = "\(fmt.string(from: Date())) \(s)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

// MARK: - Slots (things on a mouse you can assign; which ones a mouse has is in its MouseProfile)

enum Slot: String, CaseIterable, Codable, Identifiable {
    case middle, modeShift, gesture, forward, back, thumbPanel, thumbWheel
    case gestureUp, gestureDown, gestureLeft, gestureRight

    var id: String { rawValue }

    /// The parts of a control that has gestures; `.gesture` stands for its plain click.
    static let gestureParts: [Slot] = [.gesture] + swipes
    static let swipes: [Slot] = [.gestureUp, .gestureDown, .gestureLeft, .gestureRight]

    var isSwipe: Bool { Slot.swipes.contains(self) }

    /// Name of a hold-and-move direction. The controls themselves are named by the mouse's profile.
    var swipeTitle: String {
        switch self {
        case .gestureUp: return "Hold + move up"
        case .gestureDown: return "Hold + move down"
        case .gestureLeft: return "Hold + move left"
        case .gestureRight: return "Hold + move right"
        default: return ""
        }
    }

    /// Short label for the gesture tab strip.
    var partLabel: String {
        switch self {
        case .gestureUp: return "↑"
        case .gestureDown: return "↓"
        case .gestureLeft: return "←"
        case .gestureRight: return "→"
        default: return "Click"
        }
    }
}

// MARK: - Actions

struct Action: Codable, Equatable {
    var kind: String
    var keyCode: Int? = nil
    var modifiers: UInt? = nil
    var label: String? = nil
    var appPath: String? = nil

    static let standard = Action(kind: "default")
    static let nothing = Action(kind: "none")
    var isDefault: Bool { kind == "default" }
    var isNothing: Bool { kind == "none" }
    var isDrag: Bool { kind == "dragWindow" }
}

enum Effect {
    case passthrough
    case nothing
    case key(Int, NSEvent.ModifierFlags)
    case media(Int32)
    case dock(String)
    case middleClick
    case dragWindow
    case open(String)
}

struct Preset: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let effect: Effect
}

struct PresetGroup: Identifiable {
    let title: String
    let presets: [Preset]
    var id: String { title }
}

enum Catalog {
    static let appsPath: String = FileManager.default.fileExists(atPath: "/System/Applications/Apps.app")
        ? "/System/Applications/Apps.app" : "/System/Applications/Launchpad.app"

    static let groups: [PresetGroup] = [
        PresetGroup(title: "Agents", presets: [
            // Handled by AppState, which owns the wheel.
            Preset(id: "agentWheel", title: "Show the agent wheel", symbol: "circle.hexagongrid.fill", effect: .nothing),
        ]),
        PresetGroup(title: "Mouse", presets: [
            Preset(id: "default", title: "Mouse default", symbol: "computermouse", effect: .passthrough),
            Preset(id: "none", title: "Do nothing", symbol: "nosign", effect: .nothing),
            Preset(id: "middleClick", title: "Middle click", symbol: "circle.circle", effect: .middleClick),
            Preset(id: "dragWindow", title: "Drag the window", symbol: "arrow.up.and.down.and.arrow.left.and.right", effect: .dragWindow),
        ]),
        PresetGroup(title: "Navigate", presets: [
            Preset(id: "back", title: "Back", symbol: "chevron.backward", effect: .key(33, .command)),
            Preset(id: "forward", title: "Forward", symbol: "chevron.forward", effect: .key(30, .command)),
            Preset(id: "prevTab", title: "Previous tab", symbol: "arrow.left.square", effect: .key(48, [.control, .shift])),
            Preset(id: "nextTab", title: "Next tab", symbol: "arrow.right.square", effect: .key(48, .control)),
            Preset(id: "newTab", title: "New tab", symbol: "plus.square", effect: .key(17, .command)),
            Preset(id: "closeTab", title: "Close tab or window", symbol: "xmark.square", effect: .key(13, .command)),
            Preset(id: "reopenTab", title: "Reopen closed tab", symbol: "arrow.uturn.backward.square", effect: .key(17, [.command, .shift])),
        ]),
        PresetGroup(title: "Windows & desktops", presets: [
            Preset(id: "missionControl", title: "Mission Control", symbol: "rectangle.3.group", effect: .dock("com.apple.expose.awake")),
            Preset(id: "appExpose", title: "App windows", symbol: "macwindow.on.rectangle", effect: .dock("com.apple.expose.front.awake")),
            Preset(id: "showDesktop", title: "Show desktop", symbol: "menubar.dock.rectangle", effect: .dock("com.apple.showdesktop.awake")),
            Preset(id: "apps", title: "Show apps", symbol: "square.grid.3x3", effect: .open(appsPath)),
            Preset(id: "spaceLeft", title: "Desktop to the left", symbol: "arrow.left.to.line", effect: .key(123, .control)),
            Preset(id: "spaceRight", title: "Desktop to the right", symbol: "arrow.right.to.line", effect: .key(124, .control)),
            Preset(id: "switchApp", title: "Switch app", symbol: "square.on.square", effect: .key(48, .command)),
            Preset(id: "spotlight", title: "Spotlight", symbol: "magnifyingglass", effect: .key(49, .command)),
        ]),
        PresetGroup(title: "Edit", presets: [
            Preset(id: "copy", title: "Copy", symbol: "doc.on.doc", effect: .key(8, .command)),
            Preset(id: "paste", title: "Paste", symbol: "doc.on.clipboard", effect: .key(9, .command)),
            Preset(id: "cut", title: "Cut", symbol: "scissors", effect: .key(7, .command)),
            Preset(id: "undo", title: "Undo", symbol: "arrow.uturn.backward", effect: .key(6, .command)),
            Preset(id: "redo", title: "Redo", symbol: "arrow.uturn.forward", effect: .key(6, [.command, .shift])),
        ]),
        PresetGroup(title: "Media", presets: [
            Preset(id: "playPause", title: "Play / pause", symbol: "playpause", effect: .media(16)),
            Preset(id: "nextTrack", title: "Next track", symbol: "forward.end", effect: .media(17)),
            Preset(id: "prevTrack", title: "Previous track", symbol: "backward.end", effect: .media(18)),
            Preset(id: "volumeUp", title: "Volume up", symbol: "speaker.wave.3", effect: .media(0)),
            Preset(id: "volumeDown", title: "Volume down", symbol: "speaker.wave.1", effect: .media(1)),
            Preset(id: "mute", title: "Mute", symbol: "speaker.slash", effect: .media(7)),
        ]),
        PresetGroup(title: "System", presets: [
            Preset(id: "screenshot", title: "Screenshot an area", symbol: "camera.viewfinder", effect: .key(21, [.command, .shift])),
            Preset(id: "screenshotTools", title: "Screenshot tools", symbol: "camera", effect: .key(23, [.command, .shift])),
            Preset(id: "lock", title: "Lock screen", symbol: "lock", effect: .key(12, [.command, .control])),
        ]),
    ]

    /// What the thumb wheel can do when it is rolled.
    static let wheelModes: [Preset] = [
        Preset(id: "default", title: "Scroll sideways", symbol: "arrow.left.and.right", effect: .passthrough),
        Preset(id: "wheelVolume", title: "Volume", symbol: "speaker.wave.2", effect: .nothing),
        Preset(id: "wheelTabs", title: "Switch tabs", symbol: "square.on.square", effect: .nothing),
        Preset(id: "wheelZoom", title: "Zoom in and out", symbol: "plus.magnifyingglass", effect: .nothing),
        Preset(id: "wheelDesktops", title: "Switch desktops", symbol: "rectangle.split.3x1", effect: .nothing),
        Preset(id: "wheelUndo", title: "Undo and redo", symbol: "arrow.uturn.backward", effect: .nothing),
    ]

    static let byID: [String: Preset] = Dictionary(
        (groups.flatMap { $0.presets } + wheelModes).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func title(_ a: Action, slot: Slot) -> String {
        if slot == .thumbWheel { return wheelModes.first { $0.id == a.kind }?.title ?? "Scroll sideways" }
        return title(a)
    }

    static func symbol(_ a: Action, slot: Slot) -> String {
        if slot == .thumbWheel { return wheelModes.first { $0.id == a.kind }?.symbol ?? "arrow.left.and.right" }
        return symbol(a)
    }

    static func title(_ a: Action) -> String {
        switch a.kind {
        case "shortcut": return a.label ?? "Shortcut"
        case "app": return "Open " + appName(a.appPath)
        default: return byID[a.kind]?.title ?? "Mouse default"
        }
    }

    static func symbol(_ a: Action) -> String {
        switch a.kind {
        case "shortcut": return "keyboard"
        case "app": return "app.badge"
        default: return byID[a.kind]?.symbol ?? "computermouse"
        }
    }

    static func appName(_ path: String?) -> String {
        guard let path else { return "app" }
        return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    /// Human label for a recorded shortcut, e.g. "⌘⇧K".
    static func shortcutLabel(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String?) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        let special: [Int: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
            109: "F10", 103: "F11", 111: "F12",
        ]
        if let k = special[keyCode] { return s + k }
        return s + (characters?.uppercased() ?? "Key \(keyCode)")
    }
}

// MARK: - Saved settings

enum ConfigStore {
    /// Where MouseHerdr keeps what it is told.
    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseHerdr")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(shared)
        // Settings saved under the app's earlier name carry over.
        let legacy = dir.deletingLastPathComponent().appendingPathComponent("MightyMouse/config.json")
        if !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: file)
        }
        return dir
    }()

    /// The MX Master 4's file. It was the only one before other mice were recognised, so it keeps its name.
    private static let shared = "config.json"

    /// The file one mouse's choices are saved in.
    static func file(for profile: MouseProfile, in folder: URL = ConfigStore.folder) -> URL {
        profile.id == MouseProfile.mxMaster4.id
            ? folder.appendingPathComponent(shared)
            : folder.appendingPathComponent("mice").appendingPathComponent(profile.id + ".json")
    }

    private static func read(_ url: URL) -> [Slot: Action]? {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([String: Action].self, from: data) else { return nil }
        var out: [Slot: Action] = [:]
        for (k, v) in saved { if let slot = Slot(rawValue: k) { out[slot] = v } }
        return out
    }

    /// A mouse's saved choices on top of its own defaults.
    ///
    /// A mouse with nothing saved yet starts from what was changed on the MX Master 4, so a back
    /// button that was given another job keeps it on the next mouse. Choices that are only the
    /// MX Master 4's defaults are not carried over: the new mouse's own defaults win.
    static func load(for profile: MouseProfile, in folder: URL = ConfigStore.folder) -> [Slot: Action] {
        var result = profile.defaults
        if let own = read(file(for: profile, in: folder)) {
            for (slot, action) in own { result[slot] = action }
        } else if profile.id != MouseProfile.mxMaster4.id, let first = read(folder.appendingPathComponent(shared)) {
            let untouched = MouseProfile.mxMaster4.defaults
            for slot in profile.slots {
                if let action = first[slot], action != untouched[slot] ?? .standard { result[slot] = action }
            }
        }
        return result
    }

    /// Give a mouse a file of its own the first time it is followed, holding what it starts out
    /// with. From then on a change made on the MX Master 4 no longer reaches it, so what its
    /// owner was told about its buttons stays true.
    static func settle(_ profile: MouseProfile, in folder: URL = ConfigStore.folder) {
        guard profile.id != MouseProfile.mxMaster4.id,
              !FileManager.default.fileExists(atPath: file(for: profile, in: folder).path) else { return }
        save(load(for: profile, in: folder), for: profile, in: folder)
    }

    static func save(_ assignments: [Slot: Action], for profile: MouseProfile, in folder: URL = ConfigStore.folder) {
        let raw = Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value) })
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = file(for: profile, in: folder)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(raw).write(to: url, options: .atomic)
        } catch { Log.write("config save failed: \(error)") }
    }
}

/// What MouseHerdr remembers about the mice it has met, kept beside the button settings.
struct MouseMemory: Codable, Equatable {
    /// Models picked by hand, by device: "046d:c52b" → "m720".
    var chosen: [String: String] = [:]
    /// Devices that have been followed, and their owner told what opens the agent wheel on them.
    var introduced: [String] = []
    /// Devices that were offered while another mouse was being followed. They are not offered twice.
    var offered: [String] = []
    /// The device to follow when several are connected, if the person picked one.
    var pinned: String?
    /// The profile last in use. It is shown until a mouse is found again.
    var last: String?
    /// This Mac ran MouseHerdr when every mouse was taken for an MX Master 4. The mouse behind a
    /// Logi Bolt receiver, which can't say what it is, is still taken for one here.
    var boltCarriesMXMaster4 = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chosen = try c.decodeIfPresent([String: String].self, forKey: .chosen) ?? [:]
        introduced = try c.decodeIfPresent([String].self, forKey: .introduced) ?? []
        offered = try c.decodeIfPresent([String].self, forKey: .offered) ?? []
        pinned = try c.decodeIfPresent(String.self, forKey: .pinned)
        last = try c.decodeIfPresent(String.self, forKey: .last)
        boltCarriesMXMaster4 = try c.decodeIfPresent(Bool.self, forKey: .boltCarriesMXMaster4) ?? false
    }

    /// Whether anything has been remembered yet on this Mac.
    static func exists(in folder: URL = ConfigStore.folder) -> Bool {
        FileManager.default.fileExists(atPath: file(in: folder).path)
    }

    static func file(in folder: URL = ConfigStore.folder) -> URL { folder.appendingPathComponent("mice.json") }

    static func load(from folder: URL = ConfigStore.folder) -> MouseMemory {
        guard let data = try? Data(contentsOf: file(in: folder)),
              let memory = try? JSONDecoder().decode(MouseMemory.self, from: data) else { return MouseMemory() }
        return memory
    }

    func save(to folder: URL = ConfigStore.folder) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try enc.encode(self).write(to: MouseMemory.file(in: folder), options: .atomic)
        } catch { Log.write("mouse memory save failed: \(error)") }
    }

    /// This device has been followed before, so its owner knows what it does.
    func wasIntroduced(_ device: MouseDevice) -> Bool { introduced.contains(device.key) }

    /// This device has been pointed out before, one way or the other.
    func wasOffered(_ device: MouseDevice) -> Bool { offered.contains(device.key) || introduced.contains(device.key) }

    mutating func introduce(_ device: MouseDevice) {
        if !introduced.contains(device.key) { introduced = (introduced + [device.key]).sorted() }
    }

    mutating func offer(_ device: MouseDevice) {
        if !offered.contains(device.key) { offered = (offered + [device.key]).sorted() }
    }
}

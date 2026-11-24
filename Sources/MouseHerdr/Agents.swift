import AppKit
import SwiftUI

/// One coding agent running in herdr-core.
struct AgentInfo: Identifiable, Equatable {
    let id: String        // terminal address, e.g. "t7"
    let agent: String     // e.g. "claude-code"
    let status: String    // idle, working, done, blocked, error, or "" when unknown
    let space: String
    let tab: String
    var title = ""        // what the session is about
    var message = ""      // what the agent last said it wants (its question, for one that is waiting)
    var kind = ""         // question, permission, auth…
    var typeOption: Int?  // the number of the dialog's "Type something" choice, when it has one
    var hints: [Int: String] = [:]   // the explanation shown under each choice, by choice number (1-based)
    var screenOptions: [String] = [] // the numbered choices read off its dialog, in order
    var prompt = ""                  // the dialog's own question line, e.g. "Do you want to proceed?"
    var lastActive: Date?            // when it last changed what it is doing; nil until that is known
    var folder = ""                  // the folder it was started in
    var helpers = 0                  // how many terminals it started with `hc run` are busy right now
    var inner = 0                    // how many sub-agents it is running inside itself are busy right now

    /// For a request to approve an action: the tool it wants to use and exactly what it would do.
    var permission: (tool: String, detail: String)? {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let approve = text.lowercased().hasPrefix("approve ")
        guard kind == "permission" || approve else { return nil }
        if approve { text = String(text.dropFirst(8)) }
        // "Bash: rm -rf build" → the tool, then what it would run.
        if let colon = text.firstIndex(of: ":"), text[..<colon].count <= 24, !text[..<colon].contains(" ") {
            return (String(text[..<colon]), String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        return ("", text)
    }

    /// The agent's words, split into the question and any choices it offered.
    var speech: (text: String, options: [String]) { speech(full: false) }

    /// `full` keeps the whole question; otherwise it is shortened to a preview.
    func speech(full: Bool) -> (text: String, options: [String]) {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["answer:", "approve:", "permission:"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        var options: [String] = []
        let asksApproval = permission != nil
        // An approval shows exactly what would run; nothing in it is a list of choices.
        if let permission { text = permission.detail }
        // Choices arrive as a trailing "(A · B · C)"; find the bracket that closes at the very end.
        if !asksApproval, text.hasSuffix(")") {
            let chars = Array(text)
            var depth = 0, open: Int?
            for i in stride(from: chars.count - 1, through: 0, by: -1) {
                if chars[i] == ")" { depth += 1 }
                else if chars[i] == "(" { depth -= 1; if depth == 0 { open = i; break } }
            }
            if let open, open > 0 {
                let parts = String(chars[(open + 1)..<(chars.count - 1)]).components(separatedBy: " · ")
                if parts.count > 1 {
                    options = parts.prefix(4).map { $0.count > 44 ? String($0.prefix(43)) + "…" : $0 }
                    text = String(chars[..<open]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // "Do you want to proceed?" dialogs list their choices only on screen.
        if options.isEmpty {
            options = screenOptions.prefix(5).map { $0.count > 44 ? String($0.prefix(43)) + "…" : $0 }
        }
        let limit = full ? 1600 : 220
        if text.count > limit { text = String(text.prefix(limit - 1)) + "…" }
        return (text, options)
    }

    /// True when the preview leaves part of the question out.
    var isLongQuestion: Bool { speech(full: true).text.count > 220 }

    var hasSpeech: Bool { !message.isEmpty || !title.isEmpty }

    var needsYou: Bool { status == "blocked" || status == "error" }

    var statusWord: String {
        switch status {
        case "blocked": return "needs you"
        case "error": return "error"
        case "working": return "working"
        case "done": return "done"
        case "idle": return "idle"
        default: return "running"
        }
    }

    var color: Color {
        switch status {
        case "blocked": return Palette.accent
        case "error": return .red
        case "working": return Color(red: 0.35, green: 0.62, blue: 1.0)
        case "done": return Color(red: 0.30, green: 0.80, blue: 0.47)
        default: return Color(white: 0.6)
        }
    }

    /// How long a session can sit quiet before it starts to fade, when it has lost all its colour,
    /// and (much later) when its wedge is as small as it gets.
    static let freshFor: TimeInterval = 5 * 60
    static let greyAfter: TimeInterval = 8 * 3600
    static let smallAfter: TimeInterval = 7 * 86400

    /// 1 for a session that is busy, waiting on you or only just went quiet, falling to 0 the longer
    /// it is left alone. It falls fast at first and slowly later, so minutes and hours both show.
    func freshness(now: Date = Date()) -> Double {
        if needsYou || status == "working" { return 1 }
        guard let lastActive else { return 1 }   // not known yet, so don't guess
        let quiet = now.timeIntervalSince(lastActive)
        if quiet <= Self.freshFor { return 1 }
        if quiet >= Self.greyAfter { return 0 }
        return 1 - log(quiet / Self.freshFor) / log(Self.greyAfter / Self.freshFor)
    }

    /// How big its wedge is: 1 is the size of a busy agent's, 0 the smallest. One that has
    /// finished and not been looked at starts at full size and gives it up slowly, over days. One
    /// that is idle is small at once, so the agents with something going on stand out.
    func size(now: Date = Date()) -> Double {
        if needsYou || status == "working" { return 1 }
        let most = status == "done" ? 1 : Self.idleSize
        guard let lastActive else { return most }
        let quiet = now.timeIntervalSince(lastActive)
        if quiet <= 0 { return most }
        if quiet >= Self.smallAfter { return 0 }
        return min(most, 1 - pow(quiet / Self.smallAfter, 0.7))
    }

    /// The most an idle agent's wedge is given, on the same scale.
    static let idleSize = 0.25

    /// How long ago it last did something, in a few characters. Nil while it is busy or waiting
    /// on you (that is happening now) and before the time is known.
    func ago(now: Date = Date()) -> String? {
        if needsYou || status == "working" { return nil }
        guard let lastActive else { return nil }
        return Self.short(now.timeIntervalSince(lastActive)).map { "\($0) ago" } ?? "just now"
    }

    /// How long a busy agent has been at its current turn, such as "5m"; nil for the first minute.
    func busyFor(now: Date = Date()) -> String? {
        guard status == "working", let lastActive else { return nil }
        return Self.short(now.timeIntervalSince(lastActive))
    }

    /// A length of time in a few characters: "5m", "3h", "2d". Nil for under a minute.
    static func short(_ seconds: TimeInterval) -> String? {
        if seconds < 60 { return nil }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }

    /// The status colour, washed out to plain grey as the session goes quiet.
    func color(freshness: Double) -> Color {
        guard freshness < 1 else { return color }
        let grey = NSColor(srgbRed: 0.44, green: 0.44, blue: 0.44, alpha: 1)
        let mixed = NSColor(color).usingColorSpace(.sRGB)?.blended(withFraction: CGFloat(1 - max(0, freshness)), of: grey)
        return Color(nsColor: mixed ?? grey)
    }

    /// Every sub-agent it has busy, of either kind herdr-core knows about.
    var subAgents: Int { helpers + inner }

    /// What tells this session from the others in its space: what it is about, or else its tab.
    var sessionName: String {
        if !title.isEmpty { return title }
        if tab.isEmpty { return agent }
        return Int(tab) != nil ? "Tab \(tab)" : tab
    }

    /// Lower sorts first: the ones that want attention, then finished, then busy.
    var rank: Int {
        switch status {
        case "blocked": return 0
        case "error": return 1
        case "done": return 2
        case "working": return 3
        default: return 4
        }
    }
}

/// Whether herdr-core, the thing that knows about the agents, can be reached.
/// Herdr is optional, so every state here is a normal one to be in.
enum HerdrStatus: Equatable {
    case unknown                // not asked yet
    case notInstalled           // no `hc` command on this Mac
    case notRunning             // `hc` is there, but it failed, timed out or made no sense
    case running(agents: Int)   // answered; the count may be zero

    /// A short description for the settings window and the log.
    var summary: String {
        switch self {
        case .unknown: return "checking…"
        case .notInstalled: return "not installed"
        case .notRunning: return "installed, but not running"
        case .running(let n): return n == 0 ? "running, no agents" : "running, \(n) agent\(n == 1 ? "" : "s")"
        }
    }

    var isRunning: Bool { if case .running = self { return true }; return false }

    /// Developer aid: the names the snapshot modes accept after `--state`.
    init?(flag: String) {
        switch flag {
        case "not-installed": self = .notInstalled
        case "not-running": self = .notRunning
        case "empty": self = .running(agents: 0)
        case "unknown": self = .unknown
        default: return nil
        }
    }
}

/// Reads agent state from herdr-core (`hc`) and asks the Herdr app to show one.
final class AgentWatcher {
    private let queue = DispatchQueue(label: "mm.agents", qos: .userInitiated)
    /// Answers and jumps go on their own queue so a slow listing can't hold them up. It runs them
    /// side by side: herdr-core can hold an answer back for a long time (see `sendTimeout`), and
    /// a jump, or an answer to another agent, must not wait behind it.
    private let actions = DispatchQueue(label: "mm.agents.actions", qos: .userInitiated, attributes: .concurrent)
    private static let shells: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "pwsh", "powershell", "dash", "ksh", "tcsh"]
    private(set) var latest: [AgentInfo] = []
    /// What the last fetch found out about Herdr itself. Read on the main thread.
    private(set) var status = HerdrStatus.unknown
    /// Jumping to an agent needs the Herdr app; viewing and answering do not.
    private(set) var appInstalled = true
    /// Developer aid: snapshots pin the state so a real fetch can't change the picture.
    var pinned: (status: HerdrStatus, app: Bool)? {
        didSet { if let pinned { status = pinned.status; appInstalled = pinned.app } }
    }

    static let appBundleID = "dev.herdr.app"
    /// How long any one `hc` or `herdr-app` call may take before it is given up on.
    static let timeout: TimeInterval = 4
    /// An answer is waited for far longer than a look, because herdr-core holds it back on
    /// purpose: it presses keys only once the terminal has had about 3 seconds with no input from
    /// a person. Pointer movement over the agent's pane is such input when the agent has asked its
    /// terminal to report it, as Claude Code does, so a key can be held for as long as the pointer
    /// keeps moving there.
    ///
    /// Giving up does not take the answer back. herdr-core keeps the key and presses it once the
    /// terminal goes quiet, whether or not whoever asked is still there. So this is only how long
    /// MouseHerdr waits to hear what became of an answer, and it waits as long as it sensibly can:
    /// until it hears, it must not say the answer was sent, nor that it was not, nor send another.
    static let keysTimeout: TimeInterval = 120
    /// Typed text waits for a person to send or clear a draft they left in that terminal, for up
    /// to 60 seconds after their last key.
    static let sendTimeout: TimeInterval = 70

    /// What became of an answer.
    enum Delivery: Equatable {
        /// herdr-core pressed the key. `late` is true when the agent had stopped waiting by then,
        /// so the key went to whatever it was showing instead of to the question.
        case delivered(late: Bool)
        /// It did not go: `hc` is missing, or herdr-core said no.
        case failed
        /// MouseHerdr stopped waiting. herdr-core still has the key, and presses it once the
        /// terminal has been left alone.
        case stillHeld
        /// Not sent, because the answer before it is still on its way to this agent.
        case refused
    }

    /// How a command went.
    enum Ran: Equatable {
        /// It finished, and printed this.
        case output(Data)
        /// It could not be started, or finished saying that it had failed.
        case failed
        /// It was still going when its time ran out.
        case gaveUp
    }

    static func tool(_ name: String) -> String? {
        // Developer aid: MOUSEHERDR_HC / MOUSEHERDR_HERDR_APP name the exact file to use
        // (or one that doesn't exist), to try out the "not installed" and "not running" cases.
        let key = "MOUSEHERDR_" + name.uppercased().replacingOccurrences(of: "-", with: "_")
        if let forced = ProcessInfo.processInfo.environment[key] {
            return FileManager.default.isExecutableFile(atPath: forced) ? forced : nil
        }
        let home = NSHomeDirectory()
        for dir in ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.cargo/bin"] {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// True when the Herdr app can be asked to show an agent: its command or the app itself is here.
    static func herdrAppInstalled() -> Bool {
        if tool("herdr-app") != nil { return true }
        // The override above also hides the app, so "no Herdr app" can be tried on a Mac that has it.
        if ProcessInfo.processInfo.environment["MOUSEHERDR_HERDR_APP"] != nil { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) != nil
    }

    /// Run a command and return what it printed, or nil if it failed or took too long.
    /// Never call this on the main thread.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = AgentWatcher.timeout) -> Data? {
        if case .output(let data) = launch(path, args, timeout: timeout) { return data }
        return nil
    }

    /// Run a command and say how it went: what it printed, that it failed, or that it was given
    /// up on. Never call this on the main thread.
    static func launch(_ path: String, _ args: [String], timeout: TimeInterval = AgentWatcher.timeout) -> Ran {
        final class Box { var data = Data() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            Log.write("agents: could not start \(path): \(error.localizedDescription)")
            return .failed
        }
        // Read on another thread so a command that never finishes can't keep us waiting.
        let box = Box(), finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            finished.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var ended = finished.wait(timeout: .now() + timeout) == .success
        // It may have closed its output and still be going.
        while ended && p.isRunning { if Date() > deadline { ended = false } else { usleep(20_000) } }
        guard ended else {
            p.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            let name = ([(path as NSString).lastPathComponent] + args.prefix(2)).joined(separator: " ")
            Log.write("agents: \(name) did not answer within \(Int(timeout)) seconds; gave up")
            return .gaveUp
        }
        return p.terminationStatus == 0 ? .output(box.data) : .failed
    }

    static func parse(_ data: Data) -> [AgentInfo] { parseList(data) ?? [] }

    /// The agents in `hc ls --json` output, or nil when that isn't what the data is.
    static func parseList(_ data: Data) -> [AgentInfo]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let terms = root["terminals"] as? [[String: Any]] else { return nil }
        var found: [(agent: AgentInfo, parent: String?)] = []
        for t in terms {
            guard let id = t["address"] as? String else { continue }
            let agent = t["agent"] as? String ?? ""
            let status = t["status"] as? String ?? ""
            // Plain shells aren't agents unless they report a status.
            if status.isEmpty && (agent.isEmpty || shells.contains(agent)) { continue }
            let place = (t["where"] as? String ?? "").components(separatedBy: " / ")
            var info = AgentInfo(id: id, agent: agent, status: status,
                                 space: place.first ?? agent, tab: place.count > 1 ? place[1] : "")
            info.folder = t["cwd"] as? String ?? ""
            found.append((info, t["parent"] as? String))
        }
        // A sub-agent is a terminal an agent started with `hc run`; herdr-core names the starter as
        // its parent. It belongs to that agent, so it is counted there while it is busy and gets
        // no wedge of its own, unless it is waiting on you, which has to be seen.
        let ids = Set(found.map { $0.agent.id })
        var helpers: [String: Int] = [:]
        var out: [AgentInfo] = []
        for (agent, parent) in found {
            guard let parent, ids.contains(parent) else { out.append(agent); continue }
            if agent.status != "done", agent.status != "idle" { helpers[parent, default: 0] += 1 }
            if agent.needsYou { out.append(agent) }
        }
        for i in out.indices { out[i].helpers = helpers[out[i].id] ?? 0 }
        return out.sorted { ($0.rank, $0.space, $0.tab) < ($1.rank, $1.space, $1.tab) }
    }

    /// Read a dialog off the agent's screen: its numbered choices, the explanation under each,
    /// its own question line, and the number of its "Type something" choice if it has one.
    static func parseDialog(_ screen: String) -> (hints: [Int: String], typeOption: Int?, options: [String], prompt: String) {
        func trimmed(_ l: String) -> String { l.trimmingCharacters(in: .whitespaces) }
        func isRule(_ t: String) -> Bool { t.hasPrefix("─") || t.hasPrefix("╌") }
        func isFooter(_ t: String) -> Bool { t.hasPrefix("Enter to") || t.hasPrefix("Esc to") || t.hasPrefix("[hc]") }
        var lines = screen.components(separatedBy: "\n")
        // The conversation above the dialog can contain numbered lists of its own. The selection
        // marker ("❯ 1.") is only in the dialog, so keep just the block of lines around it.
        if let marker = lines.lastIndex(where: { $0.range(of: #"❯\s*\d{1,2}\.\s"#, options: .regularExpression) != nil }) {
            var first = marker, last = marker
            while first > 0 {
                let t = trimmed(lines[first - 1])
                if t.isEmpty || isRule(t) { break }
                first -= 1
            }
            while last < lines.count - 1 {
                let t = trimmed(lines[last + 1])
                if t.isEmpty || isRule(t) || isFooter(t) { break }
                last += 1
            }
            lines = Array(lines[first...last])
        }

        var hints: [Int: String] = [:]
        var labels: [Int: String] = [:]
        var typeOption: Int?
        var current: Int?
        var promptLines: [String] = []
        for raw in lines {
            let line = trimmed(raw)
            if isRule(line) || isFooter(line) { current = nil; continue }
            var body = line
            if body.hasPrefix("❯") { body = trimmed(String(body.dropFirst())) }
            let digits = body.prefix { $0.isNumber }
            if !digits.isEmpty, digits.count <= 2, body.dropFirst(digits.count).hasPrefix(". "), let n = Int(digits) {
                let label = String(body.dropFirst(digits.count + 2))
                if label.lowercased().hasPrefix("type something") { typeOption = n; current = nil }
                else { labels[n] = label; current = n }
                continue
            }
            if labels.isEmpty, typeOption == nil, !line.isEmpty { promptLines.append(line) }
            guard let n = current, !line.isEmpty, raw.hasPrefix("   ") else {
                if line.isEmpty { current = nil }
                continue
            }
            hints[n] = (hints[n].map { $0 + " " } ?? "") + line
        }
        // Choices are numbered 1, 2, 3… with no gaps; stop at the first gap.
        var options: [String] = []
        while let label = labels[options.count + 1] { options.append(label) }
        return (hints, typeOption, options, promptLines.last ?? "")
    }

    /// When a terminal last changed what it is doing, from its `hc get` answer.
    static func lastActive(_ obj: [String: Any]) -> Date? {
        guard let ms = (obj["status_ms"] as? NSNumber)?.doubleValue, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// How many sub-agents the agent runs inside itself are busy, from its `hc get` answer.
    /// herdr-core lists those under "records", each with its own state; they are not terminals.
    static func busyRecords(_ obj: [String: Any]) -> Int {
        guard let records = obj["records"] as? [String: Any] else { return 0 }
        return records.values.filter {
            let state = ($0 as? [String: Any])?["state"] as? String
            return state == "working" || state == "blocked"
        }.count
    }

    /// A plain listing doesn't say what a session is about or when it was last active, so keep
    /// what the last full look found. A status that has changed since then changed just now.
    ///
    /// An agent that is still waiting keeps the question it was last seen asking, so that the
    /// wheel can show it the moment it opens. It may have moved on to another question without
    /// its status changing, which is why the wheel looks again before it lets one be answered.
    /// `fresh` names the agents this look has just read in full; they are left as they are.
    static func carry(from old: [AgentInfo], into new: [AgentInfo], fresh: Set<String> = [], now: Date = Date()) -> [AgentInfo] {
        let known = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return new.map { a in
            guard !fresh.contains(a.id), let before = known[a.id] else { return a }
            var a = a
            a.title = before.title
            a.inner = before.inner
            a.lastActive = before.status == a.status ? before.lastActive : now
            if before.status == a.status {
                a.message = before.message
                a.kind = before.kind
                a.prompt = before.prompt
                a.screenOptions = before.screenOptions
                a.hints = before.hints
                a.typeOption = before.typeOption
            }
            return a
        }
    }

    /// How much to find out about each agent beyond the plain listing.
    enum Detail {
        /// The listing only: who is there and in what state.
        case none
        /// Also what the agents that are waiting on you are asking, read no more often than `questionAge`.
        case waiting
        /// Also what every agent is about and saying.
        case all
    }

    /// How old a waiting agent's question may be before the background look reads it again.
    static let questionAge: TimeInterval = 12

    /// Fill in what the agents picked by `wanted` are saying (title and question) from `hc get`.
    /// `read` comes back with the agents that answered. One that did not is left as the listing
    /// has it, and whoever asked keeps what was known about it rather than showing it blank.
    private static func addDetails(_ list: [AgentInfo], hc: String, wanted: (AgentInfo) -> Bool = { _ in true })
        -> (agents: [AgentInfo], read: Set<String>) {
        var out = list
        var read: Set<String> = []
        let lock = NSLock()
        let picked = list.map(wanted)
        DispatchQueue.concurrentPerform(iterations: list.count) { i in
            guard picked[i] else { return }
            guard let data = run(hc, ["get", list[i].id, "--json"]),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let status = obj["status"] as? [String: Any]
            // A waiting agent's dialog may also offer a free-text choice; find its number on the screen.
            var dialog = parseDialog("")
            if list[i].needsYou, let screen = run(hc, ["read", list[i].id]), let text = String(data: screen, encoding: .utf8) {
                dialog = parseDialog(text)
                // A choice too long for its button is shown in full when it is pointed at.
                for (n, label) in dialog.options.enumerated() where label.count > 44 && dialog.hints[n + 1] == nil {
                    dialog.hints[n + 1] = label
                }
            }
            lock.lock()
            out[i].typeOption = dialog.typeOption
            out[i].hints = dialog.hints
            out[i].screenOptions = dialog.options
            out[i].prompt = dialog.prompt
            out[i].title = obj["title"] as? String ?? ""
            out[i].message = status?["msg"] as? String ?? ""
            out[i].kind = status?["kind"] as? String ?? ""
            out[i].lastActive = lastActive(obj)
            out[i].inner = busyRecords(obj)
            read.insert(list[i].id)
            lock.unlock()
        }
        return (out, read)
    }

    /// Ask herdr-core what is running. Works out the state of Herdr from how the call went,
    /// so a missing, stopped or stuck herdr-core each come back as an answer rather than a failure.
    /// `stale` says, for an agent that is waiting, whether its question is due to be read again;
    /// it only matters for `.waiting`. `read` comes back with the agents that were read in full.
    static func look(details: Detail, stale: (AgentInfo) -> Bool = { _ in true })
        -> (status: HerdrStatus, agents: [AgentInfo], read: Set<String>) {
        guard let hc = tool("hc") else { return (.notInstalled, [], []) }
        // A failed, slow or garbled listing all mean the same to the person: it isn't answering.
        guard let data = run(hc, ["ls", "--json"]), var list = parseList(data) else { return (.notRunning, [], []) }
        var read: Set<String> = []
        switch details {
        case .none: break
        case .waiting:
            let due = Set(list.filter { $0.needsYou && stale($0) }.map(\.id))
            if !due.isEmpty { (list, read) = addDetails(list, hc: hc) { due.contains($0.id) } }
        case .all:
            (list, read) = addDetails(list, hc: hc)
        }
        return (.running(agents: list.count), list, read)
    }

    /// When each waiting agent's question was last read, so that the background look reads it
    /// again only now and then. Used on the main thread.
    private var questionRead: [String: Date] = [:]

    /// Fetch the current agents; the result arrives on the main thread, with `status` and
    /// `appInstalled` brought up to date first. Call it on the main thread.
    func fetch(details: Detail = .none, _ done: @escaping ([AgentInfo]) -> Void) {
        let lastRead = questionRead, asked = Date()
        queue.async {
            let found = Self.look(details: details) { agent in
                lastRead[agent.id].map { asked.timeIntervalSince($0) >= Self.questionAge } ?? true
            }
            let app = Self.herdrAppInstalled()
            DispatchQueue.main.async {
                if self.pinned == nil {
                    if found.status.summary != self.status.summary, !(found.status.isRunning && self.status.isRunning) {
                        Log.write("agents: herdr-core \(found.status.summary)")
                    }
                    if app != self.appInstalled { Log.write("agents: Herdr app \(app ? "found" : "not installed")") }
                    self.status = found.status
                    self.appInstalled = app
                    self.latest = Self.carry(from: self.latest, into: found.agents, fresh: found.read)
                    // Note whose question was just read, and forget those who are no longer waiting:
                    // the next time they ask, it is read at once.
                    for id in found.read { self.questionRead[id] = asked }
                    let waiting = Set(found.agents.filter(\.needsYou).map(\.id))
                    self.questionRead = self.questionRead.filter { waiting.contains($0.key) }
                }
                done(self.latest)
            }
        }
    }

    /// The agents with an answer on its way, and which of their choices it is (counted from 0),
    /// by id. Main thread only.
    private(set) var answering: [String: Int] = [:]

    /// True if an answer to this agent may go now. While herdr-core is still holding the last
    /// one, another would be delivered right after it and land on whatever the agent asks next.
    private func beginAnswer(_ agent: AgentInfo, option: Int) -> Bool {
        guard answering[agent.id] == nil else {
            Log.write("agents: the last answer to \(agent.id) is still on its way; this one was not sent")
            return false
        }
        answering[agent.id] = option
        return true
    }

    /// The answer is no longer on its way; tell whoever sent it what became of it.
    private func endAnswer(_ agent: AgentInfo, _ outcome: Delivery, _ done: ((Delivery) -> Void)?) {
        DispatchQueue.main.async {
            self.answering[agent.id] = nil
            done?(outcome)
        }
    }

    /// What became of a key, going by how `hc keys` went.
    ///
    /// When it finishes, herdr-core has pressed the key, and it names the agent's status at that
    /// moment: an agent that was no longer waiting on a person by then did not get the key as an
    /// answer to its question. When it is given up on, the key has not been pressed and has not
    /// been dropped either: herdr-core presses it once the terminal goes quiet.
    static func delivery(of ran: Ran) -> Delivery {
        switch ran {
        case .output(let data):
            let status = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
            return .delivered(late: status != "blocked" && status != "error")
        case .failed:
            return .failed
        case .gaveUp:
            return .stillHeld
        }
    }

    /// Press one key in the agent's terminal and wait to hear what became of it.
    /// Never call this on the main thread.
    static func press(_ key: String, in agent: AgentInfo, timeout: TimeInterval = AgentWatcher.keysTimeout) -> Delivery {
        guard let hc = tool("hc") else {
            Log.write("agents: can't answer, hc is not installed")
            return .failed
        }
        let asked = Date()
        let outcome = delivery(of: launch(hc, ["keys", agent.id, key], timeout: timeout))
        switch outcome {
        case .delivered(let late):
            let waited = Date().timeIntervalSince(asked)
            if waited >= 1 {
                Log.write(String(format: "agents: herdr-core held the answer to \(agent.id) for %.1f seconds before pressing it", waited))
            }
            if late { Log.write("agents: the answer to \(agent.id) went in after it had stopped asking") }
        case .failed:
            Log.write("agents: hc keys failed; the answer was not sent")
        case .stillHeld:
            // Not "not sent": it will still be pressed, and may land on whatever is asked by then.
            Log.write("agents: herdr-core still holds the answer to \(agent.id), and presses it once that terminal has been left alone")
        case .refused:
            break
        }
        return outcome
    }

    /// Answer the agent's question by pressing the number of the chosen option in its terminal.
    /// `done` is told what became of the answer, on the main thread: at once if it could not be
    /// sent, and otherwise only when herdr-core has pressed the key, which can be seconds later.
    /// Call it on the main thread.
    func answer(_ agent: AgentInfo, option: Int, then done: ((Delivery) -> Void)? = nil) {
        guard beginAnswer(agent, option: option) else { done?(.refused); return }
        Log.write("agents: answering \(agent.id) with option \(option + 1)")
        actions.async {
            self.endAnswer(agent, Self.press("\(option + 1)", in: agent), done)
        }
    }

    /// Answer in the person's own words: pick the dialog's free-text choice, then type the text.
    func answer(_ agent: AgentInfo, typed text: String, then done: ((Delivery) -> Void)? = nil) {
        guard let number = agent.typeOption else {
            Log.write("agents: can't type an answer to \(agent.id), its question has no free-text choice")
            done?(.failed)
            return
        }
        guard beginAnswer(agent, option: number - 1) else { done?(.refused); return }
        Log.write("agents: answering \(agent.id) with typed text (\(text.count) characters)")
        actions.async {
            var outcome = Self.press("\(number)", in: agent)
            // The text goes only into the box that the free-text choice opens. If that choice did
            // not go in as an answer, there is no box, and the text would be typed somewhere else.
            if outcome == .delivered(late: false), let hc = Self.tool("hc") {
                Thread.sleep(forTimeInterval: 0.7)
                switch Self.launch(hc, ["send", "--force", agent.id, text], timeout: Self.sendTimeout) {
                case .output:
                    break
                case .failed, .gaveUp:
                    // Unlike a key, text whose sender has gone is dropped by herdr-core, so giving
                    // up on it does mean it was not typed.
                    Log.write("agents: hc send failed; the answer was not sent")
                    outcome = .failed
                }
            } else if outcome == .delivered(late: true) {
                Log.write("agents: \(agent.id) had stopped asking, so the typed answer was not sent")
            }
            self.endAnswer(agent, outcome, done)
        }
    }

    /// Bring this agent's terminal to the front in the Herdr app.
    func focus(_ agent: AgentInfo) {
        Log.write("agents: focusing \(agent.id) (\(agent.space) / \(agent.tab))")
        actions.async {
            guard Self.herdrAppInstalled() else {
                Log.write("agents: can't jump to \(agent.id), the Herdr app is not installed")
                return
            }
            if let app = Self.tool("herdr-app") {
                let ok = Self.run(app, ["do", "agent.focus", "{\"terminal\":\"\(agent.id)\"}"]) != nil
                if !ok { Log.write("agents: herdr-app agent.focus failed") }
            } else {
                Log.write("agents: no herdr-app command, so Herdr opens without picking the agent")
            }
            // Bring the Herdr window forward. Going through Launch Services works even though
            // MouseHerdr itself is a background app; a plain activate() request gets ignored.
            DispatchQueue.main.async {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.appBundleID) else {
                    Log.write("agents: Herdr app not found")
                    return
                }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                    if let error { Log.write("agents: could not bring Herdr forward: \(error.localizedDescription)") }
                    else {
                        DispatchQueue.main.async {
                            app?.activate(options: [.activateAllWindows])
                            if let w = app, w.isHidden { w.unhide() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - The ring

/// How the wedges are put in order around the wheel.
enum RingOrder: String, CaseIterable {
    case recent   // whoever was active last comes first
    case space    // by space name: every agent keeps its place, and a space's sessions sit together
}

final class RingModel: ObservableObject {
    /// One wedge of the wheel. Angles are radians, 0 pointing right, growing clockwise on screen.
    /// `start`, `end` and `outer` are its size at rest; a quiet agent's wedge rests smaller.
    struct Slice: Identifiable {
        let agent: AgentInfo
        let start: Double
        let end: Double
        let inner: CGFloat
        let outer: CGFloat
        /// 1 for an agent that was just active, down to 0 for one long quiet.
        var fresh = 1.0
        /// "5m ago", "3d ago"… for an agent that has gone quiet.
        var ago: String?
        /// "5m", "2h"… for how long a busy agent has been at its current turn.
        var busyFor: String?
        /// Pinned by the person: it stays near the front, at full size and colour.
        var pinned = false
        /// Another session of the same space is on the wheel but there is no band to say so,
        /// so the wedge also says what this session is about.
        var sibling = false
        /// How much each side and the rim grow while the wedge is pointed at, back to full size.
        var widen = 0.0
        var raise: CGFloat = 0
        /// The wedge on that side is another session of the same space.
        var joinsPrevious = false
        var joinsNext = false
        /// One or two words that tell this agent from the others; never cut short.
        var name = ""
        /// Which project it belongs to, counted from 0, for its color; nil for one in none.
        var project: Int?
        /// This wedge stands for the idle agents, and how many: pointing at it shows them.
        var folded = 0
        var id: String { agent.id }
        var mid: Double { (start + end) / 2 }
        var inFamily: Bool { joinsPrevious || joinsNext }
        /// The rim while pointed at.
        var reach: CGFloat { outer + raise }
    }

    /// The name of a space, written once over its sessions when several sit side by side.
    struct Band: Identifiable, Equatable {
        let id: String
        let name: String
        let start: Double
        let end: Double
        let radius: CGFloat      // at rest
        let members: [String]
        /// How far outside its wedges the middle of the band runs.
        static let lift: CGFloat = 14
    }

    /// What the wheel says in its middle when it has no agents to show.
    struct Notice: Equatable {
        var symbol: String
        var title: String
        var detail: String
        var tint = Color(white: 0.75)

        static let notInstalled = Notice(
            symbol: "shippingbox", title: "Herdr isn't installed",
            detail: "This wheel shows the coding agents you run with Herdr. Get it at herdr.dev.\nTo stop this tap, see the Agents page.")
        static let notRunning = Notice(
            symbol: "moon.zzz.fill", title: "herdr-core isn't running",
            detail: "It is installed but didn't answer. Start it with “hc\u{00A0}server\u{00A0}start” and your agents will appear here.",
            tint: Palette.accent)
        static let empty = Notice(
            symbol: "circle.dashed", title: "No agents found",
            detail: "herdr-core is running, but there are no coding agents in it right now.",
            tint: Color(red: 0.30, green: 0.80, blue: 0.47))
        static let noApp = Notice(
            symbol: "macwindow.badge.plus", title: "No Herdr app installed",
            detail: "Jumping to an agent needs the Herdr app from herdr.dev. Reading and answering here still work.",
            tint: Palette.accent)
    }

    @Published var slices: [Slice] = []
    @Published var bands: [Band] = []
    var order = RingOrder.recent
    /// The agents the person has pinned, by terminal address.
    var pinned: Set<String> = []
    @Published var notice: Notice?
    /// True until Herdr has answered for the first time; the hub says it is looking.
    @Published var looking = false
    /// False when the Herdr app is missing, so a wedge can't be jumped to.
    @Published var canJump = true
    var herdr = HerdrStatus.unknown
    /// A notice that stays until the wheel closes, whatever new data says.
    var heldNotice = false
    @Published var highlighted: String?
    /// The idle agents each have a wedge. Until then they share one, so that the agents with
    /// something going on have the wheel to themselves.
    @Published var unfolded = false
    /// The id of the wedge that stands for the idle agents.
    static let foldID = "+idle"
    /// Fewer idle agents than this are shown as they are.
    static let foldFrom = 2
    /// The agent the hub in the middle stands for, so that it can be reached without moving the
    /// pointer, which rests on the hub as the wheel opens: the agent that most recently started
    /// waiting on you or, when nobody is, the one that was active last.
    @Published var centre: String?
    /// Whether the hub's agent was waiting when it was picked. See `layout`.
    private var centreWaiting = false
    /// The pointer is on the hub.
    @Published var onHub = false
    /// False while the wheel is off screen, so its animations stop costing anything.
    @Published var active = true
    /// Where the speech bubble for the highlighted agent sits, relative to the wheel's centre.
    @Published var bubble: Bubble?

    struct Bubble: Equatable {
        var offset: CGSize
        var size: CGSize
        var toward: CGSize     // unit vector from the bubble to the agent it belongs to
        var textHeight: CGFloat
        var optionCount: Int
        var expanded = false   // showing the whole question rather than a preview
        var hintOnLeft = false // which side of the bubble has room for a choice's explanation
    }

    /// Which answer button the pointer is over, and which one was picked.
    @Published var hoveredOption: Int?
    @Published var sentOption: Int?
    /// What became of the answer that was picked; nil while it is on its way. herdr-core presses
    /// the key only once the agent's terminal has been left alone for a few seconds, so an answer
    /// can be picked seconds before the agent gets it. The bubble says it was sent only once it was.
    @Published var delivery: AgentWatcher.Delivery?
    /// The answer has been on its way for long enough that herdr-core must be holding it back.
    @Published var held = false
    /// The wheel was asked to close while an answer was on its way; it goes once that is in.
    @Published var leaving = false
    /// The agents have been looked at since the wheel opened. Until then a question on show is
    /// the one last seen, which the agent may have moved on from, so it can be read but not
    /// answered: an answer is sent as a key press, and it must land on the question that is shown.
    @Published var confirmed = false
    /// An answer can be sent now: the question is the current one and no answer is on its way.
    /// Another sent while one is on its way would be pressed right after it, on whatever the
    /// agent asks next. One that could not be sent can be tried again.
    var canAnswer: Bool { confirmed && (sentOption == nil || delivery == .failed) }

    /// How long an answer is on its way before the bubble says that it is being held back.
    static let heldAfter: TimeInterval = 1.2

    /// How the button of one of the choices looks.
    enum ButtonState: Equatable {
        case resting
        /// Picked, and on its way: herdr-core has not pressed the key yet.
        case sending
        /// herdr-core pressed the key.
        case sent
        /// It could not be sent.
        case failed
    }

    func buttonState(_ option: Int) -> ButtonState {
        guard sentOption == option else { return .resting }
        switch delivery {
        case nil, .stillHeld, .refused: return .sending
        case .delivered: return .sent
        case .failed: return .failed
        }
    }

    /// What the bubble says about the answer that was picked, or nil when none was.
    var answerNote: String? {
        guard sentOption != nil else { return nil }
        switch delivery {
        case nil, .refused:
            if leaving { return "Sending… the wheel closes once it has gone in" }
            return held ? "herdr-core sends it once that terminal has been quiet for 3 s…" : "Sending…"
        case .delivered(let late):
            return late ? "Sent, but the agent had already moved on" : "Sent — waiting for the agent…"
        case .failed:
            return "Could not send it — click an answer to try again"
        case .stillHeld:
            return "Still held by herdr-core until that terminal is quiet"
        }
    }

    // Bubble layout, shared by drawing and hit-testing.
    static let bubbleWidth: CGFloat = 400
    static let pad: CGFloat = 16
    static let headerHeight: CGFloat = 16
    static let optionHeight: CGFloat = 44
    static let optionGap: CGFloat = 8
    static let hintHeight: CGFloat = 20

    static func bubbleMetrics(for a: AgentInfo, expanded: Bool = false) -> (size: CGSize, textHeight: CGFloat, options: Int) {
        let speech = a.speech(full: expanded)
        let body = speech.text.isEmpty ? a.title : speech.text
        // Measure the text the same way it will be drawn.
        let base = NSFont.systemFont(ofSize: 14, weight: .medium)
        let font = a.permission != nil
            ? NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)   // a command is shown as typed
            : base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 14) } ?? base
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        let box = (body as NSString).boundingRect(
            with: CGSize(width: bubbleWidth - 2 * pad, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: para])
        let textHeight = min(ceil(box.height) + 4, expanded ? 620 : 190)
        let n = a.needsYou ? speech.options.count + (a.typeOption != nil ? 1 : 0) : 0
        var h = pad + headerHeight + 6 + textHeight + pad
        if n > 0 { h += 12 + CGFloat(n) * optionHeight + CGFloat(n - 1) * optionGap + hintHeight }
        return (CGSize(width: bubbleWidth, height: h), textHeight, n)
    }

    /// An answer button's frame, measured from the bubble's top-left corner.
    static func optionRect(_ i: Int, in b: Bubble) -> CGRect {
        let top = pad + headerHeight + 6 + b.textHeight + 12
        return CGRect(x: pad, y: top + CGFloat(i) * (optionHeight + optionGap), width: b.size.width - 2 * pad, height: optionHeight)
    }

    var outerRadius: CGFloat = 250

    func layout(_ agents: [AgentInfo], now: Date = Date()) {
        if heldNotice { return }
        looking = herdr == .unknown && agents.isEmpty
        switch herdr {
        case .notInstalled: notice = .notInstalled
        case .notRunning: notice = .notRunning
        case .running: notice = agents.isEmpty ? .empty : nil
        case .unknown: notice = nil
        }
        // Without herdr-core there is nothing true to show, so don't leave old wedges up.
        let agents = (herdr == .notInstalled || herdr == .notRunning) ? [] : agents
        // Every agent gets a wedge, except that the idle ones share one until they are asked for.
        let idle = unfolded ? [] : agents.filter { $0.status == "idle" && !pinned.contains($0.id) }
        // A wheel of nothing but idle agents shows them all: there is no one to make room for.
        let folding = idle.count >= Self.foldFrom && idle.count < agents.count
        let apart = folding ? agents.filter { a in !idle.contains { $0.id == a.id } } : agents
        var all = Self.arrange(apart, order: order, pinned: pinned)
        if folding { all.append(AgentInfo(id: Self.foldID, agent: "", status: "idle", space: "\(idle.count) idle", tab: "")) }
        outerRadius = all.count > 9 ? 300 : (all.count > 6 ? 275 : 250)
        guard !all.isEmpty else { slices = []; bands = []; highlighted = nil; centre = nil; return }

        // The hub keeps its agent for as long as the wheel is open, so that a question being read
        // there is not swapped for a newer one. It moves on when that agent has gone, or when it
        // stops or starts waiting: answered, the next one that wants something takes its place.
        if let held = all.first(where: { $0.id == centre }), held.needsYou == centreWaiting {
            // still the one
        } else {
            let pick = Self.centreAgent(all.filter { $0.id != Self.foldID })
            centre = pick?.id
            centreWaiting = pick?.needsYou ?? false
        }

        // Agents waiting on you get wider wedges that also reach further in, so they are the closest
        // targets. Busy ones are all one size. A quiet one starts at that size and slowly gets thinner
        // and shorter the longer it sits, down to half the height, unless it is pinned.
        let fresh = all.map { pinned.contains($0.id) || $0.id == Self.foldID ? 1 : $0.freshness(now: now) }
        let size = all.map { pinned.contains($0.id) || $0.id == Self.foldID ? 1 : $0.size(now: now) }
        // Only the by-space order puts a space's sessions together, so only there are they joined up.
        let grouped = order == .space
        let sessions = Dictionary(all.map { ($0.space, 1) }, uniquingKeysWith: +)
        let names = AgentNames.names(for: all)
        let projects = AgentNames.projects(for: all.filter { $0.id != Self.foldID }.map(\.space))
        let weights = zip(all, size).map { a, f in a.needsYou ? 1.45 : Self.quietWidth + (1 - Self.quietWidth) * f }
        let unit = min(2 * Double.pi / weights.reduce(0, +), 2 * Double.pi / 3.2)
        let spans = weights.map { $0 * unit }
        let used = spans.reduce(0, +)
        let full = used > 2 * Double.pi - 0.001
        let readable = Double(Self.readableWidth / (96 + (outerRadius - 96) * 0.54))
        // Start so the first wedge (or the whole group, when it doesn't fill the circle) is centred at the top.
        var angle = -Double.pi / 2 - (full ? spans[0] / 2 : used / 2)
        var result: [Slice] = []
        for (i, a) in all.enumerated() {
            let span = spans[i]
            var s = Slice(agent: a, start: angle, end: angle + span, inner: a.needsYou ? 60 : 96,
                          outer: a.needsYou ? outerRadius + 16 : outerRadius - (outerRadius - 96) * Self.quietDip * CGFloat(1 - size[i]))
            s.fresh = fresh[i]
            s.ago = a.ago(now: now)
            s.busyFor = a.busyFor(now: now)
            s.pinned = pinned.contains(a.id)
            s.name = names[a.id] ?? a.space
            s.project = projects[a.space]
            if a.id == Self.foldID { s.folded = idle.count; s.name = "+\(idle.count)" }
            // Pointed at, a wedge is as big as a busy one, and on a crowded wheel wide enough to read.
            s.widen = max(0, max(a.needsYou ? span : unit, readable) - span) / 2
            if !a.needsYou { s.raise = outerRadius - s.outer }
            s.joinsPrevious = grouped && i > 0 && all[i - 1].space == a.space
            s.joinsNext = grouped && i + 1 < all.count && all[i + 1].space == a.space
            s.sibling = !s.inFamily && (sessions[a.space] ?? 0) > 1
            result.append(s)
            angle += span
        }
        slices = result

        // One name over each run of sessions from the same space.
        var named: [Band] = []
        var i = 0
        while i < result.count {
            var j = i
            while result[j].joinsNext { j += 1 }
            if j > i {
                let run = result[i...j]
                named.append(Band(id: result[i].id, name: result[i].agent.space, start: result[i].start, end: result[j].end,
                                  radius: (run.map { $0.outer }.max() ?? outerRadius) + Band.lift, members: run.map { $0.id }))
            }
            i = j + 1
        }
        bands = named
        if let h = highlighted, !result.contains(where: { $0.id == h }) { highlighted = nil }
    }

    /// How much shorter the wedge that has been quiet the longest is than a busy one. A thin
    /// wedge's name runs along it, so it keeps most of its length to have room for the name.
    static let quietDip: CGFloat = 0.2
    /// The width of a wedge that has been quiet the longest, as a share of a busy one's.
    static let quietWidth = 0.45
    /// How wide a wedge is, where its label goes, once it is pointed at: room for a name.
    static let readableWidth: CGFloat = 140

    /// The order the agents go round the wheel in. Waiting agents lead, then pinned ones.
    static func arrange(_ agents: [AgentInfo], order: RingOrder, pinned: Set<String> = []) -> [AgentInfo] {
        func group(_ a: AgentInfo) -> Int { a.needsYou ? 0 : (pinned.contains(a.id) ? 1 : (a.status == "working" ? 2 : 3)) }
        func before(_ a: String, _ b: String) -> Bool? {
            let c = a.compare(b, options: [.caseInsensitive, .numeric])
            if c != .orderedSame { return c == .orderedAscending }
            return a == b ? nil : a < b
        }
        func byPlace(_ a: AgentInfo, _ b: AgentInfo) -> Bool { before(a.space, b.space) ?? before(a.tab, b.tab) ?? (a.id < b.id) }
        // Waiting, pinned, busy, then whoever went quiet last; an agent whose time isn't known goes after those.
        func moreRecent(_ a: AgentInfo, _ b: AgentInfo) -> Bool {
            let ga = group(a), gb = group(b)
            if ga != gb { return ga < gb }
            if ga == 1 { return byPlace(a, b) }   // pinned agents keep their places among themselves
            let ta = a.lastActive ?? .distantPast, tb = b.lastActive ?? .distantPast
            if ta != tb { return ta > tb }
            return (a.rank, a.space, a.tab, a.id) < (b.rank, b.space, b.tab, b.id)
        }
        let kept = agents.sorted(by: moreRecent)
        guard order == .space else { return kept }

        // A space with someone waiting or pinned comes first and brings its other sessions along.
        var lead: [String: Int] = [:]
        for a in kept { lead[a.space] = min(lead[a.space] ?? 2, min(group(a), 2)) }
        let bySpace = kept.sorted { a, b in
            let la = lead[a.space] ?? 2, lb = lead[b.space] ?? 2
            if la != lb { return la < lb }
            if let first = before(a.space, b.space) { return first }
            let ga = min(group(a), 2), gb = min(group(b), 2)
            if ga != gb { return ga < gb }
            return before(a.tab, b.tab) ?? (a.id < b.id)
        }
        return bySpace
    }

    /// The hub's radius. Nothing inside it is on a wedge.
    static let hubRadius: CGFloat = 46

    /// The agent the hub stands for among these: whoever most recently started waiting on you,
    /// or else whoever is busy or was active last. This is the wheel's "most recent" order, leaving
    /// pins out of it: a pin keeps an agent near the front, it does not make it the latest.
    static func centreAgent(_ agents: [AgentInfo]) -> AgentInfo? {
        arrange(agents, order: .recent).first
    }

    /// Whether a point, as an offset from the centre, is on the hub.
    static func isOnHub(_ p: CGSize) -> Bool { hypot(p.width, p.height) <= hubRadius }

    /// What the pointer is aiming at: on the hub, the hub's agent; anywhere else, the wedge under it.
    func aim(at p: CGSize) -> String? {
        Self.isOnHub(p) ? centre : target(for: p)
    }

    /// Start afresh for a wheel that is opening: the hub picks its agent anew.
    func forgetCentre() {
        centre = nil
        onHub = false
    }

    /// The agent the pointer is aiming at, given its offset from the centre (y down). This goes by
    /// where each wedge rests: the one pointed at is drawn bigger and lies over its neighbours, but
    /// moving onto a neighbour's place picks the neighbour, so even a sliver can always be reached.
    func target(for p: CGSize) -> String? {
        guard !Self.isOnHub(p) else { return nil }
        let angle = atan2(Double(p.height), Double(p.width))
        for s in slices {
            var d = (angle - s.start).truncatingRemainder(dividingBy: 2 * .pi)
            if d < 0 { d += 2 * .pi }
            if d < s.end - s.start { return s.id }
        }
        return nil
    }
}

/// A pie wedge between two radii, with a small gap to its neighbours.
struct Wedge: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat
    /// The gap on each side. Sessions of the same space are only a hairline apart.
    var startGap: CGFloat = Wedge.gap
    var endGap: CGFloat = Wedge.gap
    static let gap: CGFloat = 3.5
    static let hairline: CGFloat = 0.75

    // Lets a wedge grow and shrink smoothly rather than jump.
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(start, end), AnimatablePair(inner, outer)) }
        set { start = newValue.first.first; end = newValue.first.second; inner = newValue.second.first; outer = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: .radians(start + Double(startGap / outer)),
                 endAngle: .radians(end - Double(endGap / outer)), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .radians(end - Double(endGap / inner)),
                 endAngle: .radians(start + Double(startGap / inner)), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Part of a circle's edge, for the band that names a space.
struct Arc: Shape {
    var start: Double
    var end: Double
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<Double, Double>> {
        get { AnimatablePair(radius, AnimatablePair(start, end)) }
        set { radius = newValue.first; start = newValue.second.first; end = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        return p
    }
}

/// A short name written along a circle, kept the right way up on the lower half.
struct ArcText: View {
    let text: String
    let mid: Double       // the angle its middle sits at
    let radius: CGFloat
    let room: CGFloat     // how much of the circle's edge it may take up

    static let size: CGFloat = 11
    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }()

    /// Each letter and how far along the edge its middle is from the middle of the text.
    static func letters(_ text: String, room: CGFloat) -> [(letter: String, at: CGFloat)] {
        func width(_ s: String) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: font]).width * 10) / 10 }
        // A name too long for its room loses words from the end, down to its first.
        var words = text.split(separator: " ").map(String.init)
        while words.count > 1, width(words.joined(separator: " ")) > room { words.removeLast() }
        var chars = (words.isEmpty ? text : words.joined(separator: " ")).map { String($0) }
        var widths = chars.map(width)
        // One word that is still too long is cut, which is rare: a band spans two wedges or more.
        while chars.count > 1, widths.reduce(0, +) > room { chars.removeLast(); widths.removeLast() }
        var x = -widths.reduce(0, +) / 2
        var out: [(letter: String, at: CGFloat)] = []
        for (c, w) in zip(chars, widths) {
            out.append((c, x + w / 2))
            x += w
        }
        return out
    }

    var body: some View {
        // Clockwise reads left to right along the top; along the bottom it is the other way round.
        let flipped = sin(mid) > 0
        let letters = Self.letters(text, room: room)
        return ZStack {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, l in
                let angle = mid + (flipped ? -1 : 1) * Double(l.at / radius)
                Text(l.letter)
                    .font(.system(size: Self.size, weight: .bold, design: .rounded))
                    .fixedSize()
                    .rotationEffect(.radians(angle + (flipped ? -Double.pi / 2 : Double.pi / 2)))
                    .offset(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius)
            }
        }
    }
}

struct RingView: View {
    @ObservedObject var model: RingModel
    static let side: CGFloat = 1400

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.black.opacity(0.50), Color.black.opacity(0.30), .clear],
                                         center: .center, startRadius: 40, endRadius: model.outerRadius + 90))
                if let notice = model.notice {
                    noticeCard(notice)
                } else {
                    // A wheel that is only waiting for an answer to go in before it closes steps back,
                    // leaving the bubble that says so.
                    let fade = model.leaving ? 0.3 : 1.0
                    ForEach(model.slices) { s in
                        slice(s, on: model.highlighted == s.id, t: t)
                            .opacity(fade)
                            .zIndex(model.highlighted == s.id ? 1 : 0)   // grown, it lies over its neighbours' edges
                    }
                    ForEach(model.bands) { b in
                        band(b).opacity(fade).zIndex(2)
                    }
                    hub.opacity(fade).zIndex(3)
                }
                if let b = model.bubble, let a = model.slices.first(where: { $0.id == model.highlighted })?.agent {
                    SpeechBubble(agent: a, bubble: b, model: model)
                        .offset(x: b.offset.width, y: b.offset.height)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: Self.side, height: Self.side)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: model.highlighted)
        .animation(.easeOut(duration: 0.18), value: model.notice)
    }

    // MARK: Notice

    /// The wheel with nothing in it: an empty track where the wedges go, and the reason in the middle.
    private func noticeCard(_ n: RingModel.Notice) -> some View {
        let track: CGFloat = 196
        return ZStack {
            Circle().stroke(Color(white: 0.13).opacity(0.9), lineWidth: 34).frame(width: track * 2, height: track * 2)
            Circle().stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [3, 9]))
                .frame(width: track * 2, height: track * 2)
            VStack(spacing: 7) {
                Image(systemName: n.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(n.tint)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(n.tint.opacity(0.55), lineWidth: 1.5))
                    .padding(.bottom, 3)
                Text(n.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(n.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineSpacing(2).opacity(0.78)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Click anywhere to close")
                    .font(.system(size: 10, weight: .medium)).opacity(0.45).padding(.top, 5)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(width: 264)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.08)], center: .top, startRadius: 4, endRadius: 260)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 12)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: Wedges

    private func slice(_ s: RingModel.Slice, on: Bool, t: Double) -> some View {
        let a = s.agent, urgent = a.needsYou
        let pulse = 0.5 + 0.5 * sin(t * 4.2)
        let pop: CGFloat = on ? 16 : (urgent ? CGFloat(3 * pulse) : 0)
        // A quiet agent's wedge rests small and grey; pointing at it brings it back to full size and colour.
        let fresh = on ? 1 : s.fresh
        let start = s.start - (on ? s.widen : 0), end = s.end + (on ? s.widen : 0)
        let outer = on ? s.reach : s.outer
        // Finished and not looked at since: herdr-core calls that done until the agent is opened.
        let unread = a.status == "done"
        let tint = unread ? a.color : a.color(freshness: fresh)
        let startGap = s.joinsPrevious ? Wedge.hairline : Wedge.gap, endGap = s.joinsNext ? Wedge.hairline : Wedge.gap
        let shape = Wedge(start: start, end: end, inner: s.inner, outer: outer, startGap: startGap, endGap: endGap)
        let rim = Wedge(start: start, end: end, inner: outer - 7, outer: outer, startGap: startGap, endGap: endGap)
        let fill: AnyShapeStyle = urgent
            ? AnyShapeStyle(RadialGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.40), Palette.accent, Color(red: 0.93, green: 0.30, blue: 0.30)],
                                           center: .center, startRadius: s.inner, endRadius: outer))
            : AnyShapeStyle(RadialGradient(colors: [Color(white: on ? 0.36 : 0.20), Color(white: on ? 0.26 : 0.11)],
                                           center: .center, startRadius: s.inner, endRadius: outer))
        let radius = s.inner + (outer - s.inner) * 0.54
        let arcWidth = CGFloat(end - start) * radius
        return ZStack {
            shape.fill(fill).opacity(urgent ? 1 : 0.95)
            // Its project's color, under everything else, so that a project can be found without reading.
            if !urgent, let p = s.project { shape.fill(Palette.projects[p % Palette.projects.count]).opacity(on ? 0.34 : 0.14 + 0.10 * fresh) }
            if !urgent {
                rim.fill(tint).opacity(a.status == "working" ? 0.55 + 0.45 * pulse : 0.9)
            }
            shape.stroke(on ? Color.white : Color.white.opacity(urgent ? 0.5 : 0.10), lineWidth: on ? 3 : 1)
            // A wedge that rests too narrow for the usual label keeps just its picture and name.
            if arcWidth < 56 {
                // Too thin to write across, so the label runs along it, the right way up on either side.
                let middle = (s.inner + outer) / 2
                spoke(s, t: t, length: outer - s.inner - 16, tint: tint, fresh: fresh)
                    .rotationEffect(.radians(cos(s.mid) < 0 ? s.mid + .pi : s.mid))
                    .offset(x: CGFloat(cos(s.mid)) * middle, y: CGFloat(sin(s.mid)) * middle)
            } else {
                label(s, on: on, t: t, width: max(arcWidth < 90 ? 52 : 64, min(150, arcWidth - 14)), tint: tint, fresh: fresh,
                      brief: arcWidth < 90)
                    .offset(x: CGFloat(cos(s.mid)) * radius, y: CGFloat(sin(s.mid)) * radius)
            }
            if s.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(45))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .offset(x: CGFloat(cos(s.mid)) * (outer - 19), y: CGFloat(sin(s.mid)) * (outer - 19))
            }
        }
        // An agent that has finished and not been looked at glows, as one that is asking does.
        .shadow(color: urgent ? Palette.accent.opacity(0.45 + 0.4 * pulse) : (unread ? a.color.opacity(0.75) : .black.opacity(0.35)),
                radius: urgent ? 16 : (unread ? 15 : 6))
        .offset(x: CGFloat(cos(s.mid)) * pop, y: CGFloat(sin(s.mid)) * pop)
    }

    private func label(_ s: RingModel.Slice, on: Bool, t: Double, width: CGFloat, tint: Color, fresh: Double,
                       brief: Bool) -> some View {
        let a = s.agent, urgent = a.needsYou, family = s.inFamily
        // A quiet agent says how long it has been quiet (its picture already says done or idle),
        // and a busy one how long it has been at this turn.
        let since = s.ago ?? s.busyFor.map { "working \($0)" }
        let state = since ?? a.statusWord
        // The band over a family already names the space, so each of its wedges says which session it is.
        // A wedge too narrow for all that keeps only the time.
        let detail = brief ? (s.ago ?? s.busyFor ?? "") : (a.tab.isEmpty || (family && a.title.isEmpty) ? state : "\(a.tab) · \(state)")
        return VStack(spacing: 3) {
            icon(a, t: t)
                .font(.system(size: urgent ? 30 : 25, weight: .semibold))
                .foregroundStyle(urgent ? Color.white : tint)
                .frame(height: urgent ? 36 : 30)
                .overlay {
                    // Up and to the right of the picture, like a badge.
                    if a.subAgents > 0 {
                        helpersPill(a.subAgents, urgent: urgent).fixedSize().offset(x: urgent ? 31 : 28, y: -9)
                    }
                }
            name(s.name).font(.system(size: family ? (urgent ? 13.5 : 12.5) : (urgent ? 15.5 : 14), weight: .bold, design: .rounded))
            if s.sibling, !brief, !a.title.isEmpty {
                // What the session is about, when there is room for all of it.
                ViewThatFits(in: .horizontal) {
                    Text(a.title).font(.system(size: 11, weight: .semibold, design: .rounded)).fixedSize().opacity(0.92)
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            if !detail.isEmpty {
                // When both don't fit, the tab goes and the state or time stays.
                ViewThatFits(in: .horizontal) {
                    Text(detail).lineLimit(1).fixedSize()
                    Text(brief ? detail : state).lineLimit(1)
                }
                .font(.system(size: 11.5, weight: .medium)).opacity(0.82)
            }
        }
        .foregroundStyle(.white)
        .frame(width: width)
        .opacity(0.55 + 0.45 * fresh)
        .scaleEffect(on ? 1.08 : 0.86 + 0.14 * CGFloat(fresh))
    }

    /// An agent's name, whole: on one line, or a word to a line, or as its two letters where
    /// even a word does not fit. Never with part of it left out.
    private func name(_ text: String) -> some View {
        let words = text.split(separator: " ").map(String.init)
        let small = Font.system(size: 11, weight: .bold, design: .rounded)
        return ViewThatFits(in: .horizontal) {
            Text(text).fixedSize()
            if words.count > 1 { VStack(spacing: 0) { ForEach(words, id: \.self) { Text($0).fixedSize() } } }
            Text(text).font(small).fixedSize()
            if words.count > 1 { VStack(spacing: 0) { ForEach(words, id: \.self) { Text($0).fixedSize() } }.font(small) }
            if words.count > 1, words[0].count > 2 { Text(words[0]).font(small).fixedSize() }
            Text(AgentNames.monogram(text)).fixedSize()
        }
    }

    /// The label of a wedge too thin to write across: its picture, name and time in one line.
    private func spoke(_ s: RingModel.Slice, t: Double, length: CGFloat, tint: Color, fresh: Double) -> some View {
        let a = s.agent
        return HStack(spacing: 4) {
            icon(a, t: t)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(a.needsYou ? Color.white : tint)
            // The whole name with the time, the name alone, or its two letters: whichever fits.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(s.name).fixedSize()
                    if let since = s.ago ?? s.busyFor { Text(since).font(.system(size: 10.5, weight: .medium)).opacity(0.75).fixedSize() }
                }
                Text(s.name).fixedSize()
                Text(s.name).font(.system(size: 10.5, weight: .bold, design: .rounded)).fixedSize()
                Text(AgentNames.monogram(s.name)).fixedSize()
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: max(40, length))
        .opacity(0.55 + 0.45 * fresh)
    }

    /// How many sub-agents the agent has busy right now.
    private func helpersPill(_ count: Int, urgent: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 8, weight: .heavy))
            Text("\(count)").font(.system(size: 10.5, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 1.5)
        .background(Capsule().fill(urgent ? Color.black.opacity(0.30) : Color.white.opacity(0.18)))
        .overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 0.75))
    }

    /// The space's name on a dark strip just outside its sessions.
    private func band(_ b: RingModel.Band) -> some View {
        // When one of its sessions is pointed at, the band moves out with it rather than being covered.
        let lifted = model.slices.first { $0.id == model.highlighted && b.members.contains($0.id) }
        let radius = lifted.map { $0.reach + 16 + RingModel.Band.lift } ?? b.radius
        let trim = Double(13 / radius)   // room for the strip's round ends
        return ZStack {
            Arc(start: b.start + trim, end: b.end - trim, radius: radius)
                .stroke(Color(white: 0.09).opacity(0.92), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            ArcText(text: b.name, mid: (b.start + b.end) / 2, radius: radius,
                    room: CGFloat(b.end - b.start - 2 * trim) * radius)
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .shadow(color: .black.opacity(0.35), radius: 4)
    }

    /// A little moving picture of what the agent is doing.
    @ViewBuilder
    private func icon(_ a: AgentInfo, t: Double) -> some View {
        switch a.status {
        case "working":
            Image(systemName: "gearshape.fill")
                .rotationEffect(.degrees((t * 150).truncatingRemainder(dividingBy: 360)))
        case "blocked":
            Image(systemName: "hand.raised.fill")
                .rotationEffect(.degrees(12 * sin(t * 6)), anchor: .bottom)
                .scaleEffect(1 + 0.08 * sin(t * 6))
        case "error":
            Image(systemName: "exclamationmark.triangle.fill")
                .opacity(0.6 + 0.4 * abs(sin(t * 5)))
        case "done":
            Image(systemName: "checkmark.circle.fill")
        case "idle":
            Image(systemName: "moon.zzz.fill")
                .offset(y: CGFloat(2 * sin(t * 1.6)))
        default:
            Image(systemName: "terminal.fill")
        }
    }

    // MARK: Hub

    private var hub: some View {
        let waiting = model.slices.filter { $0.agent.needsYou }.count
        let pointed = model.slices.first { $0.id == model.highlighted }
        let focus = pointed?.agent
        return VStack(spacing: 1) {
            if model.slices.isEmpty {
                // Only seen for a moment: before herdr-core has answered for the first time.
                Text(model.looking ? "Looking for" : "No agents").font(.system(size: 13, weight: .semibold))
                Text(model.looking ? "agents…" : "running").font(.system(size: 11)).opacity(0.7)
            } else if let focus {
                Text(focus.statusWord).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(focus.needsYou ? Palette.accent : focus.color)
                if let since = pointed?.ago ?? pointed?.busyFor.map({ "for \($0)" }) {
                    Text(since).font(.system(size: 10.5, weight: .medium)).opacity(0.85)
                }
                // On the hub itself there are two things to say about clicking, so the agent's kind makes room.
                if !model.onHub { Text(focus.agent).font(.system(size: 10.5)).opacity(0.75).lineLimit(1) }
                Text(model.canJump ? "click to open" : "no Herdr app").font(.system(size: 9.5)).opacity(model.onHub ? 0.8 : 0.5)
                if model.onHub {
                    // On the hub itself the other button puts the wheel away.
                    Text("right-click closes").font(.system(size: 9)).opacity(0.5)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: pointed?.pinned == true ? "pin.slash.fill" : "pin.fill").font(.system(size: 7.5))
                        Text("right-click")
                    }
                    .font(.system(size: 9)).opacity(0.5)
                }
            } else if waiting > 0 {
                Text("\(waiting)").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.accent)
                Text(waiting == 1 ? "needs you" : "need you").font(.system(size: 10.5)).opacity(0.8)
            } else {
                Text("\(model.slices.count)").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("agents").font(.system(size: 10.5)).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .frame(width: RingModel.hubRadius * 2, height: RingModel.hubRadius * 2)
        .background(Circle().fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.08)], center: .top, startRadius: 4, endRadius: 90)))
        // With the pointer on it, the hub is a button for the agent it names.
        .overlay(Circle().stroke(model.onHub ? Palette.accent : Color.white.opacity(0.22), lineWidth: model.onHub ? 2.5 : 1.5))
        .shadow(color: model.onHub ? Palette.accent.opacity(0.55) : .black.opacity(0.5), radius: 10)
    }
}

/// A cartoon speech bubble with the agent's question in it.
struct SpeechBubble: View {
    let agent: AgentInfo
    let bubble: RingModel.Bubble

    private struct Tail: Shape {
        let toward: CGSize
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let tx = toward.width, ty = toward.height
            // Distance from the centre to the bubble's edge in that direction.
            let edge = min(abs(tx) > 0.001 ? rect.width / 2 / abs(tx) : .infinity,
                           abs(ty) > 0.001 ? rect.height / 2 / abs(ty) : .infinity)
            let tip = CGPoint(x: c.x + tx * (edge + 26), y: c.y + ty * (edge + 26))
            let base = CGPoint(x: c.x + tx * (edge - 14), y: c.y + ty * (edge - 14))
            let px = -ty * 15, py = tx * 15
            var p = Path()
            p.move(to: tip)
            p.addLine(to: CGPoint(x: base.x + px, y: base.y + py))
            p.addLine(to: CGPoint(x: base.x - px, y: base.y - py))
            p.closeSubpath()
            return p
        }
    }

    @ObservedObject var model: RingModel

    var body: some View {
        let speech = agent.speech(full: bubble.expanded)
        let ink = Color(white: 0.10)
        let approval = agent.needsYou ? agent.permission : nil
        let slice = model.slices.first { $0.id == agent.id }
        let ago = slice?.ago ?? (agent.needsYou ? nil : slice?.busyFor)
        let heading = approval != nil
            ? "Needs approval" + (approval!.tool.isEmpty ? "" : " · \(approval!.tool)")
            : agent.needsYou
                ? (agent.kind.isEmpty ? "Waiting for you" : "Asks: \(agent.kind)")
                : agent.statusWord.capitalized
        return ZStack(alignment: .topLeading) {
            Group {
                Tail(toward: bubble.toward).fill(Color.white)
                Tail(toward: bubble.toward).stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white)
                RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ink, lineWidth: 2.5)
                // Cover the outline where the tail joins the bubble.
                Tail(toward: bubble.toward).fill(Color.white).scaleEffect(0.86)
            }
            .frame(width: bubble.size.width, height: bubble.size.height)

            HStack(spacing: 6) {
                if approval != nil {
                    Image(systemName: "exclamationmark.shield.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
                } else {
                    Circle().fill(agent.needsYou ? Palette.accent : agent.color).frame(width: 8, height: 8)
                }
                Text("\(agent.space.uppercased())  ·  \(heading.uppercased())" + (ago.map { "  ·  \($0.uppercased())" } ?? ""))
                    .font(.system(size: 10, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(agent.needsYou ? Palette.accent : Color(white: 0.4)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: bubble.size.width - 2 * RingModel.pad, height: RingModel.headerHeight, alignment: .leading)
            .offset(x: RingModel.pad, y: RingModel.pad)

            Text(speech.text.isEmpty ? agent.title : speech.text)
                .font(approval != nil ? .system(size: 13, weight: .medium, design: .monospaced)
                                      : .system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .lineSpacing(2)
                .frame(width: bubble.size.width - 2 * RingModel.pad, height: bubble.textHeight, alignment: .topLeading)
                .offset(x: RingModel.pad, y: RingModel.pad + RingModel.headerHeight + 6)

            if bubble.optionCount > 0 {
                ForEach(0..<bubble.optionCount, id: \.self) { i in
                    let r = RingModel.optionRect(i, in: bubble)
                    let own = i >= speech.options.count
                    answerButton(i, own ? "Type your own answer…" : speech.options[i], own: own,
                                 deny: !own && speech.options[i].lowercased().hasPrefix("no"),
                                 hot: model.canAnswer && model.hoveredOption == i, state: model.buttonState(i))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        // Faint until the question has been checked to be the one the agent is asking now.
                        .opacity(model.confirmed ? 1 : 0.45)
                }
                if let i = model.hoveredOption, let hint = agent.hints[i + 1], !hint.isEmpty {
                    let r = RingModel.optionRect(i, in: bubble)
                    hintCard(hint)
                        .offset(x: bubble.hintOnLeft ? -(300 + 14) : bubble.size.width + 14, y: r.minY - 6)
                        .transition(.opacity)
                }
                Text(model.answerNote
                     ?? (!model.confirmed ? "Checking that this is still what it asks…"
                     : (!bubble.expanded && agent.isLongQuestion) ? "Move onto the bubble to read the whole question"
                     : approval != nil ? "\(agent.prompt.isEmpty ? "Do you want to proceed?" : agent.prompt)  Click an answer to send it"
                     : "Point at an answer and click to send it"))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .foregroundStyle(Color(white: 0.45))
                    .frame(width: bubble.size.width - 2 * RingModel.pad, height: RingModel.hintHeight, alignment: .center)
                    .offset(x: RingModel.pad, y: bubble.size.height - RingModel.pad - RingModel.hintHeight + 6)
            }
        }
        .frame(width: bubble.size.width, height: bubble.size.height, alignment: .topLeading)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: model.hoveredOption)
        .animation(.easeOut(duration: 0.15), value: model.sentOption)
        .animation(.easeOut(duration: 0.15), value: model.delivery)
    }

    /// The explanation for the choice under the pointer, like an item tooltip in a game.
    private func hintCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(width: 300, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.11).opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .frame(width: 300, height: RingModel.optionHeight, alignment: .topLeading)
    }

    /// A chunky, game-style answer button with a key-cap number.
    private func answerButton(_ i: Int, _ text: String, own: Bool, deny: Bool = false, hot: Bool,
                              state: RingModel.ButtonState) -> some View {
        let green = Color(red: 0.20, green: 0.72, blue: 0.42)
        // The picked button says what became of the answer. On its way is the blue of an agent at
        // work, and only an answer that herdr-core has pressed is the green of done.
        let tint: Color?
        switch state {
        case .resting: tint = nil
        case .sending: tint = Color(red: 0.35, green: 0.62, blue: 1.0)
        case .sent: tint = green
        case .failed: tint = Color(red: 0.86, green: 0.27, blue: 0.25)
        }
        // Refusing looks different from agreeing, so a "No" is never picked by mistake.
        let hotColors = deny
            ? [Color(white: 0.42), Color(white: 0.26)]
            : [Color(red: 1.0, green: 0.60, blue: 0.40), Palette.accent]
        let face: AnyShapeStyle = tint.map { AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.9), $0], startPoint: .top, endPoint: .bottom)) }
            ?? (hot
                ? AnyShapeStyle(LinearGradient(colors: hotColors, startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.91)], startPoint: .top, endPoint: .bottom)))
        let lit = hot || tint != nil
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(lit ? Color.white : Color(white: 0.14))
                switch state {
                case .sent:
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(green)
                case .sending:
                    Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .heavy)).foregroundStyle(tint ?? .blue)
                case .failed:
                    Image(systemName: "exclamationmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(tint ?? .red)
                case .resting:
                    if own {
                        Image(systemName: "pencil").font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(hot ? (deny ? Color(white: 0.2) : Palette.accent) : Color.white)
                    } else {
                        Text("\(i + 1)").font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(hot ? (deny ? Color(white: 0.2) : Palette.accent) : Color.white)
                    }
                }
            }
            .frame(width: 26, height: 26)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .italic(own)
                .foregroundStyle(lit ? Color.white : Color(white: own ? 0.35 : 0.12))
                .lineLimit(1).minimumScaleFactor(0.78)
            Spacer(minLength: 0)
            if hot && tint == nil {
                Image(systemName: "arrow.right.circle.fill").font(.system(size: 17)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(face))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(lit ? Color.white.opacity(0.0) : Color(white: 0.10).opacity(0.22), lineWidth: 1.5))
        // A darker lip underneath gives the button some depth.
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(tint.map { $0.opacity(0.55) }
                  ?? (hot ? (deny ? Color(white: 0.14) : Color(red: 0.78, green: 0.26, blue: 0.20)) : Color(white: 0.72)))
            .offset(y: hot ? 2 : 3))
        .offset(y: hot ? 1 : 0)
        .scaleEffect(hot ? 1.025 : 1)
    }
}

/// Shows the agent ring around the pointer and tracks which agent is aimed at.
final class AgentRing {
    let model = RingModel()
    var onAim: (() -> Void)?
    var onChoose: ((AgentInfo) -> Void)?
    /// The person asked to pin or unpin the agent being aimed at.
    var onPin: ((AgentInfo) -> Void)?
    private var shown: [AgentInfo] = []    // what the wheel was last given to show
    /// The person picked one of the agent's offered answers (by index). What became of the
    /// answer comes back through `answered`.
    var onAnswer: ((AgentInfo, Int) -> Void)?
    /// The choice (counted from 0) of an answer that is still on its way to this agent, if one is.
    var answerOnItsWay: ((String) -> Int?)?
    /// The person wants to type their own answer; the point is where to put the text box (Cocoa screen coordinates).
    var onType: ((AgentInfo, CGPoint) -> Void)?
    /// The wheel has come up, or has been put away.
    var onOpenChange: ((Bool) -> Void)?
    private var lastQuestion = ""
    private var pointerOnWheel = false     // the pointer is over a wedge right now
    private var pointerOnBubble = false
    private var expandedFor: String?           // agent whose bubble is showing its whole question
    private var anchor: (x: CGFloat, bottom: CGFloat)?   // keeps the answer buttons still while it grows
    private var panel: WheelPanel?
    private var timer: Timer?
    private var centre = CGPoint.zero      // screen coordinates, top-left origin
    private var openedAt = Date()          // when the wheel came up, and so began taking the pointer
    private var sentAt: Date?              // when the answer that is on its way was picked
    private var leaveBy: Date?             // asked to close while it was: the wheel goes then at the latest
    private var afterLeaving: (() -> Void)?
    private let onScreen: Bool

    /// `onScreen` false keeps the wheel off the screen, for tests: it is laid out, aimed and
    /// answered from as usual, but no window comes up and the pointer is left alone.
    init(onScreen: Bool = true) {
        self.onScreen = onScreen
    }

    var isOpen: Bool { timer != nil }

    /// The side of the see-through window the wheel is drawn in, centred on the wheel. It has to
    /// reach past the widest thing beside the biggest wheel (a bubble with a choice's explanation
    /// next to it, or a bubble showing a whole long question) or that gets cut off at its edge.
    static let canvas: CGFloat = 2200

    /// How long after the wheel opens an answer can still be held back by what the pointer did
    /// before it opened: herdr-core's 3 seconds, and a little for the asking.
    static let quietWait: TimeInterval = 3.5

    /// The wheel's window: see-through, over everything, and never the active window.
    ///
    /// It takes the pointer for as long as it is up, on the whole canvas and not only where
    /// something is drawn. Left to pass through, every movement on the wheel also went to the
    /// window underneath. An agent's pane that reports pointer movement, as Claude Code's does,
    /// passes each one on as input, and herdr-core presses an answer's key only once the pane
    /// has had about 3 seconds without any. So answering the agent whose pane the wheel was
    /// opened over kept its own answer from going in for as long as the pointer moved.
    static func makePanel(showing model: RingModel) -> WheelPanel {
        let p = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: canvas, height: canvas),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        // Said outright: a see-through window that is not told takes the pointer only where it is drawn on.
        p.ignoresMouseEvents = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.contentView = NSHostingView(rootView: RingView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity))
        return p
    }

    func show(_ agents: [AgentInfo], herdr: HerdrStatus, appInstalled: Bool) {
        model.herdr = herdr
        model.canJump = appInstalled
        model.heldNotice = false
        model.highlighted = nil
        pointerOnWheel = false
        pointerOnBubble = false
        expandedFor = nil
        anchor = nil
        model.hoveredOption = nil
        showAnswer(for: nil)
        model.leaving = false
        leaveBy = nil
        afterLeaving = nil
        openedAt = Date()
        model.bubble = nil
        model.active = true
        model.forgetCentre()
        model.unfolded = false
        foldSince = nil
        model.confirmed = false     // what is shown at first is what was last seen; `update` brings the present
        shown = agents
        model.layout(agents)
        let side = Self.canvas
        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(x: mouse.x - side / 2, y: mouse.y - side / 2)
        // Keep the ring's busy middle on screen.
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let v = screen.visibleFrame, margin: CGFloat = 300
            let cx = min(max(mouse.x, v.minX + margin), v.maxX - margin)
            let cy = min(max(mouse.y, v.minY + margin), v.maxY - margin)
            origin = CGPoint(x: cx - side / 2, y: cy - side / 2)
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        centre = CGPoint(x: origin.x + side / 2, y: primaryHeight - (origin.y + side / 2))

        if panel == nil, onScreen {
            let p = Self.makePanel(showing: model)
            // Clicks are picked up by the button tap before any window sees them. One that gets
            // this far, because the tap is not running, would otherwise be lost on the wheel.
            p.onClick = { [weak self] right in
                if right { self?.pinAimed() } else { self?.choose() }
            }
            panel = p
        }
        panel?.setFrameOrigin(origin)
        panel?.orderFrontRegardless()

        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        onOpenChange?(true)
        // The pointer starts on the hub, so the hub's agent is aimed at from the first moment:
        // if it is waiting on you, its question is there as the wheel appears.
        track()
    }

    /// New data arrived while the ring is open.
    func update(_ agents: [AgentInfo], herdr: HerdrStatus, appInstalled: Bool) {
        guard isOpen else { return }
        model.herdr = herdr
        model.canJump = appInstalled
        shown = agents
        model.layout(agents)
        model.confirmed = true
        placeBubble()
    }

    /// The set of pinned agents changed; rearrange an open wheel straight away.
    func setPinned(_ ids: Set<String>) {
        model.pinned = ids
        guard isOpen else { return }
        model.layout(shown)
        placeBubble()
    }

    /// A right-click: pin or unpin the wedge being aimed at and stay open. Anywhere else it is an ordinary click.
    private var foldSince: Date?           // when the pointer came to rest on the idle agents' wedge
    /// How long the pointer rests on the idle agents' wedge before they are shown.
    static let unfoldAfter: TimeInterval = 0.45

    /// Give each idle agent its own wedge, for as long as the wheel stays open.
    func unfold() {
        guard !model.unfolded else { return }
        model.unfolded = true
        foldSince = nil
        model.highlighted = nil
        model.layout(shown)
        placeBubble()
    }

    func pinAimed() {
        if model.leaving { return }
        // On the hub a right-click puts the wheel away, the other half of a left-click opening its agent.
        if model.onHub { leave(); return }
        guard model.notice == nil, pointerOnWheel, model.highlighted != RingModel.foldID,
              let picked = model.slices.first(where: { $0.id == model.highlighted })?.agent else {
            choose()
            return
        }
        onPin?(picked)
    }

    // MARK: Answers on their way

    /// Show what is known of an answer to the agent now aimed at: none, or one that is still on
    /// its way. That may have been picked before the wheel was aimed here, or before it opened,
    /// and it still counts: another sent now would be pressed right after it.
    private func showAnswer(for id: String?) {
        let pending = id.flatMap { answerOnItsWay?($0) }
        model.sentOption = pending
        model.delivery = nil
        model.held = false
        sentAt = pending == nil ? nil : Date()
    }

    /// herdr-core has said what became of an answer that the wheel sent. Call it on the main thread.
    func answered(_ agent: AgentInfo, option: Int, _ outcome: AgentWatcher.Delivery) {
        // Only while that answer is still the one on show; the wheel may have been aimed elsewhere,
        // or closed and opened again, since it was picked.
        guard isOpen, model.highlighted == agent.id, model.sentOption == option, model.delivery == nil else { return }
        if outcome == .refused {
            // The answer before this one is still on its way, and is the one to show.
            showAnswer(for: agent.id)
            return
        }
        model.delivery = outcome
        model.held = false
        sentAt = nil
        // A wheel that was only waiting for this goes now, once there has been time to see it.
        if model.leaving { leaveBy = Date().addingTimeInterval(0.45) }
    }

    /// Put the wheel away because the person asked for that, then do `after` (open an agent, say).
    ///
    /// While an answer is on its way the wheel stays up until it has gone in. It is the wheel that
    /// keeps the pointer from the agent's pane, and herdr-core presses the key only once that pane
    /// has been left alone for about 3 seconds: put away at once, with the pointer then moving
    /// over the pane, the answer would be held back for as long as it moved. The wait is short,
    /// because the pane has been left alone since the wheel opened, and it has an end.
    private func leave(then after: (() -> Void)? = nil) {
        let onItsWay = model.sentOption != nil && model.delivery == nil
        guard isOpen, let until = Self.stayUntil(opened: openedAt, picked: onItsWay ? sentAt : nil) else {
            close()
            after?()
            return
        }
        leaveBy = until
        afterLeaving = after
        model.leaving = true
        model.hoveredOption = nil
    }

    /// Until when a wheel that has been asked to close stays up for an answer that is on its way,
    /// or nil to close at once. `picked` is when that answer was picked, nil when none is on its way.
    ///
    /// What can hold the answer back is what the pointer did over the pane before the wheel opened,
    /// so it is expected within `quietWait` of the wheel opening, or at once when that is already
    /// past. Whatever else holds it, the wheel does not wait beyond that.
    static func stayUntil(opened: Date, picked: Date?, now: Date = Date()) -> Date? {
        guard let picked else { return nil }
        let until = max(opened.addingTimeInterval(quietWait), picked.addingTimeInterval(1))
        return now < until ? until : nil
    }

    /// Put the wheel away because the person asked for that, with Escape or from outside.
    func dismiss() {
        if !model.leaving { leave() }
    }

    private func track() {
        // Asked to close while an answer was on its way: the wheel waits for that and nothing else,
        // wherever the pointer goes meanwhile.
        if model.leaving {
            if Date() >= (leaveBy ?? .distantPast) {
                let after = afterLeaving
                close()
                after?()
            }
            return
        }
        guard let m = CGEvent(source: nil)?.location else { return }
        let rel = CGSize(width: m.x - centre.x, height: m.y - centre.y)
        let r = hypot(rel.width, rel.height)

        // An answer that has been on its way for a while is being held back; the bubble says why.
        let held = model.sentOption != nil && model.delivery == nil
            && (sentAt.map { Date().timeIntervalSince($0) >= RingModel.heldAfter } ?? false)
        if held != model.held { model.held = held }

        // Is the pointer over the bubble, or one of its answer buttons?
        var option: Int?
        var overBubble = false
        if let b = model.bubble {
            let local = CGPoint(x: rel.width - b.offset.width + b.size.width / 2,
                                y: rel.height - b.offset.height + b.size.height / 2)
            overBubble = CGRect(origin: .zero, size: b.size).insetBy(dx: -45, dy: -45).contains(local)
            for i in 0..<b.optionCount where RingModel.optionRect(i, in: b).insetBy(dx: -3, dy: -4).contains(local) { option = i }
        }
        // Moving onto the bubble opens up the whole question. It grows upward from its bottom
        // edge so the answer buttons stay under the pointer.
        if let b = model.bubble, !b.expanded, let id = model.highlighted, expandedFor != id,
           let a = model.slices.first(where: { $0.id == id })?.agent, a.isLongQuestion {
            let local = CGPoint(x: rel.width - b.offset.width + b.size.width / 2,
                                y: rel.height - b.offset.height + b.size.height / 2)
            if CGRect(origin: .zero, size: b.size).insetBy(dx: -6, dy: -6).contains(local) {
                expandedFor = id
                anchor = (b.offset.width, b.offset.height + b.size.height / 2)
                placeBubble()
                return
            }
        }
        if option != model.hoveredOption {
            model.hoveredOption = option
            if option != nil { onAim?() }
        }
        pointerOnBubble = overBubble
        pointerOnWheel = r <= model.outerRadius + 22 && model.target(for: rel) != nil
        // A notice is small, so it lets go sooner than a wheel with bubbles around it.
        if !overBubble && r > (model.notice != nil ? 300 : model.outerRadius + 330) { leave(); return }

        // On the hub the pointer aims at the hub's agent.
        let onHub = model.notice == nil && model.centre != nil && RingModel.isOnHub(rel)
        if onHub != model.onHub {
            model.onHub = onHub
            placeBubble()       // a bubble that only a question earns on the hub may now show, or go
        }

        // Which wedge is aimed at only changes while the pointer is on the wheel itself,
        // so travelling out to the bubble keeps that agent selected.
        guard r <= model.outerRadius + 22, !overBubble || r <= model.outerRadius else { return }
        let aim = model.aim(at: rel)
        // Resting on the idle agents' wedge shows them.
        if aim == RingModel.foldID {
            if let since = foldSince { if Date().timeIntervalSince(since) >= Self.unfoldAfter { unfold(); return } } else { foldSince = Date() }
        } else {
            foldSince = nil
        }
        if aim != model.highlighted {
            model.highlighted = aim
            showAnswer(for: aim)
            expandedFor = nil
            anchor = nil
            placeBubble()
            if aim != nil { onAim?() }
        }
    }

    /// Put the speech bubble just outside the highlighted wedge, kept on screen.
    private func placeBubble() {
        // From the hub, only an agent that is waiting on you shows what it says: its question is
        // why the wheel was opened. One that is merely the latest shows its words when pointed at.
        guard let s = model.slices.first(where: { $0.id == model.highlighted }), s.agent.hasSpeech,
              !model.onHub || s.agent.needsYou else {
            model.bubble = nil
            return
        }
        if s.agent.message != lastQuestion {
            // A new question: start again from the preview.
            lastQuestion = s.agent.message
            showAnswer(for: s.id)
            expandedFor = nil
            anchor = nil
        }
        let expanded = expandedFor == s.id
        let metrics = RingModel.bubbleMetrics(for: s.agent, expanded: expanded)
        let size = metrics.size
        let dx = CGFloat(cos(s.mid)), dy = CGFloat(sin(s.mid))
        let reach = s.reach + 54 + abs(dx) * size.width / 2 + abs(dy) * size.height / 2
        var pos = CGPoint(x: dx * reach, y: dy * reach)
        if expanded, let anchor { pos = CGPoint(x: anchor.x, y: anchor.bottom - size.height / 2) }
        // Keep it inside the screen the wheel is on.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let here = CGPoint(x: centre.x, y: primaryHeight - centre.y)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(here, $0.frame, false) }) {
            let v = screen.visibleFrame
            let minX = v.minX - centre.x + size.width / 2 + 10, maxX = v.maxX - centre.x - size.width / 2 - 10
            let top = primaryHeight - v.maxY, bottom = primaryHeight - v.minY
            let minY = top - centre.y + size.height / 2 + 10, maxY = bottom - centre.y - size.height / 2 - 10
            if minX < maxX { pos.x = min(max(pos.x, minX), maxX) }
            if minY < maxY { pos.y = min(max(pos.y, minY), maxY) }
        }
        // The explanation card goes on whichever side of the bubble has room.
        var hintOnLeft = false
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(here, $0.frame, false) }) {
            hintOnLeft = centre.x + pos.x + size.width / 2 + 330 > screen.visibleFrame.maxX
        }
        // The tail points back at the middle of the wedge.
        let anchor = CGPoint(x: dx * (s.inner + s.outer) / 2, y: dy * (s.inner + s.outer) / 2)
        let vx = anchor.x - pos.x, vy = anchor.y - pos.y
        let len = max(1, hypot(vx, vy))
        model.bubble = RingModel.Bubble(offset: CGSize(width: pos.x, height: pos.y), size: size,
                                        toward: CGSize(width: vx / len, height: vy / len),
                                        textHeight: metrics.textHeight, optionCount: metrics.options, expanded: expanded,
                                        hintOnLeft: hintOnLeft)
    }

    /// Pick whatever is aimed at (or just close when nothing is).
    ///
    /// A click on the hub opens the hub's agent, so the latest agent, or the one asking for you,
    /// can be reached without moving the pointer. `fromTrigger` is a second press of the control
    /// that opened the wheel: on the hub that still closes it, as it always has, so the wheel can
    /// be glanced at and put away with the same button.
    func choose(fromTrigger: Bool = false) {
        // Already on its way out, waiting only for an answer to go in.
        if model.leaving { return }
        // A notice has nothing to pick: any click or tap just closes it.
        if model.notice != nil { close(); return }
        let picked = model.slices.first { $0.id == model.highlighted }?.agent
        // The wedge that stands for the idle agents opens them up; the wheel stays.
        if picked?.id == RingModel.foldID, pointerOnWheel || fromTrigger { unfold(); return }
        // On a wedge, or on the hub that stands for one.
        let onAgent = pointerOnWheel || (model.onHub && !fromTrigger)
        // On an answer button: send that answer and stay open for the next question.
        if let option = model.hoveredOption, let picked, picked.needsYou {
            // Not while an answer is on its way, nor before the question has been checked to be the current one.
            guard model.canAnswer else { return }
            if option >= picked.speech.options.count {
                // The free-text choice: swap the wheel for a text box where the bubble was.
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                let b = model.bubble
                let spot = CGPoint(x: centre.x + (b?.offset.width ?? 0),
                                   y: primaryHeight - (centre.y + (b?.offset.height ?? 0) + (b?.size.height ?? 0) / 2 - 60))
                close()
                onType?(picked, spot)
                return
            }
            // Picked, and on its way. The button turns green only when `answered` says it went in.
            model.sentOption = option
            model.delivery = nil
            model.held = false
            sentAt = Date()
            onAnswer?(picked, option)
            return
        }
        // A click on the bubble itself (not on a button) does nothing.
        if pointerOnBubble && !onAgent { return }
        // Without the Herdr app there is nowhere to jump to; say so rather than closing on a click that did nothing.
        if onAgent, let picked, !model.canJump {
            Log.write("agents: can't jump to \(picked.id), the Herdr app is not installed")
            model.highlighted = nil
            model.bubble = nil
            model.hoveredOption = nil
            model.slices = []
            model.bands = []
            model.notice = .noApp
            model.heldNotice = true
            model.onHub = false
            pointerOnWheel = false
            pointerOnBubble = false
            return
        }
        // Only a click on a wedge or on the hub opens an agent; clicking anywhere else just dismisses the wheel.
        // Opening it brings its pane under the pointer, so that too waits for an answer on its way.
        let fromHub = model.onHub
        leave { [weak self] in
            guard onAgent, let picked else { return }
            if fromHub { Log.write("agents: opening \(picked.id) from the middle of the wheel") }
            self?.onChoose?(picked)
        }
    }

    /// Take the wheel off the screen now, whatever is on its way.
    func close() {
        let wasOpen = isOpen
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        model.active = false
        model.onHub = false
        model.leaving = false
        leaveBy = nil
        afterLeaving = nil
        if wasOpen { onOpenChange?(false) }
    }
}

/// The window the wheel is drawn in. A click normally never reaches it, because the button tap
/// picks clicks up before any window sees them; one that does is handed on to be acted on.
final class WheelPanel: NSPanel {
    var onClick: ((_ right: Bool) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: onClick?(false)
        case .rightMouseDown: onClick?(true)
        default: super.sendEvent(event)
        }
    }
}


// MARK: - Typing an answer

/// A borderless panel that can still take the keyboard.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ReplyView: View {
    let agent: AgentInfo
    let send: (String) -> Void
    let cancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let ink = Color(white: 0.10)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Palette.accent).frame(width: 8, height: 8)
                Text("\(agent.space.uppercased())  ·  YOUR ANSWER")
                    .font(.system(size: 10, weight: .heavy)).kerning(0.5).foregroundStyle(Palette.accent)
            }
            Text(agent.speech.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.35)).lineLimit(3)
            TextField("Type your answer…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.94)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.accent, lineWidth: 2))
                .focused($focused)
                .onSubmit { submit() }
            HStack {
                Text("Return to send  ·  Esc to cancel").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color(white: 0.45))
                Spacer()
                Button("Send") { submit() }
                    .buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.small)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ink, lineWidth: 2.5))
        .padding(14)   // room for the shadow
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .colorScheme(.light)
        .onExitCommand { cancel() }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { send(t) }
    }
}

/// A small text box for answering an agent in your own words.
final class ReplyBox: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var previous: NSRunningApplication?

    var isOpen: Bool { panel != nil }

    func show(for agent: AgentInfo, at spot: CGPoint, send: @escaping (String) -> Void) {
        close(restore: false)
        previous = NSWorkspace.shared.frontmostApplication
        let host = NSHostingView(rootView: ReplyView(agent: agent, send: { [weak self] text in
            send(text)
            self?.close(restore: true)
        }, cancel: { [weak self] in self?.close(restore: true) }))
        let size = host.fittingSize
        var origin = CGPoint(x: spot.x - size.width / 2, y: spot.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(spot, $0.frame, false) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
            origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
        }
        let p = KeyPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        p.delegate = self
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    /// Clicking away cancels.
    func windowDidResignKey(_ notification: Notification) { close(restore: false) }

    func close(restore: Bool) {
        guard let p = panel else { return }
        panel = nil
        p.delegate = nil
        p.orderOut(nil)
        // Hand the keyboard back to whatever was in front.
        if restore, let app = previous, let url = app.bundleURL, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
        previous = nil
    }
}

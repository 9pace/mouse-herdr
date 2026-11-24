import Foundation

/// Short names for agents: one or two words that tell each from the rest, so that a wedge can
/// show its whole name and never a name with the middle cut out.
enum AgentNames {
    /// What is left of a space's name after its colon: "Shop: cart page" is about "cart page".
    static func subject(of space: String) -> String {
        guard let colon = space.range(of: ": ") else { return space }
        return space[colon.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    /// A name for an agent with no space, from its folder: "2026-11-20-fix-the-thing" is "fix the thing".
    static func spaceName(forFolder path: String) -> String {
        var name = (path as NSString).lastPathComponent
        if let date = name.range(of: #"^\d{4}-\d{2}-\d{2}-"#, options: .regularExpression) { name.removeSubrange(date) }
        return name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    private static let filler: Set<String> = ["the", "a", "an", "and", "or", "for", "of", "to", "in", "on", "with", "then", "from", "by", "at", "as", "is"]
    /// A name longer than this keeps only its first word.
    static let longest = 18

    /// One or two words for each label: the words no other label has, in the order they come.
    /// A label with no word of its own keeps its first words.
    static func short(_ labels: [String]) -> [String] {
        let words = labels.map { label in
            label.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "#" || $0 == "-") }).map(String.init)
                .filter { !filler.contains($0.lowercased()) }
        }
        var uses: [String: Int] = [:]
        for w in words { for k in Set(w.map { $0.lowercased() }) { uses[k, default: 0] += 1 } }
        return zip(labels, words).map { label, w in
            var own = w.filter { uses[$0.lowercased()] == 1 }
            // A number alone says nothing: keep the word before it.
            if !own.isEmpty, own.allSatisfy({ $0.allSatisfy(\.isNumber) }), let lead = w.first(where: { !$0.allSatisfy(\.isNumber) }) { own.insert(lead, at: 0) }
            var pick = Array((own.isEmpty ? w : own).prefix(2))
            if pick.joined(separator: " ").count > longest { pick = Array(pick.prefix(1)) }
            let name = pick.joined(separator: " ")
            guard let first = name.first else { return label.isEmpty ? "Agent" : String(label.prefix(longest)) }
            return first.uppercased() + name.dropFirst()
        }
    }

    /// Two letters to stand for a name where there is no room for it: the first letter of each
    /// of two words, or the first two of one.
    static func monogram(_ short: String) -> String {
        let w = short.split(separator: " ")
        let second = w.count > 1 ? w[1].first(where: { $0.isLetter || $0.isNumber }).map(String.init) ?? "" : ""
        let raw = w.count > 1 ? String(w[0].prefix(1)) + second : String(short.prefix(2))
        guard let first = raw.first else { return "?" }
        return first.uppercased() + raw.dropFirst().lowercased()
    }

    /// The short name of each agent, by id. An agent is named after what its space is about; one
    /// that shares its space with another, after its own session; one with no space, after its folder.
    static func names(for agents: [AgentInfo]) -> [String: String] {
        let spaces = agents.map { $0.space.isEmpty && !$0.folder.isEmpty ? spaceName(forFolder: $0.folder) : $0.space }
        var uses: [String: Int] = [:]
        for s in spaces { uses[s, default: 0] += 1 }
        let labels = agents.enumerated().map { i, a -> String in
            let about = spaces[i] == "~" ? "Home" : subject(of: spaces[i])
            if about.isEmpty { return a.tab.count > 2 ? a.tab : "Agent \(a.id.split(separator: "/").last ?? "")" }
            guard uses[spaces[i]]! > 1 else { return about }
            // Its tab's name if it has a real one, else what its terminal calls itself, unless
            // that is only the name of the program.
            if a.tab.count > 2 { return a.tab }
            if !a.title.isEmpty, a.title.caseInsensitiveCompare(a.agent.replacingOccurrences(of: "-", with: " ")) != .orderedSame { return a.title }
            return a.tab.isEmpty ? about : "\(about) \(a.tab)"
        }
        return Dictionary(zip(agents.map(\.id), short(labels)), uniquingKeysWith: { a, _ in a })
    }
}

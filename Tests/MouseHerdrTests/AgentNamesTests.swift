import XCTest
@testable import MouseHerdr

final class AgentNamesTests: XCTestCase {
    private func agent(_ id: String, _ space: String, tab: String = "1", title: String = "", folder: String = "") -> AgentInfo {
        var a = AgentInfo(id: id, agent: "claude-code", status: "idle", space: space, tab: tab)
        a.title = title
        a.folder = folder
        return a
    }

    func testShortNamesUseTheWordsNoOtherAgentHas() {
        XCTAssertEqual(AgentNames.short(["build the scout", "build the worker and relay", "prune tests in commands"]),
                       ["Scout", "Worker relay", "Prune tests"])
        // With nothing of its own a label keeps its first words; a long pair is cut to one word.
        XCTAssertEqual(AgentNames.short(["same words", "same words"]), ["Same words", "Same words"])
        XCTAssertEqual(AgentNames.short(["extraordinarily complicated"]), ["Extraordinarily"])
        XCTAssertEqual(AgentNames.short([""]), ["Agent"])
        // A number alone says nothing, so the word before it stays.
        XCTAssertEqual(AgentNames.short(["revive test 1", "revive test 2"]), ["Revive 1", "Revive 2"])
        XCTAssertTrue(AgentNames.short(["a very long name that goes on", "x"]).allSatisfy { $0.count <= AgentNames.longest })
    }

    func testMonograms() {
        XCTAssertEqual(AgentNames.monogram("Scout"), "Sc")
        XCTAssertEqual(AgentNames.monogram("Prune tests"), "Pt")
        XCTAssertEqual(AgentNames.monogram("Voice #5"), "V5")
        XCTAssertEqual(AgentNames.monogram(""), "?")
    }

    func testAnAgentIsNamedAfterItsSpaceItsSessionOrItsFolder() {
        let names = AgentNames.names(for: [
            agent("t1", "Shop: cart page"), agent("t2", "Shop: search"),
            // Two in one space go by their own session: its title, or its tab.
            agent("t3", "Shop: reviews", tab: "2", title: "Moderation queue"), agent("t4", "Shop: reviews", tab: "2", title: "Claude Code"),
            agent("t5", "~", tab: "notes"), agent("t6", "~", tab: "1"),
            agent("t7", "", folder: "/home/me/tasks/2026-11-20-shop-945-search-ignores-filters"), agent("devdesk/t8", ""),
        ])
        XCTAssertEqual(names["t1"], "Cart page")
        XCTAssertEqual(names["t2"], "Search")
        XCTAssertEqual(names["t3"], "Moderation queue")
        XCTAssertEqual(names["t4"], "Reviews 2")
        XCTAssertEqual(names["t5"], "Notes")
        XCTAssertEqual(names["t6"], "Home 1")
        XCTAssertEqual(names["t7"], "Shop 945")
        XCTAssertEqual(names["devdesk/t8"], "Agent t8")
        XCTAssertEqual(AgentNames.spaceName(forFolder: "/a/b/plain_name"), "plain name")
    }

    func testEveryWedgeCarriesItsShortName() {
        let model = RingModel()
        model.layout([agent("t1", "Shop: cart page"), agent("t2", "Shop: search")])
        XCTAssertEqual(Set(model.slices.map(\.name)), ["Cart page", "Search"])
    }
}

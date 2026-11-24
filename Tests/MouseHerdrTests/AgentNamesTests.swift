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

    private func busy(_ id: String, _ space: String, _ status: String = "working") -> AgentInfo {
        AgentInfo(id: id, agent: "claude-code", status: status, space: space, tab: "1")
    }

    func testIdleAgentsShareOneWedgeUntilTheyAreAskedFor() {
        let model = RingModel()
        let list = [busy("t1", "Shop: cart"), busy("t2", "Shop: search", "done"), agent("t3", "Old: one"), agent("t4", "Old: two"), agent("t5", "Old: three")]
        model.layout(list)
        XCTAssertEqual(model.slices.map(\.id), ["t1", "t2", RingModel.foldID])
        XCTAssertEqual(model.slices.last?.folded, 3)
        XCTAssertEqual(model.slices.last?.name, "+3")
        // The shared wedge is as big as a busy one, and never the agent the middle stands for.
        XCTAssertEqual(model.slices[2].end - model.slices[2].start, model.slices[0].end - model.slices[0].start, accuracy: 1e-9)
        XCTAssertNotEqual(model.centre, RingModel.foldID)
        model.unfolded = true
        model.layout(list)
        XCTAssertEqual(Set(model.slices.map(\.id)), ["t1", "t2", "t3", "t4", "t5"])
        XCTAssertTrue(model.slices.allSatisfy { $0.folded == 0 })
    }

    func testOneIdleAgentAPinnedOneAndAWheelOfOnlyIdleAgentsAreNotFolded() {
        let model = RingModel()
        model.layout([busy("t1", "Shop: cart"), agent("t3", "Old: one")])
        XCTAssertEqual(Set(model.slices.map(\.id)), ["t1", "t3"])
        model.layout([agent("t3", "Old: one"), agent("t4", "Old: two"), agent("t5", "Old: three")])
        XCTAssertEqual(model.slices.count, 3)
        model.pinned = ["t4"]
        model.layout([busy("t1", "Shop: cart"), agent("t3", "Old: one"), agent("t4", "Old: two"), agent("t5", "Old: three")])
        XCTAssertEqual(Set(model.slices.map(\.id)), ["t1", "t4", RingModel.foldID])
        XCTAssertEqual(model.slices.first { $0.id == RingModel.foldID }?.folded, 2)
    }

    func testPickingTheSharedWedgeShowsTheIdleAgentsAndKeepsTheWheelOpen() {
        let ring = AgentRing(onScreen: false)
        var chosen: [String] = []
        ring.onChoose = { chosen.append($0.id) }
        ring.show([busy("t1", "Shop: cart"), agent("t3", "Old: one"), agent("t4", "Old: two")], herdr: .running(agents: 3), appInstalled: true)
        ring.model.highlighted = RingModel.foldID
        ring.choose(fromTrigger: true)
        XCTAssertTrue(ring.isOpen)
        XCTAssertEqual(chosen, [])
        XCTAssertEqual(Set(ring.model.slices.map(\.id)), ["t1", "t3", "t4"])
        // The next time the wheel opens they share a wedge again.
        ring.close()
        ring.show([busy("t1", "Shop: cart"), agent("t3", "Old: one"), agent("t4", "Old: two")], herdr: .running(agents: 3), appInstalled: true)
        XCTAssertEqual(ring.model.slices.count, 2)
    }

    func testProjectsAreNumberedLargestFirstAndNeedTwoAgents() {
        let p = AgentNames.projects(for: ["Shop: cart", "Shop: search", "Shop runner: scout", "Docs: intro", "Loose", "Pay: a", "Pay: b"])
        XCTAssertEqual(p["Shop: cart"], 0)
        XCTAssertEqual(p["Shop runner: scout"], 0)   // a prefix that only extends another joins it
        XCTAssertEqual(p["Pay: a"], 1)
        XCTAssertNil(p["Docs: intro"])
        XCTAssertNil(p["Loose"])
        let model = RingModel()
        model.layout([busy("t1", "Shop: cart"), busy("t2", "Shop: search"), busy("t3", "Loose")])
        let project = Dictionary(uniqueKeysWithValues: model.slices.map { ($0.id, $0.project) })
        XCTAssertEqual(project["t1"], 0)
        XCTAssertEqual(project["t2"], 0)
        XCTAssertEqual(project["t3"], .some(nil))
    }
}

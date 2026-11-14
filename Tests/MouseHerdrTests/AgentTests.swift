import XCTest
@testable import MouseHerdr

final class AgentTests: XCTestCase {
    func testEmptyListingIsDifferentFromAnUnavailableService() {
        XCTAssertEqual(AgentWatcher.parseList(Data(#"{"terminals":[]}"#.utf8)), [])
        for invalid in ["", "not json", "{}", #"{"terminals":null}"#, "[]"] {
            XCTAssertNil(AgentWatcher.parseList(Data(invalid.utf8)), invalid)
        }
    }

    func testListingFiltersShellsAndPutsWaitingAgentsFirst() throws {
        let data = Data("""
        {"terminals":[
          {"address":"t1","agent":"zsh","where":"project / shell"},
          {"address":"t2","agent":"claude-code","status":"working","where":"web / tests"},
          {"address":"t3","agent":"claude-code","status":"blocked","where":"api / review"},
          {"address":"t4","agent":"claude-code","status":"done","where":"docs / build"},
          {"agent":"claude-code","status":"blocked"}
        ]}
        """.utf8)
        let agents = try XCTUnwrap(AgentWatcher.parseList(data))
        XCTAssertEqual(agents.map(\.id), ["t3", "t4", "t2"])
        XCTAssertEqual(agents[0].space, "api")
        XCTAssertEqual(agents[0].tab, "review")
        XCTAssertTrue(agents[0].needsYou)
        XCTAssertFalse(agents[1].needsYou)
    }

    func testShellWithReportedStatusIsKept() throws {
        let agents = try XCTUnwrap(AgentWatcher.parseList(
            Data(#"{"terminals":[{"address":"t1","agent":"bash","status":"error"}]}"#.utf8)))
        XCTAssertEqual(agents.count, 1)
        XCTAssertTrue(agents[0].needsYou)
    }

    func testQuestionChoicesKeepNestedParentheses() {
        var agent = AgentInfo(id: "t1", agent: "claude-code", status: "blocked", space: "demo", tab: "1")
        agent.message = "answer: Which option? (First (Recommended) · Second · Third)"
        XCTAssertEqual(agent.speech.text, "Which option?")
        XCTAssertEqual(agent.speech.options, ["First (Recommended)", "Second", "Third"])

        agent.message = "Check the build (including tests)"
        XCTAssertEqual(agent.speech.text, agent.message)
        XCTAssertTrue(agent.speech.options.isEmpty)
    }

    func testLongQuestionHasAnExpandablePreview() {
        var agent = AgentInfo(id: "t1", agent: "claude-code", status: "blocked", space: "demo", tab: "1")
        let question = String(repeating: "More detail. ", count: 30)
        agent.message = "answer: \(question) (Yes · No)"
        XCTAssertTrue(agent.isLongQuestion)
        XCTAssertEqual(agent.speech.text.count, 220)
        XCTAssertEqual(agent.speech(full: true).text, question.trimmingCharacters(in: .whitespaces))
        XCTAssertEqual(agent.speech.options, ["Yes", "No"])
    }

    func testDialogSeparatesChoiceHintsFromFreeTextAndFooter() {
        let screen = """
        ❯ 1. First (Recommended)
             First explanation
             continues here.
          2. Second
             Another explanation.
          3. Type something.
        ──────────
             Enter to select
        """
        let dialog = AgentWatcher.parseDialog(screen)
        XCTAssertEqual(dialog.hints, [1: "First explanation continues here.", 2: "Another explanation."])
        XCTAssertEqual(dialog.typeOption, 3)
    }

    func testDialogWithoutFreeTextDoesNotOfferTypedReply() {
        let dialog = AgentWatcher.parseDialog("  1. Yes\n  2. No\n──────────\n")
        XCTAssertNil(dialog.typeOption)
        XCTAssertTrue(dialog.hints.isEmpty)
    }

    // A real Claude Code approval prompt, as herdr-core shows it.
    private let approvalScreen = """
    ❯ Tidy up the build folder
    ⏺ Here is the plan:
      1. Remove the stale artifacts
      2. Rebuild
      3. Run the tests
      4. Report back
      5. Stop
    ────────────────────────────────────────
     Bash command
     Delete hello.txt from the test directory
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     rm /tmp/mm-perm-test/hello.txt
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     Do you want to proceed?
     ❯ 1. Yes
       2. Yes, and always allow access to /tmp/mm-perm-test from this project
       3. Yes, and switch to auto mode · auto mode handles these prompts for you
       4. No
     Esc to cancel · Tab to amend
    """

    func testApprovalDialogListsItsOwnChoicesAndIgnoresNumberedTextAbove() {
        let dialog = AgentWatcher.parseDialog(approvalScreen)
        XCTAssertEqual(dialog.options.count, 4)
        XCTAssertEqual(dialog.options.first, "Yes")
        XCTAssertEqual(dialog.options.last, "No")
        XCTAssertEqual(dialog.prompt, "Do you want to proceed?")
        XCTAssertNil(dialog.typeOption)
        XCTAssertTrue(dialog.hints.isEmpty)
    }

    func testApprovalShowsTheCommandAndTheScreenChoices() {
        var agent = AgentWatcher.parse(try! JSONSerialization.data(withJSONObject: ["terminals": [
            ["address": "t1", "agent": "claude-code", "status": "blocked", "where": "space / 1"],
        ]]))[0]
        agent.kind = "permission"
        agent.message = "approve Bash: rm /tmp/mm-perm-test/hello.txt"
        agent.screenOptions = AgentWatcher.parseDialog(approvalScreen).options
        XCTAssertEqual(agent.permission?.tool, "Bash")
        XCTAssertEqual(agent.permission?.detail, "rm /tmp/mm-perm-test/hello.txt")
        let speech = agent.speech(full: true)
        XCTAssertEqual(speech.text, "rm /tmp/mm-perm-test/hello.txt")
        XCTAssertEqual(speech.options.count, 4)
        XCTAssertEqual(speech.options[3], "No")
        XCTAssertTrue(speech.options[1].hasSuffix("…"))   // long choices are shortened for the button
    }

    func testQuestionChoicesStillComeFromTheMessage() {
        var agent = AgentWatcher.parse(try! JSONSerialization.data(withJSONObject: ["terminals": [
            ["address": "t1", "agent": "claude-code", "status": "blocked", "where": "space / 1"],
        ]]))[0]
        agent.kind = "question"
        agent.message = "answer: Keep it? (Yes (Recommended) · No)"
        XCTAssertNil(agent.permission)
        XCTAssertEqual(agent.speech.options, ["Yes (Recommended)", "No"])
        XCTAssertEqual(agent.speech.text, "Keep it?")
    }

    // MARK: The wheel's order, fading and families

    private func agent(_ id: String, _ status: String, _ space: String, _ tab: String = "1", quiet minutes: Double? = nil,
                       now: Date = Date(timeIntervalSince1970: 2_000_000)) -> AgentInfo {
        var a = AgentInfo(id: id, agent: "claude-code", status: status, space: space, tab: tab)
        a.lastActive = minutes.map { now.addingTimeInterval(-$0 * 60) }
        return a
    }
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testQuietAgentsFadeWhileBusyAndWaitingOnesStayFresh() {
        XCTAssertEqual(agent("t1", "done", "a", quiet: 1).freshness(now: now), 1)
        XCTAssertEqual(agent("t1", "done", "a", quiet: 60 * 24).freshness(now: now), 0)
        let hour = agent("t1", "done", "a", quiet: 60).freshness(now: now)
        let four = agent("t1", "idle", "a", quiet: 240).freshness(now: now)
        XCTAssertTrue(0 < four && four < hour && hour < 1, "\(four) \(hour)")
        // Busy or waiting on you is active now, however long ago that began.
        XCTAssertEqual(agent("t1", "working", "a", quiet: 60 * 24).freshness(now: now), 1)
        XCTAssertEqual(agent("t1", "blocked", "a", quiet: 60 * 24).freshness(now: now), 1)
        // Nothing is known before the first full look, so nothing is faded.
        XCTAssertEqual(agent("t1", "done", "a").freshness(now: now), 1)
    }

    func testQuietAgentsSayHowLongAgoInAFewCharacters() {
        let expected: [(Double, String)] = [(0.5, "just now"), (1, "1m ago"), (59.9, "59m ago"), (60, "1h ago"),
                                            (23.9 * 60, "23h ago"), (24 * 60, "1d ago"), (3.5 * 24 * 60, "3d ago")]
        for (minutes, text) in expected {
            XCTAssertEqual(agent("t1", "done", "a", quiet: minutes).ago(now: now), text)
        }
        // A clock that disagrees slightly must not produce a negative time.
        XCTAssertEqual(agent("t1", "idle", "a", quiet: -2).ago(now: now), "just now")
        // Busy and waiting agents are active now, and an unknown time is not guessed.
        XCTAssertNil(agent("t1", "working", "a", quiet: 90).ago(now: now))
        XCTAssertNil(agent("t1", "blocked", "a", quiet: 90).ago(now: now))
        XCTAssertNil(agent("t1", "done", "a").ago(now: now))

        let model = RingModel()
        model.herdr = .running(agents: 2)
        model.layout([agent("t1", "working", "a"), agent("t2", "done", "b", quiet: 125)], now: now)
        XCTAssertEqual(model.slices.map(\.ago), [nil, "2h ago"])
    }

    func testBusyAgentsSayHowLongTheirTurnHasRun() {
        XCTAssertNil(agent("t1", "working", "a", quiet: 0.5).busyFor(now: now))
        XCTAssertEqual(agent("t1", "working", "a", quiet: 5).busyFor(now: now), "5m")
        XCTAssertEqual(agent("t1", "working", "a", quiet: 130).busyFor(now: now), "2h")
        XCTAssertEqual(agent("t1", "working", "a", quiet: 60 * 50).busyFor(now: now), "2d")
        XCTAssertNil(agent("t1", "working", "a").busyFor(now: now))
        XCTAssertNil(agent("t1", "done", "a", quiet: 5).busyFor(now: now))

        let model = RingModel()
        model.herdr = .running(agents: 2)
        model.layout([agent("t1", "working", "a", quiet: 12), agent("t2", "done", "b", quiet: 125)], now: now)
        XCTAssertEqual(model.slices.map(\.busyFor), ["12m", nil])
    }

    func testSubAgentsAreCountedOnTheAgentThatStartedThemAndGetNoWedge() throws {
        let data = Data("""
        {"terminals":[
          {"address":"t1","agent":"claude-code","status":"working","where":"web / 1"},
          {"address":"t2","agent":"claude-code","status":"working","where":"web / 1","parent":"t1"},
          {"address":"t3","agent":"npm","where":"web / 1","parent":"t1"},
          {"address":"t4","agent":"claude-code","status":"done","where":"web / 1","parent":"t1"},
          {"address":"t5","agent":"zsh","where":"web / 1","parent":"t1"},
          {"address":"t6","agent":"claude-code","status":"idle","where":"api / 1"},
          {"address":"t7","agent":"claude-code","status":"blocked","where":"web / 1","parent":"t1"},
          {"address":"t8","agent":"zsh","where":"docs / 1"},
          {"address":"t9","agent":"claude-code","status":"working","where":"docs / 1","parent":"t8"}
        ]}
        """.utf8)
        let agents = try XCTUnwrap(AgentWatcher.parseList(data))
        let helpers = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.helpers) })
        // The busy one, the plain program and the one waiting count; the finished one and the bare shell don't.
        XCTAssertEqual(helpers["t1"], 3)
        XCTAssertEqual(helpers["t6"], 0)
        // Sub-agents have no wedge of their own, except one that is waiting on you.
        // An agent started from a plain shell is nobody's sub-agent.
        XCTAssertEqual(agents.map(\.id), ["t7", "t9", "t1", "t6"])
    }

    func testSubAgentsRunInsideAnAgentAreCountedFromItsRecords() {
        let answer: [String: Any] = ["records": [
            "a1": ["app": "claude-code", "state": "working", "title": "Research"],
            "a2": ["app": "claude-code", "state": "done", "title": "Earlier"],
            "a3": ["app": "claude-code", "state": "blocked"],
            "a4": ["app": "claude-code"],
        ]]
        XCTAssertEqual(AgentWatcher.busyRecords(answer), 2)
        XCTAssertEqual(AgentWatcher.busyRecords([:]), 0)
        XCTAssertEqual(AgentWatcher.busyRecords(["records": NSNull()]), 0)

        // Both kinds add up on the pill, and a plain listing keeps the inner count it can't see.
        var known = agent("t1", "working", "a")
        known.inner = 2
        var listed = agent("t1", "working", "a")
        listed.helpers = 1
        let carried = AgentWatcher.carry(from: [known], into: [listed], now: now)
        XCTAssertEqual(carried[0].inner, 2)
        XCTAssertEqual(carried[0].subAgents, 3)
    }

    func testPinnedAgentsStayNearTheFrontAtFullSize() throws {
        let list = [
            agent("t1", "working", "a", quiet: 1), agent("t2", "done", "b", quiet: 60 * 48), agent("t3", "done", "c", quiet: 2),
            agent("t4", "blocked", "d"), agent("t5", "done", "a", "2", quiet: 60 * 72),
        ]
        XCTAssertEqual(RingModel.arrange(list, order: .recent).map(\.id), ["t4", "t1", "t3", "t2", "t5"])
        // After anyone waiting, and in a fixed order among themselves however recent they are.
        XCTAssertEqual(RingModel.arrange(list, order: .recent, pinned: ["t2", "t5"]).map(\.id), ["t4", "t5", "t2", "t1", "t3"])
        // By space, a pinned agent brings its space forward and leads it.
        XCTAssertEqual(RingModel.arrange(list, order: .space, pinned: ["t5"]).map(\.id), ["t4", "t5", "t1", "t2", "t3"])

        let model = RingModel()
        model.herdr = .running(agents: 5)
        model.pinned = ["t5"]
        model.layout(list, now: now)
        let pinned = try XCTUnwrap(model.slices.first { $0.id == "t5" })
        let busy = try XCTUnwrap(model.slices.first { $0.id == "t1" })
        XCTAssertTrue(pinned.pinned)
        XCTAssertEqual(pinned.fresh, 1)
        XCTAssertEqual(pinned.end - pinned.start, busy.end - busy.start, accuracy: 1e-9)
        XCTAssertEqual(pinned.outer, busy.outer)
        XCTAssertEqual(pinned.ago, "3d ago")   // it still says how long it has been quiet
    }

    func testQuietWedgesKeepGettingThinnerAndShorterDownToHalfHeight() throws {
        let model = RingModel()
        model.herdr = .running(agents: 6)
        model.layout([
            agent("busy", "working", "a", quiet: 300), agent("busy2", "working", "b"), agent("hour", "done", "c", quiet: 60),
            agent("day", "done", "d", quiet: 60 * 24), agent("days", "idle", "e", quiet: 60 * 72), agent("month", "done", "f", quiet: 60 * 24 * 40),
        ], now: now)
        func slice(_ id: String) throws -> RingModel.Slice { try XCTUnwrap(model.slices.first { $0.id == id }) }
        let ids = ["busy", "hour", "day", "days", "month"]
        let widths = try ids.map { try slice($0).end - slice($0).start }
        let rims = try ids.map { try slice($0).outer }
        XCTAssertEqual(widths, widths.sorted(by: >))
        XCTAssertEqual(Set(widths).count, 5)
        XCTAssertEqual(rims, rims.sorted(by: >))
        XCTAssertEqual(Set(rims).count, 5)
        // Busy agents are all one width, however long they have been at it.
        XCTAssertEqual(try slice("busy2").end - slice("busy2").start, widths[0], accuracy: 1e-9)
        // The longest quiet is half as tall as a busy one, and no less.
        let month = try slice("month"), busy = try slice("busy")
        XCTAssertEqual(month.outer - month.inner, (busy.outer - busy.inner) / 2, accuracy: 1e-9)
        XCTAssertEqual(widths[4] / widths[0], RingModel.quietWidth, accuracy: 1e-9)
        // Colour is gone long before the size stops changing.
        XCTAssertEqual(try slice("day").fresh, 0)
    }

    func testAnAgentThatJustWentQuietStartsAtFullSizeAndShrinksSlowly() {
        XCTAssertEqual(agent("t1", "done", "a", quiet: 0).size(now: now), 1)
        XCTAssertGreaterThan(agent("t1", "done", "a", quiet: 10).size(now: now), 0.98)
        XCTAssertGreaterThan(agent("t1", "done", "a", quiet: 60).size(now: now), 0.95)
        XCTAssertGreaterThan(agent("t1", "done", "a", quiet: 6 * 60).size(now: now), 0.85)
        let day = agent("t1", "done", "a", quiet: 24 * 60).size(now: now)
        XCTAssertTrue(0.6 < day && day < 0.85, "\(day)")
        XCTAssertEqual(agent("t1", "idle", "a", quiet: 8 * 24 * 60).size(now: now), 0)
        XCTAssertEqual(agent("t1", "working", "a", quiet: 8 * 24 * 60).size(now: now), 1)
        XCTAssertEqual(agent("t1", "done", "a").size(now: now), 1)
    }

    func testLastActiveComesFromTheStatusTime() {
        XCTAssertEqual(AgentWatcher.lastActive(["status_ms": 1_794_674_912_276]), Date(timeIntervalSince1970: 1_794_674_912.276))
        XCTAssertNil(AgentWatcher.lastActive(["status_ms": NSNull()]))
        XCTAssertNil(AgentWatcher.lastActive([:]))
    }

    func testPlainListingKeepsWhatIsKnownAndNoticesAChange() {
        var known = agent("t1", "done", "a", quiet: 90)
        known.title = "Fix the build"
        let same = AgentWatcher.carry(from: [known], into: [agent("t1", "done", "a"), agent("t2", "done", "b")], now: now)
        XCTAssertEqual(same[0].title, "Fix the build")
        XCTAssertEqual(same[0].lastActive, known.lastActive)
        XCTAssertNil(same[1].lastActive)
        let changed = AgentWatcher.carry(from: [agent("t1", "working", "a", quiet: 90)], into: [agent("t1", "done", "a")], now: now)
        XCTAssertEqual(changed[0].lastActive, now)
    }

    func testSpaceOrderKeepsSessionsOfASpaceTogetherAndWaitingOnesFirst() {
        let list = [
            agent("t1", "working", "zebra", quiet: 0), agent("t2", "done", "Apple", "2", quiet: 300),
            agent("t3", "done", "mango", quiet: 5), agent("t4", "working", "apple-pie", quiet: 1),
            agent("t5", "idle", "Apple", "10", quiet: 2), agent("t6", "done", "Apple", "1", quiet: 900),
        ]
        XCTAssertEqual(RingModel.arrange(list, order: .space).map(\.id), ["t6", "t2", "t5", "t4", "t3", "t1"])
        // The same agents in a different state stay where they were.
        var later = list
        later[2] = agent("t3", "working", "mango", quiet: 0)
        XCTAssertEqual(RingModel.arrange(later, order: .space).map(\.id), ["t6", "t2", "t5", "t4", "t3", "t1"])
        // One that needs you brings its whole space to the front.
        later[0] = agent("t1", "blocked", "zebra")
        later.append(agent("t7", "done", "zebra", "2", quiet: 40))
        XCTAssertEqual(RingModel.arrange(later, order: .space).map(\.id), ["t1", "t7", "t6", "t2", "t5", "t4", "t3"])
    }

    func testRecentOrderPutsWaitingThenBusyThenLatestQuiet() {
        let list = [
            agent("t1", "done", "a", quiet: 300), agent("t2", "working", "b", quiet: 50), agent("t3", "done", "c", quiet: 5),
            agent("t4", "error", "d", quiet: 900), agent("t5", "working", "e", quiet: 2), agent("t6", "idle", "f"),
        ]
        XCTAssertEqual(RingModel.arrange(list, order: .recent).map(\.id), ["t4", "t5", "t2", "t3", "t1", "t6"])
    }

    func testEveryAgentGetsAWedgeAndTheyAllGetThinner() {
        func wheel(_ count: Int) -> RingModel {
            let model = RingModel()
            model.herdr = .running(agents: count)
            model.layout((0..<count).map { agent("t\($0)", "working", "s\($0)") } + [agent("w", "blocked", "s0", "2")], now: now)
            return model
        }
        let twelve = wheel(12), twenty = wheel(20)
        XCTAssertEqual(twelve.slices.count, 13)
        XCTAssertEqual(twenty.slices.count, 21)
        XCTAssertEqual(twenty.slices.first?.id, "w")
        // They share the whole circle, so each is thinner by the same share.
        XCTAssertEqual(twenty.slices.map { $0.end - $0.start }.reduce(0, +), 2 * .pi, accuracy: 1e-9)
        let ratio = (twenty.slices[1].end - twenty.slices[1].start) / (twelve.slices[1].end - twelve.slices[1].start)
        XCTAssertEqual(ratio, (12 + 1.45) / (20 + 1.45), accuracy: 1e-9)
        XCTAssertEqual((twenty.slices[0].end - twenty.slices[0].start) / (twenty.slices[1].end - twenty.slices[1].start), 1.45, accuracy: 1e-9)
        for order in RingOrder.allCases {
            let list = (0..<30).map { agent("t\($0)", "done", "s\($0)", quiet: Double(10 + $0)) }
            XCTAssertEqual(RingModel.arrange(list, order: order).count, 30)
        }
    }

    func testQuietWedgesRestSmallerAndGrowBackWhenPointedAt() throws {
        let model = RingModel()
        model.herdr = .running(agents: 3)
        model.layout([agent("t1", "working", "a"), agent("t2", "done", "b", quiet: 60 * 24), agent("t3", "done", "c", quiet: 1)], now: now)
        let busy = try XCTUnwrap(model.slices.first { $0.id == "t1" })
        let quiet = try XCTUnwrap(model.slices.first { $0.id == "t2" })
        XCTAssertEqual(quiet.fresh, 0)
        XCTAssertLessThan(quiet.end - quiet.start, busy.end - busy.start)
        XCTAssertLessThan(quiet.outer, busy.outer)
        // Pointed at, it is as wide and as tall as a busy one.
        XCTAssertEqual(quiet.end - quiet.start + 2 * quiet.widen, busy.end - busy.start, accuracy: 1e-9)
        XCTAssertEqual(quiet.reach, busy.outer)
        XCTAssertEqual(busy.widen, 0)
        XCTAssertEqual(busy.raise, 0)
        XCTAssertTrue(model.bands.isEmpty)
    }

    func testPointingGoesByWhereWedgesRestSoANeighbourIsAlwaysInReach() throws {
        let model = RingModel()
        model.herdr = .running(agents: 3)
        model.layout([agent("t1", "done", "a", quiet: 60 * 24), agent("t2", "done", "b", quiet: 60 * 24), agent("t3", "working", "c")], now: now)
        let quiet = try XCTUnwrap(model.slices.first { $0.id == "t1" })
        let next = try XCTUnwrap(model.slices.first { $0.id == "t2" })
        XCTAssertGreaterThan(quiet.widen, 0.01)
        func point(_ angle: Double) -> CGSize { CGSize(width: cos(angle) * 150, height: sin(angle) * 150) }
        // Just past its resting edge the grown wedge is drawn, but the neighbour whose place it is gets picked.
        model.highlighted = quiet.id
        XCTAssertEqual(model.target(for: point(quiet.end - 0.001)), quiet.id)
        XCTAssertEqual(model.target(for: point(quiet.end + quiet.widen / 2)), next.id)
        // The hub in the middle belongs to nobody.
        XCTAssertNil(model.target(for: CGSize(width: 10, height: 10)))
    }

    func testOnACrowdedWheelAPointedAtWedgeGrowsWideEnoughToRead() throws {
        let model = RingModel()
        model.herdr = .running(agents: 24)
        model.layout((0..<24).map { agent("t\($0)", $0 < 4 ? "working" : "done", "s\($0)", quiet: Double($0) * 600) }, now: now)
        let labelRadius = 96 + (model.outerRadius - 96) * 0.54
        for s in model.slices {
            XCTAssertGreaterThanOrEqual(CGFloat(s.end - s.start + 2 * s.widen) * labelRadius, RingModel.readableWidth - 0.001, s.id)
        }
        // Every one of them can still be pointed at.
        for s in model.slices {
            XCTAssertEqual(model.target(for: CGSize(width: cos(s.mid) * 150, height: sin(s.mid) * 150)), s.id)
        }
    }

    func testSessionsOfOneSpaceShareABandAndAreNamedByWhatTheyDo() throws {
        let model = RingModel()
        model.herdr = .running(agents: 4)
        var first = agent("t1", "working", "mouse", "1"), second = agent("t2", "done", "mouse", "2", quiet: 1)
        first.title = "Group the wheel"
        let named = agent("t4", "done", "mouse", "notes", quiet: 1)
        model.order = .space
        model.layout([agent("t3", "done", "alone", quiet: 1), second, first, named], now: now)
        XCTAssertEqual(model.slices.map(\.id), ["t3", "t1", "t2", "t4"])
        XCTAssertEqual(model.slices.map(\.inFamily), [false, true, true, true])
        XCTAssertEqual(model.slices.map(\.joinsPrevious), [false, false, true, true])
        let band = try XCTUnwrap(model.bands.first)
        XCTAssertEqual(model.bands.count, 1)
        XCTAssertEqual(band.name, "mouse")
        XCTAssertEqual(band.members, ["t1", "t2", "t4"])
        XCTAssertEqual(band.start, model.slices[1].start)
        XCTAssertEqual(band.end, model.slices[3].end)
        XCTAssertEqual(first.sessionName, "Group the wheel")
        XCTAssertEqual(second.sessionName, "Tab 2")
        XCTAssertEqual(named.sessionName, "notes")

        XCTAssertFalse(model.slices.contains { $0.sibling })

        // Ordered by recency there are no bands, even for sessions that land side by side;
        // each wedge is marked so it can say what its own session is about.
        model.order = .recent
        model.layout([first, agent("t3", "done", "alone", quiet: 30), agent("t2", "done", "mouse", "2", quiet: 1)], now: now)
        XCTAssertEqual(model.slices.map(\.id), ["t1", "t2", "t3"])
        XCTAssertTrue(model.bands.isEmpty)
        XCTAssertFalse(model.slices.contains { $0.inFamily })
        XCTAssertEqual(model.slices.map(\.sibling), [true, true, false])
    }

    func testBandNameIsCutToFitItsRoom() {
        let whole = ArcText.letters("mouse", room: 400)
        XCTAssertEqual(whole.map(\.letter).joined(), "mouse")
        XCTAssertEqual(whole.first!.at, -whole.last!.at, accuracy: 3)   // centred on the middle
        let cut = ArcText.letters("a-very-long-space-name-indeed", room: 60)
        XCTAssertEqual(cut.last?.letter, "…")
        XCTAssertLessThan(cut.count, 29)
        XCTAssertLessThanOrEqual(cut.last!.at - cut.first!.at, 60)
    }
}

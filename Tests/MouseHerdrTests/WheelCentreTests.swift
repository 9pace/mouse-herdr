import XCTest
@testable import MouseHerdr

/// The hub in the middle of the wheel, which stands for one agent so that it can be opened
/// without moving the pointer, and the version the window shows.
final class WheelCentreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func agent(_ id: String, _ status: String, quiet minutes: Double? = nil) -> AgentInfo {
        var a = AgentInfo(id: id, agent: "claude-code", status: status, space: "space-\(id)", tab: "1")
        a.lastActive = minutes.map { now.addingTimeInterval(-$0 * 60) }
        return a
    }

    private func wheel(_ agents: [AgentInfo], pinned: Set<String> = [], order: RingOrder = .recent, back: String? = nil) -> RingModel {
        let model = RingModel()
        model.back = back
        model.herdr = .running(agents: agents.count)
        model.pinned = pinned
        model.order = order
        model.layout(agents, now: now)
        return model
    }

    // MARK: Which agent the hub stands for

    func testTheHubStandsForWhoeverAskedMostRecently() {
        let model = wheel([
            agent("busy", "working", quiet: 1), agent("finished", "done", quiet: 0.2),
            agent("askedEarlier", "blocked", quiet: 30), agent("askedLast", "blocked", quiet: 2),
        ])
        XCTAssertEqual(model.centre, "askedLast")
        // An agent that failed wants attention as much as one that asks.
        XCTAssertEqual(wheel([agent("busy", "working", quiet: 1), agent("failed", "error", quiet: 50)]).centre, "failed")
    }

    func testWithNobodyWaitingTheHubStandsForTheAgentToGoBackTo() {
        let agents = [agent("longTurn", "working", quiet: 40), agent("newTurn", "working", quiet: 1), agent("finished", "done", quiet: 0.1)]
        let model = wheel(agents, back: "longTurn")
        XCTAssertEqual(model.centre, "longTurn")
        XCTAssertTrue(model.centreIsBack)
        // Without one to go back to, or with one that has gone, the middle stands for no one.
        XCTAssertNil(wheel(agents).centre)
        XCTAssertNil(wheel(agents, back: "closed").centre)
        XCTAssertFalse(wheel(agents).centreIsBack)
        // Someone asking comes first.
        let asked = wheel(agents + [agent("asking", "blocked", quiet: 5)], back: "longTurn")
        XCTAssertEqual(asked.centre, "asking")
        XCTAssertFalse(asked.centreIsBack)
    }

    func testNeitherAPinNorTheOrderChangesWhoTheHubStandsFor() {
        let agents = [agent("pinnedOld", "done", quiet: 600), agent("latest", "working", quiet: 1), agent("before", "working", quiet: 9)]
        XCTAssertEqual(wheel(agents, pinned: ["pinnedOld"], back: "before").centre, "before")
        XCTAssertEqual(wheel(agents, pinned: ["pinnedOld"], order: .space, back: "before").centre, "before")
    }

    func testTheAgentToGoBackToKeepsAWedgeEvenWhenItIsIdle() {
        let agents = [agent("busy", "working", quiet: 1), agent("idleA", "idle", quiet: 9), agent("idleB", "idle", quiet: 9), agent("before", "idle", quiet: 3)]
        let model = wheel(agents, back: "before")
        XCTAssertEqual(model.centre, "before")
        XCTAssertTrue(model.slices.contains { $0.id == "before" })
        XCTAssertEqual(model.slices.first { $0.id == RingModel.foldID }?.folded, 2)
    }

    func testAWheelWithNoAgentsHasNothingInTheMiddle() {
        XCTAssertNil(wheel([]).centre)
        let stopped = RingModel()
        stopped.herdr = .notRunning
        stopped.layout([agent("stale", "blocked", quiet: 1)], now: now)
        XCTAssertNil(stopped.centre, "without herdr-core there is nothing true to open")
    }

    func testTheHubKeepsItsAgentWhileTheWheelIsOpenAndMovesOnOnceItIsAnswered() {
        let model = wheel([agent("first", "blocked", quiet: 10), agent("busy", "working", quiet: 1)])
        XCTAssertEqual(model.centre, "first")

        // Another agent asks something while the first question is being read: the hub stays put.
        let second = agent("second", "blocked", quiet: 0)
        model.layout([agent("first", "blocked", quiet: 10), agent("busy", "working", quiet: 1), second], now: now)
        XCTAssertEqual(model.centre, "first")

        // The first one is answered and gets on with it: the next question takes the hub.
        model.layout([agent("first", "working", quiet: 0), agent("busy", "working", quiet: 1), second], now: now)
        XCTAssertEqual(model.centre, "second")

        // That agent goes away altogether: the hub falls back to the agent to go back to.
        model.back = "busy"
        model.layout([agent("first", "working", quiet: 0), agent("busy", "working", quiet: 1)], now: now)
        XCTAssertEqual(model.centre, "busy")
    }

    func testAnAgentThatStartsAskingWhileItHasTheHubIsLookedAtAgain() {
        let model = wheel([agent("latest", "working", quiet: 1), agent("older", "done", quiet: 9)], back: "latest")
        XCTAssertEqual(model.centre, "latest")
        // Somebody else starts waiting: with nobody waiting before, the hub's agent keeps the hub.
        model.layout([agent("latest", "working", quiet: 1), agent("older", "blocked", quiet: 0)], now: now)
        XCTAssertEqual(model.centre, "latest", "what a click would open does not change under the pointer")
        // The wheel is opened afresh: now the one that is waiting has it.
        model.forgetCentre()
        model.layout([agent("latest", "working", quiet: 1), agent("older", "blocked", quiet: 0)], now: now)
        XCTAssertEqual(model.centre, "older")
    }

    func testTheFrontTerminalIsTheActiveTabOfTheActiveSpace() {
        let listing = """
        {"spaces":[
          {"machine":null,"active":false,"tabs":[{"active":true,"terminals":[{"terminal":"t1"}]}]},
          {"machine":null,"active":true,"tabs":[{"active":false,"terminals":[{"terminal":"t2"}]},{"active":true,"terminals":[{"terminal":"t3"},{"terminal":"t4"}]}]}
        ]}
        """
        XCTAssertEqual(AgentWatcher.frontTerminal(in: Data(listing.utf8)), "t3")
        let remote = #"{"spaces":[{"machine":"devdesk","active":true,"tabs":[{"active":true,"terminals":[{"terminal":"t7"}]}]}]}"#
        XCTAssertEqual(AgentWatcher.frontTerminal(in: Data(remote.utf8)), "devdesk/t7")
        XCTAssertNil(AgentWatcher.frontTerminal(in: Data("{}".utf8)))
    }

    func testTheAgentInFrontBecomesTheOneToGoBackToWhenAnotherTakesItsPlace() {
        var fronts = FrontHistory()
        fronts.note("t1")
        XCTAssertNil(fronts.back)
        fronts.note("t2")
        XCTAssertEqual(fronts.back, "t1")
        // Hearing the same one again, or nothing, changes nothing.
        fronts.note("t2")
        fronts.note(nil)
        XCTAssertEqual(fronts.front, "t2")
        XCTAssertEqual(fronts.back, "t1")
        fronts.note("t1")
        XCTAssertEqual(fronts.back, "t2")
    }

    // MARK: Aiming

    func testOnTheHubThePointerAimsAtTheHubsAgentAndElsewhereAtAWedge() throws {
        let model = wheel([agent("asking", "blocked", quiet: 1), agent("busy", "working", quiet: 2), agent("quiet", "done", quiet: 30)])
        XCTAssertEqual(model.centre, "asking")
        // Where the pointer rests as the wheel opens, and anywhere else on the hub.
        XCTAssertEqual(model.aim(at: .zero), "asking")
        XCTAssertEqual(model.aim(at: CGSize(width: 20, height: -30)), "asking")
        XCTAssertNil(model.target(for: .zero), "the hub is not part of any wedge")
        XCTAssertTrue(RingModel.isOnHub(CGSize(width: RingModel.hubRadius, height: 0)))
        XCTAssertFalse(RingModel.isOnHub(CGSize(width: RingModel.hubRadius + 1, height: 0)))

        // Off the hub, it is the wedge under the pointer, whichever agent the hub stands for.
        for slice in model.slices {
            let radius = Double((slice.inner + slice.outer) / 2)
            let point = CGSize(width: cos(slice.mid) * radius, height: sin(slice.mid) * radius)
            XCTAssertEqual(model.aim(at: point), slice.id)
        }
        // A wheel with nothing in it has nothing to aim at from the middle.
        XCTAssertNil(wheel([]).aim(at: .zero))
    }

    // MARK: Having the question to hand

    /// A waiting agent as a full look finds it, with what it asks and the choices it offers.
    private func asking(_ id: String, _ question: String) -> AgentInfo {
        var a = agent(id, "blocked", quiet: 3)
        a.title = "Refunds"
        a.message = "answer: \(question) (Yes · No)"
        a.kind = "question"
        a.prompt = "Do you want to proceed?"
        a.screenOptions = ["Yes", "No"]
        a.hints = [1: "Go ahead"]
        a.typeOption = 3
        return a
    }

    func testAWaitingAgentKeepsItsQuestionBetweenLooksSoTheWheelCanOpenWithIt() {
        let known = asking("t1", "Ship it?")
        // The plain listing, taken every few seconds, says only that it is still waiting.
        let listed = AgentWatcher.carry(from: [known], into: [agent("t1", "blocked")], now: now)
        XCTAssertEqual(listed[0].message, known.message)
        XCTAssertEqual(listed[0].speech.text, "Ship it?")
        XCTAssertEqual(listed[0].speech.options, ["Yes", "No"])
        XCTAssertEqual(listed[0].kind, "question")
        XCTAssertEqual(listed[0].prompt, "Do you want to proceed?")
        XCTAssertEqual(listed[0].screenOptions, ["Yes", "No"])
        XCTAssertEqual(listed[0].hints, [1: "Go ahead"])
        XCTAssertEqual(listed[0].typeOption, 3)
        XCTAssertEqual(listed[0].title, "Refunds")
        XCTAssertEqual(listed[0].lastActive, known.lastActive)
    }

    func testAQuestionIsForgottenOnceTheAgentIsNoLongerWaiting() {
        let answered = AgentWatcher.carry(from: [asking("t1", "Ship it?")], into: [agent("t1", "working")], now: now)
        XCTAssertEqual(answered[0].message, "", "an agent that got its answer is not shown still asking")
        XCTAssertTrue(answered[0].screenOptions.isEmpty)
        XCTAssertNil(answered[0].typeOption)
        XCTAssertEqual(answered[0].title, "Refunds", "what the session is about stays")
        XCTAssertEqual(answered[0].lastActive, now)
    }

    func testWhatALookHasJustReadIsNotOverwrittenByWhatWasKnownBefore() {
        // The agent moved on to a second question while still waiting; this look read it.
        var fresh = asking("t1", "And deploy it?")
        fresh.title = "Refunds, part two"
        let merged = AgentWatcher.carry(from: [asking("t1", "Ship it?"), asking("t2", "Other?")],
                                        into: [fresh, agent("t2", "blocked")], fresh: ["t1"], now: now)
        XCTAssertEqual(merged[0].speech.text, "And deploy it?")
        XCTAssertEqual(merged[0].title, "Refunds, part two")
        // The other one was only listed, and keeps the question it was last seen with.
        XCTAssertEqual(merged[1].speech.text, "Other?")
    }

    func testAQuestionCanBeReadAtOnceButAnsweredOnlyOnceItIsKnownToBeCurrent() {
        let model = wheel([asking("t1", "Ship it?")])
        // The wheel has just opened with the question it had to hand.
        XCTAssertFalse(model.confirmed)
        XCTAssertFalse(model.canAnswer, "the agent may have moved on, and an answer is a key press")
        // The agents have been looked at again.
        model.confirmed = true
        XCTAssertTrue(model.canAnswer)
        // One answer at a time.
        model.sentOption = 0
        XCTAssertFalse(model.canAnswer)
    }

    // MARK: Escape

    func testEscapeClosesTheWheelAndTheAppInFrontNeverSeesIt() {
        var key = EscapeKey()
        key.watching = true                       // the wheel is up
        XCTAssertTrue(key.needsTap)
        XCTAssertEqual(key.pressed(repeating: false, plain: true), .ask)
        key.watching = false                      // …and using the key put it away
        // The key is still down: its repeats and its release are kept too, so the app in front
        // does not get the tail end of a key press it never saw begin.
        XCTAssertTrue(key.needsTap)
        XCTAssertEqual(key.pressed(repeating: true, plain: true), .keep)
        XCTAssertEqual(key.pressed(repeating: true, plain: true), .keep)
        XCTAssertTrue(key.released())
        // Let go, with the wheel closed: no key is looked at any more.
        XCTAssertFalse(key.needsTap)
        XCTAssertFalse(key.held)
    }

    func testEscapeIsLeftAloneWhenTheWheelIsNotShowing() {
        var key = EscapeKey()
        XCTAssertFalse(key.needsTap)
        XCTAssertEqual(key.pressed(repeating: false, plain: true), .pass)
        XCTAssertFalse(key.released(), "its release goes to the app as well")
        XCTAssertFalse(key.held)
    }

    func testEscapeWithCommandOrOptionBelongsToTheSystem() {
        var key = EscapeKey()
        key.watching = true
        // ⌥⌘⎋ opens Force Quit; that is not ours to take.
        XCTAssertEqual(key.pressed(repeating: false, plain: false), .pass)
        XCTAssertFalse(key.released())
    }

    func testAnEscapeThatNothingWantedGoesThrough() {
        var key = EscapeKey()
        key.watching = true
        XCTAssertEqual(key.pressed(repeating: false, plain: true), .ask)
        key.notUsed()                             // the wheel had just closed by itself
        XCTAssertFalse(key.held)
        XCTAssertFalse(key.released(), "the release follows the press to the app")
    }

    func testAMissedReleaseDoesNotSwallowTheNextEscape() {
        var key = EscapeKey()
        key.watching = true
        XCTAssertEqual(key.pressed(repeating: false, plain: true), .ask)
        // The release never arrived. The wheel is opened again and Escape pressed afresh:
        // it is asked about, not kept as a repeat of the old one.
        XCTAssertEqual(key.pressed(repeating: false, plain: true), .ask)
        key.watching = false
        // And pressed afresh with nothing showing, it goes to the app.
        XCTAssertEqual(key.pressed(repeating: false, plain: true), .pass)
        XCTAssertFalse(key.held)
    }

    func testSwitchingTheKeyTapOffIsAskedForOnce() {
        var key = EscapeKey()
        XCTAssertNil(key.tapChange(), "nothing to watch for, and no tap yet")
        key.watching = true                       // the wheel opens; the tap is made, which leaves it on
        key.tapIs(on: true)
        XCTAssertNil(key.tapChange())
        key.watching = false                      // the wheel closes
        XCTAssertEqual(key.tapChange(), false)
        // The system reports that switching-off back to the tap. Answering it by switching the
        // tap off again would be reported again, without end.
        key.tapIs(on: false)
        XCTAssertNil(key.tapChange())
        XCTAssertNil(key.tapChange())
        key.watching = true                       // the wheel opens again
        XCTAssertEqual(key.tapChange(), true)
        XCTAssertNil(key.tapChange())
    }

    func testAKeyTapTheSystemSwitchedOffIsSwitchedBackOnWhileTheWheelShows() {
        var key = EscapeKey()
        key.watching = true
        key.tapIs(on: true)
        key.tapIs(on: false)                      // the system gave up on it: it was too slow to answer
        XCTAssertEqual(key.tapChange(), true)
        // A report that arrives late, after the wheel opened again, costs one more switching-on
        // and no more.
        key.tapIs(on: false)
        XCTAssertEqual(key.tapChange(), true)
        XCTAssertNil(key.tapChange())
    }

    func testTheKeyTapStaysOnForTheReleaseOfAnEscapeThatWasUsed() {
        var key = EscapeKey()
        key.watching = true
        key.tapIs(on: true)
        XCTAssertEqual(key.pressed(repeating: false, plain: true), .ask)
        key.watching = false                      // using it closed the wheel
        XCTAssertNil(key.tapChange(), "still on: the release has yet to come")
        XCTAssertTrue(key.released())
        XCTAssertEqual(key.tapChange(), false)
    }

    // MARK: The version in the window

    func testTheWindowSaysWhichCopyIsRunning() {
        XCTAssertEqual(AppVersion.label(number: "1.0.37", commit: "c48b7e7"), "v1.0.37 · c48b7e7")
        XCTAssertEqual(AppVersion.label(number: "1.0", commit: "c48b7e7+"), "v1.0 · c48b7e7+")
        XCTAssertEqual(AppVersion.label(number: "1.0", commit: nil), "v1.0")
        XCTAssertEqual(AppVersion.label(number: nil, commit: "c48b7e7"), "c48b7e7")
        XCTAssertNil(AppVersion.label(number: nil, commit: nil), "a copy that doesn't know says nothing")
    }

    func testTheVersionCanBeSaidInWords() {
        XCTAssertEqual(AppVersion.sentence(number: "1.0.37", commit: nil, branch: nil), "MouseHerdr 1.0.37")
        XCTAssertEqual(AppVersion.sentence(number: "1.0", commit: "c48b7e7", branch: "main"),
                       "MouseHerdr 1.0, built from commit c48b7e7 on main")
        XCTAssertEqual(AppVersion.sentence(number: "1.0", commit: "c48b7e7+", branch: "feature/wheel"),
                       "MouseHerdr 1.0, built from commit c48b7e7 on feature/wheel, with changes that were not committed")
        XCTAssertEqual(AppVersion.sentence(number: "1.0", commit: "c48b7e7", branch: nil), "MouseHerdr 1.0, built from commit c48b7e7")
        XCTAssertEqual(AppVersion.sentence(number: nil, commit: nil, branch: "main"), "MouseHerdr of an unknown version")
    }
}

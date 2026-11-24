import XCTest
@testable import MouseHerdr

final class UnreadTests: XCTestCase {
    private func done(turn: Int, seen: Int?, known: Bool = true, status: String = "done") -> AgentInfo {
        var a = AgentInfo(id: "t1", agent: "claude-code", status: status, space: "Shop: cart", tab: "1")
        a.turn = turn
        a.seenTurn = seen
        a.seenKnown = known
        a.inApp = true
        return a
    }

    func testAFinishedAgentIsUnreadUntilTheTurnItFinishedOnHasBeenSeen() {
        XCTAssertTrue(done(turn: 5, seen: 4).unread)
        XCTAssertFalse(done(turn: 5, seen: 5).unread)
        // One the Herdr app has never shown has no seen turn at all.
        XCTAssertTrue(done(turn: 1, seen: nil).unread)
        // Before herdr-core has been asked, nothing is called unread.
        XCTAssertFalse(done(turn: 5, seen: nil, known: false).unread)
        // One with no tab in the Herdr app cannot be seen there, so it is never unread.
        var outside = done(turn: 1, seen: nil)
        outside.inApp = false
        XCTAssertFalse(outside.unread)
        XCTAssertTrue(AgentWatcher.inApp(["labels": ["herdr.tab": "tb1"]]))
        XCTAssertFalse(AgentWatcher.inApp(["labels": [:]]))
        // Only a finished agent can be unread.
        XCTAssertFalse(done(turn: 5, seen: 4, status: "idle").unread)
        XCTAssertFalse(done(turn: 5, seen: 4, status: "working").unread)
    }

    func testTheTurnComesFromTheListingAndTheSeenTurnFromTheAppsLabel() throws {
        let list = try XCTUnwrap(AgentWatcher.parseList(Data(#"{"terminals":[{"address":"t1","agent":"claude-code","status":"done","turn":7,"where":"a / b"}]}"#.utf8)))
        XCTAssertEqual(list.first?.turn, 7)
        XCTAssertEqual(AgentWatcher.seenTurn(["labels": ["herdr.seen": "7"]]), 7)
        XCTAssertNil(AgentWatcher.seenTurn(["labels": ["where": "a / b"]]))
        XCTAssertNil(AgentWatcher.seenTurn([:]))
    }

    func testWhatWasSeenIsKeptAcrossAPlainListing() {
        let before = done(turn: 5, seen: 5)
        var fresh = AgentInfo(id: "t1", agent: "claude-code", status: "done", space: "Shop: cart", tab: "1")
        fresh.turn = 6
        // The agent took another turn since: the plain listing knows the turn, and what was seen is carried.
        let carried = AgentWatcher.carry(from: [before], into: [fresh])
        XCTAssertEqual(carried.first?.seenTurn, 5)
        XCTAssertTrue(carried.first?.unread ?? false)
    }
}

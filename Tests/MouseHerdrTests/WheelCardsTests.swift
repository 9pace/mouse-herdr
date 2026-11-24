import SwiftUI
import XCTest
@testable import MouseHerdr

/// What the wheel says about the agent being pointed at: a bubble with the question and its
/// answers for one that is asking, and a caption under the wheel for any other.
///
/// The bubble used to be the place for both. Where the screen ended before it fitted beyond
/// its wedge, it was pushed back onto the wheel and the wedge was drawn over its last answers.
final class WheelCardsTests: XCTestCase {
    private func agent(_ id: String, _ status: String, space: String = "", tab: String = "1", title: String = "") -> AgentInfo {
        var a = AgentInfo(id: id, agent: "claude-code", status: status, space: space.isEmpty ? "space-\(id)" : space, tab: tab)
        a.title = title
        a.lastActive = Date()
        return a
    }

    private func asking(_ id: String) -> AgentInfo {
        var a = agent(id, "blocked")
        a.kind = "question"
        a.message = "answer: Which one? (This · That · The other)"
        return a
    }

    private func wheel(_ agents: [AgentInfo], pointingAt id: String) -> RingModel {
        let model = RingModel()
        model.herdr = .running(agents: agents.count)
        model.layout(agents)
        model.highlighted = id
        return model
    }

    /// How far the nearest point of a bubble is from the wheel's centre.
    private func gap(_ spot: CGPoint, _ size: CGSize) -> CGFloat {
        hypot(max(abs(spot.x) - size.width / 2, 0), max(abs(spot.y) - size.height / 2, 0))
    }

    // MARK: Where the bubble goes

    // The wheel of the screenshot that showed the fault: a dozen wedges, so 300 points across
    // its radius, with the asking agent's wedge at the top and four answers to its question.
    private let size = CGSize(width: 400, height: 470)
    private let up = -Double.pi / 2
    private let reach: CGFloat = 316
    private let clearance: CGFloat = 362

    func testABubbleGoesJustBeyondItsWedgeWhereThereIsRoom() {
        let room = CGRect(x: -1200, y: -1000, width: 2400, height: 2000)
        let placed = RingModel.bubbleSpot(size: size, mid: up, reach: reach, clearance: clearance, room: room)
        XCTAssertFalse(placed.round)
        XCTAssertEqual(placed.spot.x, 0, accuracy: 0.01)
        // Its near edge is 54 points beyond the wedge.
        XCTAssertEqual(placed.spot.y + size.height / 2, -(reach + 54), accuracy: 0.01)
    }

    func testWhereTheScreenEndsBeforeItFitsTheBubbleGoesRoundTheWheelAndStaysOffIt() {
        // The screen ends 640 points above the wheel's centre, and the bubble needs 840.
        let room = CGRect(x: -1200, y: -640, width: 2400, height: 1440)
        let placed = RingModel.bubbleSpot(size: size, mid: up, reach: reach, clearance: clearance, room: room)
        XCTAssertTrue(placed.round)
        // On the screen…
        let box = CGRect(x: placed.spot.x - size.width / 2, y: placed.spot.y - size.height / 2, width: size.width, height: size.height)
        XCTAssertTrue(room.contains(box), "\(box) is not inside \(room)")
        // …and clear of the wheel, where it used to be pushed down onto its own wedge.
        XCTAssertGreaterThanOrEqual(gap(placed.spot, size), clearance - 0.5)
        // As near its wedge as that allows: still in the upper half, beside the wheel.
        XCTAssertLessThan(placed.spot.y, 0)
    }

    func testItGoesRoundTheWheelOnTheSideThatHasRoom() {
        // No room above, and the screen ends just to the right of the wheel as well.
        let room = CGRect(x: -1200, y: -640, width: 1200 + 420, height: 1440)
        let placed = RingModel.bubbleSpot(size: size, mid: up, reach: reach, clearance: clearance, room: room)
        XCTAssertTrue(placed.round)
        XCTAssertLessThan(placed.spot.x, 0)
        XCTAssertGreaterThanOrEqual(gap(placed.spot, size), clearance - 0.5)
    }

    func testOnAScreenWithNoRoomAnywhereTheBubbleIsStillKeptOnIt() {
        let room = CGRect(x: -420, y: -420, width: 840, height: 840)
        let placed = RingModel.bubbleSpot(size: size, mid: up, reach: reach, clearance: clearance, room: room)
        XCTAssertFalse(placed.round)
        let box = CGRect(x: placed.spot.x - size.width / 2, y: placed.spot.y - size.height / 2, width: size.width, height: size.height)
        XCTAssertTrue(room.contains(box))
    }

    func testThePointerPassesOverOtherWedgesOnlyWhileItIsGettingCloserToTheBubble() {
        let now = Date()
        XCTAssertTrue(AgentRing.passesOver(nearing: now.addingTimeInterval(-0.1), now: now))
        // Stopped on a wedge, or turned away from the bubble: that wedge is aimed at.
        XCTAssertFalse(AgentRing.passesOver(nearing: now.addingTimeInterval(-0.5), now: now))
        XCTAssertFalse(AgentRing.passesOver(nearing: nil, now: now))
    }

    // MARK: What is said about the agent being pointed at

    func testAnAgentThatIsNotAskingHasACaptionWithItsWholePlaceAndWhatItIsAbout() {
        let done = agent("t1", "done", space: "CLI perf benchmark design: open questions", tab: "review",
                         title: "CDK integration tests architecture")
        let model = wheel([done, agent("t2", "working")], pointingAt: "t1")
        XCTAssertEqual(model.caption, RingModel.Caption(place: "CLI perf benchmark design: open questions  ·  review",
                                                        detail: "CDK integration tests architecture"))
    }

    func testAnAgentThatIsAskingHasItsBubbleAndNoCaption() {
        let model = wheel([asking("t1"), agent("t2", "working")], pointingAt: "t1")
        XCTAssertNil(model.caption)
    }

    func testNothingIsWrittenUnderTheWheelFromTheHubOrForTheSharedIdleWedge() {
        let agents = [agent("t1", "working", title: "Cart"), agent("t2", "idle"), agent("t3", "idle")]
        let model = wheel(agents, pointingAt: "t1")
        XCTAssertNotNil(model.caption)
        // On the hub the pointer has not picked anyone yet.
        model.onHub = true
        XCTAssertNil(model.caption)
        model.onHub = false
        model.highlighted = RingModel.foldID
        XCTAssertNil(model.caption)
    }

    func testOnlyAnAgentThatIsAskingGetsABubbleOnTheOpenWheel() {
        let waiting = asking("t1")
        let done = agent("t2", "done", title: "Release notes")
        let ring = AgentRing(onScreen: false)
        addTeardownBlock { ring.close() }
        ring.show([waiting, done], herdr: .running(agents: 2), appInstalled: true)

        ring.model.highlighted = "t2"
        ring.model.onHub = false
        ring.update([waiting, done], herdr: .running(agents: 2), appInstalled: true)
        XCTAssertNil(ring.model.bubble)
        XCTAssertEqual(ring.model.caption?.detail, "Release notes")

        ring.model.highlighted = "t1"
        ring.update([waiting, done], herdr: .running(agents: 2), appInstalled: true)
        XCTAssertEqual(ring.model.bubble?.optionCount, 3)
        XCTAssertNil(ring.model.caption)
    }

    // MARK: Glass

    /// The views of a kind under a view, however deep.
    private func descendants<T: NSView>(of view: NSView, _ kind: T.Type) -> [T] {
        view.subviews.flatMap { ($0 as? T).map { [$0] } ?? [] + descendants(of: $0, kind) }
    }

    /// A card drawn in a window that is never put on the screen.
    private func card(live: Bool) -> NSView {
        let glass = WheelGlass(outline: { Path(roundedRect: $0, cornerRadius: 24, style: .continuous) }, live: live)
            .frame(width: 400, height: 300)
        let host = NSHostingView(rootView: glass)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        addTeardownBlock { window.close() }
        return host
    }

    func testOnTheScreenACardShowsWhatIsBehindTheWindowBlurredInItsOwnShape() throws {
        let blur = try XCTUnwrap(descendants(of: card(live: true), NSVisualEffectView.self).first)
        XCTAssertEqual(blur.blendingMode, .behindWindow)
        // The wheel's window is never the active one; glass that waited for that would stay flat.
        XCTAssertEqual(blur.state, .active)
        // Cut to the card's outline, with room round it for a bubble's tail.
        let mask = try XCTUnwrap(blur.maskImage)
        XCTAssertEqual(mask.size, CGSize(width: 400 + 2 * WheelGlass.bleed, height: 300 + 2 * WheelGlass.bleed))
    }

    func testOffTheScreenTheCardsAreNotGlass() {
        // A picture or a test has nothing behind the window to show through, and a picture
        // cannot draw a view that blurs.
        XCTAssertFalse(AgentRing(onScreen: false).model.glass)
        XCTAssertFalse(RingModel().glass)
        XCTAssertTrue(descendants(of: card(live: false), NSVisualEffectView.self).isEmpty)
    }
}

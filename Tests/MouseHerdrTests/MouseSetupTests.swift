import XCTest
@testable import MouseHerdr

final class MouseSetupTests: XCTestCase {
    private let microsoft = MouseDevice(vendorID: 0x045E, productID: 0x00CB, name: "Microsoft USB Optical Mouse", transport: "USB", buttons: 3)
    private let magic = MouseDevice(vendorID: 0x004C, productID: 0x0269, name: "Roy’s Magic Mouse", transport: "Bluetooth")
    private let receiver = MouseDevice(vendorID: 0x046D, productID: 0xC52B, name: "USB Receiver", transport: "USB", buttons: 16)
    private let unknown = MouseDevice(vendorID: 0x1BCF, productID: 0x0005, name: "2.4G Wireless Mouse", transport: "USB", buttons: 5)

    private func profile(_ id: String) -> MouseProfile { MouseProfile.named(id)! }

    private func triggers(_ p: MouseProfile, _ changes: [Slot: Action] = [:], ringOnTap: Bool = true) -> [String] {
        MouseSetup.triggers(profile: p, assignments: p.defaults.merging(changes) { _, new in new }, ringOnTap: ringOnTap)
    }

    // MARK: What opens the wheel

    func testOutOfTheBoxTheWheelClickOpensTheWheelOnAnOrdinaryMouse() {
        XCTAssertEqual(triggers(profile("msBasicOptical")), ["The wheel click"])
        XCTAssertEqual(triggers(.generic), ["The wheel click"])
        XCTAssertEqual(triggers(profile("kensingtonExpert")), ["The top left button"])
    }

    func testTheMXMaster4OpensItWithATapOnItsPadUnlessThatIsSwitchedOff() {
        XCTAssertEqual(triggers(.mxMaster4), ["A quick tap on the haptic panel"])
        XCTAssertEqual(triggers(.mxMaster4, ringOnTap: false), [])
        // The pad only opens the wheel while it is set to drag windows.
        XCTAssertEqual(triggers(.mxMaster4, [.thumbPanel: Action(kind: "copy")]), [])
    }

    func testEveryButtonGivenTheWheelIsListedIncludingGestures() {
        let found = triggers(profile("mxMaster3S"), [.back: Action(kind: "agentWheel"), .gestureUp: Action(kind: "agentWheel")])
        XCTAssertEqual(found, ["The wheel click", "The back button", "Gesture button: hold + move up"])
        XCTAssertEqual(triggers(profile("msBasicOptical"), [.middle: .standard]), [])
    }

    // MARK: What a new mouse is told

    func testANewMouseIsToldWhichButtonOpensTheWheelAndToTryIt() {
        let p = profile("msBasicOptical")
        let notice = MouseSetup.notice(for: microsoft, profile: p, triggers: triggers(p))
        XCTAssertEqual(notice.kind, .ready)
        XCTAssertEqual(notice.title, "Microsoft Basic Optical Mouse detected")
        XCTAssertTrue(notice.text.hasPrefix("The wheel click now opens the agent wheel"), notice.text)
        XCTAssertTrue(notice.text.contains("in place of a middle click"), "it says what the button no longer does: \(notice.text)")
        XCTAssertTrue(notice.text.contains("Press it to try"), notice.text)
        // A button that was never a middle click gives nothing up.
        let back = MouseSetup.notice(for: microsoft, profile: .generic, triggers: ["The back button"])
        XCTAssertFalse(back.text.contains("middle click"), back.text)
        XCTAssertEqual(notice.primary, "Got it")
        XCTAssertEqual(notice.secondary, "Choose another button…")
        XCTAssertEqual(notice.device, microsoft)
    }

    func testAMouseWithNoSpareButtonIsToldSoInsteadOfBeingPromisedOne() {
        let p = profile("magicMouse")
        let notice = MouseSetup.notice(for: magic, profile: p, triggers: triggers(p))
        XCTAssertEqual(notice.kind, .noButton)
        XCTAssertEqual(notice.title, "Apple Magic Mouse detected", "the owner's name on the device is not repeated")
        XCTAssertTrue(notice.text.contains("no spare button"), notice.text)
        XCTAssertTrue(notice.text.contains("menu bar"), notice.text)
        XCTAssertNil(notice.secondary)
        XCTAssertEqual(MouseSetup.notice(for: microsoft, profile: .generic2, triggers: []).kind, .noButton)
    }

    func testAMouseWhoseButtonsAreAllTakenIsAskedToChooseOne() {
        let p = profile("msBasicOptical")
        // Its wheel click was given another job, carried over from the MX Master 4.
        let notice = MouseSetup.notice(for: microsoft, profile: p, triggers: triggers(p, [.middle: Action(kind: "copy")]))
        XCTAssertEqual(notice.kind, .chooseButton)
        XCTAssertEqual(notice.primary, "Choose a button…")
        XCTAssertTrue(notice.text.contains("Nothing on it opens the agent wheel yet"), notice.text)
    }

    func testAReceiverIsNotSaidToBeAMouse() {
        let p = profile("logitechReceiver")
        let notice = MouseSetup.notice(for: receiver, profile: p, triggers: triggers(p))
        XCTAssertEqual(notice.kind, .ready)
        XCTAssertEqual(notice.title, "Logitech USB receiver detected")
        XCTAssertTrue(notice.text.hasPrefix("If a mouse is connected through it: the wheel click now opens"), notice.text)
    }

    func testAnUnknownMouseIsCalledWhatItCallsItself() {
        let notice = MouseSetup.notice(for: unknown, profile: .generic, triggers: triggers(.generic))
        XCTAssertEqual(notice.title, "2.4G Wireless Mouse detected")
        XCTAssertEqual(MouseSetup.title(device: MouseDevice(vendorID: 1, productID: 2), profile: .generic), "Five-button mouse")
    }

    func testASecondMouseIsOfferedWithoutTakingOver() {
        let notice = MouseSetup.notice(alsoConnected: microsoft, following: "Logitech MX Master 4")
        XCTAssertEqual(notice.kind, .alsoConnected)
        XCTAssertEqual(notice.title, "Microsoft Basic Optical Mouse is connected too")
        XCTAssertTrue(notice.text.contains("one mouse at a time"), notice.text)
        XCTAssertTrue(notice.text.contains("your Logitech MX Master 4"), notice.text)
        XCTAssertEqual(notice.primary, "Use this mouse")
        XCTAssertEqual(notice.secondary, "Not now")
        XCTAssertEqual(MouseSetup.notice(alsoConnected: unknown, following: "x").title, "2.4G Wireless Mouse is connected too")
    }

    // MARK: What is said, and when

    private let mx4 = MouseDevice(vendorID: 0x046D, productID: 0xB042, name: "MX Master 4", transport: "Bluetooth Low Energy", buttons: 7)

    /// What the app would say now. It asks after every change and every couple of seconds.
    private func next(following mouse: MouseDevice?, among connected: [MouseDevice], memory: MouseMemory,
                      byChoice: Bool = false) -> MouseNotice? {
        let p = MouseChooser.profile(for: mouse, memory: memory, firstRun: true)
        return MouseSetup.nextNotice(following: mouse, profile: p, among: MouseChooser.candidates(connected),
                                     triggers: triggers(p), memory: memory, byChoice: byChoice)
    }

    /// The Mac this was developed on, the first time the new version starts: an MX Master 4 in
    /// use, a Microsoft mouse plugged in beside it, and a receiver.
    func testASecondMouseIsOfferedOnceAndIntroducedOnceItIsTaken() throws {
        var memory = MouseMemory()
        let connected = [mx4, microsoft, receiver]

        // The MX Master 4 is followed and needs no introduction, so the other mouse is offered.
        let offer = try XCTUnwrap(next(following: mx4, among: connected, memory: memory))
        XCTAssertEqual(offer.kind, .alsoConnected)
        XCTAssertEqual(offer.device, microsoft)
        XCTAssertTrue(offer.text.contains("your Logitech MX Master 4"), offer.text)

        // Once it has been seen it is not offered again. The receiver never is: it may have no mouse behind it.
        MouseSetup.acknowledge(offer, in: &memory)
        XCTAssertTrue(memory.wasOffered(microsoft))
        XCTAssertFalse(memory.wasIntroduced(microsoft), "being offered is not being introduced")
        XCTAssertNil(next(following: mx4, among: connected, memory: memory))
        XCTAssertFalse(memory.wasOffered(receiver))

        // "Use this mouse": the Microsoft mouse is followed, and only now is its owner told what opens the wheel.
        let ready = try XCTUnwrap(next(following: microsoft, among: connected, memory: memory, byChoice: true))
        XCTAssertEqual(ready.kind, .ready)
        XCTAssertEqual(ready.device, microsoft)
        XCTAssertTrue(ready.text.contains("wheel click now opens the agent wheel"), ready.text)
        MouseSetup.acknowledge(ready, in: &memory)
        XCTAssertTrue(memory.wasIntroduced(microsoft))

        // Nothing is said twice, whichever of them is followed afterwards.
        XCTAssertNil(next(following: microsoft, among: connected, memory: memory, byChoice: true))
        XCTAssertNil(next(following: mx4, among: connected, memory: memory))
    }

    /// The MX Master 4's Bluetooth link drops when it naps. A notice about the mouse that stood
    /// in, withdrawn before anybody saw it, must not count as said.
    func testANoticeNobodySawIsSaidAgain() throws {
        var memory = MouseMemory()
        let unseen = try XCTUnwrap(next(following: microsoft, among: [microsoft], memory: memory))
        XCTAssertEqual(unseen.kind, .ready)
        // The MX Master 4 comes back and the notice is withdrawn unseen: nothing was noted.
        XCTAssertEqual(memory, MouseMemory())
        XCTAssertFalse(MouseSetup.stillTrue(unseen, following: mx4, among: [mx4, microsoft]))
        // So the next time the Microsoft mouse is on its own, it is introduced after all.
        XCTAssertEqual(next(following: microsoft, among: [microsoft], memory: memory), unseen)
        MouseSetup.acknowledge(unseen, in: &memory)
        XCTAssertNil(next(following: microsoft, among: [microsoft], memory: memory))
    }

    func testAMouseFoundOnItsOwnIsIntroducedOnceEvenAcrossRestarts() throws {
        var memory = MouseMemory()
        XCTAssertNil(next(following: nil, among: [], memory: memory), "no mouse, nothing to say")
        let ready = try XCTUnwrap(next(following: microsoft, among: [microsoft], memory: memory))
        XCTAssertEqual(ready.kind, .ready)
        MouseSetup.acknowledge(ready, in: &memory)

        // What was said is kept in the memory file, so a restart doesn't repeat it.
        let restarted = try JSONDecoder().decode(MouseMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(restarted, memory)
        XCTAssertNil(next(following: microsoft, among: [microsoft], memory: restarted))
    }

    func testAnMXMaster4OnItsOwnGetsNoNotice() {
        XCTAssertNil(next(following: mx4, among: [mx4, receiver], memory: MouseMemory()))
    }

    func testNothingIsOfferedToSomeoneWhoPickedTheirMouseByHand() throws {
        var memory = MouseMemory()
        let ready = try XCTUnwrap(next(following: microsoft, among: [microsoft, mx4], memory: memory, byChoice: true))
        XCTAssertEqual(ready.kind, .ready)
        MouseSetup.acknowledge(ready, in: &memory)
        // Having chosen the Microsoft mouse over the MX Master 4, they are not asked to switch back.
        XCTAssertNil(next(following: microsoft, among: [microsoft, mx4], memory: memory, byChoice: true))
    }

    func testAMouseThatMayOnlyBeStandingInIsGivenTimeBeforeAnythingIsSaid() {
        // The Microsoft mouse taking over from an MX Master 4 may be gone again in seconds.
        XCTAssertTrue(MouseSetup.isStandIn(microsoft, after: MouseChooser.tier(mx4)))
        XCTAssertTrue(MouseSetup.isStandIn(receiver, after: MouseChooser.tier(microsoft)))
        // The MX Master 4 coming back, or a mouse on a Mac that had none, is not standing in for anything.
        XCTAssertFalse(MouseSetup.isStandIn(mx4, after: MouseChooser.tier(microsoft)))
        XCTAssertFalse(MouseSetup.isStandIn(microsoft, after: -1))
        XCTAssertFalse(MouseSetup.isStandIn(microsoft, after: MouseChooser.tier(microsoft)))
        XCTAssertGreaterThan(MouseSetup.settleTime(standIn: true), MouseSetup.settleTime(standIn: false))
        XCTAssertGreaterThanOrEqual(MouseSetup.settleTime(standIn: true), 8, "long enough for a Bluetooth mouse to reconnect")
        // A profile remembered from last time ranks like a device of that kind.
        XCTAssertEqual(MouseSetup.tier(of: .mxMaster4), MouseChooser.tier(mx4))
        XCTAssertEqual(MouseSetup.tier(of: profile("msBasicOptical")), MouseChooser.tier(microsoft))
        XCTAssertEqual(MouseSetup.tier(of: .generic), MouseChooser.tier(unknown))
        XCTAssertEqual(MouseSetup.tier(of: profile("logitechReceiver")), MouseChooser.tier(receiver))
    }

    func testANoticeIsWithdrawnWhenItNoLongerDescribesThings() {
        let p = profile("msBasicOptical")
        let ready = MouseSetup.notice(for: microsoft, profile: p, triggers: triggers(p))
        XCTAssertTrue(MouseSetup.stillTrue(ready, following: microsoft, among: [microsoft, mx4]))
        XCTAssertFalse(MouseSetup.stillTrue(ready, following: mx4, among: [microsoft, mx4]), "another mouse took over")
        XCTAssertFalse(MouseSetup.stillTrue(ready, following: nil, among: []), "it was unplugged")

        let offer = MouseSetup.notice(alsoConnected: microsoft, following: "Logitech MX Master 4")
        XCTAssertTrue(MouseSetup.stillTrue(offer, following: mx4, among: [mx4, microsoft]))
        XCTAssertFalse(MouseSetup.stillTrue(offer, following: mx4, among: [mx4]), "the mouse on offer was unplugged")
        XCTAssertFalse(MouseSetup.stillTrue(offer, following: microsoft, among: [mx4, microsoft]), "the offer was taken another way")
    }

    // MARK: How the window describes the mouse

    func testTheWindowSaysHowTheMouseWasFoundAndHowItIsConnected() {
        let p = profile("msBasicOptical")
        XCTAssertEqual(MouseSetup.title(device: microsoft, profile: p), "Microsoft Basic Optical Mouse")
        XCTAssertEqual(MouseSetup.subtitle(device: microsoft, profile: p, pickedByHand: false), "USB · recognised")
        XCTAssertEqual(MouseSetup.subtitle(device: receiver, profile: profile("logitechReceiver"), pickedByHand: false), "USB · mouse model unknown")
        XCTAssertEqual(MouseSetup.subtitle(device: unknown, profile: .generic, pickedByHand: false), "USB · not in the list yet")
        XCTAssertEqual(MouseSetup.subtitle(device: receiver, profile: profile("m720"), pickedByHand: true), "USB · model picked by you")
        XCTAssertEqual(MouseSetup.subtitle(device: magic, profile: profile("magicMouse"), pickedByHand: false), "Bluetooth · recognised")
        // Nothing connected: the mouse last used is still named.
        XCTAssertEqual(MouseSetup.title(device: nil, profile: .mxMaster4), "Logitech MX Master 4")
        XCTAssertEqual(MouseSetup.subtitle(device: nil, profile: .mxMaster4, pickedByHand: false), "Not connected")
        // A model picked for a receiver is named as that model.
        XCTAssertEqual(MouseSetup.title(device: receiver, profile: profile("m720")), "Logitech M720 Triathlon")
        // A receiver taken for the MX Master 4 this Mac always had is said to be an assumption.
        let bolt = MouseDevice(vendorID: 0x046D, productID: 0xC548, name: "USB Receiver", transport: "USB", buttons: 16)
        XCTAssertEqual(MouseSetup.title(device: bolt, profile: .mxMaster4), "Logitech MX Master 4")
        XCTAssertEqual(MouseSetup.subtitle(device: bolt, profile: .mxMaster4, pickedByHand: false), "USB receiver · assumed to be this mouse")
    }

    func testABrandIsNotSaidTwice() {
        XCTAssertEqual(profile("zowie").fullName, "Zowie gaming mouse")
        XCTAssertEqual(profile("keychronM").fullName, "Keychron M series")
        XCTAssertEqual(MouseProfile.generic.fullName, "Five-button mouse")
    }
}

import XCTest
@testable import MouseHerdr

/// Saved button choices and what is remembered about mice. Everything is written to a folder made
/// for the test, never to the real settings.
final class MouseSettingsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("mouseherdr-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func profile(_ id: String) -> MouseProfile { MouseProfile.named(id)! }

    /// The file as the MX Master 4 has always written it: every slot, defaults included.
    private func writeMXMaster4File(changing changes: [Slot: Action] = [:]) {
        ConfigStore.save(MouseProfile.mxMaster4.defaults.merging(changes) { _, new in new }, for: .mxMaster4, in: folder)
    }

    // MARK: Button choices

    func testTheMXMaster4KeepsTheFileItAlwaysHad() {
        XCTAssertEqual(ConfigStore.file(for: .mxMaster4, in: folder).lastPathComponent, "config.json")
        XCTAssertEqual(ConfigStore.file(for: .mxMaster4, in: folder).deletingLastPathComponent().path, folder.path)
        let other = ConfigStore.file(for: profile("msBasicOptical"), in: folder)
        XCTAssertEqual(other.lastPathComponent, "msBasicOptical.json")
        XCTAssertEqual(other.deletingLastPathComponent().lastPathComponent, "mice")
    }

    func testTheMXMaster4FileIsReadAndWrittenAsBefore() throws {
        // The format older versions wrote: a flat map from slot to action.
        let old = #"{"middle":{"kind":"default"},"thumbPanel":{"kind":"copy"},"back":{"kind":"shortcut","keyCode":8,"modifiers":1048576,"label":"⌘C"}}"#
        try Data(old.utf8).write(to: folder.appendingPathComponent("config.json"))
        var loaded = ConfigStore.load(for: .mxMaster4, in: folder)
        XCTAssertEqual(loaded[.thumbPanel], Action(kind: "copy"))
        XCTAssertEqual(loaded[.back]?.label, "⌘C")
        XCTAssertEqual(loaded[.forward], Action(kind: "forward"), "a slot the file doesn't mention keeps its default")

        loaded[.middle] = Action(kind: "agentWheel")
        ConfigStore.save(loaded, for: .mxMaster4, in: folder)
        let raw = try JSONDecoder().decode([String: Action].self, from: Data(contentsOf: folder.appendingPathComponent("config.json")))
        XCTAssertEqual(raw["middle"], Action(kind: "agentWheel"))
        XCTAssertEqual(raw["thumbPanel"], Action(kind: "copy"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("mice").path), "nothing else is written")
    }

    func testANewMouseStartsFromItsOwnDefaults() {
        let p = profile("msBasicOptical")
        XCTAssertEqual(ConfigStore.load(for: p, in: folder), p.defaults)
        XCTAssertEqual(ConfigStore.load(for: p, in: folder)[.middle], Action(kind: "agentWheel"))
    }

    func testEachMouseKeepsItsOwnChoices() {
        let microsoft = profile("msBasicOptical")
        writeMXMaster4File()
        ConfigStore.save([.middle: Action(kind: "missionControl")], for: microsoft, in: folder)

        XCTAssertEqual(ConfigStore.load(for: microsoft, in: folder)[.middle], Action(kind: "missionControl"))
        XCTAssertEqual(ConfigStore.load(for: .mxMaster4, in: folder)[.middle], .standard, "the MX Master 4 is untouched")
        XCTAssertEqual(ConfigStore.load(for: .generic3, in: folder)[.middle], Action(kind: "agentWheel"), "and so is every other mouse")
    }

    func testWhatWasChangedOnTheMXMaster4CarriesOverToANewMouseButItsDefaultsDoNot() {
        writeMXMaster4File(changing: [.back: Action(kind: "missionControl"), .modeShift: Action(kind: "agentWheel")])

        let five = ConfigStore.load(for: .generic, in: folder)
        XCTAssertEqual(five[.back], Action(kind: "missionControl"), "a back button with another job keeps it")
        XCTAssertEqual(five[.forward], Action(kind: "forward"))
        // The MX Master 4's wheel click is left alone by default. That is not a choice to carry
        // over: on this mouse the wheel click is what opens the agent wheel.
        XCTAssertEqual(five[.middle], Action(kind: "agentWheel"))
        XCTAssertNil(five[.modeShift], "a button this mouse doesn't have is not brought along")
        XCTAssertNil(five[.thumbPanel])

        XCTAssertEqual(ConfigStore.load(for: profile("mxMaster3S"), in: folder)[.modeShift], Action(kind: "agentWheel"),
                       "but it is on a mouse that has that button")
    }

    func testOnceAMouseHasChoicesOfItsOwnNothingIsCarriedOverAnyMore() {
        writeMXMaster4File(changing: [.back: Action(kind: "missionControl")])
        var mine = ConfigStore.load(for: .generic, in: folder)
        mine[.forward] = Action(kind: "copy")
        ConfigStore.save(mine, for: .generic, in: folder)

        // The MX Master 4 changes afterwards.
        writeMXMaster4File(changing: [.back: Action(kind: "paste"), .forward: Action(kind: "paste")])
        let again = ConfigStore.load(for: .generic, in: folder)
        XCTAssertEqual(again[.back], Action(kind: "missionControl"))
        XCTAssertEqual(again[.forward], Action(kind: "copy"))
    }

    /// Its owner was told what the wheel click does. A later change to the MX Master 4 must not
    /// quietly change it.
    func testAMouseGetsAFileOfItsOwnTheFirstTimeItIsFollowed() {
        let microsoft = profile("msBasicOptical")
        writeMXMaster4File()
        ConfigStore.settle(microsoft, in: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ConfigStore.file(for: microsoft, in: folder).path))

        // The MX Master 4's wheel click is given another job afterwards.
        writeMXMaster4File(changing: [.middle: Action(kind: "copy")])
        XCTAssertEqual(ConfigStore.load(for: microsoft, in: folder)[.middle], Action(kind: "agentWheel"))
        // A mouse that has not had its turn yet still starts from what the MX Master 4 has now.
        XCTAssertEqual(ConfigStore.load(for: .generic3, in: folder)[.middle], Action(kind: "copy"))

        // Being followed again changes nothing that was chosen since.
        ConfigStore.save([.middle: Action(kind: "paste")], for: microsoft, in: folder)
        ConfigStore.settle(microsoft, in: folder)
        XCTAssertEqual(ConfigStore.load(for: microsoft, in: folder)[.middle], Action(kind: "paste"))
    }

    func testTheMXMaster4FileIsNotWrittenJustBecauseItIsFollowed() {
        ConfigStore.settle(.mxMaster4, in: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ConfigStore.file(for: .mxMaster4, in: folder).path))
    }

    func testAGestureMouseCarriesOverItsDirections() {
        writeMXMaster4File(changing: [.gestureLeft: Action(kind: "prevTab")])
        XCTAssertEqual(ConfigStore.load(for: profile("mxMaster3S"), in: folder)[.gestureLeft], Action(kind: "prevTab"))
        XCTAssertNil(ConfigStore.load(for: .generic, in: folder)[.gestureLeft])
    }

    func testABrokenOrUnknownFileIsIgnored() throws {
        let p = profile("razerViper")
        let file = ConfigStore.file(for: p, in: folder)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        XCTAssertEqual(ConfigStore.load(for: p, in: folder), p.defaults)

        try Data(#"{"middle":{"kind":"copy"},"noSuchSlot":{"kind":"paste"}}"#.utf8).write(to: file)
        XCTAssertEqual(ConfigStore.load(for: p, in: folder)[.middle], Action(kind: "copy"))
        XCTAssertEqual(ConfigStore.load(for: p, in: folder)[.back], Action(kind: "back"))
    }

    // MARK: What is remembered about mice

    func testWhatIsRememberedAboutMiceSurvivesARestart() {
        let microsoft = MouseDevice(vendorID: 0x045E, productID: 0x00CB, name: "Microsoft USB Optical Mouse")
        var memory = MouseMemory.load(from: folder)
        XCTAssertEqual(memory, MouseMemory(), "nothing is remembered at first")
        XCTAssertFalse(memory.wasIntroduced(microsoft))
        XCTAssertFalse(memory.wasOffered(microsoft))

        memory.introduce(microsoft)
        memory.introduce(microsoft)
        memory.offer(MouseDevice(vendorID: 0x1532, productID: 0x0084, name: "Razer DeathAdder V2"))
        memory.chosen["046d:c52b"] = "m720"
        memory.pinned = microsoft.key
        memory.last = "msBasicOptical"
        memory.boltCarriesMXMaster4 = true
        XCTAssertFalse(MouseMemory.exists(in: folder))
        memory.save(to: folder)
        XCTAssertTrue(MouseMemory.exists(in: folder))

        let again = MouseMemory.load(from: folder)
        XCTAssertEqual(again, memory)
        XCTAssertEqual(again.introduced, ["045e:00cb"], "a mouse is noted once")
        XCTAssertEqual(again.offered, ["1532:0084"])
        XCTAssertTrue(again.wasIntroduced(microsoft))
        XCTAssertTrue(again.wasOffered(microsoft), "a mouse that was introduced needs no offer")
        XCTAssertEqual(MouseMemory.file(in: folder).lastPathComponent, "mice.json")
    }

    func testAnOlderOrBrokenMemoryFileStillLoads() throws {
        try Data(#"{"last":"razerViper"}"#.utf8).write(to: MouseMemory.file(in: folder))
        let partial = MouseMemory.load(from: folder)
        XCTAssertEqual(partial.last, "razerViper")
        XCTAssertTrue(partial.chosen.isEmpty)
        XCTAssertTrue(partial.introduced.isEmpty)
        XCTAssertNil(partial.pinned)

        try Data("{ broken".utf8).write(to: MouseMemory.file(in: folder))
        XCTAssertEqual(MouseMemory.load(from: folder), MouseMemory())
    }
}

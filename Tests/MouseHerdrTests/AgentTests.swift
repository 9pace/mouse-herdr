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
}

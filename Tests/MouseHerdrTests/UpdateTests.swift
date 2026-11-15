import XCTest
@testable import MouseHerdr

final class UpdateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "MouseHerdr.UpdateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testAutomaticUpdatesDefaultOnAndOptOutPersistsAcrossLaunches() {
        let first = UpdateManager(defaults: defaults)
        XCTAssertTrue(first.automaticUpdates)
        first.automaticUpdates = false
        let second = UpdateManager(defaults: defaults)
        XCTAssertFalse(second.automaticUpdates)
        XCTAssertFalse(defaults.bool(forKey: "SUEnableAutomaticChecks"))
        XCTAssertFalse(defaults.bool(forKey: "SUAutomaticallyUpdate"))
        second.automaticUpdates = true
        XCTAssertTrue(UpdateManager(defaults: defaults).automaticUpdates)
        XCTAssertTrue(defaults.bool(forKey: "SUAutomaticallyUpdate"))
    }

    func testDisablingDownloadsInSparkleIsRespected() {
        defaults.set(false, forKey: "SUAutomaticallyUpdate")
        XCTAssertFalse(UpdatePreferences(defaults: defaults).automatic)
    }

    func testDownloadedUpdateDoesNotRestartUntilAskedAndCannotRestartTwice() {
        let manager = UpdateManager(defaults: defaults)
        var installs = 0
        manager.restartToUpdate()
        XCTAssertEqual(installs, 0)
        manager.readyToInstall(version: "1.0.50") { installs += 1 }
        XCTAssertEqual(manager.phase, .ready("1.0.50"))
        XCTAssertEqual(installs, 0)
        // Opting out affects future background checks, not an already staged update.
        manager.automaticUpdates = false
        XCTAssertTrue(manager.phase.ready)
        manager.restartToUpdate()
        XCTAssertEqual(installs, 1)
        XCTAssertEqual(manager.phase, .restarting("1.0.50"))
        manager.restartToUpdate()
        XCTAssertEqual(installs, 1)
    }

    func testFreshInstallDoesNotShowWhatsNewThenUpgradeShowsExactlyOnce() {
        let history = ReleaseHistory(defaults: defaults)
        XCTAssertFalse(history.recordLaunch(build: "48", previouslyUsedApp: false))
        XCTAssertFalse(history.recordLaunch(build: "48", previouslyUsedApp: true))
        XCTAssertTrue(history.recordLaunch(build: "49", previouslyUsedApp: true))
        XCTAssertFalse(history.recordLaunch(build: "49", previouslyUsedApp: true))
    }

    func testUpgradeFromBeforeUpdaterShowsWhatsNewWithoutOldVersionKey() {
        let history = ReleaseHistory(defaults: defaults)
        XCTAssertTrue(history.recordLaunch(build: "48", previouslyUsedApp: true))
        XCTAssertFalse(history.recordLaunch(build: "48", previouslyUsedApp: true))
    }

    func testDowngradesAndInvalidBuildsDoNotEraseWhatsNewHistory() {
        let history = ReleaseHistory(defaults: defaults)
        XCTAssertFalse(history.recordLaunch(build: "50", previouslyUsedApp: false))
        for build in ["1", "49", "50", "invalid", "0", ""] {
            XCTAssertFalse(history.recordLaunch(build: build, previouslyUsedApp: true))
        }
        XCTAssertFalse(history.recordLaunch(build: nil, previouslyUsedApp: true))
        XCTAssertEqual(defaults.string(forKey: "lastLaunchedReleaseBuild"), "50")
        XCTAssertTrue(history.recordLaunch(build: "51", previouslyUsedApp: true))
    }

    func testCreatingManagerDoesNotStartNetworkOrUpdateService() {
        let manager = UpdateManager(defaults: defaults)
        XCTAssertFalse(manager.canCheck)
        XCTAssertNil(manager.lastChecked)
        XCTAssertEqual(manager.phase, .idle)
        manager.checkForUpdates()
        XCTAssertEqual(manager.phase, .idle)
        XCTAssertFalse(UpdateManager.isReleaseBundle(Bundle(for: Self.self)))
    }
}

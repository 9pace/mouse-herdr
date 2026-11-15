import AppKit
import Combine
import Security
import Sparkle

/// Use Sparkle's preferences so its own dialogs and our settings have one source of truth.
struct UpdatePreferences {
    let defaults: UserDefaults

    var automatic: Bool {
        (defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true)
            && (defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool ?? true)
    }

    func setAutomatic(_ enabled: Bool) {
        defaults.set(enabled, forKey: "SUEnableAutomaticChecks")
        defaults.set(enabled, forKey: "SUAutomaticallyUpdate")
    }
}

struct ReleaseHistory {
    let defaults: UserDefaults

    /// A fresh install gets onboarding; an upgrade gets What's New once, including an
    /// upgrade from a version that predates the updater. Downgrades don't erase history.
    func recordLaunch(build: String?, previouslyUsedApp: Bool) -> Bool {
        guard let build, let current = UInt64(build), current > 0 else { return false }
        let previous = defaults.string(forKey: "lastLaunchedReleaseBuild").flatMap(UInt64.init)
        if current > (previous ?? 0) {
            defaults.set(build, forKey: "lastLaunchedReleaseBuild")
        }
        return previous.map { current > $0 } ?? previouslyUsedApp
    }
}

enum UpdatePhase: Equatable {
    case idle, checking, available(String), downloading(String), preparing(String)
    case ready(String), restarting(String), upToDate, failed(String), unavailable

    var message: String {
        switch self {
        case .idle: return "Updates are checked automatically once a day."
        case .checking: return "Checking for updates…"
        case .available(let version): return "MouseHerdr \(version) is available."
        case .downloading(let version): return "Downloading MouseHerdr \(version) in the background…"
        case .preparing(let version): return "Preparing MouseHerdr \(version)…"
        case .ready(let version): return "MouseHerdr \(version) is ready to install."
        case .restarting: return "Restarting to install the update…"
        case .upToDate: return "You’re up to date."
        case .failed(let reason): return reason
        case .unavailable: return "This is a source build. Automatic updates are available in releases downloaded from GitHub."
        }
    }

    var ready: Bool { if case .ready = self { return true }; return false }
    var menuTitle: String {
        if ready { return "Restart to Update…" }
        if busy { return message }
        if case .available = self { return "Update Available…" }
        return "Check for Updates…"
    }
    var busy: Bool {
        switch self {
        case .checking, .downloading, .preparing, .restarting: return true
        default: return false
        }
    }
}

/// Sparkle owns scheduling, validation, staging and installation. Its installer waits
/// for this process to quit, so HID controls are released by the normal shutdown path.
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published var automaticUpdates: Bool {
        didSet {
            guard automaticUpdates != oldValue else { return }
            if let updater = controller?.updater {
                updater.automaticallyChecksForUpdates = automaticUpdates
                updater.automaticallyDownloadsUpdates = automaticUpdates
            } else {
                preferences.setAutomatic(automaticUpdates)
            }
        }
    }
    @Published private(set) var phase: UpdatePhase = .idle
    @Published private(set) var canCheck = false
    @Published private(set) var lastChecked: Date?

    var showWhatsNew: (() -> Void)?
    private let preferences: UpdatePreferences
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private var installReadyUpdate: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        preferences = UpdatePreferences(defaults: defaults)
        automaticUpdates = preferences.automatic
        super.init()
    }

    /// Only normal app startup calls this. Developer tools, snapshots and tests never
    /// start an updater or register its installer.
    func start() {
        guard controller == nil else { return }
        guard Self.isReleaseBundle(Bundle.main) else { phase = .unavailable; return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        // Coalesce notifications: changing our checkbox writes two Sparkle properties.
        func changed() {
            DispatchQueue.main.async { [weak self, weak updater] in
                guard let self, let updater else { return }
                self.canCheck = updater.canCheckForUpdates
                self.lastChecked = updater.lastUpdateCheckDate
                self.automaticUpdates = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
            }
        }
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { _, _ in changed() },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { _, _ in changed() },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { _, _ in changed() },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { _, _ in changed() }
        ]
        do {
            try updater.start()
        } catch {
            phase = .failed("Updates couldn’t start. \(error.localizedDescription)")
            Log.write("updater: failed to start: \(error.localizedDescription)")
        }
    }

    func checkForUpdates() {
        guard canCheck, let updater = controller?.updater else { return }
        if !updater.sessionInProgress { phase = .checking }
        updater.checkForUpdates()
    }

    func restartToUpdate() {
        guard case .ready(let version) = phase, let installReadyUpdate else { return }
        phase = .restarting(version)
        installReadyUpdate()
    }

    /// Refuse to replace a development copy (and its different TCC identity) with a
    /// public release. Sparkle verifies the archive signature and app code signature.
    static func isReleaseBundle(_ bundle: Bundle) -> Bool {
        guard bundle.bundleIdentifier == "dev.mouseherdr.app",
              bundle.object(forInfoDictionaryKey: "MouseHerdrReleaseBuild") as? Bool == true,
              bundle.object(forInfoDictionaryKey: "SUFeedURL") is String,
              bundle.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return false }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        phase = .available(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        phase = .downloading(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        phase = .preparing(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        // Keep the app running. Return true to own the restart button and keep Sparkle
        // from presenting repeated dialogs while this already verified update waits.
        readyToInstall(version: item.displayVersionString, install: immediateInstallationBlock)
        return true
    }

    func readyToInstall(version: String, install: @escaping () -> Void) {
        installReadyUpdate = install
        phase = .ready(version)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error as NSError? {
            if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
                phase = .upToDate
            } else if error.domain == SUSparkleErrorDomain && error.code == SUError.installationCanceledError.rawValue {
                phase = .idle
            } else {
                phase = .failed("Update couldn’t finish. \(error.localizedDescription)")
                Log.write("updater: \(error.localizedDescription)")
            }
            installReadyUpdate = nil
        } else if !phase.ready {
            phase = .idle
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        // If an update needs interaction (e.g. an informational release), expose it in
        // settings and the menu. Manual checks still use Sparkle's standard dialogs.
        if !handleShowingUpdate { phase = .available(update.displayVersionString) }
    }

    func standardUserDriverShowVersionHistory(for item: SUAppcastItem) {
        showWhatsNew?()
    }

    /// Deterministic screenshots without network traffic or a running update service.
    func poseReadyUpdate() { phase = .ready("1.1.0") }
}

enum ReleaseNotes {
    static func bundled(in bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "ReleaseNotes", withExtension: "md"),
              let notes = try? String(contentsOf: url, encoding: .utf8), !notes.isEmpty else {
            return "See the release history on GitHub for the changes in this version."
        }
        return notes
    }
}

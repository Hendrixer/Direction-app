import SwiftUI
import Sparkle
import DirectionCore

/// Updates for the copies we sign and hand out (docs/releasing.md). Sparkle reads the feed and the public key
/// that scripts/release.sh writes into the signed copy's Info.plist, checks once a day, and asks before
/// installing. A copy built from source has no feed, so it never updates itself: `git pull` and build again.
@MainActor @Observable final class AppUpdates {
    static let shared = AppUpdates()
    /// The signed copy's updater; nil in a copy built from source, in tests and in snapshots.
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var watching: NSKeyValueObservation?
    /// False while a check is already showing or the updater hasn't started.
    private(set) var canCheck = false

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let rendering = CommandLine.arguments.contains { $0.hasPrefix("--snapshot") || $0.hasSuffix("-probe") }
        guard !feed.isEmpty, !DirectionPaths.isTesting, !rendering else { controller = nil; return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = c
        watching = c.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let can = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = can }
        }
    }

    /// This copy updates itself.
    var updates: Bool { controller != nil }
    /// Direction › Check for Updates…
    func check() { controller?.checkForUpdates(nil) }
    /// Settings › General › Check for updates automatically.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}

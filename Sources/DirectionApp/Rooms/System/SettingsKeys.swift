import Foundation
import AppKit
import DirectionCore

/// UserDefaults keys for Settings. Rooms read these with @AppStorage; the defaults are
/// registered once at launch so `UserDefaults.bool(forKey:)` agrees with the spec.
enum SettingsKey {
    // General
    static let whenOpening = "whenOpening"            // "lastFilm" | "films" | "newFilm"
    static let showFilmsWhenEmpty = "showFilmsWhenEmpty"
    static let screeningFullScreen = "screeningFullScreen"
    static let hideControlsAfter = "hideControlsAfter" // seconds as Double; 0 = never
    static let audioOutput = "audioOutput"            // Core Audio device UID; "" = system default
    static let filmGrain = "filmGrain"
    static let reduceMotion = "reduceMotion"          // "system" | "on" | "off"
    // Editor
    static let defaultLatitude = "defaultLatitude"
    static let waitForReadBack = "waitForReadBack"
    static let cutFeelingTwoWays = "cutFeelingTwoWays"
    static let askBeforeGuessing = "askBeforeGuessing"
    static let conflictOrder = "conflictOrder"        // "feeling,story,pace,picture,sound"
    // Cutting
    static let handleSeconds = "handleSeconds"
    static let frameRate = "frameRateForNewFilms"     // "match" | "23.976" | …
    static let loudness = "loudnessTarget"            // LUFS as Double
    static let ducking = "musicDucking"               // dB as Double; 0 = don't duck
    static let transitions = "transitions"            // "hard" | "editor"
    // Notifications (the four switches use NotificationKey)
    static let outsideNotes = "notifyOutside"         // "now" | "hourly" | "daily" | "never"
    static let holdDuringScreening = "holdDuringScreening"
    static let notificationSound = "notificationSound" // "default" | "none"
    // Storage
    static let libraryFolder = "libraryFolder"
    static let footageImport = "footageImport"        // "link" | "copy"
    // Sharing
    static let linkNotes = "linkViewersCanNote"
    static let linkExpiry = "linkExpiryDays"          // Int days; 0 = never
    static let linkWatermark = "linkWatermark"
    static let linkDownload = "linkAllowDownload"
    static let linkPassword = "linkRequirePassword"
    static let creditOutsideNotes = "creditOutsideNotes"
    // Window state
    static let settingsTab = "settingsTab"
    static let settingsFlash = "settingsFlash"
    static let recentCommands = "recentCommands"

    static let defaultConflictOrder = NoteKind.allCases.map(\.rawValue).joined(separator: ",")
    static var defaultLibrary: String { NSHomeDirectory() + "/Movies/Direction" }

    static var defaults: [String: Any] {
        [
            whenOpening: "lastFilm", showFilmsWhenEmpty: true, screeningFullScreen: false, hideControlsAfter: 2.0, audioOutput: "", filmGrain: true, reduceMotion: "system",
            defaultLatitude: Latitude.faithful.rawValue, waitForReadBack: true, cutFeelingTwoWays: true, askBeforeGuessing: true, conflictOrder: defaultConflictOrder,
            handleSeconds: 2.0, frameRate: "match", loudness: -14.0, ducking: 6.0, transitions: "hard",
            NotificationKey.cutReady: true, NotificationKey.question: true, NotificationKey.cant: true, NotificationKey.delivery: true,
            outsideNotes: "hourly", holdDuringScreening: true, notificationSound: "default",
            footageImport: "link",
            linkNotes: true, linkExpiry: 7, linkWatermark: true, linkDownload: false, linkPassword: false, creditOutsideNotes: true,
        ]
    }

    /// Call once at launch, before any window reads a setting.
    static func register(_ store: UserDefaults = .standard) { store.register(defaults: defaults) }

    /// The conflict order as kinds, highest first. Unknown or missing kinds fall back to Murch's order.
    static func conflictKinds(_ raw: String) -> [NoteKind] {
        var out = raw.split(separator: ",").compactMap { NoteKind(rawValue: String($0)) }
        out = out.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        for k in NoteKind.allCases where !out.contains(k) { out.append(k) }
        return out
    }

    /// Reduce Motion from Settings › General, or the system's setting when it says Follow system.
    @MainActor static var reducesMotion: Bool {
        switch UserDefaults.standard.string(forKey: reduceMotion) {
        case "on": true
        case "off": false
        default: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }
}

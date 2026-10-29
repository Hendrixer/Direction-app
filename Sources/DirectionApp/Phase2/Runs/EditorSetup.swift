import SwiftUI
import DirectionCore

/// Settings › Editor › Who edits (product-model.md › EditorSetup). App-wide, in the standard defaults.
enum EditorSetupKey {
    /// "claudeCode" | "codex" | "yourOwn". Absent until the director picks (frame 56 or Settings).
    static let runsOn = "editorRunsOn"
    static let claudeVersion = "editorVersionClaudeCode"
    static let codexVersion = "editorVersionCodex"
    /// "rightAway" | "askFirst"
    static let startWork = "editorStartWork"
    static let scripts = "editorRunsScripts"
    /// true once the ready job answered; false after a sign-in failure; absent until checked.
    static func signedIn(_ p: EditorProgram) -> String { "editorSignedIn." + p.rawValue }
}

/// Who runs the editor: a program Direction starts, or a session you run yourself.
enum EditorRunsOn: String, CaseIterable, Sendable {
    case claudeCode, codex, yourOwn
    var program: EditorProgram? { EditorProgram(rawValue: rawValue) }
    var label: String { program?.name ?? "Your own session" }
}

/// Reads and writes go through here so previews and snapshots keep their values in memory and
/// never touch the defaults.
@MainActor
enum EditorSetup {
    private static func value(_ key: String) -> Any? {
        let p = EditorPrograms.shared
        return p.preview ? p.previewValues[key] : UserDefaults.standard.object(forKey: key)
    }
    private static func put(_ key: String, _ value: Any?) {
        let p = EditorPrograms.shared
        if p.preview { p.previewValues[key] = value } else { UserDefaults.standard.set(value, forKey: key) }
        p.changes += 1
    }
    /// Whether the director has chosen (the setup sheet shows until then).
    static var isChosen: Bool { value(EditorSetupKey.runsOn) != nil }
    /// The choice, or the spec's default: Claude Code if installed, else Codex, else your own session.
    static var runsOn: EditorRunsOn {
        if let raw = value(EditorSetupKey.runsOn) as? String, let c = EditorRunsOn(rawValue: raw) { return c }
        let found = EditorPrograms.shared
        if found.install(.claudeCode) != nil || !found.checked { return .claudeCode }
        if found.install(.codex) != nil { return .codex }
        return .yourOwn
    }
    static func choose(_ c: EditorRunsOn) { put(EditorSetupKey.runsOn, c.rawValue) }
    static func version(_ p: EditorProgram) -> String {
        value(p == .claudeCode ? EditorSetupKey.claudeVersion : EditorSetupKey.codexVersion) as? String ?? p.defaultVersion
    }
    static func setVersion(_ v: String, for p: EditorProgram) { put(p == .claudeCode ? EditorSetupKey.claudeVersion : EditorSetupKey.codexVersion, v) }
    static var asksFirst: Bool { value(EditorSetupKey.startWork) as? String == "askFirst" }
    static func setAsksFirst(_ on: Bool) { put(EditorSetupKey.startWork, on ? "askFirst" : "rightAway") }
    static var runsScripts: Bool { value(EditorSetupKey.scripts) as? Bool ?? true }
    static func setRunsScripts(_ on: Bool) { put(EditorSetupKey.scripts, on) }
    static func signedIn(_ p: EditorProgram) -> Bool? { value(EditorSetupKey.signedIn(p)) as? Bool }
    static func setSignedIn(_ p: EditorProgram, _ on: Bool?) { put(EditorSetupKey.signedIn(p), on) }
    /// Direction starts the editor (not your own session).
    static var directionStarts: Bool { runsOn != .yourOwn }
    /// Chosen, and the program it starts is on this Mac.
    static var ready: Bool { isChosen && runsOn.program.map { EditorPrograms.shared.install($0) != nil } ?? false }
}

/// Programs found on this Mac. Looked for once at launch, and again on Check again.
@MainActor @Observable final class EditorPrograms {
    static let shared = EditorPrograms()
    private(set) var installs: [EditorProgram: EditorInstall] = [:]
    /// The first search has finished.
    private(set) var checked = false
    private(set) var checking = false
    /// Sign-in checks in flight.
    private(set) var signingIn: Set<EditorProgram> = []
    /// Previews and snapshots set what they show; nothing is looked for and nothing is saved.
    var preview = false
    @ObservationIgnored var previewValues: [String: Any] = [:]
    /// Bumped on every setting change so views that read EditorSetup redraw.
    var changes = 0

    func install(_ p: EditorProgram) -> EditorInstall? { installs[p] }

    func refresh() {
        guard !checking, !preview else { return }
        checking = true
        Task.detached {
            var found: [EditorProgram: EditorInstall] = [:]
            for p in EditorProgram.allCases { if let i = EditorDiscovery.find(p) { found[p] = i } }
            _ = EditorDiscovery.loginPath
            await MainActor.run {
                self.installs = found; self.checked = true; self.checking = false; self.changes += 1
                if let p = EditorSetup.runsOn.program, EditorSetup.isChosen { self.checkSignIn(p) }
            }
        }
    }
    func refreshIfNeeded() { if !checked { refresh() } }

    /// Runs the ready job once (at setup, and after a failure). Its answer is remembered.
    func checkSignIn(_ p: EditorProgram, force: Bool = false) {
        guard !preview, let i = installs[p], !signingIn.contains(p), force || EditorSetup.signedIn(p) == nil else { return }
        signingIn.insert(p)
        let version = EditorSetup.version(p)
        Task.detached {
            let ok = EditorDiscovery.checkSignedIn(i, version: version)
            await MainActor.run { EditorSetup.setSignedIn(p, ok); self.signingIn.remove(p) }
        }
    }

    /// For previews and snapshots: what each program looks like, and the settings to show.
    func setPreview(_ installs: [EditorProgram: EditorInstall], values: [String: Any] = [:]) {
        preview = true; self.installs = installs; previewValues = values; checked = true; changes += 1
    }
}

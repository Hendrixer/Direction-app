import SwiftUI
import DirectionCore

/// Settings › Engines › Who edits (product-model.md › EditorSetup). App-wide, in the standard defaults.
enum EditorSetupKey {
    /// "claudeCode" | "codex" | "yourOwn". Absent until the director picks (frame 56 or Settings).
    static let runsOn = "editorRunsOn"
    /// Speed and quality a new film starts with: the last one chosen (FilmQuality raw value).
    static let quality = "filmQuality"
    /// "rightAway" | "askFirst"
    static let startWork = "editorStartWork"
    static let scripts = "editorRunsScripts"
    /// true once the ready job answered; false after a sign-in failure; absent until checked.
    static func signedIn(_ p: EditorProgram) -> String { "editorSignedIn." + p.rawValue }
    /// true when the program has no sign-in of its own and works with the API key the shell sets.
    static func shellKey(_ p: EditorProgram) -> String { "editorShellKey." + p.rawValue }
}

extension EditorProgram {
    /// "ClaudeCode", as the settings keys spell it.
    var keyName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The jobs, as the editor's picks list them.
extension EditorJob {
    /// In the order a film is made, then styles and techniques.
    static let byFilm: [EditorJob] = [.script, .breakdown, .logFootage, .assemble, .turnover, .finish, .style, .technique]
    var workName: String {
        switch self {
        case .script: "A/V script"; case .breakdown: "Breakdown"; case .logFootage: "Logging takes"; case .assemble: "Assembly"
        case .turnover: "Notes"; case .finish: "Finishing"; case .style: "Styles"; case .technique: "Techniques"
        }
    }
}

/// Who runs the editor: a program Direction starts, or a session you run yourself.
enum EditorRunsOn: String, CaseIterable, Sendable {
    case claudeCode, codex, gemini, yourOwn
    var program: EditorProgram? { EditorProgram(rawValue: rawValue) }
    var label: String { program?.name ?? "Your own session" }
    init(_ program: EditorProgram) { self = EditorRunsOn(rawValue: program.rawValue) ?? .yourOwn }
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
    /// The choice, or the spec's default: the first agent installed (Claude Code, then Codex, then Gemini CLI), else
    /// your own session.
    static var runsOn: EditorRunsOn {
        if let raw = value(EditorSetupKey.runsOn) as? String, let c = EditorRunsOn(rawValue: raw) { return c }
        let found = EditorPrograms.shared
        if !found.checked { return .claudeCode }
        return found.installed.first.map(EditorRunsOn.init) ?? .yourOwn
    }
    static func choose(_ c: EditorRunsOn) { put(EditorSetupKey.runsOn, c.rawValue) }
    /// A film's editor: the one chosen for it in Who's editing?, or this setting for a film started before
    /// films kept their own (DirectingState.editor).
    static func runsOn(film choice: String?) -> EditorRunsOn { choice.flatMap(EditorRunsOn.init(rawValue:)) ?? runsOn }
    /// Chosen (for the film or here), and the program it starts is on this Mac (or the first look hasn't finished yet).
    static func ready(_ runsOn: EditorRunsOn, chosen: Bool) -> Bool {
        let p = EditorPrograms.shared
        return chosen && runsOn.program.map { !p.checked || p.install($0) != nil } ?? false
    }

    // MARK: Version and effort (specs/editor.md › Speed and quality)

    /// `effort` if offered, else the nearest offered below it, else the program's default ("").
    nonisolated static func fitted(_ effort: String, _ offered: [String]) -> String {
        if offered.contains(effort) { return effort }
        let below = EditorProgram.efforts.firstIndex(of: effort).map { EditorProgram.efforts[..<$0].reversed() } ?? []
        return below.first(where: offered.contains) ?? ""
    }
    /// A new run on the version and effort for its job at the film's speed and quality (`EditorPicks`).
    /// A run that hasn't started takes the film's setting again when it launches; once started, it keeps them.
    static func newRun(_ job: EditorJob, on p: EditorProgram, quality: FilmQuality, turnoverID: String? = nil, assetCount: Int? = nil, assetIDs: [String]? = nil) -> EditorRun {
        let pick = EditorPicks.pick(p, job, quality)
        var run = EditorRun(job: job, program: p.rawValue, version: pick.version, turnoverID: turnoverID, assetCount: assetCount, assetIDs: assetIDs)
        run.effort = pick.effort
        return run
    }
    /// What a new film starts with: the speed and quality chosen last, or what the old Made with setting
    /// said (Cheapest is Faster) until one is.
    static var defaultQuality: FilmQuality {
        if let q = (value(EditorSetupKey.quality) as? String).flatMap(FilmQuality.init) { return q }
        guard !EditorPrograms.shared.preview, let old = SharedSettings.defaults.string(forKey: "madeQuality") else { return .balanced }
        return old == "cheapest" ? .faster : FilmQuality(rawValue: old) ?? .balanced
    }
    static func setDefaultQuality(_ q: FilmQuality) { put(EditorSetupKey.quality, q.rawValue) }
    static var asksFirst: Bool { value(EditorSetupKey.startWork) as? String == "askFirst" }
    static func setAsksFirst(_ on: Bool) { put(EditorSetupKey.startWork, on ? "askFirst" : "rightAway") }
    static var runsScripts: Bool { value(EditorSetupKey.scripts) as? Bool ?? true }
    static func setRunsScripts(_ on: Bool) { put(EditorSetupKey.scripts, on) }
    static func signedIn(_ p: EditorProgram) -> Bool? { value(EditorSetupKey.signedIn(p)) as? Bool }
    static func setSignedIn(_ p: EditorProgram, _ on: Bool?) { put(EditorSetupKey.signedIn(p), on) }
    static func usesShellKey(_ p: EditorProgram) -> Bool { value(EditorSetupKey.shellKey(p)) as? Bool ?? false }
    static func setUsesShellKey(_ p: EditorProgram, _ on: Bool) { put(EditorSetupKey.shellKey(p), on ? true : nil) }
    /// Chosen, and the program it starts is on this Mac (or the first look hasn't finished yet).
    static var ready: Bool { ready(runsOn, chosen: isChosen) }
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
    /// Why the last check couldn't tell (too slow, another error). Not saved: the next check asks again.
    private(set) var couldNotCheck: [EditorProgram: String] = [:]
    /// Previews and snapshots set what they show; nothing is looked for and nothing is saved.
    var preview = false
    @ObservationIgnored var previewValues: [String: Any] = [:]
    /// Bumped on every setting change so views that read EditorSetup redraw.
    var changes = 0

    func install(_ p: EditorProgram) -> EditorInstall? { installs[p] }
    /// The agents on this Mac, in EditorProgram's order: the only ones offered.
    var installed: [EditorProgram] { EditorProgram.allCases.filter { installs[$0] != nil } }

    func refresh() {
        guard !checking, !preview else { return }
        checking = true
        Task.detached {
            var found: [EditorProgram: EditorInstall] = [:]
            for p in EditorProgram.allCases { if let i = EditorDiscovery.find(p) { found[p] = i } }
            _ = EditorDiscovery.loginPath
            await MainActor.run {
                self.installs = found; self.checked = true; self.checking = false; self.changes += 1
                // A program that wasn't signed in is asked again at every launch: it may be now.
                if let p = EditorSetup.runsOn.program, EditorSetup.isChosen { self.checkSignIn(p, force: EditorSetup.signedIn(p) == false) }
            }
        }
    }
    func refreshIfNeeded() { if !checked { refresh() } }

    /// Runs the ready job (at setup, at launch while it isn't signed in, after a failure, on Check again).
    /// Only a clear answer is remembered; a check that couldn't tell says why and asks again next time.
    func checkSignIn(_ p: EditorProgram, force: Bool = false) {
        guard !preview, let i = installs[p], !signingIn.contains(p), force || EditorSetup.signedIn(p) == nil else { return }
        signingIn.insert(p); couldNotCheck[p] = nil
        // The version cutting runs on: the one most of the work uses.
        let version = EditorPicks.pick(p, .assemble, .balanced).version
        Task.detached {
            var answer = EditorDiscovery.checkSignedIn(i, version: version)
            // No sign-in of its own, but the shell sets an API key: that's how this person uses it in Terminal.
            var withKey = false
            if case .notSignedIn = answer, EditorDiscovery.hasShellKey(p), EditorDiscovery.checkSignedIn(i, version: version, shellKey: true) == .signedIn { answer = .signedIn; withKey = true }
            switch answer {
            case .signedIn: DirectionLog.info("\(p.name) is signed in\(withKey ? " with the API key the shell sets" : "")", "editor")
            case .notSignedIn(let why): DirectionLog.warning("\(p.name) isn\u{2019}t signed in: \(why)", "editor")
            case .couldNotCheck(let why): DirectionLog.warning("Couldn\u{2019}t check \(p.name)\u{2019}s sign-in: \(why)", "editor")
            }
            await MainActor.run {
                switch answer {
                case .signedIn: EditorSetup.setSignedIn(p, true); EditorSetup.setUsesShellKey(p, withKey)
                case .notSignedIn: EditorSetup.setSignedIn(p, false); EditorSetup.setUsesShellKey(p, false)
                case .couldNotCheck(let why): EditorSetup.setSignedIn(p, nil); self.couldNotCheck[p] = why
                }
                self.signingIn.remove(p); self.changes += 1
            }
        }
    }

    /// For previews and snapshots: what each program looks like, and the settings to show.
    func setPreview(_ installs: [EditorProgram: EditorInstall], values: [String: Any] = [:]) {
        preview = true; self.installs = installs; previewValues = values; checked = true; changes += 1
    }
}

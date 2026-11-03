import SwiftUI
import DirectionCore

/// Settings › Engines › Who edits (product-model.md › EditorSetup). App-wide, in the standard defaults.
enum EditorSetupKey {
    /// "claudeCode" | "codex" | "yourOwn". Absent until the director picks (frame 56 or Settings).
    static let runsOn = "editorRunsOn"
    /// What the director changed for one job ("editorEffortClaudeCode.script"); absent while it's
    /// Direction's pick. The single keys before 2026-11-03 ("editorEffortClaudeCode") aren't read.
    static func version(_ p: EditorProgram, _ job: EditorJob) -> String { "editorVersion\(p.keyName).\(job.rawValue)" }
    static func effort(_ p: EditorProgram, _ job: EditorJob) -> String { "editorEffort\(p.keyName).\(job.rawValue)" }
    /// "rightAway" | "askFirst"
    static let startWork = "editorStartWork"
    static let scripts = "editorRunsScripts"
    /// true once the ready job answered; false after a sign-in failure; absent until checked.
    static func signedIn(_ p: EditorProgram) -> String { "editorSignedIn." + p.rawValue }
}

extension EditorProgram {
    /// "ClaudeCode", as the settings keys spell it.
    var keyName: String { self == .claudeCode ? "ClaudeCode" : "Codex" }
}

/// The jobs as Settings › Engines › Change per job… lists them.
extension EditorJob {
    /// In the order a film is made, then styles and techniques.
    static let byFilm: [EditorJob] = [.script, .breakdown, .logFootage, .assemble, .turnover, .finish, .style, .technique]
    var workName: String {
        switch self {
        case .script: "A/V script"; case .breakdown: "Breakdown"; case .logFootage: "Logging takes"; case .assemble: "Assembly"
        case .turnover: "Notes"; case .finish: "Finishing"; case .style: "Styles"; case .technique: "Techniques"
        }
    }
    /// Direction's pick: Extra high where the work is judgement (cutting, answering notes, a style's
    /// taste), High where the editor writes at length to a plan or works through a list.
    var pickedEffort: String {
        switch self { case .assemble, .turnover, .style: "xhigh"; default: "high" }
    }
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

    // MARK: Version and effort, per job (specs/editor.md › Version and effort)

    /// The version a job runs on: the director's, or Direction's pick (the program's first).
    static func version(_ p: EditorProgram, for job: EditorJob) -> String {
        value(EditorSetupKey.version(p, job)) as? String ?? p.defaultVersion
    }
    /// The effort a job runs at: the director's, or Direction's pick. A version that doesn't take
    /// it gets the nearest it does below it, or the program's default.
    static func effort(_ p: EditorProgram, for job: EditorJob) -> String {
        fitted(value(EditorSetupKey.effort(p, job)) as? String ?? job.pickedEffort, p.efforts(version(p, for: job)).map(\.id))
    }
    /// Direction's pick for a job, as `version` (by default the one the job runs on now) takes it.
    static func pickedEffort(_ p: EditorProgram, for job: EditorJob, on version: String? = nil) -> String {
        fitted(job.pickedEffort, p.efforts(version ?? self.version(p, for: job)).map(\.id))
    }
    /// `effort` if offered, else the nearest offered below it, else the program's default ("").
    static func fitted(_ effort: String, _ offered: [String]) -> String {
        if offered.contains(effort) { return effort }
        let below = EditorProgram.efforts.firstIndex(of: effort).map { EditorProgram.efforts[..<$0].reversed() } ?? []
        return below.first(where: offered.contains) ?? ""
    }
    /// Choosing Direction's pick forgets the change, so the job follows Direction's picks again.
    static func setVersion(_ v: String, for p: EditorProgram, job: EditorJob) {
        put(EditorSetupKey.version(p, job), v == p.defaultVersion ? nil : v)
    }
    static func setEffort(_ e: String, for p: EditorProgram, job: EditorJob) {
        put(EditorSetupKey.effort(p, job), e == pickedEffort(p, for: job) ? nil : e)
    }
    /// Jobs whose version or effort the director changed.
    static func changed(_ p: EditorProgram) -> [EditorJob] {
        EditorJob.byFilm.filter { value(EditorSetupKey.version(p, $0)) != nil || value(EditorSetupKey.effort(p, $0)) != nil }
    }
    static func restorePicks(_ p: EditorProgram) {
        for job in EditorJob.allCases { put(EditorSetupKey.version(p, job), nil); put(EditorSetupKey.effort(p, job), nil) }
    }
    /// A new run on the version and effort chosen for its job; it keeps them once it has started.
    static func newRun(_ job: EditorJob, on p: EditorProgram, turnoverID: String? = nil, assetCount: Int? = nil, assetIDs: [String]? = nil) -> EditorRun {
        var run = EditorRun(job: job, program: p.rawValue, version: version(p, for: job), turnoverID: turnoverID, assetCount: assetCount, assetIDs: assetIDs)
        run.effort = effort(p, for: job)
        return run
    }
    static var asksFirst: Bool { value(EditorSetupKey.startWork) as? String == "askFirst" }
    static func setAsksFirst(_ on: Bool) { put(EditorSetupKey.startWork, on ? "askFirst" : "rightAway") }
    static var runsScripts: Bool { value(EditorSetupKey.scripts) as? Bool ?? true }
    static func setRunsScripts(_ on: Bool) { put(EditorSetupKey.scripts, on) }
    static func signedIn(_ p: EditorProgram) -> Bool? { value(EditorSetupKey.signedIn(p)) as? Bool }
    static func setSignedIn(_ p: EditorProgram, _ on: Bool?) { put(EditorSetupKey.signedIn(p), on) }
    /// Direction starts the editor (not your own session).
    static var directionStarts: Bool { runsOn != .yourOwn }
    /// Chosen, and the program it starts is on this Mac (or the first look hasn't finished yet).
    static var ready: Bool {
        let p = EditorPrograms.shared
        return isChosen && runsOn.program.map { !p.checked || p.install($0) != nil } ?? false
    }
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
        // The version cutting runs on: the one most of the work uses.
        let version = EditorSetup.version(p, for: .assemble)
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

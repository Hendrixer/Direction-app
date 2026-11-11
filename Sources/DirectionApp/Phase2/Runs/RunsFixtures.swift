import SwiftUI
import DirectionCore

// Frames 43, 56, 57 and 58 (design/spec/specs/editor.md). Programs and settings are preview values
// held in memory, so a snapshot never reads or writes the defaults or looks for programs.
@MainActor
enum RunsFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "43-settings-editor": { settings() },
            "56-editor-setup": { setup() },
            "56-editor-not-signed-in": { setup(signedIn: false) },
            "56-editor-none-found": { setup(found: false) },
            "57-editor-working": { working() },
            "58-editor-stopped": { stopped() },
        ]
    }

    /// Claude Code 2.4.1 found and signed in, Codex and OpenCode found too (only installed agents are offered);
    /// `found: false`, none at all.
    static func previewPrograms(chosen: Bool, signedIn: Bool = true, found: Bool = true) {
        var values: [String: Any] = [EditorSetupKey.signedIn(.claudeCode): signedIn, EditorSetupKey.signedIn(.opencode): true]
        if chosen { values[EditorSetupKey.runsOn] = EditorRunsOn.claudeCode.rawValue }
        let installs: [EditorProgram: EditorInstall] = found ? [
            .claudeCode: EditorInstall(program: .claudeCode, path: "/Users/you/.local/bin/claude", version: "2.4.1"),
            .codex: EditorInstall(program: .codex, path: "/opt/homebrew/bin/codex", version: "0.164.0"),
            .opencode: EditorInstall(program: .opencode, path: "/Users/you/.opencode/bin/opencode", version: "2.2.7", acp: ["acp"]),
        ] : [:]
        EditorPrograms.shared.setPreview(installs, values: values)
    }

    // MARK: 43

    private static func settings() -> SnapshotScene {
        SettingsKey.register()
        previewPrograms(chosen: true)
        return SnapshotScene(size: CGSize(width: Gate.Size.settingsWidth, height: 789),
                             SettingsView(initialTab: .editor, preview: true).frame(width: Gate.Size.settingsWidth, height: 789, alignment: .top).clipped().background(Gate.Surface.ground))
    }

    // MARK: 56

    /// Over the Footage step (frame 04's state): nothing set up yet, so the pill says so.
    /// Who's editing? for a new film; not signed in: the sign-in step, with Check again.
    private static func setup(signedIn: Bool = true, found: Bool = true) -> SnapshotScene {
        previewPrograms(chosen: false, signedIn: signedIn, found: found)
        let m = StartFixtures.newFilm()
        m.project?.assets = []; m.dailies = Dailies(); m.displayed = m.project
        m.runs.previewStarts = true; m.runs.previewReady = false
        m.sheet = .editorSetup
        return .film(m)
    }

    // MARK: 57, 58

    /// 14:06:00 on Oct 28, four minutes into Cut 4.
    static let now = Date(timeIntervalSince1970: SampleFilm.date(10, 28, 14, 6) + 50)

    static func run(_ state: EditorRunState, reason: EditorRunReason? = nil) -> EditorRun {
        var r = EditorRun(id: "run-cut-4", job: .turnover, state: state, program: EditorProgram.claudeCode.rawValue, version: "claude-opus-5-5", turnoverID: "turnover-3", createdAt: now.timeIntervalSince1970 - 245)
        r.effort = "xhigh"; r.startedAt = now.timeIntervalSince1970 - 240; r.session = "8a1f0c2e-preview"; r.spend = 0.84; r.invocations = 1; r.reason = reason
        if state == .failed { r.endedAt = SampleFilm.date(10, 28, 14, 6) }
        return r
    }

    /// The editor's last five acts on Cut 4, newest first (frame 57).
    static var activity: [EditorActivity] {
        let t = now.timeIntervalSince1970
        func a(_ id: Int64, _ ago: Double, _ verb: String, _ object: String, _ detail: String? = nil, mono: Bool = false, time: Double? = nil) -> EditorActivity {
            EditorActivity(id: id, runID: "run-cut-4", verb: verb, object: object, detail: detail, mono: mono, time: time, tool: "direction_edit", startedAt: t - ago, at: t - ago, count: 1, turnoverID: "turnover-3")
        }
        return [
            a(5, 1, "Watching", "1:12\u{2013}1:14", mono: true, time: SampleFilm.tc(1, 12, 8)),
            a(4, 12, "Reframing", "3B T2 to 1.6\u{00D7}", "note 3", time: SampleFilm.tc(1, 5)),
            a(3, 40, "Trimming", "scene 1", "\u{2212}4.2 s \u{00B7} note 1", time: SampleFilm.tc(0, 9, 12)),
            a(2, 75, "Listening to", "2A T5", "note 2"),
            a(1, 190, "Reading back", "7 notes"),
        ]
    }

    /// Frame 57: the Cut room while the editor cuts Cut 4, its popover open from the pill.
    private static func working() -> SnapshotScene {
        let m = NotesFixtures.cutting()
        m.position = SampleFilm.tc(0, 46, 12)
        m.runs.previewStarts = true
        m.runs.runs = [run(.working)]
        m.runs.activity = activity
        m.runs.previewPillOpen = true
        return SnapshotScene(ZStack(alignment: .topLeading) {
            FilmWindow(app: nil, model: m)
            ActivityPopoverChrome { EditorActivityPopover(model: m, run: m.runs.runs[0], now: now) }.offset(x: 1018, y: 46)
        })
    }

    /// Frame 58: the run failed during Cut 4 because Claude Code isn't signed in.
    private static func stopped() -> SnapshotScene {
        let m = NotesFixtures.cutting()
        m.position = SampleFilm.tc(0, 46, 12)
        m.turnovers[0].state = .failed
        m.turnovers[0].progress["note-3"] = .stopped
        m.turnovers[0].message = EditorStopCopy.title(.notSignedIn, run: nil)
        m.turnovers[0].updatedAt = SampleFilm.date(10, 28, 14, 6)
        m.runs.previewStarts = true
        m.runs.runs = [run(.failed, reason: .notSignedIn)]
        m.runs.activity = activity
        return .film(m)
    }
}

/// What NSPopover draws around the activity popover: panel, radius 12, line-2 ring, the arrow centered.
/// The shadow is `.pop`'s `0 24px 60px -12px`: inset before the blur, so it never reaches the pill.
private struct ActivityPopoverChrome<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .clipShape(shape)
            .background(shape.fill(Color.black.opacity(0.9)).padding(12).offset(y: 24).blur(radius: 30))
            .overlay(shape.strokeBorder(Gate.Line.strong, lineWidth: 1))
            .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1).padding(.horizontal, 12).padding(.top, 1) }
            .overlay(alignment: .top) {
                Rectangle().fill(Gate.Surface.panel).frame(width: 12, height: 12)
                    .overlay(alignment: .top) { Gate.Line.strong.frame(height: 1) }
                    .overlay(alignment: .leading) { Gate.Line.strong.frame(width: 1) }
                    .rotationEffect(.degrees(45))
                    .offset(y: -6)
            }
    }
}

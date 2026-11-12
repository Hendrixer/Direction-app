import Testing
import Foundation
import DirectionCore
import DirectionTools
@testable import DirectionApp

/// A real editor run on a scratch copy of a film, to measure a change to how the editor works (docs/editor-runs.md ›
/// Measuring a run). It spends the signed-in agent's plan, so it only runs when asked:
///
///     DIRECTION_LIVE_EDITOR_FILM=<a copy of a film, never the film itself> DIRECTION_LIVE_EDITOR_BASE="Cut 4"
///     DIRECTION_LIVE_EDITOR_NOTES=7,8,9 DIRECTION_LIVE_EDITOR_QUALITY=fastest DIRECTION_LIVE_EDITOR_HELPER=<direction>
///     swift test --filter LiveEditorRunTests   (with the scratch DIRECTION_* paths set, as scripts/test.sh sets them)
///
/// It puts the copy back to the named cut, writes the numbered notes again as new ones, turns them over without
/// waiting for an OK, and runs the film's editor (Claude Code) on them at that speed and quality. The session's id
/// is printed: its steps are in the agent's own session file.
@MainActor
struct LiveEditorRunTests {
    nonisolated static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["DIRECTION_LIVE_EDITOR_FILM"] != nil), .timeLimit(.minutes(60)))
    func aTurnoverOnACopyOfAFilm() async throws {
        let env = Self.env
        let film = URL(fileURLWithPath: try #require(env["DIRECTION_LIVE_EDITOR_FILM"]))
        // Never a film in the director's own folder.
        #expect(!film.path.hasPrefix(NSHomeDirectory() + "/Movies/"))
        guard !film.path.hasPrefix(NSHomeDirectory() + "/Movies/") else { return }
        let quality = try #require(FilmQuality(rawValue: env["DIRECTION_LIVE_EDITOR_QUALITY"] ?? "fastest"))
        let numbers = Set((env["DIRECTION_LIVE_EDITOR_NOTES"] ?? "").split(separator: ",").compactMap { Int($0) })
        let store = try ProjectStore(url: film)
        let base = try #require(try store.cuts().first { $0.name == env["DIRECTION_LIVE_EDITOR_BASE"] })
        _ = try store.restore(revision: base.editRevision, expectedRevision: try store.revision(), key: UUID().uuidString, keepingLocks: true)
        let old = try store.notes().filter { $0.number.map(numbers.contains) == true }.sorted { ($0.number ?? 0) < ($1.number ?? 0) }
        #expect(old.count == numbers.count)
        let revision = try store.revision()
        let notes = try old.map { try store.addComment(text: $0.text, sequenceID: nil, revision: revision, range: $0.range, time: $0.time, extra: NoteFields(kind: $0.kind)) }
        let turnover = try store.turnOver(noteIDs: notes.map(\.id), latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        _ = try store.updateDirectingState(summary: "Speed and quality for a measured run") { $0.quality = quality; $0.editor = EditorProgram.claudeCode.rawValue; $0.editorPaused = false }
        // Notes from earlier runs would help this one where the first had none.
        try? "# Notes between runs\n\nWhat I\u{2019}d want to know next time I pick up this film.\n".write(to: film.appendingPathComponent("Editor/NOTES.md"), atomically: true, encoding: .utf8)

        let install = try #require(EditorDiscovery.find(.claudeCode), "Claude Code isn\u{2019}t installed")
        EditorPrograms.shared.setPreview([.claudeCode: install],
                                         values: [EditorSetupKey.runsOn: "claudeCode", EditorSetupKey.signedIn(.claudeCode): true])
        let runner = EditorRunner.shared
        runner.programOverride = [:]; runner.helperOverride = env["DIRECTION_LIVE_EDITOR_HELPER"]
        let pick = EditorPicks.pick(.claudeCode, .turnover, quality)
        let run = EditorRun(job: .turnover, program: "claudeCode", version: pick.version, turnoverID: turnover.id)
        try store.saveRun(run)
        let started = Date()
        runner.launch(run, store: store)
        var ended: EditorRun?
        for _ in 0..<(55 * 60 * 2) {
            if let r = try store.run(run.id), !r.state.isActive, !runner.isLive(run.id), r.endedAt != nil { ended = r; break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let r = try #require(ended, "The run didn\u{2019}t end in 55 minutes")
        print("LIVE RUN \(quality.rawValue) \(pick.version) \(pick.effort ?? "") state=\(r.state.rawValue) seconds=\(Int(Date().timeIntervalSince(started))) invocations=\(r.invocations) spend=\(r.spend ?? 0) session=\(r.session ?? "none") delivered=\((try? store.turnover(turnover.id).state.rawValue) ?? "?")\nSUMMARY \(r.summary ?? "")")
        #expect(r.state == .done)
    }
}

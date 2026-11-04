import Testing
import Foundation
import DirectionCore
import DirectionTools
@testable import DirectionApp

/// The brief's Shape in the app (start.md › 03 · Shape, cut.md › Changing the shape): every job reads it, and
/// saving a new one changes the cut with black bars, or adds a note asking the editor to fill the frame.
@MainActor
struct FilmShapeAppTests {
    private func film() throws -> (ProjectStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-shape-" + UUID().uuidString)
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Film.direction"), name: "Shape")
        let take = MediaAsset(id: "a", name: "a.mov", path: "/shape-test-a.mov", duration: .init(seconds: 10), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)])
        _ = try store.addAsset(take, append: true, expectedRevision: 0)
        return (store, dir)
    }

    @Test func everyJobReadsTheShape() throws {
        let (store, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
        var brief = Brief(); brief.logline = "Two years in one room."; brief.feeling = "Quiet."; brief.shape = .tall
        try store.saveBrief(brief)
        let text = try EditorJobs.text(for: EditorRun(job: .logFootage, program: "claudeCode", version: "claude-opus-5-5"), store: store)
        #expect(text.contains("- Shape: 9:16.") && text.contains("`reframe` skill"))
        brief.shape = nil
        try store.saveBrief(brief)
        #expect(!(try EditorJobs.text(for: EditorRun(job: .logFootage, program: "claudeCode", version: "claude-opus-5-5"), store: store)).contains("- Shape:"))
    }

    @Test func savingANewShapeChangesTheCutWithBarsOrAsksTheEditorToFill() throws {
        let (store, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.createCut(name: "Assembly", sequenceID: nil, revision: nil)
        let m = FilmModel()
        m.runtime = try ToolRuntime(store: store)
        m.refresh(force: true)
        #expect(m.shapeLabel == "16:9" && m.footageShapeLabel == "16:9" && m.shapeBlocker == nil)
        let change = try #require(m.shapeChange(to: .tall))
        #expect(change.from == "16:9" && change.to == "9:16" && change.taller && m.shapeChange(to: .wide) == nil)

        // Fill the frame: bars at once, and a note for the next turnover.
        var tall = m.brief; tall.shape = .tall
        let noteID = m.saveBrief(tall, fill: true)
        m.refresh(force: true)
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(m.shapeLabel == "9:16" && m.brief.shape == .tall && m.toast?.title == "Assembly is 9:16 now")
        let note = try #require(noteID.flatMap { m.note($0) })
        #expect(note.text == "Fill the 9:16 frame: crop each shot instead of the black bars." && note.kind == .picture && note.lifecycle == .written)

        // Back to as shot, with bars: no note.
        var asShot = m.brief; asShot.shape = nil
        #expect(m.saveBrief(asShot) == nil)
        m.refresh(force: true)
        #expect(m.shapeLabel == "16:9" && m.brief.shape == nil && m.shapeChange(to: nil) == nil)

        // Picture locked: the shape can't change, and saving keeps the one it has.
        try store.dropNote(id: note.id)
        try store.lockPicture(cutID: nil, locked: true)
        m.refresh(force: true)
        #expect(m.shapeBlocker == "Picture is locked. Unlock it to change the shape.")
        var square = m.brief; square.shape = .square
        m.saveBrief(square)
        #expect(m.brief.shape == nil && m.shapeLabel == "16:9" && m.error != nil)
    }
}

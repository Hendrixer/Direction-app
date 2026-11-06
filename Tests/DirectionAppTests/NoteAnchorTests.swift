import Testing
import Foundation
import CoreGraphics
import DirectionCore
import DirectionTools
@testable import DirectionApp

/// Notes are made the moment you point at something (specs/cut.md › Making a note): a mark, a stretch, a box
/// or the whole cut, each its own note at once, written up in its row.
@MainActor
struct NoteAnchorTests {
    /// A one-minute cut of three takes, on a real store.
    static func film() throws -> (FilmModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direction-note-anchors-" + UUID().uuidString)
        let store = try ProjectStore.create(at: directory.appendingPathComponent("Film.direction"), name: "Marks")
        func take(_ id: String) -> MediaAsset { MediaAsset(id: id, name: id + ".mov", path: "/\(id).mov", duration: .init(seconds: 20), video: [.init(id: 1, width: 640, height: 360, frameRate: 30)]) }
        for a in ["a", "b", "c"] { _ = try store.addAsset(take(a), append: true, expectedRevision: store.revision()) }
        _ = try store.createCut(name: "Assembly", sequenceID: nil, revision: nil)
        let m = FilmModel()
        m.runtime = try ToolRuntime(store: store)
        m.refresh(force: true)
        return (m, directory)
    }

    /// The bug a director hit: a box taken away, then a new one drawn later in the cut, written up, then clicked.
    /// The new box's note sits where it was drawn, with its own box, and that box still moves.
    @Test func aBoxDrawnAfterOneWasTakenAwayKeepsItsOwnMoment() throws {
        let (m, dir) = try Self.film(); defer { try? FileManager.default.removeItem(at: dir) }
        m.position = 10
        m.beginRegion()
        m.region = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        m.finishBox(new: true)
        let first = try #require(m.selectedNote)
        #expect(first.region?.x == 0.1 && m.notesUI.editingNoteID == first.id)
        m.dropFromSheet(first)
        m.position = 40
        m.beginRegion()
        m.region = CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3)
        m.finishBox(new: true)
        m.draftText = "Brighter here."
        m.saveWriting()
        let note = try #require(m.notes.first { $0.text == "Brighter here." })
        #expect(abs((note.time?.seconds ?? -1) - 40) < 0.1, "saved at \(note.time?.seconds ?? -1)")
        #expect(note.region?.x == 0.5 && note.lifecycle == .written)
        #expect(m.note(first.id)?.lifecycle == .dropped)
        m.position = 0
        m.select(note)
        #expect(m.position == note.time?.seconds && m.visibleRegion?.minX == 0.5 && m.boxEditable)
        // It moves, and a box taken off leaves the note on its moment.
        m.region = CGRect(x: 0.4, y: 0.5, width: 0.3, height: 0.3)
        m.finishBox(new: false)
        #expect(m.note(note.id)?.region?.x == 0.4 && m.region == nil)
        m.removeBox(m.note(note.id)!)
        #expect(m.note(note.id)?.region == nil && m.note(note.id)?.time != nil)
    }

    /// A mark, a stretch, a box and the whole cut: each is a note at once with no words, its icon says which, and
    /// paused its row opens to write in. N while the cut plays only drops the mark.
    @Test func everyWayToPointMakesANoteAtOnce() throws {
        let (m, dir) = try Self.film(); defer { try? FileManager.default.removeItem(at: dir) }
        m.position = 5
        m.mark()
        let mark = try #require(m.selectedNote)
        #expect(mark.lifecycle == .draft && mark.time?.seconds == 5 && NoteAnchor(mark) == .moment && m.notesUI.editingNoteID == mark.id)
        m.markStretch(12...18)
        let stretch = try #require(m.selectedNote)
        #expect(stretch.range == MediaRange(start: 12, end: 18) && NoteAnchor(stretch) == .stretch && m.notesUI.editingNoteID == stretch.id)
        m.position = 30
        m.beginRegion()
        #expect(m.drawingRegion && m.isDrawing)
        m.region = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        m.finishBox(new: true)
        let box = try #require(m.selectedNote)
        #expect(NoteAnchor(box) == .box && box.time?.seconds == 30 && !m.drawingRegion)
        m.noteWholeCut()
        let whole = try #require(m.selectedNote)
        #expect(NoteAnchor(whole) == .wholeCut && whole.time == nil && whole.range == nil)
        #expect(Set(m.draftNotes.map(\.id)) == [mark.id, stretch.id, box.id, whole.id])
        #expect(m.anchorIcon(stretch) == "arrow.left.and.right" && m.anchorIcon(box) == "viewfinder")
        // Playing: a mark waits to be written.
        m.stopWriting()
        m.playing = true
        m.position = 50
        m.mark()
        #expect(m.notesUI.editingNoteID == nil && m.notes.contains { $0.time?.seconds == 50 && $0.lifecycle == .draft })
        m.playing = false
        // esc while drawing makes nothing.
        let count = m.notes.count
        m.beginStretch(); m.rangeSelection = 20...25; m.cancelDrawing()
        #expect(m.notes.count == count && m.stripRange == nil)
    }

    /// A stretch pulls longer and moves; what it rests on in the footage moves with it. ⌫ takes it away.
    @Test func aStretchCanBePulledMovedAndRemoved() throws {
        let (m, dir) = try Self.film(); defer { try? FileManager.default.removeItem(at: dir) }
        m.beginStretch()
        m.rangeSelection = 10...14
        m.finishStretch(new: true)
        let note = try #require(m.selectedNote)
        #expect(note.range == MediaRange(start: 10, end: 14) && m.stretchEditable && m.stripRange == 10...14)
        let before = note.anchors
        m.rangeSelection = 22...30
        m.finishStretch(new: false)
        let moved = try #require(m.note(note.id))
        #expect(moved.range == MediaRange(start: 22, end: 30) && moved.anchors != before && m.stripRange == 22...30)
        // I and O move its edges to the playhead.
        m.position = 25
        m.setStretchEdge(start: false)
        #expect(m.note(note.id)?.range == MediaRange(start: 22, end: 25))
        m.dropFromSheet(m.note(note.id)!)
        #expect(m.note(note.id)?.lifecycle == .dropped && m.selectedNote?.id != note.id && m.stripRange == nil)
        // With nothing selected, I starts a new two-second stretch here.
        m.selectedNoteID = nil
        m.position = 40
        m.setStretchEdge(start: true)
        #expect(m.selectedNote?.range == MediaRange(start: 40, end: 42))
    }

    /// A note is written in its row: ↩ keeps the words, esc closes it as it was, and an empty one stays a mark.
    @Test func aNoteIsWrittenInItsRow() throws {
        let (m, dir) = try Self.film(); defer { try? FileManager.default.removeItem(at: dir) }
        m.position = 8
        m.mark()
        let id = try #require(m.selectedNote?.id)
        m.stopWriting()
        #expect(m.note(id)?.lifecycle == .draft && m.notesUI.editingNoteID == nil)
        m.beginWriting(m.note(id)!)
        m.draftText = "Hold on her."
        m.draftKind = .pace
        m.saveWriting()
        #expect(m.note(id)?.text == "Hold on her." && m.note(id)?.kind == .pace && m.note(id)?.lifecycle == .written)
        // Editing it again and pressing esc changes nothing.
        m.beginWriting(m.note(id)!)
        m.draftText = "Something else"
        m.stopWriting()
        #expect(m.note(id)?.text == "Hold on her.")
        // Making another note keeps the words being written in the first.
        m.beginWriting(m.note(id)!)
        m.draftText = "Hold on her longer."
        m.markStretch(20...24)
        #expect(m.note(id)?.text == "Hold on her longer." && m.selectedNote?.range != nil)
    }
}

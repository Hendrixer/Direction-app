import SwiftUI
import DirectionCore

// Owner: System agent (frame 53). Shared context menus; every room uses these.

/// Right-click a scene on any strip.
struct SceneContextMenu: View {
    var model: FilmModel
    var scene: StripScene
    var body: some View {
        Text("\(scene.label) · \(Timecode.range(scene.start, scene.end, fps: model.fps))")
        Button("Play from Here") { model.seek(scene.start); if !model.playing { model.togglePlayback() } }
        Button("Mark Here") { model.seek(scene.start); model.mark() }
        Button("Note on This Scene") { model.anchorMode = .scene; model.seek(scene.start); model.go(.notes); model.composerFocus += 1 }
        Divider()
        if model.dailies.scenes.contains(where: { $0.id == scene.id }) {
            Button(scene.locked ? "Unlock Scene" : "Lock Scene") { model.lockScene(scene.id, !scene.locked) }
            Button("Open in Dailies") { model.selectedSceneID = scene.id; model.go(.dailies) }
        }
        Button("Open in Script") { model.seek(scene.start); model.go(.script) }
    }
}

/// Right-click a note row.
struct NoteContextMenu: View {
    var model: FilmModel
    var note: ReviewComment
    var body: some View {
        Button("Play from Note") { model.select(note); model.togglePlayback() }
        if [.draft, .written, .reopened].contains(note.lifecycle) {
            Button("Edit Note") { model.select(note); model.draftText = note.text; model.draftKind = note.kind; model.composerFocus += 1 }
            Menu("Kind") {
                ForEach(NoteKind.allCases, id: \.self) { k in Button(k.label) { model.editNote(note.id, kind: .some(k)) } }
            }
        }
        Divider()
        if let n = note.number { Button("Copy Link to Note \(n)") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("direction://note/\(note.id)", forType: .string) } }
        if ![.answered, .accepted, .dropped].contains(note.lifecycle) {
            Divider()
            Button("Drop Note", role: .destructive) { model.dropNote(note.id) }
        }
    }
}

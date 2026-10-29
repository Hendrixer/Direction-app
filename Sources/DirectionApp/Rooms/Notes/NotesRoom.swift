import SwiftUI
import DirectionCore

// Owner: Notes agent. Frames 17–28. Replace these stubs.

struct NotesRoom: View {
    @Bindable var model: FilmModel
    var body: some View { Text("Notes").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct TurnoverSheet: View {
    @Bindable var model: FilmModel
    var body: some View { AttachedSheet(onDismiss: { model.sheet = nil }) { SheetHeader(title: "Turn over") } }
}

extension FilmModel {
    var notesPrimary: PrimaryAction? { PrimaryAction(title: "Turn over", icon: "arrow.right", count: String(readyNotes.count), enabled: !readyNotes.isEmpty && openTurnover == nil) { self.sheet = .turnover } }
}

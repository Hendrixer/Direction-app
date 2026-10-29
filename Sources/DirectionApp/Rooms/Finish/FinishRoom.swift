import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. Frames 34–38. Replace these stubs.

struct FinishRoom: View {
    @Bindable var model: FilmModel
    var body: some View { Text("Finish").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct LockPictureSheet: View {
    @Bindable var model: FilmModel
    var body: some View { AttachedSheet(onDismiss: { model.sheet = nil }) { SheetHeader(title: "Lock picture") } }
}

struct DeliverSheet: View {
    @Bindable var model: FilmModel
    var body: some View { AttachedSheet(onDismiss: { model.sheet = nil }) { SheetHeader(title: "Deliver") } }
}

extension FilmModel {
    var finishPrimary: PrimaryAction? { PrimaryAction(title: "Deliver…", icon: "square.and.arrow.up") { self.sheet = .deliver } }
}

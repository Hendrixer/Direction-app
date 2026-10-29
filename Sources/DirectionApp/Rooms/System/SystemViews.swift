import SwiftUI
import DirectionCore

// Owner: System agent. Frames 39–53, Settings, menus. Replace these stubs.

struct SystemBanners: View {
    @Bindable var model: FilmModel
    var body: some View { EmptyView() }
}

struct EditorPopover: View {
    @Bindable var model: FilmModel
    var body: some View { Text(model.pill.text).padding() }
}

struct ShareSheet: View {
    @Bindable var model: FilmModel
    var body: some View { AttachedSheet(onDismiss: { model.sheet = nil }) { SheetHeader(title: "Share") } }
}

struct RelinkSheet: View {
    @Bindable var model: FilmModel
    var body: some View { AttachedSheet(onDismiss: { model.sheet = nil }) { SheetHeader(title: "Find missing footage") } }
}

struct CommandMenuOverlay: View {
    @Bindable var model: FilmModel
    var app: AppModel?
    var body: some View { EmptyView() }
}

struct ShortcutsOverlay: View {
    @Bindable var model: FilmModel
    var body: some View { EmptyView() }
}

struct SettingsView: View {
    var body: some View { Text("Settings").frame(width: Gate.Size.settingsWidth, height: 400) }
}

struct DirectionCommands: Commands {
    var app: AppModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Film") { app.newFilm() }.keyboardShortcut("n")
            Button("Open…") { app.chooseFilm() }.keyboardShortcut("o")
        }
    }
}

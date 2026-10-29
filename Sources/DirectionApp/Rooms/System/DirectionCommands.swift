import SwiftUI
import AppKit
import DirectionCore

/// The menu bar (system.md › Menu bar): Direction, File, Edit, View, Film, Cut, Playback, Window, Help.
/// Items act on the open film and are disabled, not hidden, when they don't apply. Key equivalents
/// come from the shortcut registry; single-key shortcuts (N, Space, J/K/L…) stay in the rooms so a
/// menu never takes a keystroke from a note field.
struct DirectionCommands: Commands {
    var app: AppModel

    init(app: AppModel) {
        self.app = app
        SettingsKey.register()
        SystemNotifications.install(app: app)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Direction") { NSApp.orderFrontStandardAboutPanel(nil) }
        }
        CommandGroup(after: .appSettings) {
            Button("Check for Updates\u{2026}") {}.disabled(true)
        }
        CommandGroup(replacing: .newItem) { FileMenuItems(app: app) }
        CommandGroup(replacing: .saveItem) { CloseItem(app: app) }
        CommandGroup(replacing: .printItem) {}
        CommandGroup(after: .pasteboard) { EditMenuItems(app: app) }
        CommandGroup(before: .toolbar) { ViewMenuItems(app: app) }
        CommandMenu("Film") { FilmMenuItems(app: app) }
        CommandMenu("Cut") { CutMenuItems(app: app) }
        CommandMenu("Playback") { PlaybackMenuItems(app: app) }
        CommandGroup(before: .windowArrangement) {
            Button("Films") { app.closeFilm() }.shortcut(.films).disabled(app.film == nil)
            Divider()
        }
        CommandGroup(replacing: .help) { HelpMenuItems(app: app) }
    }
}

/// Opens the command menu narrowed to a section (Help › How Direction Works, Edit › Find…).
@MainActor enum CommandMenuLaunch { static var pendingFilter: CommandSection? }

/// What the menus need that changes often, updated only when it actually changes
/// (SystemBanners keeps it current), so menu bodies don't re-run with the playhead.
@MainActor @Observable
final class MenuState {
    static let shared = MenuState()
    /// The Dailies scene under the playhead.
    var sceneID: String?
    var missingCount = 0
}

// MARK: File

private struct FileMenuItems: View {
    var app: AppModel
    var body: some View {
        let film = app.film
        Button("New Film\u{2026}") { app.newFilm() }.shortcut(.newFilm)
        Button("Open\u{2026}") { app.chooseFilm() }.shortcut(.openFilm)
        Menu("Open Recent") {
            let _ = app.films.count
            let recent = NSDocumentController.shared.recentDocumentURLs
            ForEach(recent, id: \.self) { url in Button(url.deletingPathExtension().lastPathComponent) { app.open(url) } }
            if !recent.isEmpty { Divider() }
            Button("Clear Menu") { NSDocumentController.shared.clearRecentDocuments(nil) }.disabled(recent.isEmpty)
        }
        Divider()
        Button("Bring Footage\u{2026}") { film?.chooseFootage() }.shortcut(.bringFootage).disabled(film == nil)
        Button("Find Missing Footage\u{2026}") { film?.sheet = .relink }.disabled(film == nil || MenuState.shared.missingCount == 0)
        Divider()
        Button("Share \(film?.watchedCut?.name ?? "Cut")\u{2026}") { film?.sheet = .share }.shortcut(.share).disabled(film?.cuts.isEmpty ?? true)
        Button("Export\u{2026}") { if let film { film.sheet = film.isPictureLocked ? .deliver : .share } }.shortcut(.export).disabled(film?.cuts.isEmpty ?? true)
        Divider()
        Button("Show in Finder") { if let film { FilmActions(film).revealInFinder() } else { NSWorkspace.shared.open(URL(fileURLWithPath: UserDefaults.standard.string(forKey: SettingsKey.libraryFolder) ?? SettingsKey.defaultLibrary)) } }
    }
}

/// ⌘W: the film closes back to Films; other windows (Settings) close.
private struct CloseItem: View {
    var app: AppModel
    var body: some View {
        Button(app.film == nil ? "Close Window" : "Close Film") {
            guard let key = NSApp.keyWindow else { return }
            if key.frameAutosaveName == "DirectionMainWindow", app.film != nil {
                app.closeFilm()
                if !UserDefaults.standard.bool(forKey: SettingsKey.showFilmsWhenEmpty) { NSApp.terminate(nil) }
            } else { key.performClose(nil) }
        }
        .shortcut(.closeFilm)
    }
}

// MARK: Edit

private struct EditMenuItems: View {
    var app: AppModel
    var body: some View {
        let film = app.film
        Button("Copy Timecode") { if let film { FilmActions(film).copyTimecode() } }.shortcut(.copyTimecode).disabled(film == nil || film?.duration == 0)
        Divider()
        Button("Find\u{2026}") {
            guard let film else { return }
            CommandMenuLaunch.pendingFilter = switch film.room { case .notes, .screening, .changes: .notes; case .dailies: .takes; default: nil }
            film.showCommandMenu = true
        }
        .shortcut(.find).disabled(film == nil)
    }
}

// MARK: View

private struct ViewMenuItems: View {
    var app: AppModel
    var body: some View {
        let film = app.film
        ForEach(Array(Room.allCases.enumerated()), id: \.offset) { i, room in
            Button(room.title) { film?.go(room) }
                .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                .disabled(film.map { !$0.isEnabled(room) || $0.onboardingStep != nil } ?? true)
        }
        Divider()
        Button("Show Notes") { film?.go(.notes) }.keyboardShortcut("s", modifiers: [.command, .option]).disabled(film == nil || film?.room == .notes)
        Button("Show Transcript Captions") {}.disabled(true)
        Button("Show Safe Areas") {}.disabled(true)
        Divider()
        Button("Command Menu") { film?.showCommandMenu = true }.shortcut(.commandMenu).disabled(film == nil)
        Button("Keyboard Shortcuts") { film?.showShortcuts = true }.disabled(film == nil)
        Divider()
    }
}

// MARK: Film

private struct FilmMenuItems: View {
    var app: AppModel
    var body: some View {
        let film = app.film, actions = film.map(FilmActions.init)
        Button("Brief\u{2026}") { film?.sheet = .brief }.shortcut(.brief).disabled(film == nil)
        Button("Editor\u{2026}") { film?.showEditorPopover = true }.shortcut(.editor).disabled(film == nil || film?.onboardingStep != nil)
        // ⇧⌘L is Lock Picture (system.md, finish.md), so the Look sheet takes ⌥⌘L.
        Button("Look at Footage") { if let film { film.index.lookAtFootage(film) } }.disabled(film?.project?.assets.isEmpty ?? true)
        Button("Look\u{2026}") { film?.openLook() }.keyboardShortcut("l", modifiers: [.command, .option]).disabled(film.map { $0.cuts.isEmpty || $0.sheet != nil } ?? true)
        Divider()
        Picker("How Much Freedom", selection: Binding(get: { film?.directing.latitude ?? LatitudeSetting.current }, set: { LatitudeSetting.set($0, film: film) })) {
            ForEach(Latitude.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .disabled(film == nil)
        // ⌥⌘.: interrupts a run Direction started after its current tool call, or resumes it.
        Button(film?.editorIsPaused == true ? "Resume Editor" : "Pause Editor") { if let film { film.setEditorPaused(!film.editorIsPaused) } }
            .keyboardShortcut(".", modifiers: [.option, .command]).disabled(film == nil)
        // Your own session only: when Direction starts the editor there's nothing to copy.
        if film?.runs.startsEditor != true { Button("Copy Request for Your Editor") { film?.copyEditorRequest() }.disabled(film?.url == nil) }
        Divider()
        // MenuState follows the playhead's scene, so the menu doesn't rebuild on every frame.
        let scene = MenuState.shared.sceneID.flatMap { id in film?.dailies.scenes.first { $0.id == id } }
        Button(scene?.locked == true ? "Unlock Current Scene" : "Lock Current Scene") { actions?.toggleCurrentSceneLock() }
            .shortcut(.lockScene).disabled(scene == nil || film?.isPictureLocked == true)
        Button("Lock Picture\u{2026}") { film?.sheet = .lockPicture }.shortcut(.lockPicture).disabled(film == nil || actions?.lockPictureUnavailableReason != nil)
        Button("Unlock Picture\u{2026}") { actions?.confirmUnlockPicture() }.disabled(!(film?.isPictureLocked ?? false))
        Divider()
        SettingsMenuButton(title: "Film Settings\u{2026}", tab: .editor)
    }
}

/// Opens Settings at a tab from a menu.
private struct SettingsMenuButton: View {
    var title: String
    var tab: SettingsTab
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button(title) { UserDefaults.standard.set(tab.rawValue, forKey: SettingsKey.settingsTab); openSettings() }
    }
}

// MARK: Cut

private struct CutMenuItems: View {
    var app: AppModel
    var body: some View {
        let film = app.film
        let canWatch = film.map { $0.isEnabled(.screening) && $0.onboardingStep == nil } ?? false
        Button("Start Screening") { film?.go(.screening) }.shortcut(.startScreening).disabled(!canWatch)
        Divider()
        Button("Mark This Moment") { film?.mark() }.disabled(!canWatch)
        Button("New Note") { if let film { FilmActions(film).startNote() } }.shortcut(.newNote).disabled(film == nil || film?.onboardingStep != nil)
        Button("Turn Over\u{2026}") { film?.sheet = .turnover }
            .keyboardShortcut(film?.room == .notes ? ShortcutStore.shared.menuShortcut(.turnOver) : nil)
            .disabled(film.map { $0.readyNotes.isEmpty || $0.openTurnover != nil || $0.sheet != nil } ?? true)
        Divider()
        Button("Play Changes") { film?.go(.changes); film?.playChanges() }.shortcut(.playChanges).disabled(film.map { $0.changeReel(in: $0.watchedCut).isEmpty } ?? true)
        Button("Accept Answer") { if let film, let id = film.selectedAnswerNoteID { film.acceptAnswer(id) } }
            .disabled(film.map { $0.room != .changes || $0.selectedAnswerNoteID.flatMap($0.note)?.lifecycle != .answered } ?? true)
        Divider()
        Button("Assemble from Circles") { film?.assembleFromCircles() }
            .keyboardShortcut(film?.room == .dailies ? ShortcutStore.shared.menuShortcut(.assemble) : nil)
            .disabled(film.map { $0.circledCount == 0 || $0.openTurnover != nil || !$0.cuts.isEmpty || $0.sheet != nil } ?? true)
        Divider()
        Picker("Go to Cut", selection: Binding(get: { film?.watchedCut?.id ?? "" }, set: { id in if let film { film.watch(film.cuts.first { $0.id == id }) } })) {
            ForEach((film?.cuts ?? []).reversed()) { Text($0.name).tag($0.id) }
        }
        .disabled(film?.cuts.isEmpty ?? true)
        Button("History") { film?.go(.changes) }.shortcut(.history).disabled(film.map { !$0.isEnabled(.changes) } ?? true)
    }
}

// MARK: Playback

private struct PlaybackMenuItems: View {
    var app: AppModel
    var body: some View {
        let film = app.film, actions = film.map(FilmActions.init)
        let off = film.map { $0.duration <= 0 } ?? true
        Group {
            Button(film?.playing == true ? "Pause" : "Play") { film?.togglePlayback() }
            Button("Play Backward") { film?.shuttle(-1) }
            Button("Stop") { film?.shuttle(0) }
            Button("Play Forward") { film?.shuttle(1) }
            Divider()
            Button("Previous Frame") { film?.step(frames: -1) }
            Button("Next Frame") { film?.step(frames: 1) }
            Button("Back One Second") { if let film { film.pause(); film.seek(film.position - 1) } }
            Button("Forward One Second") { if let film { film.pause(); film.seek(film.position + 1) } }
            Button("Previous Scene") { actions?.jumpScene(-1) }
            Button("Next Scene") { actions?.jumpScene(1) }
        }
        .disabled(off)
        Divider()
        Group {
            Button("Set Range In") { actions?.setRangeIn() }
            Button("Set Range Out") { actions?.setRangeOut() }
        }
        .disabled(off)
        Button("Clear Range") { actions?.clearRange() }.shortcut(.clearRange).disabled(film?.rangeSelection == nil)
        Divider()
        Group {
            Button("Go to Start") { film?.pause(); film?.seek(0) }
            Button("Go to End") { if let film { film.pause(); film.seek(max(0, film.duration - 1 / film.fps)) } }
            Button("Go to Timecode\u{2026}") { actions?.askForTimecode() }.shortcut(.goToTimecode)
        }
        .disabled(off)
        Divider()
        Toggle("Mute", isOn: Binding(get: { film?.player.isMuted ?? false }, set: { film?.player.isMuted = $0 })).shortcut(.mute).disabled(film == nil)
    }
}

// MARK: Help

private struct HelpMenuItems: View {
    var app: AppModel
    var body: some View {
        let film = app.film
        Button("Keyboard Shortcuts") { film?.showShortcuts = true }.shortcut(.help).disabled(film == nil)
        Button("How Direction Works") { CommandMenuLaunch.pendingFilter = .help; film?.showCommandMenu = true }.disabled(film == nil)
        Divider()
        Button("Connect an Editor\u{2026}") { EditorConnection.presentAlert() }
        Divider()
        // What went wrong, kept on this Mac (DirectionLog): open it in Console.
        Button("Show Direction Log") {
            if !FileManager.default.fileExists(atPath: DirectionLog.file.path) { DirectionLog.info("Log opened") }
            NSWorkspace.shared.open(DirectionLog.file)
        }
    }
}

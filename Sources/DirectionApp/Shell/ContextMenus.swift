import SwiftUI
import AppKit
import DirectionCore
import DirectionTools

// Frame 53: the shared right-click menus. Each menu is a list of entries, rendered as a native
// menu (`.contextMenu { SceneContextMenu(model:scene:) }`) and, for the frame, in the Gate look.
// Disabled items stay visible. Every item also exists in the menu bar or the command menu.

/// One row of a context menu.
struct GateMenuEntry: Identifiable {
    enum Kind { case item, header, separator, submenu([GateMenuEntry]) }
    var id: Int = 0
    var kind: Kind = .item
    var title = ""
    /// An SF Symbol, or "mark" for the director's amber pin.
    var icon: String? = nil
    /// The key shown on the right: "N", "⌘L", "Feeling ›".
    var key: String? = nil
    var shortcut: KeyboardShortcut? = nil
    var destructive = false
    var disabled = false
    var checked = false
    var action: @MainActor () -> Void = {}

    static func item(_ title: String, icon: String?, key: String? = nil, shortcut: KeyboardShortcut? = nil, destructive: Bool = false, disabled: Bool = false, checked: Bool = false, _ action: @escaping @MainActor () -> Void) -> GateMenuEntry {
        GateMenuEntry(kind: .item, title: title, icon: icon, key: key, shortcut: shortcut, destructive: destructive, disabled: disabled, checked: checked, action: action)
    }
    static func header(_ title: String) -> GateMenuEntry { GateMenuEntry(kind: .header, title: title) }
    static var separator: GateMenuEntry { GateMenuEntry(kind: .separator) }
    static func submenu(_ title: String, icon: String?, key: String? = nil, disabled: Bool = false, _ entries: [GateMenuEntry]) -> GateMenuEntry {
        GateMenuEntry(kind: .submenu(entries), title: title, icon: icon, key: key, disabled: disabled)
    }
}

extension Array where Element == GateMenuEntry {
    fileprivate var numbered: [GateMenuEntry] { enumerated().map { var e = $1; e.id = $0; return e } }
}

/// Renders entries as native menu items.
struct NativeMenuItems: View {
    var entries: [GateMenuEntry]
    var body: some View {
        ForEach(entries.numbered) { entry in
            switch entry.kind {
            case .separator: Divider()
            case .header: Text(entry.title)
            case .item:
                Button(role: entry.destructive ? .destructive : nil) { entry.action() } label: {
                    if entry.checked { Label(entry.title, systemImage: "checkmark") }
                    else if let icon = entry.icon { Label(entry.title, systemImage: icon == "mark" ? "mappin" : icon) }
                    else { Text(entry.title) }
                }
                .keyboardShortcut(entry.shortcut)
                .disabled(entry.disabled)
            case .submenu(let children):
                Menu { NativeMenuItems(entries: children) } label: {
                    if let icon = entry.icon { Label(entry.title, systemImage: icon) } else { Text(entry.title) }
                }
                .disabled(entry.disabled)
            }
        }
    }
}

/// The Gate menu look (`.pop.menu`): the reference drawing for frame 53 and any custom-drawn fallback.
struct GateMenuCard: View {
    var entries: [GateMenuEntry]
    /// The row under the pointer.
    var highlighted: String? = nil
    var minWidth: CGFloat = 220
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(entries.numbered) { entry in
                switch entry.kind {
                case .separator: SystemHairline().padding(.horizontal, 6).padding(.vertical, 4)
                case .header: SectionLabel(entry.title).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
                case .item, .submenu: row(entry)
                }
            }
        }
        .padding(5)
        .frame(minWidth: minWidth, alignment: .leading)
        .fixedSize()
        .background(SystemPopBackground(radius: 12))
    }

    private func row(_ e: GateMenuEntry) -> some View {
        let color: Color = e.disabled ? Gate.Text.disabled : e.destructive ? Gate.State.alert : Gate.Text.primary
        let keyText: String? = { if case .submenu = e.kind { return (e.key.map { $0 + " " } ?? "") + "\u{203A}" }; return e.key }()
        return HStack(spacing: 9) {
            Group {
                if e.icon == "mark" { PinMark(size: 11) }
                else if let icon = e.icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(e.destructive ? Gate.State.alert : Gate.Text.tertiary) }
            }
            .frame(width: 14, height: 14)
            Text(e.title).font(.system(size: 13)).foregroundStyle(color).lineLimit(1)
            Spacer(minLength: 24)
            if let keyText { Text(keyText).font(.system(size: 12)).foregroundStyle(Gate.Text.disabled) }
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(highlighted == e.title ? Gate.Surface.hover : .clear))
    }
}

// MARK: Scene strip

/// Right-click a scene on any strip.
struct SceneContextMenu: View {
    var model: FilmModel
    var scene: StripScene
    var body: some View { NativeMenuItems(entries: Self.entries(model: model, scene: scene)) }

    @MainActor static func entries(model: FilmModel, scene: StripScene) -> [GateMenuEntry] {
        let dailiesScene = model.dailies.scenes.first { $0.id == scene.id }
        let keys = ShortcutStore.shared
        return [
            .header("\(scene.label) · \(Timecode.range(scene.start, scene.end, fps: model.fps))"),
            .item("Play from Here", icon: "play.fill", key: "Space", shortcut: .init(.space, modifiers: [])) { FilmActions(model).play(from: scene.start) },
            .item("Mark Here", icon: "mark", key: "N", shortcut: .init("n", modifiers: []), disabled: model.duration <= 0) { model.pause(); model.seek(scene.start); model.mark() },
            .item("Note on This Scene", icon: "text.bubble") { model.seek(scene.start); FilmActions(model).startNote(anchor: .scene) },
            .separator,
            .item(scene.locked ? "Unlock Scene" : "Lock Scene", icon: scene.locked ? "lock.open" : "lock.fill", key: keys.combo(.lockScene)?.text, shortcut: keys.menuShortcut(.lockScene), disabled: dailiesScene == nil || model.isPictureLocked) { model.lockScene(scene.id, !scene.locked) },
            .item("Open in Dailies", icon: "square.grid.2x2", disabled: dailiesScene == nil) { model.selectedSceneID = scene.id; model.go(.dailies) },
            .item("History of This Scene", icon: "clock.arrow.circlepath", disabled: !model.isEnabled(.changes)) { model.seek(scene.start); model.go(.changes) },
        ]
    }
}

// MARK: Note row

/// Right-click a note row.
struct NoteContextMenu: View {
    var model: FilmModel
    var note: ReviewComment
    var body: some View { NativeMenuItems(entries: Self.entries(model: model, note: note)) }

    @MainActor static func entries(model: FilmModel, note: ReviewComment) -> [GateMenuEntry] {
        let editable = [.draft, .written, .reopened].contains(note.lifecycle) && !note.inInbox
        // A turned-over note belongs to the editor until it's answered; take the turnover back first.
        let droppable = ![.answered, .accepted, .dropped, .turnedOver].contains(note.lifecycle)
        let kinds: [GateMenuEntry] = NoteKind.allCases.map { k in
            .item(k.label, icon: nil, checked: note.kind == k) { model.editNote(note.id, kind: .some(k)) }
        } + [.item("None", icon: nil, checked: note.kind == nil) { model.editNote(note.id, kind: .some(nil)) }]
        let number = note.number.map(String.init) ?? ""
        var out: [GateMenuEntry] = [
            .item("Play from Note", icon: "play.fill", key: "Space", shortcut: .init(.space, modifiers: []), disabled: model.noteTime(note) == nil) { model.select(note); model.togglePlayback() },
        ]
        if editable || note.lifecycle == .turnedOver || note.inInbox {
            out.append(.item("Edit Note", icon: "text.bubble", key: "↩", shortcut: .init(.return, modifiers: []), disabled: !editable) {
                model.select(note); model.draftText = note.text; model.draftKind = note.kind; model.composerFocus += 1
            })
        } else {
            out.append(.item("Reply", icon: "arrowshape.turn.up.left", key: "⌘R", disabled: note.lifecycle != .answered) {
                model.selectedAnswerNoteID = note.id; model.go(.changes)
            })
        }
        out += [
            .item("Change Anchor\u{2026}", icon: "arrow.left.and.line.vertical.and.arrow.right", disabled: true) {},
            .submenu("Kind", icon: "slider.horizontal.3", key: note.kind?.label, disabled: !editable, kinds),
            .separator,
            .item("Copy Timecode", icon: "clock", disabled: model.noteTime(note) == nil) { SystemSupport.copy(model.anchorText(note)) },
            .item(number.isEmpty ? "Copy Link to Note" : "Copy Link to Note \(number)", icon: "link", disabled: note.number == nil) {
                SystemSupport.copy("direction://film/\(model.project?.id ?? "film")/note/\(number)")
            },
            .item("Show in History", icon: "clock.arrow.circlepath", disabled: note.latestAnswer == nil) {
                model.selectedAnswerNoteID = note.id; model.go(.changes)
            },
            .separator,
            .item("Drop Note", icon: "trash", key: "⌫", shortcut: .init(.delete, modifiers: []), destructive: true, disabled: !droppable) { model.dropNote(note.id) },
        ]
        return out
    }
}

// MARK: Picture

/// Right-click the picture in any room with a viewer.
struct PictureContextMenu: View {
    var model: FilmModel
    var body: some View { NativeMenuItems(entries: Self.entries(model: model)) }

    @MainActor static func entries(model: FilmModel) -> [GateMenuEntry] {
        let keys = ShortcutStore.shared
        let take = Self.takeUnderPlayhead(model)
        return [
            .item("Mark This Frame", icon: "mark", key: "N", shortcut: .init("n", modifiers: []), disabled: model.duration <= 0) { model.mark() },
            .item("Draw a Region", icon: "viewfinder", key: "R", shortcut: .init("r", modifiers: []), disabled: model.duration <= 0) {
                model.pause(); model.anchorMode = .region; model.drawingRegion = true
                if model.room != .notes && model.room != .screening { model.go(.notes) }
            },
            .item("Note on the Whole Cut", icon: "text.bubble") { FilmActions(model).startNote(anchor: .wholeCut) },
            .item("Look\u{2026}", icon: "camera.filters", key: "\u{2318}\u{2325}L", shortcut: .init("l", modifiers: [.command, .option]), disabled: model.duration <= 0) { model.openLook() },
            .separator,
            .item("Copy Timecode", icon: "clock", key: keys.combo(.copyTimecode)?.text, shortcut: keys.menuShortcut(.copyTimecode)) { FilmActions(model).copyTimecode() },
            .item("Copy Frame as Image", icon: "film", disabled: model.runtime == nil) { copyFrame(model) },
            .item("Show This Take in Dailies", icon: "square.grid.2x2", disabled: take == nil) {
                model.openTakeID = take; model.selectedSceneID = model.dailies.take(take ?? "").sceneID; model.go(.dailies)
            },
        ]
    }

    /// The take on the bottom video layer under the playhead.
    @MainActor static func takeUnderPlayhead(_ model: FilmModel) -> String? {
        model.sequence?.clips.first { $0.kind == .video && $0.layer == 0 && $0.start.seconds <= model.position && model.position < $0.end.seconds }?.assetID
    }

    /// Renders the frame at the playhead and puts it on the pasteboard as an image.
    @MainActor static func copyFrame(_ model: FilmModel) {
        guard let runtime = model.runtime, let sequence = model.sequence else { return }
        let revision = model.watchedCut.map(model.revision(of:)) ?? model.project?.editRevision ?? 0, at = model.position
        Task {
            do {
                let response = try await runtime.invoke("direction_frame", arguments: .object(["time": .number(at), "revision": .number(Double(revision)), "sequenceID": .string(sequence.id), "maxDimension": .number(1920)]))
                guard let path = response.imagePaths.first, let image = NSImage(contentsOfFile: path) else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image])
                model.toast = Toast(title: "Copied the frame at \(Timecode.format(at, fps: model.fps))")
            } catch { model.error = error.localizedDescription }
        }
    }
}

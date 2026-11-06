import SwiftUI
import AppKit

/// One key combination: a key plus modifiers. Stored as text so it survives in UserDefaults.
struct KeyCombo: Codable, Hashable, Sendable {
    /// A single character ("k", ",", "?") or a named key: return, space, delete, escape, tab, up, down, left, right, home, end.
    var key: String
    var command = false, shift = false, option = false, control = false

    init(_ key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key; self.command = command; self.shift = shift; self.option = option; self.control = control
    }
    static func cmd(_ key: String, shift: Bool = false, option: Bool = false) -> KeyCombo { .init(key, command: true, shift: shift, option: option) }

    var hasModifier: Bool { command || option || control }

    /// Key caps in Mac order: ⌃ ⌥ ⇧ ⌘ then the key. The overlay draws ⌘ first as in the frames.
    var caps: [String] {
        var out: [String] = []
        if control { out.append("⌃") }
        if command { out.append("⌘") }
        if option { out.append("⌥") }
        if shift { out.append("⇧") }
        out.append(Self.symbol(for: key))
        return out
    }
    /// Menu-style text: "⌘⇧P".
    var text: String { caps.joined() }

    static func symbol(for key: String) -> String {
        switch key {
        case "return": "↩"
        case "space": "Space"
        case "delete": "⌫"
        case "escape": "esc"
        case "tab": "⇥"
        case "up": "↑"
        case "down": "↓"
        case "left": "←"
        case "right": "→"
        case "home": "Home"
        case "end": "End"
        default: key.uppercased()
        }
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "return": .return
        case "space": .space
        case "delete": .delete
        case "escape": .escape
        case "tab": .tab
        case "up": .upArrow
        case "down": .downArrow
        case "left": .leftArrow
        case "right": .rightArrow
        case "home": .home
        case "end": .end
        default: key.count == 1 ? KeyEquivalent(Character(key)) : nil
        }
    }
    var modifiers: EventModifiers {
        var m: EventModifiers = []
        if command { m.insert(.command) }; if shift { m.insert(.shift) }; if option { m.insert(.option) }; if control { m.insert(.control) }
        return m
    }
    /// A SwiftUI shortcut for menu items. Only combinations with ⌘, ⌥ or ⌃ go into the menu bar:
    /// single keys stay in the rooms, so typing in a note field is never taken by a menu.
    var menuShortcut: KeyboardShortcut? {
        guard hasModifier, let k = keyEquivalent else { return nil }
        return KeyboardShortcut(k, modifiers: modifiers)
    }

    /// Reads a key press. nil for modifier-only presses.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let named: [UInt16: String] = [36: "return", 76: "return", 49: "space", 51: "delete", 117: "delete", 53: "escape", 48: "tab", 126: "up", 125: "down", 123: "left", 124: "right", 115: "home", 119: "end"]
        if let name = named[event.keyCode] { key = name }
        else if let chars = event.charactersIgnoringModifiers?.lowercased(), let c = chars.first, !chars.isEmpty, !c.isWhitespace { key = String(c) }
        else { return nil }
        command = flags.contains(.command); shift = flags.contains(.shift); option = flags.contains(.option); control = flags.contains(.control)
        if key.count == 1, let c = key.first, !c.isLetter, !c.isNumber { shift = false }
    }
}

enum ShortcutGroup: String, CaseIterable, Identifiable {
    case everywhere, playback, screening, script, dailies, changes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everywhere: "Everywhere"
        case .playback: "Playback"
        case .screening: "Watching and notes"
        case .script: "Script"
        case .dailies: "Dailies"
        case .changes: "Answers"
        }
    }
}

/// Every keyboard shortcut Direction has, with its default. The menu bar, the shortcuts overlay (frame 50)
/// and Settings › Shortcuts (frame 46) all read this, so nothing is written down twice.
enum ShortcutAction: String, CaseIterable, Identifiable {
    // Everywhere
    case rooms, commandMenu, shortcutsList, turnOver, lockScene, share, settings
    // Playback
    case playPause, shuttle, frame, second, scene, rangeInOut, fullScreen
    // Watching and notes
    case mark, startScreening, endScreening, region, kinds, addNote, dropDraft
    // Script
    case editCell, rowNote, moveRow
    // Dailies
    case circle, openTake, nextTake, assemble
    // The editor's answers
    case playChanges, pickOption, acceptAnswer, reply, revert
    // Menu-only commands (not in the overlay)
    case newFilm, openFilm, closeFilm, bringFootage, export, copyTimecode, find, brief, editor, lockPicture, newNote, history, goToTimecode, loop, mute, films, help, previousCut

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rooms: "Script … Finish"
        case .commandMenu: "Command menu"
        case .shortcutsList: "This list"
        case .turnOver: "Turn over"
        case .lockScene: "Lock current scene"
        case .share: "Share"
        case .settings: "Settings"
        case .playPause: "Play or pause"
        case .shuttle: "Back, stop, forward"
        case .frame: "One frame"
        case .second: "One second"
        case .scene: "Previous or next scene"
        case .rangeInOut: "Start and end a stretch"
        case .fullScreen: "Full screen"
        case .mark: "Mark this moment"
        case .startScreening: "Watch through"
        case .endScreening: "Back to notes"
        case .region: "Draw a box"
        case .kinds: "Kind: Feeling … Sound"
        case .addNote: "Add note"
        case .dropDraft: "Drop draft"
        case .editCell: "Edit a cell"
        case .rowNote: "Note on rows or shots"
        case .moveRow: "Move a row"
        case .circle: "Circle take"
        case .openTake: "Open take"
        case .nextTake: "Next take"
        case .assemble: "Assemble from circles"
        case .playChanges: "Play changes"
        case .pickOption: "Use A or B"
        case .acceptAnswer: "Accept answer"
        case .reply: "Reply"
        case .revert: "Revert this change"
        case .newFilm: "New film"
        case .openFilm: "Open a film"
        case .closeFilm: "Close film"
        case .bringFootage: "Bring footage"
        case .export: "Export"
        case .copyTimecode: "Copy time"
        case .find: "Find"
        case .brief: "Brief"
        case .editor: "Editor"
        case .lockPicture: "Lock picture"
        case .newNote: "New note"
        case .history: "History"
        case .goToTimecode: "Go to a time"
        case .loop: "Loop playback"
        case .mute: "Mute"
        case .films: "Films"
        case .help: "Keyboard shortcuts"
        case .previousCut: "Compare with previous cut"
        }
    }

    /// nil for menu-only commands, which don't appear in the overlay.
    var group: ShortcutGroup? {
        switch self {
        case .rooms, .commandMenu, .shortcutsList, .turnOver, .lockScene, .share, .settings: .everywhere
        case .playPause, .shuttle, .frame, .second, .scene, .rangeInOut, .fullScreen: .playback
        case .mark, .startScreening, .endScreening, .region, .kinds, .addNote, .dropDraft: .screening
        case .editCell, .rowNote, .moveRow: .script
        case .circle, .openTake, .nextTake, .assemble: .dailies
        case .playChanges, .pickOption, .acceptAnswer, .reply, .revert: .changes
        default: nil
        }
    }

    /// The rooms where the key works. Keys can repeat across rooms but not within one.
    var rooms: Set<Room> {
        let pictureRooms: Set<Room> = [.cut, .finish]
        switch self {
        case .turnOver: return [.cut]
        case .assemble, .circle, .openTake, .nextTake: return [.dailies]
        case .editCell, .moveRow: return [.script]
        case .rowNote: return [.script, .breakdown]
        case .playChanges, .pickOption, .acceptAnswer, .reply, .revert: return [.cut]
        case .mark, .region, .kinds, .addNote, .dropDraft, .endScreening: return [.cut]
        case .playPause, .shuttle, .frame, .second, .scene, .rangeInOut: return pictureRooms
        default: return Set(Room.allCases)
        }
    }

    /// The default keys. Rows drawn as ranges ("⌘ 1–5") are fixed and can't be recorded.
    var defaultCombo: KeyCombo? {
        switch self {
        case .commandMenu: .cmd("k")
        case .shortcutsList: .init("?")
        case .turnOver, .assemble: .cmd("return")
        case .lockScene: .cmd("l")
        case .share: .cmd("s", shift: true)
        case .settings: .cmd(",")
        case .playPause: .init("space")
        case .fullScreen: .init("f", command: true, control: true)
        case .mark: .init("n")
        case .startScreening: .cmd("return", shift: true)
        case .endScreening: .init("escape")
        case .region: .init("r")
        case .addNote: .init("return")
        case .dropDraft: .init("delete")
        case .editCell: .init("return")
        case .rowNote: .init("n")
        case .circle: .init("c")
        case .openTake: .init("space")
        case .nextTake: .init("right")
        case .playChanges: .cmd("p", shift: true)
        case .acceptAnswer: .init("y")
        case .reply: .cmd("r")
        case .revert: .cmd("delete")
        case .newFilm: .cmd("n")
        case .openFilm: .cmd("o")
        case .closeFilm: .cmd("w")
        case .bringFootage: .cmd("i")
        case .export: .cmd("e")
        case .copyTimecode: .cmd("c", shift: true)
        case .find: .cmd("f")
        case .brief: .cmd("b")
        case .editor: .cmd("e", shift: true)
        case .lockPicture: .cmd("l", shift: true)
        case .newNote: .cmd("n", option: true)
        case .history: .cmd("y")
        case .goToTimecode: .init("g", control: true)
        case .loop: .init("l", option: true)
        case .mute: .init("m", option: true)
        case .films: .cmd("0", shift: true)
        case .help: .cmd("/")
        case .previousCut: .cmd("left", option: true)
        default: nil
        }
    }

    /// Caps for rows that show more than one key or a range.
    var fixedCaps: [String]? {
        switch self {
        case .rooms: ["⌘", "1–5"]
        case .shuttle: ["J", "K", "L"]
        case .frame: ["←", "→"]
        case .second: ["⇧", "← →"]
        case .scene: ["↑", "↓"]
        case .rangeInOut: ["I", "O"]
        case .kinds: ["⌥", "1–5"]
        case .moveRow: ["⌥", "↑ ↓"]
        case .pickOption: ["A", "B"]
        case .fullScreen: ["⌃", "⌘", "F"]
        default: nil
        }
    }

    /// Shortcuts with a single combination the director can record. Settings and full screen belong to macOS.
    var isCustomizable: Bool { defaultCombo != nil && fixedCaps == nil && ![.settings, .fullScreen, .endScreening, .addNote, .help].contains(self) }

    static var overlayActions: [ShortcutAction] { allCases.filter { $0.group != nil } }
}

/// The current shortcuts: defaults plus what the director recorded in Settings › Shortcuts.
@MainActor @Observable
final class ShortcutStore {
    static let shared = ShortcutStore()
    static let defaultsKey = "shortcutOverrides"
    /// Recorded keys by action ID. A present key with a nil value means "cleared".
    private(set) var overrides: [String: KeyCombo?] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey), let stored = try? JSONDecoder().decode([String: Stored].self, from: data) {
            overrides = stored.mapValues { $0.combo }
        }
    }
    private struct Stored: Codable { var combo: KeyCombo? }

    func combo(_ action: ShortcutAction) -> KeyCombo? {
        if let o = overrides[action.rawValue] { return o }
        return action.defaultCombo
    }
    func isEdited(_ action: ShortcutAction) -> Bool { overrides[action.rawValue] != nil && combo(action) != action.defaultCombo }
    func caps(_ action: ShortcutAction) -> [String] { action.fixedCaps ?? combo(action)?.caps ?? [] }
    func menuShortcut(_ action: ShortcutAction) -> KeyboardShortcut? { combo(action)?.menuShortcut }

    /// Another action in an overlapping room that already uses these keys.
    func conflict(for action: ShortcutAction, with combo: KeyCombo) -> ShortcutAction? {
        ShortcutAction.allCases.first { other in
            other != action && other.fixedCaps == nil && self.combo(other) == combo && !other.rooms.isDisjoint(with: action.rooms)
        }
    }
    /// The same keys in a different room: allowed, and worth a note.
    func sharedAcrossRooms(_ action: ShortcutAction) -> ShortcutAction? {
        guard let mine = combo(action) else { return nil }
        return ShortcutAction.allCases.first { other in other != action && other.fixedCaps == nil && combo(other) == mine && other.rooms.isDisjoint(with: action.rooms) }
    }

    func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        if combo == action.defaultCombo { overrides.removeValue(forKey: action.rawValue) } else { overrides[action.rawValue] = .some(combo) }
        save()
    }
    /// Records the keys and clears them from the action that had them.
    func replace(_ combo: KeyCombo, for action: ShortcutAction, taking other: ShortcutAction) {
        overrides[other.rawValue] = .some(nil)
        set(combo, for: action)
    }
    func restoreDefaults() { overrides = [:]; save() }

    private func save() {
        let stored = overrides.mapValues { Stored(combo: $0) }
        if stored.isEmpty { defaults.removeObject(forKey: Self.defaultsKey) }
        else if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

extension View {
    /// Attaches the registry's menu shortcut for an action, if it has one with a modifier.
    func shortcut(_ action: ShortcutAction, _ store: ShortcutStore = .shared) -> some View {
        keyboardShortcut(store.menuShortcut(action))
    }
}

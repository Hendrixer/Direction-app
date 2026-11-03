import SwiftUI
import AppKit
import DirectionCore

enum CommandSection: Int, CaseIterable, Identifiable {
    case recent, suggested, actions, notes, scenes, takes, cuts, settings, help
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .recent: "Recent"
        case .suggested: "Suggested"
        case .actions: "Actions"
        case .notes: "Notes"
        case .scenes: "Scenes"
        case .takes: "Takes"
        case .cuts: "Cuts"
        case .settings: "Settings"
        case .help: "Help"
        }
    }
}

/// One row in the command menu.
struct CommandItem: Identifiable {
    enum Trailing { case none, keys([String]), caption(String) }
    var id: String
    var section: CommandSection
    var icon: String
    var title: String
    /// Quieter text after the title: "3 The ridge", "· locked since Cut 3".
    var sub: String? = nil
    /// An amber note number before the title.
    var number: String? = nil
    var trailing: Trailing = .none
    var synonyms: [String] = []
    /// Shown as the caption, and the row can't run. Disabled rows are never hidden.
    var disabledReason: String? = nil
    /// ⌘↩ runs it and keeps the menu open.
    var keepsOpen = false
    var run: @MainActor () -> Void

    var searchText: String { sub.map { "\(title) \($0)" } ?? title }
}

/// Short answers for Help rows.
enum CommandHelp {
    static let topics: [(String, String, [String])] = [
        ("What does locking a scene do?", "It keeps the scene\u{2019}s cut: the editor can\u{2019}t recut it, and a note that would need it comes back as \u{201C}can\u{2019}t\u{201D} with an Unlock button. Its color and sound stay open, as after picture lock. Lock the scene under the playhead with \u{2318}L.", ["lock", "scene"]),
        ("How do turnovers work?", "Write your notes, then Turn over (\u{2318}\u{21A9}) hands the whole sheet to the editor at once. It reads them back in plain terms, waits for your OK if you asked it to, then cuts the next version.", ["turn over", "notes", "send"]),
        ("What is a read-back?", "The editor\u{2019}s plan for each note, with concrete numbers, before it cuts. You approve it or correct a line.", ["plan", "readback"]),
        ("How much freedom should the editor have?", "Do what I wrote changes only what each note names. Read between the lines interprets intent and cuts Feeling notes two ways. Take a pass may also suggest changes you didn\u{2019}t ask for, marked Unasked.", ["latitude", "freedom"]),
        ("How do I connect an editor?", "Your editor is an agent like Claude Code or Codex. Add Direction to it as an MCP server (Help \u{203A} Connect an Editor\u{2026}), then ask it to open your film.", ["agent", "claude", "codex", "mcp"]),
        ("Why does a take say it\u{2019}s missing?", "Footage is linked, not copied. When a drive is unplugged or files move, those takes go offline. File \u{203A} Find Missing Footage\u{2026} relinks them; notes, circles and cuts are kept.", ["offline", "relink", "drive"]),
        ("What are outside notes?", "Notes from people you share a cut with. They wait in Notes \u{203A} Outside until you accept, edit or decline them. The editor never sees them before you accept.", ["producer", "client", "share"]),
        ("How do I share a cut?", "Screening links aren\u{2019}t available yet. Export a screening copy from the Share sheet (\u{21E7}\u{2318}S) and send it any way you like.", ["link", "export", "send"]),
    ]
}

/// Where Settings rows live, for the command menu's Settings section.
enum SettingsIndex {
    static let rows: [(SettingsTab, String)] = [
        (.general, "When Direction opens"), (.general, "Show Films when no film is open"), (.general, "Start screenings full screen"),
        (.general, "Hide controls in Screening after"), (.general, "Audio output"), (.general, "Film grain"), (.general, "Reduce motion"),
        (.editor, "Wait for my OK before cutting"), (.editor, "Cut Feeling notes two ways"), (.editor, "Ask before guessing"), (.editor, "Follow the brief"),
        (.cutting, "Handles in Play changes"), (.cutting, "Frame rate for new films"), (.cutting, "Loudness target"),
        (.engines, "Recommended"), (.engines, "Editor runs on"), (.engines, "Version and effort"), (.engines, "Start work"), (.engines, "Let the editor run scripts"),
        (.engines, "Transcribe with"), (.engines, "Whisper version"), (.engines, "Look with"), (.engines, "Detail"), (.engines, "Look at new footage automatically"),
        (.engines, "OpenRouter"), (.engines, "Ask before spending more than"), (.engines, "Stop for the month at"),
        (.cutting, "Music under dialogue"), (.cutting, "Transitions"),
        (.cutting, "Looks folder"), (.cutting, "Convert log footage automatically"),
        (.notifications, "A cut is ready"), (.notifications, "The editor has a question"), (.notifications, "The editor can\u{2019}t do a note"),
        (.notifications, "An outside note arrives"), (.notifications, "A delivery finishes"), (.notifications, "Hold notifications during a screening"), (.notifications, "Sound"),
        (.storage, "Location"), (.storage, "When you bring footage"), (.storage, "Render cache"),
        (.sharing, "Viewers can leave notes"), (.sharing, "Links expire"), (.sharing, "Show who wrote each note to the editor"),
    ]
}

/// Everything the command menu can run, built from the open film. Every menu bar command is here.
@MainActor
struct CommandCatalog {
    let model: FilmModel
    let app: AppModel?
    let openSettings: (SettingsTab, String?) -> Void
    let showHelp: (String, String) -> Void
    private var keys: ShortcutStore { .shared }
    private var actions: FilmActions { FilmActions(model) }

    func items() -> [CommandItem] { actionItems() + noteItems() + sceneItems() + takeItems() + cutItems() + settingsItems() + helpItems() }

    private func caps(_ a: ShortcutAction) -> CommandItem.Trailing { let c = keys.caps(a); return c.isEmpty ? .none : .keys(c) }

    // MARK: Actions

    func actionItems() -> [CommandItem] {
        let m = model
        var out: [CommandItem] = []
        func add(_ id: String, _ icon: String, _ title: String, sub: String? = nil, _ trailing: CommandItem.Trailing = .none, synonyms: [String] = [], disabled: String? = nil, keepsOpen: Bool = false, _ run: @escaping @MainActor () -> Void) {
            out.append(CommandItem(id: "action." + id, section: .actions, icon: icon, title: title, sub: sub, trailing: trailing, synonyms: synonyms, disabledReason: disabled, keepsOpen: keepsOpen, run: run))
        }
        // Rooms
        for (i, room) in Room.allCases.enumerated() {
            let reason: String? = m.isEnabled(room) ? nil : room == .finish ? "Lock picture first" : "Nothing to watch yet"
            add("room." + room.rawValue, roomIcon(room), "Go to \(room.title)", .keys(["⌘", "\(i + 1)"]), synonyms: ["room", "open"], disabled: reason) { m.go(room) }
        }
        // Notes and the editor
        let turnReason: String? = m.openTurnover != nil ? "The editor is still on turnover \(m.openTurnover!.number)" : m.readyNotes.isEmpty ? "No written notes yet" : nil
        add("turnOver", "arrow.right", "Turn over\u{2026}", sub: m.readyNotes.isEmpty ? nil : "\(m.readyNotes.count) notes", caps(.turnOver), synonyms: ["send", "editor", "hand"], disabled: turnReason) { m.go(.notes); m.sheet = .turnover }
        add("newNote", "text.bubble", "New note", caps(.newNote), synonyms: ["write", "add note"]) { actions.startNote() }
        add("wholeCut", "text.bubble", "Note on the whole cut", synonyms: ["write"]) { actions.startNote(anchor: .wholeCut) }
        add("mark", "mappin", "Mark this moment", caps(.mark), synonyms: ["pin", "marker"], disabled: m.duration > 0 ? nil : "Nothing to watch yet", keepsOpen: true) { m.mark() }
        add("screening", "play.rectangle", "Start screening", caps(.startScreening), synonyms: ["watch", "play"], disabled: m.isEnabled(.screening) ? nil : "Nothing to watch yet") { m.go(.screening) }
        if let s = actions.currentScene {
            add("lockScene", s.locked ? "lock.open" : "lock.fill", s.locked ? "Unlock scene" : "Lock scene", sub: s.label, caps(.lockScene), synonyms: ["freeze"], disabled: m.isPictureLocked ? "Picture is locked" : nil) { actions.toggleCurrentSceneLock() }
        } else {
            add("lockScene", "lock.fill", "Lock scene", caps(.lockScene), disabled: actions.lockSceneUnavailableReason) {}
        }
        for s in m.scenes where s.locked && s.id != actions.currentScene?.id {
            add("unlock." + s.id, "lock.open", "Unlock scene", sub: s.label, disabled: m.isPictureLocked ? "Picture is locked" : nil) { m.lockScene(s.id, false) }
        }
        if m.isPictureLocked { add("unlockPicture", "lock.open", "Unlock picture\u{2026}") { actions.confirmUnlockPicture() } }
        else { add("lockPicture", "lock.fill", "Lock picture\u{2026}", caps(.lockPicture), synonyms: ["finish", "final"], disabled: actions.lockPictureUnavailableReason) { m.sheet = .lockPicture } }
        add("playChanges", "play.fill", "Play changes", caps(.playChanges), synonyms: ["review", "watch changes"], disabled: m.changeReel(in: m.watchedCut).isEmpty ? "No changes in this cut" : nil) { m.go(.changes); m.playChanges() }
        let answer = m.selectedAnswerNoteID.flatMap(m.note)
        add("accept", "checkmark", "Accept answer", sub: answer?.number.map { "note \($0)" }, caps(.acceptAnswer), disabled: answer == nil || m.room != .changes ? "Select an answer in Changes" : nil) { if let id = answer?.id { m.acceptAnswer(id) } }
        add("assemble", "square.grid.2x2", "Assemble from circles", m.room == .dailies ? caps(.assemble) : .none, synonyms: ["assembly", "first cut"], disabled: m.circledCount == 0 ? "Circle takes first" : m.openTurnover != nil ? "The editor is busy" : !m.cuts.isEmpty ? "The assembly exists" : nil) { m.assembleFromCircles() }
        add("brief", "doc.plaintext", "Brief\u{2026}", caps(.brief), synonyms: ["logline", "intent"]) { m.sheet = .brief }
        add("editor", "diamond", "Editor\u{2026}", caps(.editor), synonyms: ["status", "agent"]) { m.showEditorPopover = true }
        add("pause", m.directing.editorPaused ? "play.fill" : "pause.fill", m.directing.editorPaused ? "Resume editor" : "Pause editor") { m.setEditorPaused(!m.directing.editorPaused) }
        for l in Latitude.allCases {
            add("latitude." + l.rawValue, "slider.horizontal.3", "Freedom: \(l.label)", m.directing.latitude == l ? .caption("Current") : .none, synonyms: ["latitude", "freedom"]) { LatitudeSetting.set(l, film: m) }
        }
        add("copyRequest", "doc.on.doc", "Copy request for your editor", synonyms: ["claude", "codex", "agent", "wake"], disabled: m.url == nil && !m.isPreview ? "Open a saved film first" : nil) { m.copyEditorRequest() }
        add("connect", "diamond", "Connect an editor\u{2026}", synonyms: ["mcp", "claude", "codex", "agent", "setup"]) { EditorConnection.presentAlert() }
        // Sharing and files
        add("share", "square.and.arrow.up", "Share \(m.watchedCut?.name ?? "cut")\u{2026}", caps(.share), synonyms: ["link", "send", "export"], disabled: m.cuts.isEmpty ? "No cut yet" : nil) { m.sheet = .share }
        add("export", "square.and.arrow.up.on.square", "Export\u{2026}", caps(.export), synonyms: ["deliver", "render"], disabled: m.isPictureLocked ? nil : m.cuts.isEmpty ? "No cut yet" : nil) { if m.isPictureLocked { m.sheet = .deliver } else { m.sheet = .share } }
        add("footage", "square.and.arrow.down", "Bring footage\u{2026}", caps(.bringFootage), synonyms: ["import", "media"]) { m.chooseFootage() }
        add("bringScript", "doc.text", m.script == nil ? "Bring in a script\u{2026}" : "Bring in a new draft\u{2026}", synonyms: ["script", "screenplay", "fountain", "draft"]) { m.chooseScript() }
        if m.script == nil { add("bringStory", "text.book.closed", "Bring in a story\u{2026}", synonyms: ["story", "treatment", "outline", "beats"]) { m.chooseScript(.story) } }
        else { add("readAgain", m.scriptKind == .story ? "doc.text" : "text.book.closed", m.scriptKind == .story ? "Read as a script\u{2026}" : "Read as a story\u{2026}", synonyms: ["story", "script", "treatment", "wrong", "kind"]) { m.readAgain(as: m.scriptKind == .story ? .script : .story) } }
        if m.breakdown?.isOK == true { add("printShootList", "printer", "Print shoot list\u{2026}", synonyms: ["shot list", "call sheet", "setups"]) { m.printShootList() } }
        let missing = m.isPreview ? MissingFootage.previewAssets(m).count : MenuState.shared.missingCount
        add("relink", "externaldrive", "Find missing footage\u{2026}", synonyms: ["relink", "offline", "drive"], disabled: missing == 0 ? "No footage is missing" : nil) { m.sheet = .relink }
        add("reveal", "folder", "Show film in Finder", synonyms: ["library", "reveal"]) { actions.revealInFinder() }
        // Playback
        add("play", m.playing ? "pause.fill" : "play.fill", m.playing ? "Pause" : "Play", caps(.playPause), keepsOpen: true) { m.togglePlayback() }
        let noPicture: String? = m.duration > 0 ? nil : "Nothing to watch yet"
        add("back", "backward.fill", "Play backward", .keys(["J"]), disabled: noPicture, keepsOpen: true) { m.shuttle(-1) }
        add("stop", "stop.fill", "Stop", .keys(["K"]), disabled: noPicture, keepsOpen: true) { m.shuttle(0) }
        add("forward", "forward.fill", "Play forward", .keys(["L"]), disabled: noPicture, keepsOpen: true) { m.shuttle(1) }
        add("prevFrame", "chevron.left", "Previous frame", .keys(["←"]), disabled: noPicture, keepsOpen: true) { m.step(frames: -1) }
        add("nextFrame", "chevron.right", "Next frame", .keys(["→"]), disabled: noPicture, keepsOpen: true) { m.step(frames: 1) }
        add("backSecond", "gobackward", "Back one second", .keys(["⇧", "←"]), disabled: noPicture, keepsOpen: true) { m.pause(); m.seek(m.position - 1) }
        add("forwardSecond", "goforward", "Forward one second", .keys(["⇧", "→"]), disabled: noPicture, keepsOpen: true) { m.pause(); m.seek(m.position + 1) }
        add("history", "clock.arrow.circlepath", "History", caps(.history), synonyms: ["changelog", "cuts"], disabled: m.isEnabled(.changes) ? nil : "No cuts yet") { m.go(.changes) }
        add("prevScene", "chevron.up", "Previous scene", .keys(["↑"]), keepsOpen: true) { actions.jumpScene(-1) }
        add("nextScene", "chevron.down", "Next scene", .keys(["↓"]), keepsOpen: true) { actions.jumpScene(1) }
        add("start", "backward.end", "Go to start", .keys(["Home"]), keepsOpen: true) { m.pause(); m.seek(0) }
        add("end", "forward.end", "Go to end", .keys(["End"]), keepsOpen: true) { m.pause(); m.seek(max(0, m.duration - 1 / m.fps)) }
        add("timecode", "clock", "Go to timecode\u{2026}", caps(.goToTimecode)) { actions.askForTimecode() }
        add("copyTimecode", "clock", "Copy timecode", sub: actions.timecode, caps(.copyTimecode)) { actions.copyTimecode() }
        add("rangeIn", "arrow.left.and.line.vertical.and.arrow.right", "Set range in", .keys(["I"]), keepsOpen: true) { actions.setRangeIn() }
        add("rangeOut", "arrow.left.and.line.vertical.and.arrow.right", "Set range out", .keys(["O"]), keepsOpen: true) { actions.setRangeOut() }
        add("clearRange", "xmark", "Clear range", caps(.clearRange), disabled: m.rangeSelection == nil ? "No range set" : nil) { actions.clearRange() }
        add("mute", m.player.isMuted ? "speaker.wave.2" : "speaker.slash", m.player.isMuted ? "Unmute" : "Mute", caps(.mute), keepsOpen: true) { m.player.isMuted.toggle() }
        // App
        if let app {
            add("newFilm", "plus", "New film\u{2026}", caps(.newFilm)) { app.newFilm() }
            add("openFilm", "folder", "Open a film\u{2026}", caps(.openFilm)) { app.chooseFilm() }
            add("films", "film", "Films", caps(.films), synonyms: ["projects", "library", "close"]) { app.closeFilm() }
        }
        add("shortcuts", "keyboard", "Keyboard shortcuts", .keys(["?"]), synonyms: ["keys", "help"]) { m.showShortcuts = true }
        add("settings", "gearshape", "Settings\u{2026}", .keys(["⌘", ","]), synonyms: ["preferences"]) { openSettings(.general, nil) }
        add("fullScreen", "arrow.up.left.and.arrow.down.right", "Enter full screen", caps(.fullScreen)) { NSApp.keyWindow?.toggleFullScreen(nil) }
        return out
    }

    private func roomIcon(_ room: Room) -> String {
        switch room {
        case .dailies: "square.grid.2x2"
        case .script: "doc.text"
        case .breakdown: "list.bullet.rectangle"
        case .screening: "play.rectangle"
        case .notes: "text.bubble"
        case .changes: "arrow.triangle.2.circlepath"
        case .finish: "checkmark.seal"
        }
    }

    // MARK: Film content

    func noteItems() -> [CommandItem] {
        model.notes.filter { !$0.text.isEmpty && $0.lifecycle != .dropped && !$0.inInbox }.sorted { ($0.number ?? .max) < ($1.number ?? .max) }.map { c in
            CommandItem(id: "note." + c.id, section: .notes, icon: "text.bubble", title: c.text, number: c.number.map(String.init), trailing: .caption(model.anchorText(c)), synonyms: [c.kind?.label ?? "", c.person?.name ?? ""]) {
                model.notesTab = .sheet; model.go(.notes); model.select(c)
            }
        }
    }

    func sceneItems() -> [CommandItem] {
        let strip = model.stripScenes
        return model.scenes.map { s in
            let start = strip.first { $0.id == s.id }?.start
            return CommandItem(id: "scene." + s.id, section: .scenes, icon: "film", title: s.label, sub: s.locked ? "· locked\(lockedSince(s).map { " since \($0)" } ?? "")" : nil,
                               trailing: start.map { .caption(Timecode.format($0, fps: model.fps)) } ?? .none, synonyms: s.setups.map(\.description)) {
                if let start { model.pause(); model.seek(start) } else { model.selectedSceneID = s.id; model.go(.dailies) }
            }
        }
    }

    private func lockedSince(_ s: DailiesScene) -> String? {
        guard let at = s.lockedAt else { return model.isPreview ? "Cut 3" : nil }
        return model.cuts.last { $0.createdAt <= at }?.name
    }

    func takeItems() -> [CommandItem] {
        model.dailies.takes.values.compactMap { t -> CommandItem? in
            guard let code = t.code else { return nil }
            let label = [t.setupCode, code].compactMap { $0 }.joined(separator: " ")
            let note = t.circled ? "circled" : t.suggestion.map { "suggested: " + Self.short($0) } ?? t.caption.map(Self.short)
            return CommandItem(id: "take." + t.assetID, section: .takes, icon: t.circled ? "circle" : "square.grid.2x2", title: label, sub: note.map { "· " + $0 }, synonyms: [t.caption ?? ""]) {
                model.openTakeID = t.assetID; model.selectedSceneID = t.sceneID; model.go(.dailies)
            }
        }.sorted { $0.title < $1.title }
    }

    /// The first clause of the editor's reason, lowercased: "warmest read".
    static func short(_ text: String) -> String {
        let first = text.split(whereSeparator: { ".;,".contains($0) }).first.map(String.init) ?? text
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.prefix(1).lowercased() + trimmed.dropFirst()
    }

    func cutItems() -> [CommandItem] {
        model.cuts.reversed().map { cut in
            let date = Date(timeIntervalSince1970: cut.createdAt).formatted(.dateTime.month(.abbreviated).day())
            return CommandItem(id: "cut." + cut.id, section: .cuts, icon: "film", title: cut.name, sub: "· \(date)", trailing: cut.id == model.watchedCut?.id ? .caption("Watching") : .none) { model.watch(cut) }
        }
    }

    func settingsItems() -> [CommandItem] {
        SettingsIndex.rows.map { tab, label in
            CommandItem(id: "settings.\(tab.rawValue).\(label)", section: .settings, icon: "gearshape", title: "\(tab.title) \u{203A} \(label)") { openSettings(tab, label) }
        }
    }

    func helpItems() -> [CommandItem] {
        CommandHelp.topics.map { q, a, syn in
            CommandItem(id: "help." + q, section: .help, icon: "questionmark.circle", title: q, synonyms: syn, keepsOpen: true) { showHelp(q, a) }
        }
    }

    /// What the room suggests with an empty query.
    func suggestedIDs() -> [String] {
        switch model.room {
        case .notes: ["action.turnOver", "action.screening", "action.share"]
        case .dailies: ["action.assemble", "action.footage", "action.screening"]
        case .script: ["action.bringScript", "action.room.breakdown", "action.brief"]
        case .breakdown: ["action.footage", "action.printShootList", "action.room.dailies"]
        case .screening: ["action.mark", "action.wholeCut", "action.room.notes"]
        case .changes: ["action.playChanges", "action.accept", "action.share"]
        case .finish: ["action.export", "action.share", "action.unlockPicture"]
        }
    }
}

/// Fuzzy, prefix-weighted matching. Returns a score (higher is better) and the matched character offsets.
enum CommandMatcher {
    static func match(_ query: String, in text: String, synonyms: [String] = []) -> (score: Int, hits: Set<Int>)? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return (0, []) }
        let t = Array(text.lowercased()), qs = Array(q)
        // Contiguous match: best at the start of a word.
        if let r = text.lowercased().range(of: q) {
            let start = text.lowercased().distance(from: text.lowercased().startIndex, to: r.lowerBound)
            let atWord = start == 0 || !(t[start - 1].isLetter || t[start - 1].isNumber)
            return ((start == 0 ? 1000 : atWord ? 800 : 500) - start, Set(start..<(start + qs.count)))
        }
        // Subsequence: every query character in order.
        var hits: Set<Int> = [], i = 0, gaps = 0, last = -1
        for (j, c) in t.enumerated() where i < qs.count && c == qs[i] {
            hits.insert(j); if last >= 0 { gaps += j - last - 1 }; last = j; i += 1
        }
        if i == qs.count && gaps < 12 { return (300 - gaps * 10, hits) }
        if synonyms.contains(where: { $0.lowercased().contains(q) || q.contains($0.lowercased()) && !$0.isEmpty }) { return (200, []) }
        return nil
    }
}

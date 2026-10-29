import SwiftUI
import AppKit
import DirectionCore

// Owner: Notes agent. Frames 17–28.
// Notes is the notes session: the picture on the left, the 380 pt sheet on the right.
// After a turnover the sheet holds the read-back; while the editor cuts it becomes
// "Cut 4 in progress" (cutting is a state of this room, not a room).

struct NotesRoom: View {
    @Bindable var model: FilmModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            FilmStage(model: model, marks: stageMarks, showsMarkButton: !model.showsCuttingPanel) { size in
                RegionLayer(model: model, size: size)
            }
            side
                .padding(.leading, 1)
                .frame(width: Gate.Size.notesSheet)
                .frame(maxHeight: .infinity)
                .background(Gate.Surface.ground)
                .hairlineBorder(.leading)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: key)
        .onAppear { focused = true }
        .onChange(of: model.sheet) { _, sheet in if sheet == nil { focused = true } }
        .onChange(of: model.notesTurnover?.state) { _, state in if state == nil { model.notesUI.cuttingSide = .progress } }
    }

    @ViewBuilder private var side: some View {
        if model.showsCuttingPanel, let t = model.notesTurnover {
            CuttingPanel(model: model, turnover: t)
        } else {
            NotesSheet(model: model, onLeave: { focused = true })
        }
    }

    /// Director pins and ranges; in the Outside tab, outside people's marks in steel too.
    private var stageMarks: [StripMark] {
        guard model.notesTab == .outside else { return model.noteMarks }
        return model.noteMarks + model.inbox.compactMap { c in
            (model.noteTime(c) ?? model.anchorScene(c)?.start).map { StripMark(id: c.id, time: $0, kind: .outside) }
        }
    }

    // MARK: Keys
    // Room keys never fire while a text field has focus: the field keeps its keystrokes.

    private func key(_ press: KeyPress) -> KeyPress.Result {
        guard model.sheet == nil, !model.showCommandMenu, !model.showShortcuts else { return .ignored }
        let mods = press.modifiers.subtracting([.capsLock, .numericPad])
        if mods == .option, let digit = Self.optionDigit(press) {
            model.setKind(NoteKind.allCases[digit - 1], composer: false)
            return .handled
        }
        guard mods.isEmpty || mods == .shift else { return .ignored }
        let shift = mods == .shift
        let regionKeys = model.anchorMode == .region && model.region != nil
        switch press.key {
        case .upArrow, .downArrow:
            let step = press.key == .upArrow ? -1 : 1
            if regionKeys { model.nudgeRegion(dx: 0, dy: CGFloat(step) * (shift ? 0.1 : 0.01)) }
            else if model.notesTab == .outside { selectOutside(step) }
            else if let q = waitingQuestion { model.moveChoice(q, step) }
            else { model.selectAdjacentNote(step) }
            return .handled
        case .leftArrow:
            if regionKeys { model.nudgeRegion(dx: shift ? -0.1 : -0.01, dy: 0) } else { model.step(frames: shift ? -model.fps : -1) }
            return .handled
        case .rightArrow:
            if regionKeys { model.nudgeRegion(dx: shift ? 0.1 : 0.01, dy: 0) } else { model.step(frames: shift ? model.fps : 1) }
            return .handled
        case .space:
            model.togglePlayback()
            return .handled
        case .delete, .deleteForward:
            return delete()
        case .return:
            return enter()
        case .escape:
            return escape()
        default:
            break
        }
        let typed = press.characters
        switch typed.lowercased() {
        case "n":
            model.mark()
            if let id = model.freshMarkID, let c = model.note(id) { model.notesTab = .sheet; model.showNote(c) }
            return .handled
        case "r" where model.notesTab == .sheet && composerShown:
            model.beginRegion()
            return .handled
        default:
            break
        }
        // With a draft selected, typing starts writing it; other single keys are the room's.
        if model.notesTab == .sheet, composerShown, model.selectedNote?.lifecycle == .draft, Self.printable(typed) {
            model.draftText += typed
            model.composerFocus += 1
            return .handled
        }
        switch typed.lowercased() {
        case "i" where composerShown: setRange(in: true); return .handled
        case "o" where composerShown: setRange(in: false); return .handled
        case "e" where model.notesTab == .outside:
            if let c = selectedOutside { model.editOutsideFirst(c) }
            return .handled
        case "j": model.shuttle(-1); return .handled
        case "k": model.shuttle(0); return .handled
        case "l": model.shuttle(1); return .handled
        default:
            if model.notesTab == .sheet, composerShown, model.selectedNote == nil, Self.printable(typed) {
                model.draftText += typed
                model.composerFocus += 1
                return .handled
            }
            return .ignored
        }
    }

    /// The sheet shows its composer: no turnover open, or you're writing notes for the next one.
    private var composerShown: Bool { model.notesTurnover == nil || model.notesUI.cuttingSide == .notes }
    private var selectedOutside: ReviewComment? { model.inbox.first { $0.id == model.notesUI.selectedOutsideID } }
    /// The question the keyboard answers: the oldest in the Questions tab, the newest in the progress panel.
    private var waitingQuestion: EditorQuestion? {
        if model.notesTab == .questions { return model.openQuestions.first }
        return model.showsCuttingPanel ? model.openQuestions.max { $0.createdAt < $1.createdAt } : nil
    }
    private func selectOutside(_ step: Int) {
        let list = model.inbox
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == model.notesUI.selectedOutsideID }.map { $0 + step } ?? (step > 0 ? 0 : list.count - 1)
        let c = list[max(0, min(list.count - 1, index))]
        model.notesUI.selectedOutsideID = c.id
        if let t = model.noteTime(c) ?? model.anchorScene(c)?.start { model.pause(); model.seek(t) }
    }

    private func delete() -> KeyPress.Result {
        if model.anchorMode == .region, model.region != nil { model.cancelRegion(); return .handled }
        if model.notesTab == .outside, let c = selectedOutside {
            model.declineOutside(c.id)
            model.toast = Toast(title: "Declined \(c.person?.name ?? "their")\u{2019}s note")
            return .handled
        }
        if model.notesTab == .sheet, let c = model.selectedNote, model.isBeforeTurnover(c) {
            model.dropFromSheet(c)
            return .handled
        }
        return .ignored
    }

    private func enter() -> KeyPress.Result {
        if model.notesTab == .outside, let c = selectedOutside { model.acceptOutside(c.id); return .handled }
        if let q = waitingQuestion, model.notesUI.choices[q.id] != nil { model.answerOrConfirm(q); return .handled }
        guard model.notesTab == .sheet, composerShown, let c = model.selectedNote else { return .ignored }
        if c.lifecycle == .draft { model.composerFocus += 1 } else { model.editInComposer(c) }
        return .handled
    }

    private func escape() -> KeyPress.Result {
        let ui = model.notesUI
        if model.drawingRegion || model.anchorMode == .region { model.cancelRegion(); return .handled }
        if ui.correctingNoteID != nil { ui.correctingNoteID = nil; ui.correction = ""; return .handled }
        if ui.editingNoteID != nil || ui.editingOutsideID != nil || !model.draftText.isEmpty { model.cancelComposer(); return .handled }
        if model.notesTab != .sheet { model.notesTab = .sheet; return .handled }
        return .ignored
    }

    /// I / O: range in and out at the playhead.
    private func setRange(in isIn: Bool) {
        let t = model.position
        let current = model.rangeSelection ?? t...min(model.duration, t + 2)
        model.rangeSelection = isIn ? t...max(t, current.upperBound) : min(t, current.lowerBound)...t
        model.anchorMode = .range
    }

    private static func printable(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }
    }
    /// ⌥1…⌥5, whatever the keyboard layout types for them.
    private static func optionDigit(_ press: KeyPress) -> Int? {
        if let d = press.key.character.wholeNumberValue, (1...5).contains(d) { return d }
        let us: [Character: Int] = ["\u{00A1}": 1, "\u{2122}": 2, "\u{00A3}": 3, "\u{00A2}": 4, "\u{221E}": 5]
        return press.characters.first.flatMap { us[$0] }
    }
}

extension FilmModel {
    /// The titlebar's one steel button in Notes: Turn over N, then Start cutting while a
    /// read-back waits, Screen Cut 3 while the editor cuts, Retry after a failure.
    var notesPrimary: PrimaryAction? {
        if let t = notesTurnover {
            switch t.state {
            case .waiting:
                return PrimaryAction(title: "Start cutting", enabled: false) {}
            case .readBack where !t.readBackApproved:
                return PrimaryAction(title: "Start cutting") { self.startCutting() }
            case .failed:
                return PrimaryAction(title: "Retry", icon: "arrow.uturn.backward") { self.copyEditorRequest() }
            default:
                if notesTab == .questions && openQuestions.contains(where: { $0.kind != "cant" }) { return nil }
                return PrimaryAction(title: "Screen \(notesCutName)", icon: "play.fill", enabled: isEnabled(.screening)) { self.go(.screening) }
            }
        }
        if notesTab == .questions && openQuestions.contains(where: { $0.kind != "cant" }) { return nil }
        let n = readyNotes.count
        return PrimaryAction(title: "Turn over", icon: "arrow.right", count: n > 0 ? String(n) : nil, enabled: n > 0) { self.sheet = .turnover }
    }
}

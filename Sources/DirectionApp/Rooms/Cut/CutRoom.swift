import SwiftUI
import AppKit
import DirectionCore

// The Cut room (specs/cut.md): watching a cut, noting it and looking at what the editor did with your notes,
// in one place. The picture on the left; on the right the sheet: each answer under the note it answers, then
// the notes for the next turnover, then the composer. Watch through (WatchThrough.swift) and Play changes
// (PlayChangesView.swift) take the whole window. While the editor cuts, the sheet becomes "Cut 4 in progress"
// (cutting is a state of this room, not a room). Older cuts open from the cut's name in the crumb.

struct CutRoom: View {
    @Bindable var model: FilmModel
    @FocusState private var focused: Bool
    private var state: ChangesState { model.changes }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                // Under a full-screen watch there's no second picture: one player, one place it plays.
                Group { if model.watchingCut || state.reelOpen { Gate.Surface.canvas } else { stage } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                side
                    .padding(.leading, 1)
                    .frame(width: Gate.Size.notesSheet)
                    .frame(maxHeight: .infinity)
                    .background(Gate.Surface.ground)
                    .hairlineBorder(.leading)
            }
            if state.reelOpen {
                PlayChangesView(model: model)
                    .padding(.top, -Gate.Size.titlebar)
                    .transition(.opacity)
                    .zIndex(5)
            }
            CutKeyCommands(model: model)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: key)
        .onAppear { focused = true }
        .onDisappear { leave() }
        .onChange(of: model.sheet) { _, sheet in if sheet == nil { focused = true } }
        .onChange(of: model.notesTurnover?.state) { _, state in if state == nil { model.notesUI.cuttingSide = .progress } }
        .onChange(of: model.playingChanges) { _, on in if on && !state.reelOpen { state.reelOpen = true } }
        .onChange(of: state.replyingNoteID) { _, id in if id == nil { focused = true } }
        .onChange(of: state.reelOpen) { _, _ in focused = true }
        .onChange(of: model.watchingCut) { _, watching in if !watching { focused = true } }
        .animation(gateAnimation(Gate.Motion.glide), value: state.reelOpen)
        .animation(gateAnimation(Gate.Motion.glide), value: model.comparingNoteID)
        .alert("Accept \(model.acceptableRemaining.count) answers?", isPresented: Binding(get: { state.confirmAcceptAll }, set: { state.confirmAcceptAll = $0 })) {
            Button("Accept \(model.acceptableRemaining.count)") { model.acceptAllRemaining() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.toReview.count > model.acceptableRemaining.count ? "They stay in \(model.reviewCut?.name ?? "this cut"). Answers with two options wait for your pick." : "They stay in \(model.reviewCut?.name ?? "this cut").")
        }
    }

    /// The picture side: two options, a whole-cut comparison, the lock bar, a made graphic, or the cut and its strip.
    @ViewBuilder private var stage: some View {
        if state.comparingCuts {
            CompareCutsStage(model: model)
        } else if let id = model.comparingNoteID, let c = model.note(id), model.hasOptions(c) {
            OptionsStage(model: model, note: c)
        } else if model.showsLockBar {
            LockStage(model: model)
        } else if let c = model.selectedAnswer, let g = model.graphics.graphic(for: c) {
            // A graphic answer (64): the answer card under the picture carries Words (Phase2/Graphics).
            GraphicAnswerStage(model: model, note: c, graphic: g)
        } else {
            FilmStage(model: model, marks: stageMarks, showsMarkButton: !model.showsCuttingPanel, showsWatch: true) { size in
                RegionLayer(model: model, size: size)
            }
        }
    }

    @ViewBuilder private var side: some View {
        if model.showsCuttingPanel, let t = model.notesTurnover {
            CuttingPanel(model: model, turnover: t)
        } else {
            NotesSheet(model: model, onLeave: { focused = true })
        }
    }

    /// Your pins for what isn't answered yet, the editor's diamonds for what it changed in the cut on screen, and in
    /// the Outside tab outside people's marks in steel.
    private var stageMarks: [StripMark] {
        let answered = Set(model.reviewAnswers.map(\.id))
        let mine = model.noteMarks.filter { !answered.contains($0.id) && model.note($0.id)?.lifecycle != .answered }
        let outside = model.notesTab != .outside ? [] : model.inbox.compactMap { c in
            (model.noteTime(c) ?? model.anchorScene(c)?.start).map { StripMark(id: c.id, time: $0, kind: .outside) }
        }
        return mine + model.answerMarks + outside
    }

    private func leave() {
        state.sticky = []
        state.showAllAnswers = false
        if state.reelOpen { model.closeReel() }
        model.comparingNoteID = nil
        state.comparingCuts = false
    }

    // MARK: Keys
    // Room keys never fire while a text field has focus: the field keeps its keystrokes.

    private func key(_ press: KeyPress) -> KeyPress.Result {
        guard !TextInput.hasFocus else { return .ignored }
        guard model.sheet == nil, !model.showCommandMenu, !model.showShortcuts else { return .ignored }
        let mods = press.modifiers.subtracting([.capsLock, .numericPad])
        let char = press.characters.lowercased()
        // Only the arrows repeat: a held N or space does it once.
        if press.phase == .repeat && ![.upArrow, .downArrow, .leftArrow, .rightArrow].contains(press.key) { return .handled }

        if state.reelOpen { return reelKey(press, mods: mods, char: char) }
        if state.ab != nil, model.comparingNoteID != nil || state.comparingCuts, let r = optionKey(char, mods: mods) { return r }

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
            if let ab = state.ab { ab.toggle() } else { model.togglePlayback() }
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
        let answer = model.notesTab == .sheet ? model.selectedAnswer : nil
        switch char {
        case "n":
            model.mark()
            if let id = model.freshMarkID, let c = model.note(id) { model.notesTab = .sheet; model.showNote(c) }
            return .handled
        // R replies to a selected answer; with a note selected it draws a region on the picture.
        case "r" where answer != nil && !model.isPictureLocked:
            model.replyToAnswer(answer?.id)
            return .handled
        case "r" where model.notesTab == .sheet && composerShown:
            model.beginRegion()
            return .handled
        // A accepts the selected answer; with two options, A and B use one.
        case "a", "b", "y":
            guard let c = answer, !model.isPictureLocked, model.status(c) == .unreviewed else { break }
            if model.hasOptions(c), char != "y" { model.useOption(c.id, char.uppercased()) }
            else if char != "b" { model.acceptAnswerFromChanges(c.id) }
            return .handled
        default:
            break
        }
        // With a draft selected, typing starts writing it; other single keys are the room's.
        if model.notesTab == .sheet, composerShown, model.selectedNote?.lifecycle == .draft, Self.printable(press.characters) {
            model.draftText += press.characters
            model.composerFocus += 1
            return .handled
        }
        switch char {
        case "w": model.watchThrough(); return .handled
        case "i" where composerShown: setRange(in: true); return .handled
        case "o" where composerShown: setRange(in: false); return .handled
        case "e" where model.notesTab == .outside:
            if let c = selectedOutside { model.editOutsideFirst(c) }
            return .handled
        case "j": model.shuttle(-1); return .handled
        case "k": model.shuttle(0); return .handled
        case "l": model.shuttle(1); return .handled
        default:
            if model.notesTab == .sheet, composerShown, model.selectedNote == nil, answer == nil, Self.printable(press.characters) {
                model.draftText += press.characters
                model.composerFocus += 1
                return .handled
            }
            return .ignored
        }
    }

    /// Play changes takes the keys while it's up: ← → between changes, A to accept and go on, R to reply.
    private func reelKey(_ press: KeyPress, mods: EventModifiers, char: String) -> KeyPress.Result {
        guard mods.isEmpty || mods == .shift else { return .ignored }
        switch press.key {
        case .space: model.togglePlayback(); return .handled
        case .leftArrow: if mods.isEmpty { model.previousChange() } else { model.step(frames: -model.fps) }; return .handled
        case .rightArrow: if mods.isEmpty { model.nextChange() } else { model.step(frames: model.fps) }; return .handled
        case .escape: model.closeReel(); return .handled
        default: break
        }
        switch char {
        case "j": model.shuttle(-1); return .handled
        case "k": model.shuttle(0); return .handled
        case "l": model.shuttle(1); return .handled
        case "n": model.mark(); return .handled
        default: break
        }
        guard let c = model.playingAnswer, !model.isPictureLocked else { return .ignored }
        switch char {
        case "a" where !model.hasOptions(c), "y":
            guard model.status(c) == .unreviewed, !model.hasOptions(c) else { return .ignored }
            model.acceptAnswerFromChanges(c.id, advance: false); model.nextChange(); return .handled
        case "a", "b":
            guard model.hasOptions(c), model.status(c) == .unreviewed else { return .ignored }
            model.useOption(c.id, char.uppercased()); return .handled
        case "r": model.replyToAnswer(c.id); return .handled
        default: return .ignored
        }
    }

    private func optionKey(_ char: String, mods: EventModifiers) -> KeyPress.Result? {
        guard let ab = state.ab else { return nil }
        switch (char, mods) {
        case ("1", []): ab.setAudible(0); state.optionFocus = 0; return .handled
        case ("2", []): ab.setAudible(1); state.optionFocus = 1; return .handled
        case ("!", .shift), ("1", .shift), ("a", []):
            if let id = model.comparingNoteID { model.chooseOption(id, "A"); return .handled }
        case ("@", .shift), ("2", .shift), ("b", []):
            if let id = model.comparingNoteID { model.chooseOption(id, "B"); return .handled }
        default: break
        }
        return nil
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
        if model.notesTab == .sheet, let c = model.selectedAnswer {
            if model.hasOptions(c) { model.comparingNoteID = c.id; return .handled }
            return .ignored
        }
        guard model.notesTab == .sheet, composerShown, let c = model.selectedNote else { return .ignored }
        if c.lifecycle == .draft { model.composerFocus += 1 } else { model.editInComposer(c) }
        return .handled
    }

    private func escape() -> KeyPress.Result {
        let ui = model.notesUI
        if state.replyingNoteID != nil { model.cancelReply(); return .handled }
        if state.comparingCuts { state.comparingCuts = false; return .handled }
        if model.comparingNoteID != nil { model.comparingNoteID = nil; return .handled }
        if model.drawingRegion || model.anchorMode == .region { model.cancelRegion(); return .handled }
        if ui.correctingNoteID != nil { ui.correctingNoteID = nil; ui.correction = ""; return .handled }
        if ui.editingNoteID != nil || ui.editingOutsideID != nil || !model.draftText.isEmpty { model.cancelComposer(); return .handled }
        if model.notesTab != .sheet { model.notesTab = .sheet; return .handled }
        if model.watchedCutID != nil { model.watch(model.latestCut); return .handled }
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

/// Room shortcuts with ⌘: they match the Cut menu so either one runs the same action.
struct CutKeyCommands: View {
    var model: FilmModel
    var body: some View {
        let state = model.changes
        ZStack {
            Button("Reply to Answer") { model.replyToAnswer() }.keyboardShortcut("r", modifiers: .command)
            Button("Accept All Remaining") { if !model.acceptableRemaining.isEmpty && !model.isPictureLocked { state.confirmAcceptAll = true } }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Revert This Change") { if let id = model.selectedAnswerNoteID { state.revertNoteID = id } }
                .keyboardShortcut(.delete, modifiers: .command)
            Button("Lock Scene") { model.toggleLockOnCurrentScene() }.keyboardShortcut("l", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension FilmModel {
    /// The titlebar's one steel button in the Cut room, by what's waiting (specs/cut.md › The one button):
    /// Start cutting while a read-back waits for your OK; Turn over N once you've written a note; Accept N while
    /// the editor's answers wait; Lock picture… once everything is accepted.
    var cutPrimary: PrimaryAction? {
        if isPictureLocked || changes.reelOpen { return nil }
        if let t = notesTurnover {
            switch t.state {
            case .waiting:
                return PrimaryAction(title: "Start cutting", enabled: false) {}
            case .readBack where !t.readBackApproved:
                // A question asked during the read-back (a spend question, frame 62) has the steel Answer.
                if notesTab == .questions && openQuestions.contains(where: { $0.kind != "cant" }) { return nil }
                return PrimaryAction(title: "Start cutting", key: "\u{2318}\u{21A9}") { self.startCutting() }
            case .failed:
                return PrimaryAction(title: "Retry", icon: "arrow.uturn.backward") { self.copyEditorRequest() }
            default:
                if notesTab == .questions && openQuestions.contains(where: { $0.kind != "cant" }) { return nil }
                return PrimaryAction(title: "Watch \(notesCutName)", icon: "play.fill", enabled: isEnabled(.cut)) { self.watchThrough() }
            }
        }
        if notesTab == .questions && openQuestions.contains(where: { $0.kind != "cant" }) { return nil }
        // An older cut, opened from the crumb, is for looking back at: watch it.
        if let cut = watchedCut, watchedCutID != nil {
            return PrimaryAction(title: "Watch \(cut.name)", icon: "play.fill") { self.watchThrough() }
        }
        let n = readyNotes.count
        if n > 0 { return PrimaryAction(title: "Turn over", icon: "arrow.right", count: String(n)) { self.sheet = .turnover } }
        let acceptable = acceptableRemaining.count
        if acceptable > 0 {
            return PrimaryAction(title: "Accept", icon: "checkmark", count: String(acceptable), help: "Accept every answer still to look at (\u{2318}\u{21A9})") { self.changes.confirmAcceptAll = true }
        }
        if showsLockBar {
            return PrimaryAction(title: "Lock picture\u{2026}", icon: "lock.fill", enabled: picturelockBlockers.isEmpty) { self.sheet = .lockPicture }
        }
        return PrimaryAction(title: "Turn over", icon: "arrow.right", enabled: false, help: "Write a note first") {}
    }

    /// The lock bar replaces the transport once every answer is accepted and nothing new is written (34).
    var showsLockBar: Bool {
        !isPictureLocked && !cuts.isEmpty && toReview.isEmpty && reviewCut?.id == latestCut?.id && !reviewAnswers.isEmpty
            && readyNotes.isEmpty && draftNotes.isEmpty && notesTurnover == nil && comparingNoteID == nil && !changes.comparingCuts
    }

    /// ⌘L: the lock bar's selected scene, else the scene under the playhead.
    func toggleLockOnCurrentScene() {
        guard !isPictureLocked else { return }
        let id = (room == .cut && showsLockBar ? changes.lockSceneID : nil) ?? stripScene(at: position)?.id
        guard let id, let s = dailies.scenes.first(where: { $0.id == id }) else { return }
        // Unlocking from the lock bar asks first; everywhere else it's undoable at once.
        if s.locked && room == .cut && showsLockBar { changes.unlockSceneID = id; return }
        lockScene(id, !s.locked)
    }
}

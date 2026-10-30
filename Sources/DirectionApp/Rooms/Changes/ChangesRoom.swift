import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. Frames 29–33: the latest cut's answers, options, play changes,
// replies and the cut history. The lock bar (34) lives in Rooms/Finish/LockScenes.swift.

struct ChangesRoom: View {
    @Bindable var model: FilmModel
    @FocusState private var focused: Bool
    private var state: ChangesState { model.changes }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if state.mode == .history { CutHistoryView(model: model) }
                else {
                    HStack(spacing: 0) {
                        stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                        AnswersPanel(model: model)
                    }
                }
            }
            if state.reelOpen {
                PlayChangesView(model: model)
                    .padding(.top, -Gate.Size.titlebar)
                    .transition(.opacity)
                    .zIndex(5)
            }
            ChangesKeyCommands(model: model)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { handle($0) }
        .onExitCommand { escape() }
        .onAppear { appear() }
        .onDisappear { leave() }
        .onChange(of: model.playingChanges) { _, on in if on && !state.reelOpen { state.reelOpen = true } }
        .onChange(of: state.replyingNoteID) { _, id in if id == nil { focused = true } }
        .onChange(of: state.reelOpen) { _, _ in focused = true }
        .animation(gateAnimation(Gate.Motion.glide), value: state.reelOpen)
        .animation(gateAnimation(Gate.Motion.glide), value: model.comparingNoteID)
    }

    /// The picture side: options, a whole-cut comparison, the lock bar, or the cut with its strip.
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
            FilmStage(model: model, marks: model.answerMarks, showsMarkButton: false, hudPrefix: model.reviewCut?.name)
        }
    }

    private func appear() {
        if model.selectedAnswerNoteID.map({ id in !model.reviewAnswers.contains { $0.id == id } }) ?? true,
           let first = model.toReview.first ?? model.reviewAnswers.first {
            model.selectAnswer(first, cue: !model.isPreview)
        }
        focused = true
    }

    private func leave() {
        state.sticky = []
        state.chosenTab = nil
        if state.reelOpen { model.closeReel() }
        model.comparingNoteID = nil
        state.comparingCuts = false
    }

    // MARK: Keys

    private func escape() {
        if state.reelOpen { model.closeReel() }
        else if state.replyingNoteID != nil { model.cancelReply() }
        else if state.comparingCuts { state.comparingCuts = false }
        else if model.comparingNoteID != nil { model.comparingNoteID = nil }
        else if state.mode == .history { model.showAnswers() }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !TextInput.hasFocus else { return .ignored }
        let mods = press.modifiers.subtracting([.numericPad, .capsLock])
        let char = press.characters.lowercased()
        // Playback keys work in every mode.
        if mods.isEmpty || mods == .shift {
            switch press.key {
            case .space:
                if let ab = state.ab { ab.toggle() } else { model.togglePlayback() }
                return .handled
            case .leftArrow where state.reelOpen && mods.isEmpty: model.previousChange(); return .handled
            case .rightArrow where state.reelOpen && mods.isEmpty: model.nextChange(); return .handled
            case .leftArrow: model.step(frames: mods == .shift ? -model.fps : -1); return .handled
            case .rightArrow: model.step(frames: mods == .shift ? model.fps : 1); return .handled
            default: break
            }
        }
        guard mods.isEmpty || mods == .shift else { return .ignored }
        if mods.isEmpty {
            switch char {
            case "j": model.shuttle(-1); return .handled
            case "k": model.shuttle(0); return .handled
            case "l": model.shuttle(1); return .handled
            default: break
            }
        }
        if state.reelOpen { return reelKey(char) }
        if state.ab != nil, model.comparingNoteID != nil || state.comparingCuts { if let r = optionKey(char, mods: mods) { return r } }
        if state.mode == .history { return historyKey(press) }
        guard mods.isEmpty, !model.isPictureLocked else { return .ignored }
        switch (press.key, char) {
        case (.upArrow, _): moveSelection(-1); return .handled
        case (.downArrow, _): moveSelection(1); return .handled
        case (_, "y"): model.acceptSelectedAnswer(); return .handled
        case (_, "a"), (_, "b"):
            guard let c = model.selectedAnswer, model.hasOptions(c), model.status(c) == .unreviewed else { return .ignored }
            model.useOption(c.id, char.uppercased()); return .handled
        case (_, "r"): model.replyToAnswer(); return .handled
        case (.return, _):
            if let c = model.selectedAnswer, model.hasOptions(c) { model.comparingNoteID = c.id; return .handled }
            return .ignored
        default: return .ignored
        }
    }

    private func reelKey(_ char: String) -> KeyPress.Result {
        guard let c = model.playingAnswer, !model.isPictureLocked else { return .ignored }
        switch char {
        case "y":
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

    private func historyKey(_ press: KeyPress) -> KeyPress.Result {
        let rows = model.answers(in: model.historyCut)
        guard !rows.isEmpty else { return .ignored }
        let i = rows.firstIndex { $0.id == state.historyNoteID }
        switch press.key {
        case .upArrow: state.historyNoteID = rows[max(0, (i ?? rows.count) - 1)].id; return .handled
        case .downArrow: state.historyNoteID = rows[min(rows.count - 1, (i ?? -1) + 1)].id; return .handled
        default: return .ignored
        }
    }

    private func moveSelection(_ step: Int) {
        let rows = model.answers(for: model.answersTab)
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { $0.id == model.selectedAnswerNoteID }
        let next = i.map { max(0, min(rows.count - 1, $0 + step)) } ?? (step > 0 ? 0 : rows.count - 1)
        model.selectAnswer(rows[next])
    }
}

/// Room shortcuts with ⌘: they match the Cut menu so either one runs the same action.
struct ChangesKeyCommands: View {
    var model: FilmModel
    var body: some View {
        let state = model.changes
        ZStack {
            Button("Play Changes") { model.openChangesReel() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Reply to Answer") { model.replyToAnswer(state.mode == .history ? state.historyNoteID : nil) }.keyboardShortcut("r", modifiers: .command)
            Button("Accept All Remaining") { if !model.acceptableRemaining.isEmpty && !model.isPictureLocked { state.confirmAcceptAll = true } }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("History") { state.mode == .history ? model.showAnswers() : model.showCutHistory() }.keyboardShortcut("y", modifiers: .command)
            Button("Revert This Change") {
                if state.mode == .history, let id = state.historyNoteID { state.revertNoteID = id }
                else if let id = model.selectedAnswerNoteID { state.historyCutID = model.reviewCut?.id; state.historyNoteID = id; state.revertNoteID = id; model.showCutHistory() }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            Button("Lock Scene") { model.toggleLockOnCurrentScene() }.keyboardShortcut("l", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension FilmModel {
    /// The titlebar's steel button in Changes: Play changes, Screen Cut N in history, Lock picture… once nothing waits.
    var changesPrimary: PrimaryAction? {
        if isPictureLocked { return nil }
        let state = changes
        // The reel's dock carries its own steel Accept.
        if state.reelOpen { return nil }
        if state.mode == .history, let cut = historyCut {
            return PrimaryAction(title: "Screen \(cut.name)", icon: "play.fill") { self.watch(cut); self.go(.screening) }
        }
        if showsLockBar || (!cuts.isEmpty && toReview.isEmpty && !reviewAnswers.isEmpty) {
            return PrimaryAction(title: "Lock picture\u{2026}", icon: "lock.fill", enabled: picturelockBlockers.isEmpty) { self.sheet = .lockPicture }
        }
        let reel = changesDuration(in: watchedCut)
        return PrimaryAction(title: "Play changes", icon: "play.fill", count: Timecode.duration(reel), enabled: reel > 0) { self.openChangesReel() }
    }

    /// The lock bar replaces the transport once nothing is left to review (34).
    var showsLockBar: Bool {
        !isPictureLocked && !cuts.isEmpty && toReview.isEmpty && reviewCut?.id == latestCut?.id && changes.mode == .answers && comparingNoteID == nil && !changes.comparingCuts
    }

    /// ⌘L: the lock bar's selected scene, else the scene under the playhead.
    func toggleLockOnCurrentScene() {
        guard !isPictureLocked else { return }
        let id = (room == .changes && showsLockBar ? changes.lockSceneID : nil) ?? stripScene(at: position)?.id
        guard let id, let s = dailies.scenes.first(where: { $0.id == id }) else { return }
        // Unlocking from the lock bar asks first; everywhere else it's undoable at once.
        if s.locked && room == .changes && showsLockBar { changes.unlockSceneID = id; return }
        lockScene(id, !s.locked)
    }
}

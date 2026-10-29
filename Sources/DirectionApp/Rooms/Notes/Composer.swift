import SwiftUI
import AppKit
import DirectionCore

/// The sheet's foot (`.sheet-foot`): anchor line, note field, kinds and Add.
/// A new note's anchor follows the playhead until you start typing, then stays put.
struct NotesComposer: View {
    @Bindable var model: FilmModel
    /// Gives keyboard focus back to the room (esc, Cancel).
    var onLeave: () -> Void
    @State private var focusRequest = 0

    private var ui: NotesUI { model.notesUI }
    private var editing: ReviewComment? { model.editingNote }
    private var outside: ReviewComment? { model.editingOutside }
    private var draft: ReviewComment? { model.selectedNote.flatMap { $0.lifecycle == .draft ? $0 : nil } }
    private var number: Int? { model.composerNoteNumber }
    private var suggestion: NoteKind? {
        guard model.draftKind == nil else { return nil }
        return KindSuggester.suggest(model.draftText)
    }
    private var canWrite: Bool { !model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            anchorRow.frame(height: Gate.Size.control)
            NoteField(text: $model.draftText, placeholder: "What should it feel like?", label: fieldLabel, focusToken: focusRequest,
                      onFocusChange: { ui.composerFocused = $0 },
                      onSubmit: submit,
                      onEscape: { model.cancelComposer(); onLeave() },
                      onTab: takeSuggestion,
                      onOptionDigit: { digit in model.setKind(NoteKind.allCases[digit - 1], composer: true) })
            HStack(spacing: 8) {
                KindPicker(kind: $model.draftKind, suggested: suggestion)
                    .fixedSize()
                    .accessibilityElement(children: .contain).accessibilityLabel("Kind")
                Spacer(minLength: 0)
                actions
            }
            .frame(height: Gate.Size.control)
            if let suggestion {
                Text("\(Text("Editor suggests \(suggestion.label).").foregroundStyle(Gate.Voice.agent)) Press ⇥ to take it, or pick another.").foregroundStyle(Gate.Text.tertiary)
                    .font(Gate.Font.caption).lineHeight(11, 1.45)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(.top, 13).padding(.horizontal, 16).padding(.bottom, 14)
        .hairlineBorder(.top)
        .animation(gateAnimation(Gate.Motion.settle), value: suggestion)
        .onAppear(perform: honorFocusRequest)
        .onChange(of: model.composerFocus) { _, _ in noticeEditFromMenu(); honorFocusRequest() }
        .onChange(of: model.draftText) { old, new in
            if old.isEmpty, !new.isEmpty, ui.pinnedTime == nil, draft == nil, editing == nil { ui.pinnedTime = model.position }
            if new.isEmpty, editing == nil, outside == nil, model.anchorMode == .moment { ui.pinnedTime = nil }
        }
        .onChange(of: suggestion) { _, kind in
            guard let kind else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: "Suggested kind: \(kind.label). Press Tab to accept.", .priority: NSAccessibilityPriorityLevel.low.rawValue])
        }
        .onChange(of: model.anchorMode) { _, mode in if mode == .region, model.region == nil, !model.drawingRegion { model.beginRegion() } }
    }

    // MARK: Anchor line

    @ViewBuilder private var anchorRow: some View {
        HStack(spacing: 8) {
            if let outside {
                Image(systemName: "person").font(.system(size: 11, weight: .medium))
                Text("\(outside.person?.name ?? "Outside")\u{2019}s note")
                Chip(model.anchorStart(outside), icon: model.anchorIcon(outside))
                Spacer(minLength: 0)
                cancel
            } else if let editing {
                Image(systemName: "pencil").font(.system(size: 11, weight: .medium))
                Text("Editing note \(editing.number.map(String.init) ?? "")")
                Chip(model.anchorText(editing), style: .director, icon: model.anchorIcon(editing))
                Spacer(minLength: 0)
                cancel
            } else {
                Image(systemName: anchorIcon).font(.system(size: 11, weight: .medium))
                Text(anchorLabel)
                if let chip = anchorChip { Chip(chip, style: .director) }
                Spacer(minLength: 0)
                GateSelect(options: anchorOptions, selection: anchorBinding, muted: true)
                    .help("What the note is anchored to")
                    .accessibilityLabel("Anchor")
            }
        }
        .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
    }

    private var anchorIcon: String {
        switch model.anchorMode {
        case .moment: "clock"
        case .range: "arrow.left.and.line.vertical.and.arrow.right"
        case .region: "viewfinder"
        case .scene: "film"
        case .wholeCut: "text.bubble"
        }
    }
    private var anchorLabel: String {
        let n = number.map { "Note \($0)" }
        switch model.anchorMode {
        case .moment: return n.map { "\($0) at" } ?? "At"
        case .range: return n.map { "\($0), from" } ?? "From"
        case .region: return n.map { "\($0), region at" } ?? "Region at"
        case .scene: return n.map { "\($0), on" } ?? "On"
        case .wholeCut: return n.map { "\($0), on the whole cut" } ?? "On the whole cut"
        }
    }
    private var anchorChip: String? {
        switch model.anchorMode {
        case .moment, .region: return Timecode.format(model.composerTime, fps: model.fps)
        case .range:
            let r = model.rangeSelection ?? model.composerTime...min(model.duration, model.composerTime + 1)
            return Timecode.range(r.lowerBound, r.upperBound, fps: model.fps)
        case .scene: return model.stripScene(at: model.composerTime).map { "Scene \($0.number)" }
        case .wholeCut: return nil
        }
    }
    /// A draft keeps its moment; it can only gain a region.
    private var anchorOptions: [(NoteAnchorMode, String)] {
        (draft == nil ? NoteAnchorMode.allCases : [.moment, .region]).map { ($0, $0.label) }
    }
    private var anchorBinding: Binding<NoteAnchorMode> {
        Binding(get: { model.anchorMode }, set: { mode in
            if mode == .region { model.beginRegion() }
            else {
                if model.anchorMode == .region { model.region = nil; model.drawingRegion = false }
                if mode == .range, model.rangeSelection == nil { let t = model.composerTime; model.rangeSelection = t...min(model.duration, t + 2) }
                model.anchorMode = mode
            }
        })
    }

    // MARK: Actions

    private var cancel: some View {
        Button("Cancel") { model.clearComposer(); onLeave() }.buttonStyle(.gate(.ghost)).help("Stop editing (esc)")
    }

    @ViewBuilder private var actions: some View {
        if outside != nil || editing != nil {
            Button(action: submit) { HStack(spacing: 6) { Text(outside != nil ? "Accept" : "Save"); KeyHint("↩") } }
                .buttonStyle(.gate).disabled(!canWrite)
        } else {
            Button(action: submit) { HStack(spacing: 6) { Text("Add"); KeyHint("↩") } }
                .buttonStyle(.gate).disabled(!canWrite)
                .help("Add the note (↩). ⇧↩ adds a line.")
        }
    }

    private var fieldLabel: String {
        if let outside { return "\(outside.person?.name ?? "Outside") note text" }
        if let n = number { return "Note \(n) text" }
        return "New note text"
    }

    private func submit() {
        guard canWrite else { return }
        let keepWriting = draft != nil
        model.writeComposer()
        if !keepWriting { onLeave() }
    }
    private func takeSuggestion() -> Bool {
        guard let suggestion else { return false }
        model.draftKind = suggestion
        return true
    }
    private func honorFocusRequest() {
        guard model.composerFocus != ui.handledComposerFocus else { return }
        ui.handledComposerFocus = model.composerFocus
        focusRequest += 1
    }
    /// The note menu's "Edit Note" loads a written note into the composer; edit it in place.
    private func noticeEditFromMenu() {
        guard ui.editingNoteID == nil, let c = model.selectedNote, [.written, .reopened].contains(c.lifecycle), model.draftText == c.text else { return }
        ui.editingOutsideID = nil
        ui.editingNoteID = c.id
    }
}

import SwiftUI
import DirectionCore

/// Script's right panel: the picture following the playhead, then the script notes.
struct ScriptSidePanel: View {
    @Bindable var model: FilmModel
    var document: ScriptDocument
    var notes: [ReviewComment]
    @Binding var editingNoteID: String?
    @Binding var editingText: String
    var editorFocus: FocusState<ScriptFocus?>.Binding
    var onSelect: (ReviewComment) -> Void
    var onEdit: (ReviewComment) -> Void
    var onCommit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScriptPreviewPicture(model: model, document: document)
            if notes.isEmpty { empty } else { list }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.leading, 1)
        .background(Gate.Surface.ground)
        .hairlineBorder(.leading)
    }

    private var header: some View {
        HStack {
            Text("Script notes").font(Gate.Font.brandS).foregroundStyle(Gate.Text.primary)
            Spacer()
            Text("\(notes.count)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Text("Direct the words. Strike a line to lose it, hold a passage to let it breathe, drag a line to move it, or press R to hear every reading.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Text("Each gesture becomes a numbered note on the sheet. Nothing changes in the cut until you turn over.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if let say = editorLine {
                Hairline()
                HStack(alignment: .top, spacing: 9) {
                    GemMark(size: 8).padding(.top, 4)
                    Text(say).font(Gate.Font.body).foregroundStyle(Gate.Text.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Editor: \(say)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                header.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
                ForEach(notes) { note in noteRow(note).hairlineBorder(.bottom) }
            }
        }
        .scrollIndicators(.never)
    }

    private func noteRow(_ note: ReviewComment) -> some View {
        let editing = editingNoteID == note.id
        let selected = editing || model.selectedNoteID == note.id
        let editable = [.draft, .written, .reopened].contains(note.lifecycle)
        return HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 3) {
                Text(note.number.map(String.init) ?? "\u{2013}").font(Gate.Font.noteNumber).foregroundStyle(Gate.Voice.director)
                if [.turnedOver, .answered, .accepted].contains(note.lifecycle) { GemMark(size: 5) }
            }
            .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Chip(note.scriptAction?.lineLabel ?? "Line", style: .director, icon: icon(note.scriptAction?.gesture))
                    if let kind = note.kind {
                        Chip(kind.label, style: .label, mono: false).overlay(RoundedRectangle(cornerRadius: Gate.Radius.chip).strokeBorder(Gate.Line.subtle, lineWidth: 1))
                    }
                }
                if editing {
                    TextField("", text: $editingText, axis: .vertical)
                        .textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                        .lineLimit(1...4)
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .background(GateFieldBackground(focused: true))
                        .focused(editorFocus, equals: .note)
                        .onSubmit(onCommit)
                        .onKeyPress(.escape) { editingNoteID = nil; return .handled }
                        .padding(.top, 4)
                        .accessibilityLabel("Note \(note.number ?? 0)")
                    Text("Edit the words or press \u{21A9} to keep them.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                } else {
                    Mentions.text(note.text, footage: model.footageNames).font(Gate.Font.body).foregroundStyle(note.lifecycle == .draft ? Gate.Text.tertiary : Gate.Text.primary).italic(note.lifecycle == .draft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14).padding(.trailing, 16).padding(.vertical, 12)
        .background(selected ? Gate.Surface.panel : .clear)
        .overlay(alignment: .leading) { if selected { Gate.Voice.director.frame(width: 2) } }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if editable { onEdit(note) } }
        .onTapGesture { onSelect(note) }
        .contextMenu {
            if editable { Button("Edit Words") { onEdit(note) } }
            NoteContextMenu(model: model, note: note)
        }
        .accessibilityElement(children: editing ? .contain : .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func icon(_ gesture: ScriptGesture?) -> String {
        switch gesture {
        case .strike: "strikethrough"
        case .hold: "curlybraces"
        case .move: "arrow.up.and.down"
        case .reading: "quote.opening"
        case nil: "doc.text"
        }
    }

    /// The editor's one line about where the words come from: "Lines 7–16 are from 2A T2, your circle."
    private var editorLine: String? {
        guard let line = document.line(at: model.position), let scene = document.scene(of: line) else { return nil }
        guard let i = scene.lines.firstIndex(where: { $0.id == line.id }) else { return nil }
        var lo = i, hi = i
        while lo > 0, scene.lines[lo - 1].assetID == line.assetID { lo -= 1 }
        while hi < scene.lines.count - 1, scene.lines[hi + 1].assetID == line.assetID { hi += 1 }
        let a = scene.lines[lo].number, b = scene.lines[hi].number
        let take = model.dailies.take(line.assetID)
        let whose = take.circled ? ", your circle" : take.suggestion != nil ? ", my suggestion" : ""
        var out = (lo == hi ? "Line \(a) is" : "Lines \(a)\u{2013}\(b) are") + " from \(document.takeLabel(line.assetID))\(whose)."
        let others = line.readings.count - 1
        if line.kind == .dialogue {
            out += others == 0 ? " Line \(line.number) has no other reading." : " Line \(line.number) has \(ScriptText.spelled(others)) other reading\(others == 1 ? "" : "s")."
        }
        return out
    }
}

/// The picture following the playhead, with play, timecode and the line on screen.
private struct ScriptPreviewPicture: View {
    @Bindable var model: FilmModel
    var document: ScriptDocument
    var body: some View {
        let line = document.line(at: model.position)
        VStack(spacing: 8) {
            PictureView(player: model.isPreview ? nil : model.player, still: model.isPreview ? model.stripScene(at: model.position)?.art ?? .room : nil, aspect: model.aspect)
                .overlay(alignment: .bottomLeading) { HUDTag(Timecode.format(model.position, fps: model.fps)).padding(8) }
                .overlay { if model.isPreparing { GateSpinner() } }
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                Button { model.togglePlayback() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.gate(.normal, .small, icon: true)).help(model.playing ? "Pause (Space)" : "Play from this line (Space)")
                    .accessibilityLabel(model.playing ? "Pause" : "Play")
                Text("\(Text(Timecode.format(model.position, fps: model.fps)).foregroundColor(Gate.Text.primary))\(Text(" / \(Timecode.duration(model.duration))").foregroundColor(Gate.Text.disabled))")
                    .font(Gate.Font.timecode)
                Spacer(minLength: 8)
                if let line { Text("\(line.label) \u{00B7} \(document.takeLabel(line.assetID))").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(1) }
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
        .hairlineBorder(.bottom)
    }
}

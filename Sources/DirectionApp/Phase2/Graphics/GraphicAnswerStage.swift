import SwiftUI
import DirectionCore

// Frame 64 (graphics.md › The director's side): a graphic answer in Changes. The picture plays the
// cut with the graphic in it; the answer card under it has Accept, Words and Not quite; Words opens
// a popover where the director fixes the words directly.

/// The Changes stage for an answer that delivered a graphic: picture, answer card, transport.
struct GraphicAnswerStage: View {
    @Bindable var model: FilmModel
    let note: ReviewComment
    let graphic: Graphic

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                let avail = CGSize(width: g.size.width - 56, height: g.size.height - 36)
                let size = fit(model.aspect, in: avail)
                ZStack {
                    PictureView(player: model.isPreview ? nil : model.player, still: model.isPreview ? model.stripScene(at: model.position)?.art ?? .room : nil, aspect: model.aspect)
                    if model.isPreview { GraphicPreview(graphic: graphic, visible: model.answerRange(note)?.contains(model.position) ?? true) }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
                .contextMenu { PictureContextMenu(model: model) }
                .overlay(alignment: .bottomLeading) { HUDTag("\(model.reviewCut?.name ?? "Cut") \u{00B7} \(Timecode.format(model.position, fps: model.fps))").padding(12) }
                .overlay { if model.isPreparing || model.graphics.isRendering(graphic) { HStack(spacing: 8) { GateSpinner(); Text("Preparing picture").font(Gate.Font.small) }.padding(12).gateGlass(10) } }
                .position(x: g.size.width / 2, y: 28 + avail.height / 2)
            }
            GraphicAnswerCard(model: model, note: note, graphic: graphic)
                .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 6)
                .zIndex(1)
            FilmTransport(model: model, marks: model.answerMarks, showsMarkButton: false)
        }
        .background(Gate.Surface.canvas)
        .onChange(of: note.id) { _, _ in model.graphics.cancelWords() }
        .onDisappear { model.graphics.cancelWords() }
    }

    private func fit(_ aspect: CGFloat, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        return size.width / size.height > aspect ? CGSize(width: size.height * aspect, height: size.height) : CGSize(width: size.width, height: size.width / aspect)
    }
}

/// "Note 8 · Story. …" with Accept, Words and Not quite.
struct GraphicAnswerCard: View {
    @Bindable var model: FilmModel
    let note: ReviewComment
    let graphic: Graphic
    private var open: Bool { model.graphics.wordsNoteID == note.id }

    var body: some View {
        HStack(spacing: 12) {
            Text(quote).font(.system(size: 13)).lineSpacing(3).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if model.status(note) == .accepted {
                Label("Accepted", systemImage: "checkmark").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.State.approve).labelStyle(GateLabelStyle())
            } else {
                Button { model.acceptAnswerFromChanges(note.id) } label: { Label("Accept", systemImage: "checkmark") }
                    .buttonStyle(.gate(.normal)).help("Accept (Y)").disabled(model.isPictureLocked)
            }
            Button { open ? model.graphics.cancelWords() : model.graphics.openWords(graphic, for: note) } label: { Label("Words", systemImage: "character.cursor.ibeam") }
                .buttonStyle(.gate(.normal))
                .help("Change the words of \(graphic.spokenName)")
                .disabled(model.graphics.isRendering(graphic) || graphic.words.isEmpty)
                .overlay(alignment: .bottomTrailing) {
                    if open { WordsPopover(model: model, graphic: graphic).fixedSize().offset(y: -(Gate.Size.control + 6)).transition(.opacity) }
                }
            Button("Not quite") { model.replyToAnswer(note.id) }.buttonStyle(.gate(.ghost)).help("Reply (⌘R)").disabled(model.isPictureLocked)
        }
        .animation(gateAnimation(Gate.Motion.settle), value: open)
    }

    private var quote: AttributedString {
        var head = AttributedString("Note \(note.number.map(String.init) ?? "") \u{00B7} \(model.kindLabel(note)).")
        head.foregroundColor = Gate.Text.primary; head.font = .system(size: 13, weight: .medium)
        var body = AttributedString(" \u{201C}\(note.text)\u{201D} \(model.answer(note, in: model.reviewCut)?.summary ?? "")")
        body.foregroundColor = Gate.Text.secondary
        return head + body
    }
}

/// Section label, a field per word with its counter, the promise, Cancel · Change Words.
struct WordsPopover: View {
    @Bindable var model: FilmModel
    let graphic: Graphic
    @FocusState private var focus: String?
    /// The caret starts at the end of the words, ready to fix the last one, rather than selecting them all.
    @State private var selection: [String: TextSelection] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Words")
                ForEach(graphic.words) { word in field(word) }
                Text("The editor won\u{2019}t change these unless a note asks.")
                    .font(.system(size: 11.5)).lineSpacing(2).foregroundStyle(Gate.Text.tertiary)
                    .frame(maxWidth: 150, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Hairline()
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { model.graphics.cancelWords() }.buttonStyle(.gate(.normal)).keyboardShortcut(.cancelAction)
                Button("Change Words") { model.graphics.changeWords(model, graphic) }.buttonStyle(.gate(.steel)).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Gate.Surface.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Gate.Line.strong, lineWidth: 1))
        .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1).padding(.horizontal, 12).padding(.top, 1) }
        .shadow(color: .black.opacity(0.9), radius: 30, y: 24)
        .onAppear { focus = graphic.words.first?.key }
        // Focusing a field selects all of it; put the caret at the end once it has focus.
        .onChange(of: focus) { _, key in
            guard let key else { return }
            Task { selection[key] = TextSelection(insertionPoint: (model.graphics.draft[key] ?? "").endIndex) }
        }
        .onExitCommand { model.graphics.cancelWords() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Words of \(graphic.spokenName)")
    }

    private func field(_ word: GraphicWord) -> some View {
        let text = model.graphics.draft[word.key] ?? graphic.text(word.key) ?? word.text
        return VStack(alignment: .leading, spacing: 6) {
            Text(word.label).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
            TextField("", text: Binding(get: { text }, set: { model.graphics.type($0, into: word) }), selection: Binding(get: { selection[word.key] }, set: { selection[word.key] = $0 }), axis: word.text.contains("\n") ? .vertical : .horizontal)
                .focused($focus, equals: word.key)
                .gateField(focused: focus == word.key || (model.isPreview && word.key == graphic.words.first?.key))
                .accessibilityLabel(word.label)
            if let max = word.maxLength {
                Text("\(text.count) / \(max)").font(Gate.Font.mono).foregroundStyle(Gate.Text.disabled).frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(text.count) of \(max) characters")
            }
        }
    }
}

/// Snapshots have no rendered video: the Title card drawn in SwiftUI at its 1080p layout, scaled.
struct GraphicPreview: View {
    let graphic: Graphic
    var visible = true
    var body: some View {
        GeometryReader { g in
            let k = g.size.height / 1080
            if visible, let word = graphic.words.first {
                Text(graphic.text(word.key) ?? word.text)
                    .font(Gate.Font.brand(size: 64 * k, width: 100, weight: 700)).tracking(-0.005 * 64 * k)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: g.size.width, height: 64 * k)
                    .position(x: g.size.width / 2, y: 742 * k + 32 * k)
            }
        }
        .allowsHitTesting(false)
    }
}

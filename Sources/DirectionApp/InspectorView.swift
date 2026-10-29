import SwiftUI
import DirectionCore

struct InspectorView: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            switch model.panel {
            case .feedback:
                FeedbackPanel(model: model)
            case .transcript:
                roomHeading("Transcript")
                TranscriptPanel(model: model)
            case .media:
                roomHeading("Footage")
                MediaSidebar(model: model)
            }
        }.background(Gate.Surface.ground)
    }
    private func roomHeading(_ title: String) -> some View {
        Text(title).font(Gate.Font.room).foregroundStyle(Gate.Text.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Gate.Space.s4).overlay(alignment: .bottom) { DirectionDivider() }
    }
}

struct SidebarEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: Gate.Space.s3) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
                .foregroundStyle(Gate.Text.tertiary).frame(height: Gate.Space.s8)
            Text(title).font(Gate.Font.body.weight(.medium)).foregroundStyle(Gate.Text.secondary)
            Text(detail).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                .lineSpacing(3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.horizontal, Gate.Space.s4)
    }
}

struct FeedbackPanel: View {
    @Bindable var model: EditorModel
    @FocusState private var composing: Bool
    private struct NumberedNote: Identifiable {
        let number: Int
        let comment: ReviewComment
        var id: String { comment.id }
    }
    private var notes: [NumberedNote] {
        model.comments.enumerated().compactMap { index, comment in
            guard comment.sequenceID == model.sequence?.id else { return nil }
            return NumberedNote(number: index + 1, comment: comment)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Gate.Space.s2) {
                Text("Notes on " + model.cutLabel).font(Gate.Font.room).foregroundStyle(Gate.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(notes.count) " + (notes.count == 1 ? "note" : "notes"))
                    .font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(Gate.Space.s4)
                .overlay(alignment: .bottom) { DirectionDivider() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(notes) { note in
                            FeedbackCard(model: model, comment: note.comment, number: note.number).id(note.id)
                        }
                        if notes.isEmpty {
                            SidebarEmptyState(symbol: "mappin", title: "No notes yet", detail: "Mark a moment in the picture, or select a range to leave a note.")
                                .padding(.top, Gate.Space.s14)
                        }
                    }.padding(.bottom, Gate.Space.s4)
                }.onChange(of: model.selectedCommentID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
            composer
        }
        .task(id: model.commentFocusRequest) {
            // A panel opened by seeking must mount its AppKit text view before requesting focus.
            await Task.yield()
            if !Task.isCancelled { focusIfRequested() }
        }
    }
    private func focusIfRequested() {
        guard model.commentFocusPending else { return }
        composing = true
        model.commentFocusPending = false
    }
    private var anchorTitle: String {
        switch model.commentScope {
        case "range": "Range"
        case "cut": "Whole cut"
        default: "Moment"
        }
    }
    private var anchorSymbol: String {
        switch model.commentScope {
        case "range": "arrow.left.and.right"
        case "cut": "film"
        default: "clock"
        }
    }
    private var anchorTime: String {
        switch model.commentScope {
        case "range": timecode(model.selectionStart, frameRate: model.sequence?.frameRate.value ?? 30) + " – " + timecode(model.selectionEnd, frameRate: model.sequence?.frameRate.value ?? 30)
        case "cut": timecode(model.duration, frames: false)
        default: timecode(model.position, frameRate: model.sequence?.frameRate.value ?? 30, frames: !model.playing)
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: Gate.Space.s3) {
            HStack(spacing: Gate.Space.s2) {
                Image(systemName: anchorSymbol).font(Gate.Font.caption)
                    .foregroundStyle(model.commentScope == "cut" ? Gate.Text.tertiary : Gate.Voice.director)
                Text(anchorTitle).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                Spacer(minLength: Gate.Space.s2)
                Text(anchorTime).font(Gate.Font.timecode)
                    .foregroundStyle(model.commentScope == "cut" ? Gate.Text.secondary : Gate.Voice.director)
            }.accessibilityElement(children: .combine)
            ZStack(alignment: .topLeading) {
                if model.commentDraft.isEmpty {
                    Text("What should change?").foregroundStyle(Gate.Text.tertiary)
                        .padding(.horizontal, Gate.Space.s3).padding(.top, 11).allowsHitTesting(false)
                }
                TextEditor(text: $model.commentDraft).scrollContentBackground(.hidden)
                    .padding(5).frame(height: 88).focused($composing).accessibilityLabel("Note text")
            }.font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                .directionField(cornerRadius: Gate.Radius.control)
                .overlay {
                    RoundedRectangle(cornerRadius: Gate.Radius.control)
                        .strokeBorder(composing ? Gate.Text.secondary : .clear, lineWidth: 1).allowsHitTesting(false)
                }
            if model.commentScope == "range" {
                Text("Drag the selection ends to adjust.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
            }
            HStack {
                Toggle("Whole cut", isOn: Binding(
                    get: { model.commentScope == "cut" },
                    set: { model.setWholeVideoComment($0) }
                ))
                .toggleStyle(.checkbox).font(Gate.Font.caption)
                .foregroundStyle(Gate.Text.secondary).accessibilityLabel("Note on whole cut")
                Spacer()
                Button("Add note", action: model.addComment).buttonStyle(QuietButton(prominent: true))
                    .disabled(model.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.duration == 0 || (model.commentScope == "range" && (model.selectionEnd <= model.selectionStart || model.selectionStart < 0 || model.selectionEnd > model.duration)))
            }
        }.padding(Gate.Space.s4).background(Gate.Surface.ground)
            .overlay(alignment: .top) { DirectionDivider() }
    }

}

struct FeedbackCard: View {
    @Bindable var model: EditorModel
    let comment: ReviewComment
    let number: Int
    private var anchorLabel: String {
        if let range = comment.range { return timecode(range.start.seconds, frameRate: model.sequence?.frameRate.value ?? 30) + " – " + timecode(range.end.seconds, frameRate: model.sequence?.frameRate.value ?? 30) }
        return comment.time.map { timecode($0.seconds, frameRate: model.sequence?.frameRate.value ?? 30) } ?? "Whole cut"
    }
    var body: some View {
        HStack(alignment: .top, spacing: Gate.Space.s2) {
            Text("\(number)").font(Gate.Font.noteNumber).foregroundStyle(Gate.Voice.director)
                .frame(width: 30, alignment: .leading).accessibilityLabel("Note \(number)")
            VStack(alignment: .leading, spacing: Gate.Space.s2) {
                HStack(spacing: Gate.Space.s2) {
                    Button(anchorLabel) { model.seekComment(comment) }.buttonStyle(.plain)
                        .font(Gate.Font.timecode).foregroundStyle(Gate.Text.secondary)
                    Spacer(minLength: Gate.Space.s1)
                    NoteActorMark(author: comment.author)
                    if comment.region != nil {
                        Image(systemName: "viewfinder").font(Gate.Font.caption).foregroundStyle(Gate.Voice.director)
                            .help("Note marks a region of the frame").accessibilityLabel("Frame region")
                    }
                }
                Text(comment.text).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let reply = comment.replies.last {
                    VStack(alignment: .leading, spacing: Gate.Space.s1) {
                        NoteActorMark(author: reply.author, showsName: true)
                        Text(reply.text).font(Gate.Font.body).foregroundStyle(Gate.Text.secondary).lineSpacing(4)
                    }.padding(.leading, Gate.Space.s3)
                        .overlay(alignment: .leading) { DirectionDivider(vertical: true).frame(width: 1) }
                        .fixedSize(horizontal: false, vertical: true)
                }
                if comment.status != "open" || comment.editRevision != model.displayedProject?.editRevision {
                    HStack(spacing: Gate.Space.s2) {
                        if comment.status != "open" { Text(comment.status == "accepted" ? "Accepted" : "Ready to review") }
                        if comment.editRevision != model.displayedProject?.editRevision { Text("Earlier cut") }
                        Spacer()
                        if comment.status == "addressed" { Button("Accept") { model.accept(comment) } }
                        if comment.status != "open" { Button("Reopen") { model.reopen(comment) } }
                    }.buttonStyle(.plain).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                }
            }
        }.padding(.horizontal, Gate.Space.s4).padding(.vertical, Gate.Space.s3)
            .background(model.selectedCommentID == comment.id ? Gate.Surface.panel : .clear)
            .overlay(alignment: .leading) {
                if model.selectedCommentID == comment.id {
                    Rectangle().fill(Gate.Voice.director).frame(width: 2)
                }
            }
            .overlay(alignment: .bottom) { DirectionDivider() }
    }
}

private struct NoteActorMark: View {
    let author: String
    var showsName = false
    private var isAgent: Bool { author.localizedCaseInsensitiveContains("agent") }
    private var isDirector: Bool { author.caseInsensitiveCompare("Director") == .orderedSame }
    var body: some View {
        HStack(spacing: Gate.Space.s1) {
            Image(systemName: isAgent ? "diamond.fill" : (isDirector ? "mappin" : "person.fill"))
                .font(.system(size: isAgent ? 7 : 9, weight: .medium))
                .foregroundStyle(isAgent ? Gate.Voice.agent : (isDirector ? Gate.Voice.director : Gate.Text.tertiary))
            if showsName { Text(author).font(Gate.Font.caption).foregroundStyle(isAgent ? Gate.Voice.agent : Gate.Text.tertiary) }
        }.help(author).accessibilityElement(children: .ignore).accessibilityLabel(author)
    }
}

struct TranscriptPanel: View {
    @Bindable var model: EditorModel
    @State private var editText = true
    private var audioAssets: [MediaAsset] { (model.displayedProject?.assets ?? []).filter { !$0.audio.isEmpty } }
    var body: some View {
        VStack(alignment: .leading, spacing: Gate.Space.s4) {
            if !model.words.isEmpty {
                HStack {
                    Button(editText ? "Select words" : "Edit text") { editText.toggle() }.buttonStyle(QuietButton())
                    Spacer()
                    if !model.isWorkingCut { Button("Latest cut") { model.followWorkingCut() }.buttonStyle(.plain) }
                }
                if editText {
                    TextEditor(text: $model.transcriptDraft).font(Gate.Font.body).lineSpacing(8).scrollContentBackground(.hidden)
                        .padding(10).directionField(cornerRadius: 10)
                        .accessibilityLabel("Editable transcript").disabled(!model.canEdit)
                    HStack {
                        Text("Delete text to cut footage").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                        Spacer()
                        Button("Apply", action: model.applyTranscriptDraft).buttonStyle(QuietButton(prominent: true)).disabled(!model.canEdit || model.transcriptDraft == model.words.map(\.text).joined(separator: " "))
                    }
                } else {
                    ScrollView {
                        FlowLayout(spacing: 3) {
                            ForEach(model.words) { word in
                                Button {
                                    model.seek(word.range.start.seconds)
                                    if model.selectedWords.contains(word.id) { model.selectedWords.remove(word.id) } else { model.selectedWords.insert(word.id) }
                                } label: {
                                    Text(word.text).font(Gate.Font.body)
                                        .foregroundStyle(model.selectedWords.contains(word.id) ? Gate.Voice.directorInk : Gate.Text.primary)
                                        .padding(.horizontal, 4).padding(.vertical, 6)
                                        .background(model.selectedWords.contains(word.id) ? Gate.Voice.director : .clear, in: RoundedRectangle(cornerRadius: 4))
                                }.buttonStyle(.plain).accessibilityLabel(word.text + " at " + timecode(word.range.start.seconds, frameRate: model.sequence?.frameRate.value ?? 30))
                            }
                        }
                    }
                    HStack {
                        if !model.selectedWords.isEmpty { Button("Clear") { model.selectedWords = [] }.buttonStyle(.plain).foregroundStyle(Gate.Text.tertiary) }
                        Spacer()
                        Button("Remove \(model.selectedWords.count) words", action: model.deleteSelectedWords).buttonStyle(QuietButton(prominent: true)).disabled(model.selectedWords.isEmpty || !model.canEdit)
                    }
                }
            } else {
                Spacer()
                SidebarEmptyState(symbol: "text.alignleft", title: "No transcript yet", detail: "Transcribe a source, then remove words to cut the footage.")
                transcriptionControls.padding(.top, 8)
                Text("Transcribed on this Mac").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).frame(maxWidth: .infinity)
                Spacer()
            }
        }.padding(.horizontal, Gate.Space.s4).padding(.bottom, Gate.Space.s4)
    }
    private var transcriptionControls: some View {
        VStack(spacing: 12) {
            Picker("Source", selection: Binding(get: { model.selectedAssetID ?? audioAssets.first?.id ?? "" }, set: { model.selectedAssetID = $0 })) {
                ForEach(audioAssets) { asset in Text(asset.name).tag(asset.id) }
            }.labelsHidden().accessibilityLabel("Transcription source")
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Gate.Text.tertiary)
                TextField("Language", text: $model.transcriptionLanguage).textFieldStyle(.plain).accessibilityLabel("Transcription language")
            }.font(Gate.Font.control).padding(10).directionField(cornerRadius: 8)
            Menu {
                if let asset = audioAssets.first(where: { $0.id == model.selectedAssetID }) ?? audioAssets.first {
                    ForEach(asset.audio) { track in Button(track.label) { model.transcribe(asset, trackID: track.id) } }
                }
            } label: { Text("Transcribe").frame(maxWidth: .infinity) }.menuStyle(.borderlessButton).buttonStyle(QuietButton(prominent: true)).disabled(audioAssets.isEmpty || !model.canEdit)
        }
    }
}
struct FlowLayout: Layout {
    var spacing: CGFloat = 3
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { layout(width: proposal.width ?? 300, subviews: subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
        for (i, point) in result.positions.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func layout(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, positions: [CGPoint] = []
        for view in subviews { let size = view.sizeThatFits(.unspecified); if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }; positions.append(.init(x: x, y: y)); x += size.width + spacing; row = max(row, size.height) }
        return (.init(width: width, height: y + row), positions)
    }
}

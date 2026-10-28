import SwiftUI
import DirectionCore

struct InspectorView: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Button { model.panel = tab } label: {
                        Text(tab.rawValue).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(model.panel == tab ? Palette.text : Palette.muted)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(model.panel == tab ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).accessibilityLabel(tab.rawValue)
                }
            }.padding(16)
            switch model.panel {
            case .feedback: FeedbackPanel(model: model)
            case .transcript: TranscriptPanel(model: model)
            case .media: MediaSidebar(model: model)
            }
        }.background(Palette.panel)
    }
}

struct SidebarEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.muted).frame(height: 34)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .lineSpacing(4).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.horizontal, 18)
    }
}

struct FeedbackPanel: View {
    @Bindable var model: EditorModel
    @FocusState private var composing: Bool
    private var relevant: [ReviewComment] { model.comments.filter { $0.sequenceID == model.sequence?.id } }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(relevant) { comment in FeedbackCard(model: model, comment: comment).id(comment.id) }
                        if relevant.isEmpty {
                            SidebarEmptyState(symbol: "text.bubble", title: "No comments yet", detail: "Click the review bar to mark a moment. Drag its range handle to select a section.")
                                .padding(.top, 64)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 16)
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
        case "cut": "Whole video"
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
        case "range": timecode(model.selectionStart) + " – " + timecode(model.selectionEnd)
        case "cut": timecode(model.duration)
        default: timecode(model.position)
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: anchorSymbol).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Text(anchorTitle).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                Text(anchorTime).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.text)
            }
            .accessibilityElement(children: .combine)
            ZStack(alignment: .topLeading) {
                if model.commentDraft.isEmpty {
                    Text("Leave a comment…").foregroundStyle(Palette.muted)
                        .padding(.horizontal, 10).padding(.top, 11).allowsHitTesting(false)
                }
                TextEditor(text: $model.commentDraft).scrollContentBackground(.hidden)
                    .padding(5).frame(height: 88).focused($composing).accessibilityLabel("Comment text")
            }.font(.system(size: 13)).directionField(cornerRadius: 7)
            if model.commentScope == "range" {
                Text("Drag the selection ends to adjust.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            HStack {
                Toggle("Whole video", isOn: Binding(
                    get: { model.commentScope == "cut" },
                    set: { model.setWholeVideoComment($0) }
                ))
                .toggleStyle(.checkbox).font(.system(size: 11))
                .foregroundStyle(Palette.muted).accessibilityLabel("Comment on whole video")
                Spacer()
                Button("Comment", action: model.addComment).buttonStyle(QuietButton(prominent: true))
                    .disabled(model.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.duration == 0 || (model.commentScope == "range" && (model.selectionEnd <= model.selectionStart || model.selectionStart < 0 || model.selectionEnd > model.duration)))
            }
        }.padding(16).directionSurface(cornerRadius: 10, elevated: true)
            .padding(.horizontal, 16).padding(.bottom, 16)
    }

}

struct FeedbackCard: View {
    @Bindable var model: EditorModel
    let comment: ReviewComment
    private var anchorLabel: String {
        if let range = comment.range { return timecode(range.start.seconds) + " – " + timecode(range.end.seconds) }
        return comment.time.map { timecode($0.seconds) } ?? "Whole video"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(comment.author).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                Spacer(minLength: 4)
                Button(anchorLabel) { model.seekComment(comment) }.buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            Text(comment.text).font(.system(size: 13, weight: .regular)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let reply = comment.replies.last {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(Palette.line).frame(width: 1)
                    Text(reply.text).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
                }.fixedSize(horizontal: false, vertical: true)
            }
            if comment.status != "open" || comment.editRevision != model.displayedProject?.editRevision {
                HStack {
                    if comment.status != "open" { Text(comment.status == "accepted" ? "Accepted" : "Ready to review").foregroundStyle(Palette.muted) }
                    if comment.editRevision != model.displayedProject?.editRevision { Text("Earlier edit").foregroundStyle(Palette.muted) }
                    Spacer()
                    if comment.status == "addressed" { Button("Accept") { model.accept(comment) } }
                    if comment.status != "open" { Button("Reopen") { model.reopen(comment) }.foregroundStyle(Palette.muted) }
                }.buttonStyle(.plain).font(.system(size: 10))
            }
        }.padding(.horizontal, 12).padding(.vertical, 15)
            .background(model.selectedCommentID == comment.id ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .leading) {
                if model.selectedCommentID == comment.id {
                    Rectangle().fill(Palette.text.opacity(0.48)).frame(width: 2).padding(.vertical, 15)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 12)
            }
    }

}

struct TranscriptPanel: View {
    @Bindable var model: EditorModel
    @State private var editText = true
    private var audioAssets: [MediaAsset] { (model.displayedProject?.assets ?? []).filter { !$0.audio.isEmpty } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.words.isEmpty {
                HStack {
                    Button(editText ? "Select words" : "Edit text") { editText.toggle() }.buttonStyle(QuietButton())
                    Spacer()
                    if !model.isWorkingCut { Button("Edit latest") { model.followWorkingCut() }.buttonStyle(.plain) }
                }
                if editText {
                    TextEditor(text: $model.transcriptDraft).font(.system(size: 15)).lineSpacing(8).scrollContentBackground(.hidden)
                        .padding(10).directionField(cornerRadius: 10)
                        .accessibilityLabel("Editable transcript").disabled(!model.canEdit)
                    HStack {
                        Text("Delete text to cut footage").font(.system(size: 10)).foregroundStyle(Palette.muted)
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
                                    Text(word.text).font(.system(size: 15))
                                        .foregroundStyle(model.selectedWords.contains(word.id) ? Color.black : Palette.text)
                                        .padding(.horizontal, 4).padding(.vertical, 6)
                                        .background(model.selectedWords.contains(word.id) ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
                                }.buttonStyle(.plain).accessibilityLabel(word.text + " at " + timecode(word.range.start.seconds))
                            }
                        }
                    }
                    HStack {
                        if !model.selectedWords.isEmpty { Button("Clear") { model.selectedWords = [] }.buttonStyle(.plain).foregroundStyle(Palette.muted) }
                        Spacer()
                        Button("Remove \(model.selectedWords.count) words", action: model.deleteSelectedWords).buttonStyle(QuietButton(prominent: true)).disabled(model.selectedWords.isEmpty || !model.canEdit)
                    }
                }
            } else {
                Spacer()
                SidebarEmptyState(symbol: "text.alignleft", title: "No transcript yet", detail: "Transcribe a source, then remove words to cut the footage.")
                transcriptionControls.padding(.top, 8)
                Text("Transcribed on your Mac").font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                Spacer()
            }
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }
    private var transcriptionControls: some View {
        VStack(spacing: 12) {
            Picker("Source", selection: Binding(get: { model.selectedAssetID ?? audioAssets.first?.id ?? "" }, set: { model.selectedAssetID = $0 })) {
                ForEach(audioAssets) { asset in Text(asset.name).tag(asset.id) }
            }.labelsHidden().accessibilityLabel("Transcription source")
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Palette.muted)
                TextField("Language", text: $model.transcriptionLanguage).textFieldStyle(.plain).accessibilityLabel("Transcription language")
            }.font(.system(size: 12)).padding(10).directionField(cornerRadius: 8)
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

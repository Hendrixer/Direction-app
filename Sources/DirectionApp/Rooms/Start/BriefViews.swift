import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import DirectionCore

/// Frame 03: the brief, beside what the editor does with it. Continue (⌘↩) is the titlebar's primary.
struct OnboardingBriefStep: View {
    @Bindable var model: FilmModel
    var body: some View {
        let session = OnboardingSession.of(model)
        HStack(spacing: 0) {
            ScrollView {
                BriefForm(model: model, title: Bindable(session).title, brief: Bindable(session).brief, missing: session.missing)
                    .frame(width: 640)
                    .padding(.top, 40).padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            BriefAside().frame(width: 380)
        }
        .background(Gate.Surface.ground)
    }
}

/// Film › Brief (⌘B) after the first step: the same form in a sheet, with Save brief.
struct BriefSheet: View {
    @Bindable var model: FilmModel
    @State private var title: String
    @State private var brief: Brief
    @State private var missing: Set<OnboardingSession.Field> = []

    init(model: FilmModel) {
        self.model = model
        _title = State(initialValue: model.isUntitled ? "" : model.filmName)
        _brief = State(initialValue: model.brief)
    }

    var body: some View {
        AttachedSheet(width: 720, onDismiss: { model.sheet = nil }) {
            SheetHeader(title: "The brief", subtitle: model.latestCut.map { "Changes apply from the next cut. \($0.name) was made with the earlier brief." } ?? "The editor reads this first and checks against it last.")
            ScrollView {
                BriefForm(model: model, title: $title, brief: $brief, missing: missing, compact: true)
                    .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 22)
            }
            .frame(maxHeight: 600)
            SheetFooter {
                Text("Must-keeps are never cut, by anyone but you.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            } trailing: {
                Button("Cancel") { model.sheet = nil }.buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button("Save brief", action: save).buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func save() {
        missing = Set([(OnboardingSession.Field.title, title), (.logline, brief.logline), (.feeling, brief.feeling)].filter { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.0))
        guard missing.isEmpty else { return }
        let old = model.brief
        model.renameFilm(title)
        if brief != old {
            model.saveBrief(brief)
            model.registerUndo("Edit Brief") { $0.saveBrief(old) }
        }
        model.sheet = nil
    }
}

/// The questions, in visual order: title, logline, feeling, length and audience, style, must keep, references, avoid.
struct BriefForm: View {
    var model: FilmModel
    @Binding var title: String
    @Binding var brief: Brief
    var missing: Set<OnboardingSession.Field>
    var compact = false
    @FocusState private var focus: Field?
    /// Where the caret is in the fields that take "@" (techniques.md › The library).
    @State private var feelingCaret: TextSelection?
    @State private var avoidCaret: TextSelection?
    @State private var adding = false
    @State private var newTag = ""
    @State private var minText = ""
    @State private var maxText = ""
    @State private var dropTargeted = false
    /// A reference the director wants a style made from.
    @State private var styleFrom: BriefReference?

    enum Field: Hashable { case title, logline, feeling, lengthMin, lengthMax, audience, tag, avoid }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Title")
                TextField("", text: $title)
                    .textFieldStyle(.plain).font(Gate.Font.brand(size: compact ? 28 : 34, width: 125, weight: 800)).foregroundStyle(Gate.Text.primary)
                    .startPlaceholder("Untitled film", shown: title.isEmpty, font: Gate.Font.brand(size: compact ? 28 : 34, width: 125, weight: 800), inset: .init())
                    .focused($focus, equals: .title)
                    .padding(.bottom, 11)
                    .overlay(alignment: .bottom) { (missing.contains(.title) && title.isEmpty ? Gate.State.alert : Gate.Line.strong).frame(height: 1) }
                    .accessibilityLabel("Title")
                if missing.contains(.title) && title.isEmpty { needed }
            }
            question("What is it, in one sentence?", "Required") {
                TextField("", text: $brief.logline, axis: .vertical)
                    .modifier(BriefBigField(focused: focus == .logline, error: missing.contains(.logline) && brief.logline.isEmpty, minHeight: 48))
                    .startPlaceholder("One sentence: who, and what happens.", shown: brief.logline.isEmpty, font: .system(size: 17), alignment: .topLeading, inset: .init(top: 12, leading: 14, bottom: 0, trailing: 14))
                    .focused($focus, equals: .logline)
                    .accessibilityLabel("What is it, in one sentence?").accessibilityHint("Required")
                if missing.contains(.logline) && brief.logline.isEmpty { needed }
            }
            question("How should it feel?", "Required") {
                TextField("", text: $brief.feeling, selection: $feelingCaret, axis: .vertical)
                    .lineLimit(3...)
                    .libraryMentions(text: $brief.feeling, selection: $feelingCaret)
                    .modifier(BriefBigField(focused: focus == .feeling, error: missing.contains(.feeling) && brief.feeling.isEmpty, minHeight: 88))
                    .startPlaceholder("Tired, then proud. Quiet, not triumphant.", shown: brief.feeling.isEmpty, font: .system(size: 17), alignment: .topLeading, inset: .init(top: 12, leading: 14, bottom: 0, trailing: 14))
                    .focused($focus, equals: .feeling)
                    .accessibilityLabel("How should it feel?").accessibilityHint("Required")
                if missing.contains(.feeling) && brief.feeling.isEmpty { needed }
                else { Text("Talk the way you'd talk to an editor. Feelings are better than instructions.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).frame(minHeight: 17) }
                MentionChips(text: brief.feeling, footage: model.footageNames)
            }
            HStack(alignment: .top, spacing: 20) {
                question("Length", nil) {
                    HStack(spacing: 8) {
                        lengthField($minText, .lengthMin, label: "Shortest length") { brief.lengthMin = $0 }
                        Text("to").font(Gate.Font.body).foregroundStyle(Gate.Text.disabled)
                        lengthField($maxText, .lengthMax, label: "Longest length") { brief.lengthMax = $0 }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                question("Who's it for?", "Optional") {
                    TextField("", text: Binding(get: { brief.audience ?? "" }, set: { brief.audience = $0.isEmpty ? nil : $0 }))
                        .gateField(focused: focus == .audience).startPlaceholder("People who make things", shown: (brief.audience ?? "").isEmpty).focused($focus, equals: .audience)
                        .accessibilityLabel("Who's it for?")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            question("Style", "Optional. How your videos look, sound and move") { BriefStylePicker(model: model, style: $brief.style) }
            question("Must keep", "The editor will never cut these") { mustKeep }
            question("References", "Drop clips, stills or links. Say why.", accessory: {
                Button("Add\u{2026}", action: chooseReference).buttonStyle(.gate(.ghost, .small)).help("Add a clip or still")
            }) { references }
            question("Avoid", "Optional") {
                TextField("", text: Binding(get: { brief.avoid ?? "" }, set: { brief.avoid = $0.isEmpty ? nil : $0 }), selection: $avoidCaret)
                    .libraryMentions(text: Binding(get: { brief.avoid ?? "" }, set: { brief.avoid = $0.isEmpty ? nil : $0 }), selection: $avoidCaret)
                    .gateField(focused: focus == .avoid).startPlaceholder("Stock music swells", shown: (brief.avoid ?? "").isEmpty).focused($focus, equals: .avoid)
                    .accessibilityLabel("Avoid")
                MentionChips(text: brief.avoid ?? "", footage: model.footageNames)
            }
        }
        .onAppear {
            minText = brief.lengthMin.map(Timecode.duration) ?? ""
            maxText = brief.lengthMax.map(Timecode.duration) ?? ""
            if title.isEmpty && !model.isPreview { focus = .title }
        }
    }

    private var needed: some View { Text("The editor needs this to start.").font(Gate.Font.small).foregroundStyle(Gate.State.alert) }

    private func question<Content: View>(_ q: String, _ qualifier: String?, @ViewBuilder content: () -> Content) -> some View {
        question(q, qualifier, accessory: { EmptyView() }, content: content)
    }

    private func question<Accessory: View, Content: View>(_ q: String, _ qualifier: String?, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(q).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                if let qualifier { Text(qualifier).font(Gate.Font.small).foregroundStyle(Gate.Text.disabled) }
                Spacer(minLength: 0)
                accessory().frame(height: 17)
            }
            .frame(minHeight: 19)
            content()
        }
    }

    private func lengthField(_ text: Binding<String>, _ field: Field, label: String, set: @escaping (Double?) -> Void) -> some View {
        TextField("", text: text)
            .font(.system(size: 13, design: .monospaced)).gateField(focused: focus == field)
            .startPlaceholder("0:00", shown: text.wrappedValue.isEmpty, font: .system(size: 13, design: .monospaced))
            .frame(width: 76).focused($focus, equals: field)
            .onChange(of: text.wrappedValue) { _, v in set(Self.seconds(v)) }
            .accessibilityLabel(label)
    }

    /// "3:00" or "3" (minutes) → seconds.
    static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let n = parts.compactMap { $0 }
        return n.count == 1 ? n[0] * 60 : n.dropLast().reduce(0) { $0 * 60 + $1 } * 60 + n.last!
    }

    // MARK: Must keep

    private var mustKeep: some View {
        BriefFlow(spacing: 6) {
            ForEach(Array(brief.mustKeep.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 6) {
                    Image(systemName: Self.isQuote(item) ? "quote.opening" : "film").font(.system(size: 9.5)).foregroundStyle(Gate.Text.tertiary)
                    Text(item).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineLimit(1)
                    Button { brief.mustKeep.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)).foregroundStyle(Gate.Text.disabled).frame(width: 12, height: 12).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Remove \(item)")
                }
                .padding(.leading, 10).padding(.trailing, 8).frame(height: 26)
                .background(Capsule().fill(Gate.Surface.raised).overlay(Capsule().strokeBorder(Gate.Line.subtle, lineWidth: 1)))
            }
            if adding {
                TextField("A line or a moment", text: $newTag).textFieldStyle(.plain).font(.system(size: 12.5)).focused($focus, equals: .tag)
                    .frame(width: 220).padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(Gate.Surface.sunken).overlay(Capsule().strokeBorder(Gate.Text.secondary, lineWidth: 1)))
                    .onSubmit { addTag() }
                    .onExitCommand { adding = false; newTag = "" }
            } else {
                Button { adding = true; focus = .tag } label: {
                    HStack(spacing: 6) { Image(systemName: "plus").font(.system(size: 9, weight: .semibold)); Text("Add") }
                        .font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).padding(.horizontal, 10).frame(height: 26)
                        .overlay(Capsule().strokeBorder(Gate.Line.subtle, lineWidth: 1)).contentShape(Capsule())
                }
                .buttonStyle(.plain).help("Add a line or moment the editor must keep")
            }
        }
        .dropDestination(for: String.self) { items, _ in
            let lines = items.flatMap { $0.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) } }.filter { !$0.isEmpty && model.dailies.takes[$0] == nil }
            let takes = items.flatMap { $0.split(separator: "\n").map(String.init) }.compactMap { model.dailies.takes[$0] }.map { "\(model.dailiesLabel($0)), \(model.dailiesCaption($0))" }
            brief.mustKeep += lines + takes
            return !(lines + takes).isEmpty
        }
    }

    private func addTag() {
        let text = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && !brief.mustKeep.contains(text) { brief.mustKeep.append(text) }
        newTag = ""
        if text.isEmpty { adding = false }
    }

    /// A line of dialogue (ends like a sentence) shows a quote; a moment shows a film icon.
    static func isQuote(_ s: String) -> Bool { s.last.map { ".?!\u{201D}\"".contains($0) } ?? false }

    // MARK: References

    private var references: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(brief.references.enumerated()), id: \.element.id) { i, ref in
                BriefReferenceCard(reference: $brief.references[i], model: model, art: [.night, .room, .dusk, .day, .hands][i % 5], preview: model.isPreview,
                                   canMoveUp: i > 0, canMoveDown: i + 1 < brief.references.count) { action in
                    switch action {
                    case .up: brief.references.swapAt(i, i - 1)
                    case .down: brief.references.swapAt(i, i + 1)
                    case .remove: brief.references.remove(at: i)
                    case .makeStyle: styleFrom = ref
                    }
                }
            }
            if brief.references.isEmpty {
                Text("Drop a clip, a still or a link here.").font(Gate.Font.small).foregroundStyle(Gate.Text.disabled)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.Line.strong, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
        }
        .padding(4).padding(-4)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.Text.primary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).padding(-4).opacity(dropTargeted ? 1 : 0))
        .sheet(item: $styleFrom) { ref in
            StyleFromVideoSheet(model: model, videos: [ref.path.map { $0.contains("://") ? StyleVideo(link: $0) : StyleVideo(file: URL(fileURLWithPath: $0)) } ?? StyleVideo()], ask: ref.why) { styleFrom = nil }
        }
        .dropDestination(for: URL.self) { urls, _ in
            brief.references += urls.map(Self.reference)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    private func chooseReference() {
        let panel = NSOpenPanel(); panel.title = "Add a reference"; panel.allowedContentTypes = [.movie, .image]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        brief.references += panel.urls.map(Self.reference)
    }

    static func reference(_ url: URL) -> BriefReference {
        url.isFileURL ? BriefReference(title: url.deletingPathExtension().lastPathComponent, why: "", path: url.path)
                      : BriefReference(title: (url.host() ?? "") + url.path(), why: "", path: url.absoluteString)
    }
}

extension View {
    /// A text-4 placeholder over an empty field; TextField prompts don't take Gate colors on macOS.
    func startPlaceholder(_ text: String, shown: Bool, font: Font = Gate.Font.body, alignment: Alignment = .leading, inset: EdgeInsets = .init(top: 0, leading: 10, bottom: 0, trailing: 10)) -> some View {
        overlay(alignment: alignment) {
            if shown { Text(text).font(font).foregroundStyle(Gate.Text.disabled).lineLimit(1).padding(inset).allowsHitTesting(false).accessibilityHidden(true) }
        }
    }
}

/// 17 pt text in a sunken field, 12/14 padding.
private struct BriefBigField: ViewModifier {
    var focused: Bool
    var error: Bool
    var minHeight: CGFloat
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(.system(size: 17)).foregroundStyle(Gate.Text.primary).lineSpacing(6)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(GateFieldBackground(focused: focused, error: error))
    }
}

/// A reference: thumbnail, what it is, why. Editable in place; the menu reorders and removes.
private struct BriefReferenceCard: View {
    @Binding var reference: BriefReference
    var model: FilmModel
    var art: FootageArt
    var preview: Bool
    var canMoveUp: Bool
    var canMoveDown: Bool
    var act: (Action) -> Void
    @State private var image: NSImage?
    enum Action { case up, down, remove, makeStyle }
    private var isVideo: Bool { reference.path.map(ReferenceVideo.isVideo) ?? false }
    /// What Direction measured in it, once it has (styles.md › In the brief).
    private var study: VideoStudy? { preview ? nil : model.store.flatMap { ReferenceVideo.study(reference, film: $0.url) } }

    var body: some View {
        HStack(spacing: 12) {
            thumb.frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 3) {
                TextField("Reference", text: $reference.title).textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.primary)
                TextField("", text: $reference.why).textFieldStyle(.plain).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                    .startPlaceholder("Say why\u{2026}", shown: reference.why.isEmpty, font: Gate.Font.small, inset: .init())
                if isVideo { studyLine }
            }
            Menu {
                if isVideo { Button("Make a Style from This\u{2026}") { act(.makeStyle) }.disabled(model.learning != nil); Divider() }
                Button("Move Up") { act(.up) }.disabled(!canMoveUp)
                Button("Move Down") { act(.down) }.disabled(!canMoveDown)
                if let path = reference.path, !path.contains("://") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
                Divider()
                Button("Remove", role: .destructive) { act(.remove) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Text.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("More")
        }
        .padding(8)
        .gatePanel(Gate.Radius.card)
        .task(id: reference.path) { await loadImage(); if isVideo, !preview { model.studyReference(reference) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reference: \(reference.title). \(reference.why)")
    }

    /// Studying it, what was measured, or why it couldn't be.
    @ViewBuilder private var studyLine: some View {
        if model.studyingReferences.contains(reference.id) {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Studying how it\u{2019}s cut\u{2026}") }.font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
        } else if let study {
            Text(study.summary).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        } else if let problem = model.referenceProblems[reference.id] {
            HStack(spacing: 6) {
                Text("Couldn\u{2019}t study it: \(problem)").font(Gate.Font.caption).foregroundStyle(Gate.State.alert).lineLimit(2)
                Button("Try Again") { model.studyReference(reference) }.buttonStyle(.gate(.ghost, .small))
            }
        }
    }

    @ViewBuilder private var thumb: some View {
        if preview { FootageArtView(art: art) }
        else if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
        else {
            ZStack { Gate.Surface.sunken; Image(systemName: reference.path?.contains("://") == true ? "link" : "photo").font(.system(size: 14)).foregroundStyle(Gate.Text.disabled) }
        }
    }

    /// Stills load as they are; clips show their first frame.
    private func loadImage() async {
        guard !preview, let path = reference.path, !path.contains("://") else { image = nil; return }
        if let still = NSImage(contentsOfFile: path) { image = still; return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 320, height: 320)
        if let (cg, _) = try? await generator.image(at: .zero) { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
    }
}

/// How the editor uses the brief (frame 03's aside).
private struct BriefAside: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DailiesEditorLabel(text: "How the editor uses this")
            Text("Your brief is the first thing it reads, and the last thing it checks.").font(Gate.Font.brandS).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                DailiesSayLine(text: "It picks takes for the assembly with this feeling in mind.", detail: "Suggestions in Dailies say which part of the brief they serve.")
                DailiesSayLine(text: "When a note seems to fight the brief, it asks you before cutting.", detail: "\u{201C}Note 6 shortens the scene you asked to keep quiet. Still do it?\u{201D}")
                DailiesSayLine(text: "Must-keeps are never cut, by anyone but you.")
            }
            Hairline()
            Text("You can change the brief any time from Film \u{203A} Brief (\u{2318}B). Changes apply from the next cut.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28).padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Gate.Surface.sunken)
        .hairlineBorder(.leading)
    }
}

/// Tags that wrap onto new lines.
struct BriefFlow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing; row = max(row, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

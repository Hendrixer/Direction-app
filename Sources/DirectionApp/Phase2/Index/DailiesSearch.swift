import SwiftUI
import AppKit
import DirectionCore

// Frame 60: search footage in Dailies (specs/footage-index.md › 60). ⌘F focuses the field at the
// top of the take area; results replace the take grid, grouped by scene; esc goes back.

struct DailiesSearchView: View {
    @Bindable var model: FilmModel
    @Environment(\.dailiesPreview) private var preview
    @FocusState private var fieldFocused: Bool

    private var index: FootageIndexModel { model.index }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if index.searchedQuery.isEmpty {
                    EmptyView()
                } else if index.results.isEmpty {
                    empty
                } else {
                    ForEach(Array(index.groups(model).enumerated()), id: \.offset) { _, group in groupBlock(group.scene, group.hits) }
                }
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .onAppear { if !model.isPreview { fieldFocused = true } }
        .onChange(of: index.searchFocus) { _, _ in fieldFocused = true }
        .onExitCommand { index.clearSearch() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                field
                if !index.searchedQuery.isEmpty {
                    Text(countLine).font(.system(size: 13)).foregroundStyle(Gate.Text.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    GateSwitch(isOn: Binding(get: { index.circledOnly }, set: { index.circledOnly = $0; index.search(model, now: true) })).scaleEffect(0.85)
                    Text("Circled only").font(.system(size: 12)).foregroundStyle(Gate.Text.tertiary)
                }
                .accessibilityElement(children: .combine)
            }
            if index.stillLooking > 0 && !index.searchedQuery.isEmpty {
                (Text("Still looking at ") + Text(String(index.stillLooking)).font(.system(size: 11.5, design: .monospaced)).foregroundColor(Gate.Text.secondary) + Text(" takes. Results will grow."))
                    .font(.system(size: 12)).foregroundStyle(Gate.Text.tertiary)
            }
        }
    }

    private var countLine: String {
        let n = index.results.count
        return "\(n) \(n == 1 ? "shot" : "shots") for \u{201C}\(index.searchedQuery)\u{201D}" + (index.wordsOnly ? " in the words" : "")
    }

    /// `.input` with a magnifier, 300 wide, placeholder "Search footage". Typing searches after 250 ms.
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
            TextField("", text: Binding(get: { index.query }, set: { index.query = $0; index.wordsOnly = false; index.search(model) }), prompt: Text("Search footage").foregroundStyle(Gate.Text.disabled))
                .textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                .focused($fieldFocused)
                .onSubmit { openFirst() }
                .onExitCommand { index.clearSearch() }
            if !index.query.isEmpty {
                Button { index.clearSearch() } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Gate.Steel.ramp[2])
                        .frame(width: 16, height: 16).background(Circle().fill(Gate.Steel.ramp[6]))
                }
                .buttonStyle(.plain).help("Clear the search (Esc)")
            }
        }
        .padding(.horizontal, 10).frame(width: 300, height: Gate.Size.control)
        .background(GateFieldBackground(focused: fieldFocused || (model.isPreview && !index.query.isEmpty)))
        .accessibilityElement(children: .contain).accessibilityLabel("Search footage")
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("No shots look like \u{201C}\(index.searchedQuery)\u{201D}").font(Gate.Font.body).foregroundStyle(Gate.Text.secondary)
            if !index.wordsOnly {
                Button("Search words only") { index.wordsOnly = true; index.search(model, now: true) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Gate.Text.secondary).underline()
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }

    // MARK: Results

    private func groupBlock(_ scene: DailiesScene?, _ hits: [FootageSearch.Hit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(scene.map { String($0.number) } ?? "\u{2014}").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                Text(scene?.title ?? "Not in a scene").font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
                Spacer(minLength: 8)
                Text("\(hits.count) \(hits.count == 1 ? "shot" : "shots")").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 4), alignment: .leading, spacing: 18) {
                ForEach(hits, id: \.shotID) { hit in DailiesSearchResult(model: model, hit: hit) { open(hit) } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scene?.label ?? "Not in a scene")
    }

    private func open(_ hit: FootageSearch.Hit) {
        index.openAt = (hit.assetID, hit.start)
        model.openTakeID = hit.assetID
    }
    private func openFirst() { if let first = index.groups(model).first?.hits.first { open(first) } }
}

/// A take card showing the matching shot: its keyframe, the take code, the shot's range, one line
/// with the matched words in text-1, and why it matched (picture or words).
struct DailiesSearchResult: View {
    var model: FilmModel
    var hit: FootageSearch.Hit
    var open: () -> Void
    @Environment(\.dailiesPreview) private var preview

    var body: some View {
        let take = model.dailies.take(hit.assetID)
        let fps = model.asset(hit.assetID)?.video.first?.frameRate ?? 24
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { ShotKeyframe(path: hit.keyframes.dropFirst().first ?? hit.keyframes.first, art: preview.art[hit.assetID] ?? model.dailiesArt(hit.assetID)) }
                    .overlay(alignment: .topTrailing) { if take.suggestion != nil { GemMark(size: 8).padding(7) } }
                    .overlay(alignment: .bottomTrailing) { DailiesDurationTag(text: SourceTimecode.range(hit.start, hit.end, fps: fps)).padding(6) }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
                    .overlay(alignment: .topLeading) { label(take) }
                    .overlay { if take.circled { RoundedRectangle(cornerRadius: 8.5, style: .continuous).strokeBorder(Gate.Voice.director, lineWidth: 1.5).padding(-1.5) } }
                highlighted.font(.system(size: 12.5)).lineLimit(1)
                Text(hit.why.rawValue).font(.system(size: 11)).foregroundStyle(Gate.Text.disabled).padding(.top, -4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { DailiesTakeMenu(model: model, ids: [hit.assetID], onOpen: open) }
        .help("Open \(model.dailiesLabel(take)) at \(SourceTimecode.format(hit.start, fps: fps))")
        .accessibilityLabel("\(model.dailiesLabel(take)), \(hit.text), matched on \(hit.why.rawValue)\(take.circled ? ", circled" : "")")
    }

    /// "2A T3" in the corner; circled takes keep their hand-drawn circle around it.
    private func label(_ take: TakeInfo) -> some View {
        ZStack(alignment: .topLeading) {
            if take.circled { HandCircle().stroke(Gate.Voice.director, style: .init(lineWidth: 1.8, lineCap: .round)).frame(width: 56, height: 36) }
            Text(model.dailiesLabel(take)).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                .shadow(color: .black, radius: 1.5, y: 1).frame(width: 44, height: 26).offset(x: 6, y: 5)
        }
        .frame(width: 56, height: 36, alignment: .topLeading)
    }

    /// The line with its matched words brought up to text-1.
    private var highlighted: Text {
        let words = Set(hit.matched.map { $0.lowercased() })
        var out = Text("")
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let bare = token.trimmingCharacters(in: .punctuationCharacters.union(.init(charactersIn: "\u{201C}\u{201D}"))).lowercased()
            out = out + (words.contains(bare) ? Text(token).foregroundColor(Gate.Text.primary).fontWeight(.medium) : Text(token).foregroundColor(Gate.Text.tertiary))
            token = ""
        }
        for c in hit.text {
            if c.isLetter || c.isNumber || c == "'" || c == "\u{2019}" { token.append(c) }
            else { flush(); out = out + Text(String(c)).foregroundColor(Gate.Text.tertiary) }
        }
        flush()
        return out
    }
}

/// ⌘F in Dailies: the search field, not Edit › Find's command menu. A local key monitor sees the
/// key before the menu does, only while Dailies is on screen.
struct DailiesFindKey: ViewModifier {
    var model: FilmModel
    @State private var monitor: Any?
    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !model.isPreview, monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers?.lowercased() == "f",
                          model.room == .dailies, model.sheet == nil, !model.showCommandMenu else { return event }
                    model.openTakeID = nil
                    model.index.searching = true
                    model.index.searchFocus += 1
                    return nil
                }
            }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

import SwiftUI
import AppKit
import DirectionCore

// MARK: One scene (frame 07)

/// A scene's takes, setup by setup. Click watches a take, the take number or C circles. Select (or ⌘- and ⇧-click)
/// picks several to circle, move or set aside together.
struct DailiesSceneView: View {
    @Bindable var model: FilmModel
    var sceneID: String
    @Environment(\.dailiesPreview) private var preview
    @State private var filter = Filter.all
    @State private var selection: Set<String> = []
    @State private var anchor: String?
    @State private var selecting = false
    @State private var showMove = false
    @State private var hideUnusable = false
    @State private var longestFirst = false
    @FocusState private var focused: Bool

    enum Filter: Hashable { case all, circled, suggested }

    private var scene: DailiesScene? { model.scene(sceneID) }
    private var allTakes: [TakeInfo] { model.dailiesTakes(inScene: sceneID) }
    private var groups: [DailiesSetupGroup] {
        model.dailiesSetups(inScene: sceneID).map { g in
            var g = g
            g.takes = g.takes.filter { t in
                if hideUnusable && t.unusable { return false }
                switch filter { case .all: return true; case .circled: return t.circled; case .suggested: return t.suggestion != nil }
            }
            if longestFirst { g.takes.sort { model.dailiesDuration($0.assetID) > model.dailiesDuration($1.assetID) } }
            return g
        }.filter { !$0.takes.isEmpty }
    }
    private var order: [String] { groups.flatMap(\.takes).map(\.assetID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if allTakes.isEmpty {
                    Text("No takes in this scene yet. Drag takes here from Unsorted.").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
                        .frame(maxWidth: .infinity).padding(.top, 120)
                } else if groups.isEmpty {
                    Text(filter == .circled ? "Nothing circled in this scene yet." : "The editor hasn't suggested a take here.").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
                        .frame(maxWidth: .infinity).padding(.top, 120)
                } else {
                    ForEach(groups) { group in setupBlock(group) }
                }
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .safeAreaInset(edge: .bottom) { DailiesSelectionBar(model: model, ids: order.filter(selection.contains), available: !allTakes.isEmpty, selecting: selecting, showMove: $showMove) { if let id = selection.first { model.openTakeID = id } } }
        .dropDestination(for: String.self) { items, _ in dropHere(items) }
        .modifier(DailiesGridKeys(model: model, order: order, columns: 4, selection: $selection, anchor: $anchor, selecting: $selecting, showMove: $showMove))
        .focused($focused)
        .onAppear { focused = true; if let id = preview.selectedTakeID { selection = [id] } }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if scene?.locked == true { Image(systemName: "lock.fill").font(.system(size: 15)).foregroundStyle(Gate.Text.secondary) }
                    Text(scene?.label ?? "").font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary).lineLimit(1)
                }
                Text(meta).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
            Spacer(minLength: 12)
            GateSegmented(options: [(Filter.all, "All \(allTakes.count)"), (.circled, "Circled \(allTakes.filter(\.circled).count)"), (.suggested, "Suggested \(allTakes.filter { $0.suggestion != nil }.count)")], selection: $filter)
                .accessibilityLabel("Show takes")
            DailiesSelectButton(selecting: $selecting, selection: $selection).disabled(allTakes.isEmpty)
            Menu {
                Toggle("Longest Takes First", isOn: $longestFirst)
                Toggle("Hide Not Usable", isOn: $hideUnusable)
                Divider()
                Button("Move Selected Takes\u{2026}") { showMove = true }.disabled(selection.isEmpty)
            } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 13)).foregroundStyle(Gate.Text.secondary).frame(width: 28, height: 28).contentShape(Rectangle()) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Sort and display")
        }
        .popover(isPresented: $showMove, arrowEdge: .bottom) { DailiesMovePicker(model: model, ids: Array(selection)) { showMove = false } }
    }

    /// "2 takes · 6:24": what's here, and nothing else. The editor's suggestion is on its take.
    private var meta: String {
        var parts = [DailiesFormat.count(allTakes.count, "take"), Timecode.duration(allTakes.reduce(0) { $0 + model.dailiesDuration($1.assetID) })]
        if scene?.locked == true { parts.insert("Locked", at: 0) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func setupBlock(_ group: DailiesSetupGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(group.code).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                Text(group.description).font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).lineLimit(1).truncationMode(.tail).help(group.description)
                Spacer(minLength: 8)
                Text(DailiesFormat.count(group.takes.count, "take")).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 4), alignment: .leading, spacing: 18) {
                ForEach(group.takes) { take in
                    DailiesTakeCard(model: model, take: take, selected: selection.contains(take.assetID), selecting: selecting, payload: payload(take.assetID),
                                    onSelect: { focused = true; DailiesGridKeys.click(take.assetID, order: order, selecting: &selecting, selection: &selection, anchor: &anchor) { model.openTakeID = $0 } },
                                    onOpen: { model.openTakeID = take.assetID })
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.description.isEmpty ? "Setup \(group.code)" : "Setup \(group.code), \(group.description)")
    }

    private func payload(_ id: String) -> String { selection.contains(id) ? order.filter(selection.contains).joined(separator: "\n") : id }

    private func dropHere(_ items: [String]) -> Bool {
        let ids = items.flatMap { $0.split(separator: "\n").map(String.init) }.filter { model.dailies.takes[$0] != nil && model.dailies.takes[$0]?.sceneID != sceneID }
        guard !ids.isEmpty else { return false }
        model.moveTakes(ids, to: sceneID)
        return true
    }
}

/// A take in a scene grid: picture with marks, caption, then who decided what.
struct DailiesTakeCard: View {
    var model: FilmModel
    var take: TakeInfo
    var selected = false
    var selecting = false
    var payload: String
    var onSelect: () -> Void
    var onOpen: () -> Void
    @Environment(\.dailiesPreview) private var preview
    @State private var scrub: Double?
    @State private var width: CGFloat = 276
    @State private var tip = false

    var body: some View {
        let hovered = scrub != nil || preview.hoverTakeID == take.assetID
        VStack(alignment: .leading, spacing: 8) {
            DailiesTakePicture(model: model, take: take, selected: selected, selecting: selecting, hovered: hovered, scrub: model.isPreview ? nil : scrub)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
                .onContinuousHover { phase in
                    // Moving across the picture scrubs the take.
                    switch phase { case .active(let p): scrub = max(0, min(1, p.x / width)); case .ended: scrub = nil; tip = false }
                }
                // "Circle T3  C" after 600 ms of hovering (frame 07 › Hover).
                .task(id: scrub == nil) {
                    guard scrub != nil, !take.unusable else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    if !Task.isCancelled, scrub != nil { withAnimation(gateAnimation(Gate.Motion.snap)) { tip = true } }
                }
                .overlay(alignment: .topLeading) {
                    if preview.hoverTakeID == take.assetID { DailiesTip(text: "Circle \(model.dailiesShortLabel(take))", key: "C").offset(x: 113, y: 84) }
                    else if tip { DailiesTip(text: "\(take.circled ? "Uncircle" : "Circle") \(model.dailiesShortLabel(take))", key: "C").padding(8).transition(.opacity) }
                }
                .draggable(payload) { DailiesTakeThumb(asset: model.asset(take.assetID), art: preview.art[take.assetID] ?? model.dailiesArt(take.assetID), preview: model.isPreview).frame(width: 168, height: 94.5).clipShape(RoundedRectangle(cornerRadius: 7)).rotationEffect(.degrees(-3)).opacity(0.92) }
            Text(model.dailiesCaption(take)).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineSpacing(1.8).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            status.font(.system(size: 11.5)).lineLimit(1).padding(.top, -4)
        }
        .opacity(take.unusable ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu { DailiesTakeMenu(model: model, ids: [take.assetID], onOpen: onOpen) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: take.circled ? "Uncircle" : "Circle") { model.setCircle(take.assetID, !take.circled) }
        .accessibilityAction(named: "Open") { onOpen() }
        .accessibilityAction(named: take.unusable ? "Mark usable" : "Not usable") { model.setUnusable(take.assetID, !take.unusable) }
    }

    @ViewBuilder private var status: some View {
        if take.unusable { Text("Not usable as a take").foregroundStyle(Gate.Text.disabled) }
        else if model.indexFailed(take.assetID) { Text("Couldn\u{2019}t look at this take").foregroundStyle(Gate.Text.disabled) }
        // One short word or two. The editor's reason is in the take, and on hover here.
        else if take.circled { Text("Circled").foregroundStyle(Gate.Voice.director) }
        else if let angle = model.circledAngle(take.assetID) { Text("Circled with \(angle)").foregroundStyle(Gate.Voice.director.opacity(0.6)).help("The same moment as \(angle), which you circled. The editor treats it as circled too.") }
        else if take.suggestion != nil { Text("Suggested").foregroundStyle(Gate.Voice.agent).help(take.suggestionReason.map { $0.main } ?? "") }
        else if !take.flags.isEmpty { Text(take.flags.prefix(2).joined(separator: " \u{00B7} ")).foregroundStyle(Gate.Text.disabled) }
    }

    private var accessibilityText: String {
        var parts = ["\(take.setupCode ?? "") Take \(take.takeNumber == .max ? "" : String(take.takeNumber)), \(Int(model.dailiesDuration(take.assetID).rounded())) seconds", model.dailiesCaption(take)]
        if let s = take.suggestionShort { parts.append("Suggested by the editor: \(s)") }
        parts.append(take.unusable ? "Not usable" : take.circled ? "Circled" : model.circledAngle(take.assetID).map { "Circled with \($0)" } ?? "Not circled")
        parts.append(contentsOf: take.flags)
        return parts.joined(separator: ". ")
    }
}

/// The take's picture and marks: number (click to circle), hand-drawn circle, diamond, duration.
struct DailiesTakePicture: View {
    var model: FilmModel
    var take: TakeInfo
    var selected = false
    /// Picking several: each take shows whether it's picked.
    var selecting = false
    var hovered = false
    var scrub: Double? = nil
    var showsNumber = true
    var radius: CGFloat = 7
    @Environment(\.dailiesPreview) private var preview
    @State private var drawn: CGFloat = 1

    var body: some View {
        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
            .overlay { DailiesTakeThumb(asset: model.asset(take.assetID), art: preview.art[take.assetID] ?? model.dailiesArt(take.assetID), preview: model.isPreview, scrub: scrub) }
            .overlay { if hovered { Color.white.opacity(0.04) } }
            .overlay(alignment: .topTrailing) {
                if selecting { DailiesPickMark(on: selected).padding(7).accessibilityHidden(true) }
                else if take.suggestion != nil { GemMark(size: 8).padding(7).accessibilityHidden(true) }
            }
            .overlay(alignment: .bottomTrailing) { DailiesDurationTag(text: Timecode.duration(model.dailiesDuration(take.assetID))).padding(6) }
            .overlay(alignment: .bottomLeading) { if let g = model.dailies.syncGroup(for: take.assetID) { DailiesSyncBadge(model: model, group: g, assetID: take.assetID).padding(6) } }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
            .overlay(alignment: .topLeading) { if showsNumber { number } }
            .overlay {
                if take.circled { RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous).strokeBorder(Gate.Voice.director, lineWidth: 1.5).padding(-1.5) }
            }
            .overlay {
                if selected { RoundedRectangle(cornerRadius: radius + 2, style: .continuous).strokeBorder(Gate.Text.primary, lineWidth: 2).padding(take.circled ? -3.5 : -2) }
            }
            .onChange(of: take.circled) { _, on in
                guard on else { return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { drawn = 1; return }
                drawn = 0; withAnimation(Gate.Motion.settle) { drawn = 1 }
            }
    }

    /// The take number; clicking it circles. The circle draws itself on around it.
    private var number: some View {
        Button { model.setCircle(take.assetID, !take.circled) } label: {
            ZStack(alignment: .topLeading) {
                if take.circled {
                    HandCircle().trim(from: 0, to: drawn).stroke(Gate.Voice.director, style: .init(lineWidth: 1.8, lineCap: .round))
                        .frame(width: 46, height: 36).transition(.opacity.animation(Gate.Motion.snap))
                } else if model.circledAngle(take.assetID) != nil {
                    // Circled through the angle it's in sync with: the same circle, faint and broken.
                    HandCircle().stroke(Gate.Voice.director.opacity(0.45), style: .init(lineWidth: 1.4, lineCap: .round, dash: [3, 3.5]))
                        .frame(width: 46, height: 36).transition(.opacity.animation(Gate.Motion.snap))
                }
                Text(model.dailiesShortLabel(take)).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                    .shadow(color: .black, radius: 1.5, y: 1).frame(width: 34, height: 26).offset(x: 6, y: 5)
            }
            .frame(width: 46, height: 36, alignment: .topLeading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(take.unusable)
        .accessibilityLabel(take.circled ? "Uncircle \(model.dailiesLabel(take))" : "Circle \(model.dailiesLabel(take))")
    }
}

/// Right-click a take anywhere in Dailies.
struct DailiesTakeMenu: View {
    var model: FilmModel
    var ids: [String]
    var onOpen: () -> Void
    var body: some View {
        let takes = ids.compactMap { model.dailies.takes[$0] }
        let circled = !takes.isEmpty && takes.allSatisfy(\.circled), unusable = !takes.isEmpty && takes.allSatisfy(\.unusable)
        Button(circled ? "Uncircle" : "Circle") { model.toggleCircles(ids) }.disabled(unusable)
        Button("Play") { onOpen() }.disabled(ids.count != 1)
        Button("Open in Script") { model.go(.script) }
        Menu("Move to Scene") {
            ForEach(model.scenes) { s in Button(s.label) { model.moveTakes(ids, to: s.id) }.disabled(takes.allSatisfy { $0.sceneID == s.id }) }
            Divider()
            Button("Unsorted") { model.moveTakes(ids, to: nil) }
        }
        Button(unusable ? "Usable Again" : "Not Usable") { model.toggleUnusable(ids) }
        // A take Direction couldn't look at (footage-index.md › Acceptance).
        if ids.contains(where: model.indexFailed) {
            Button("Try Again") { for id in ids where model.indexFailed(id) { model.index.retry(id, film: model) } }
        }
        if ids.count == 1, let g = model.dailies.syncGroup(for: ids[0]) {
            Divider()
            Button("Use This Take\u{2019}s Sound") { model.useSyncSound(ids[0]) }.disabled(g.soundAssetID == ids[0])
            Button("Not in Sync") { model.unsync(ids[0]) }
        }
        if ids.count == 1, model.asset(ids[0])?.audio.isEmpty == false {
            Button("Transcribe Again") { model.index.transcribeAgain(ids[0], film: model) }
        }
        Divider()
        Button("Show in Finder") { model.revealTakes(ids) }
    }
}

/// Keyboard for take grids: arrows move, C circles, X sets aside, M moves, Space or ↩ opens, ⌘A selects all,
/// esc stops selecting.
struct DailiesGridKeys: ViewModifier {
    var model: FilmModel
    var order: [String]
    var columns: Int
    @Binding var selection: Set<String>
    @Binding var anchor: String?
    @Binding var selecting: Bool
    @Binding var showMove: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                guard !order.isEmpty else { return }
                let current = anchor.flatMap(order.firstIndex(of:)) ?? -1
                let step: Int
                switch direction { case .left: step = -1; case .right: step = 1; case .up: step = -columns; case .down: step = columns; @unknown default: step = 0 }
                let next = current < 0 ? 0 : max(0, min(order.count - 1, current + step))
                anchor = order[next]; selection = [order[next]]
            }
            .onKeyPress(phases: .down) { press in
                guard !TextInput.hasFocus, press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
                let ids = order.filter(selection.contains)
                switch press.key {
                case .space, .return:
                    guard let id = ids.first ?? anchor else { return .ignored }
                    model.openTakeID = id; return .handled
                default: break
                }
                switch press.characters.lowercased() {
                case "c": guard !ids.isEmpty else { return .ignored }; model.toggleCircles(ids); return .handled
                case "x": guard !ids.isEmpty else { return .ignored }; model.toggleUnusable(ids); return .handled
                case "m": guard !ids.isEmpty else { return .ignored }; showMove = true; return .handled
                default: return .ignored
                }
            }
            .onKeyPress(.escape) {
                guard selecting, !TextInput.hasFocus else { return .ignored }
                selecting = false; selection = []; return .handled
            }
            .onCommand(#selector(NSResponder.selectAll(_:))) { selecting = true; selection = Set(order); anchor = order.first }
    }

    /// A click watches the take. While selecting it picks or unpicks it; ⌘-click does the same and starts
    /// selecting, ⇧-click picks the run from the last take clicked.
    @MainActor static func click(_ id: String, order: [String], selecting: inout Bool, selection: inout Set<String>, anchor: inout String?, open: (String) -> Void) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let a = anchor, let i = order.firstIndex(of: a), let j = order.firstIndex(of: id) {
            selecting = true
            selection = Set(order[min(i, j)...max(i, j)])
        } else if flags.contains(.command) || selecting {
            if !selecting { selection = []; selecting = true }
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else {
            selection = [id]; anchor = id
            open(id)
        }
    }
}

/// "Move to scene…" from the keyboard (M): the scenes, then Unsorted.
struct DailiesMovePicker: View {
    var model: FilmModel
    var ids: [String]
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel("Move \(ids.count == 1 ? "take" : "\(ids.count) takes") to").padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
            ForEach(model.scenes) { s in item(s.label, guess: ids.count == 1 && model.dailies.takes[ids[0]]?.guessSceneID == s.id) { model.moveTakes(ids, to: s.id) } }
            Hairline().padding(.vertical, 4).padding(.horizontal, 6)
            item("Unsorted", guess: false) { model.moveTakes(ids, to: nil) }
        }
        .padding(6).frame(width: 240)
    }
    private func item(_ title: String, guess: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); done() } label: {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(Gate.Text.primary)
                Spacer(minLength: 8)
                if guess { GemMark(size: 6.4); Text("Editor's guess").foregroundStyle(Gate.Voice.agent).font(Gate.Font.small) }
            }
            .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 26).contentShape(Rectangle())
        }
        .buttonStyle(DailiesMenuRowStyle())
    }
}

struct DailiesMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { DailiesMenuRow(configuration: configuration) }
    private struct DailiesMenuRow: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label.background(RoundedRectangle(cornerRadius: 6).fill(hovered || configuration.isPressed ? Gate.Surface.hover : .clear)).onHover { hovered = $0 }
        }
    }
}

/// A help tag as the frames draw it, for snapshots of hover states.
/// On a take's picture: the takes it's in sync with ("B1"), and a waveform when the cut uses its sound.
struct DailiesSyncBadge: View {
    var model: FilmModel
    var group: SyncGroup
    var assetID: String
    var body: some View {
        // Angles are usually other setups, so the whole label: "2B T2", "B1".
        let others = group.takes.filter { $0.assetID != assetID }.map { model.dailiesLabel(model.dailies.take($0.assetID)) }
        let sound = group.soundAssetID == assetID
        HStack(spacing: 4) {
            Image(systemName: "link").font(.system(size: 9, weight: .bold))
            Text(others.joined(separator: " ")).font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            if sound { Image(systemName: "waveform").font(.system(size: 9, weight: .bold)) }
        }
        .foregroundStyle(Gate.Text.primary)
        .padding(.horizontal, 6).frame(height: 18)
        .background(Capsule().fill(.black.opacity(0.55)).overlay(Capsule().strokeBorder(Gate.Line.strong, lineWidth: 1)))
        .help("In sync with \(others.joined(separator: ", ")) by sound\(sound ? ". The cut uses this take\u{2019}s sound." : ".") Right-click for Not in Sync or Use This Take\u{2019}s Sound.")
        .accessibilityLabel("In sync with \(others.joined(separator: ", "))\(sound ? ", its sound is used" : "")")
    }
}

/// With takes selected: what you can do with them, and the keys for it.
struct DailiesSelectionBar: View {
    var model: FilmModel
    var ids: [String]
    /// There are takes on screen to select.
    var available = true
    /// Picking several takes: the bar acts on all of them.
    var selecting = false
    @Binding var showMove: Bool
    var onOpen: () -> Void
    var body: some View {
        if available { bar }
    }
    private var bar: some View {
        let takes = ids.compactMap { model.dailies.takes[$0] }
        let circled = !takes.isEmpty && takes.allSatisfy(\.circled), unusable = !takes.isEmpty && takes.allSatisfy(\.unusable)
        // Always in the same place. With nothing selected it shows the keys, dimmed.
        return HStack(spacing: 4) {
            Text(title(takes))
                .font(.system(size: 12, weight: .semibold, design: takes.isEmpty ? .default : .monospaced))
                .foregroundStyle(takes.isEmpty ? Gate.Text.tertiary : Gate.Text.secondary).padding(.horizontal, 8)
            item(circled ? "Uncircle" : "Circle", key: "C", color: Gate.Voice.director) { model.toggleCircles(ids) }.disabled(takes.isEmpty || unusable)
            if selecting { item("Move\u{2026}", key: "M") { showMove = true }.disabled(takes.isEmpty) }
            else { item("Watch", key: "\u{21A9}") { onOpen() }.disabled(takes.count != 1) }
            item(unusable ? "Usable Again" : "Not Usable", key: "X") { model.toggleUnusable(ids) }.disabled(takes.isEmpty)
        }
        .opacity(takes.isEmpty ? 0.7 : 1)
        .padding(5).gateGlass(12).fixedSize()
        .frame(maxWidth: .infinity).padding(.bottom, 16)
    }
    private func title(_ takes: [TakeInfo]) -> String {
        if takes.isEmpty { return selecting ? "Click takes to pick them" : "Click a take to watch it" }
        return takes.count == 1 ? model.dailiesLabel(takes[0]) : "\(takes.count) takes"
    }
    private func item(_ title: String, key: String, color: Color = Gate.Text.primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).foregroundStyle(color)
                Text(key).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
            }
            .font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.gate(.ghost))
    }
}

/// "Select" in a take grid's header: turns picking several takes on, "Done" turns it off.
struct DailiesSelectButton: View {
    @Binding var selecting: Bool
    @Binding var selection: Set<String>
    var body: some View {
        Button(selecting ? "Done" : "Select") {
            withAnimation(gateAnimation(Gate.Motion.snap)) { selecting.toggle(); selection = [] }
        }
        .buttonStyle(.gate(selecting ? .normal : .ghost))
        .help(selecting ? "Stop selecting (esc)" : "Pick several takes to circle, move or set aside together")
    }
}

/// While selecting, each take's corner says whether it's picked.
struct DailiesPickMark: View {
    var on: Bool
    var body: some View {
        ZStack {
            Circle().fill(on ? Gate.Text.primary : Color.black.opacity(0.35))
            Circle().strokeBorder(on ? Color.clear : Gate.Text.primary.opacity(0.8), lineWidth: 1.5)
            if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Gate.Surface.canvas) }
        }
        .frame(width: 18, height: 18)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

struct DailiesTip: View {
    var text: String
    var key: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Text(text).foregroundStyle(Gate.Text.primary)
            if let key { Text(key).foregroundStyle(Gate.Text.disabled) }
        }
        .font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Gate.Steel.ramp[5]).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.strong, lineWidth: 1)).shadow(color: .black.opacity(0.8), radius: 10, y: 8))
        .fixedSize().allowsHitTesting(false)
    }
}

// MARK: Unsorted (frame 09) and Not usable

/// Takes the editor couldn't place. Drag one onto a scene, Move to its guess, or accept every guess.
struct DailiesUnsortedView: View {
    @Bindable var model: FilmModel
    var body: some View {
        DailiesBinGrid(model: model, takes: model.dailiesUnsorted, title: "Unsorted",
                       subtitle: "\(DailiesFormat.count(model.dailiesUnsorted.count, "take")) the editor couldn't place with confidence. Drag one onto a scene, or accept a guess.",
                       footnote: "Unsorted takes are never used in a cut until they're in a scene.",
                       emptyTitle: "Everything's in a scene.", emptyMessage: "The editor will put new footage here if it can't place it.") {
            let guesses = model.dailiesUnsorted.filter { model.scene($0.guessSceneID) != nil }.count
            Button { model.acceptGuesses() } label: { Label("Accept \(DailiesFormat.count(guesses, "guess", "guesses"))", systemImage: "checkmark") }
                .buttonStyle(.gate).disabled(guesses == 0).help("Move every take to the scene the editor guessed")
        } footer: { take in
            DailiesGuessRow(model: model, take: take)
        }
    }
}

/// Takes set aside by you or flagged by the editor. Never used in a cut.
struct DailiesUnusableView: View {
    @Bindable var model: FilmModel
    var body: some View {
        DailiesBinGrid(model: model, takes: model.dailiesUnusable, title: "Not usable",
                       subtitle: "\(DailiesFormat.count(model.dailiesUnusable.count, "take")) set aside. They're never used in a cut.",
                       footnote: "Mark a take usable again to put it back in its scene.",
                       emptyTitle: "Nothing set aside.", emptyMessage: "Press X on a take to set it aside.") {
            EmptyView()
        } footer: { take in
            HStack(spacing: 6) {
                Text(model.scene(take.sceneID)?.label ?? "Not in a scene").foregroundStyle(Gate.Text.disabled).lineLimit(1)
                Spacer(minLength: 6)
                Button("Usable again") { model.setUnusable(take.assetID, false) }.buttonStyle(.gate(.normal, .small))
            }
            .font(Gate.Font.small)
        }
    }
}

/// The 5-column bin grid shared by Unsorted and Not usable.
struct DailiesBinGrid<Action: View, Footer: View>: View {
    @Bindable var model: FilmModel
    var takes: [TakeInfo]
    var title: String
    var subtitle: String
    var footnote: String
    var emptyTitle: String
    var emptyMessage: String
    @ViewBuilder var action: Action
    @ViewBuilder var footer: (TakeInfo) -> Footer
    @Environment(\.dailiesPreview) private var preview
    @State private var selection: Set<String> = []
    @State private var anchor: String?
    @State private var selecting = false
    @State private var showMove = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary)
                        Text(subtitle).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                    }
                    Spacer(minLength: 12)
                    action
                    DailiesSelectButton(selecting: $selecting, selection: $selection).disabled(takes.isEmpty)
                }
                .popover(isPresented: $showMove, arrowEdge: .bottom) { DailiesMovePicker(model: model, ids: Array(selection)) { showMove = false } }
                if takes.isEmpty {
                    VStack(spacing: 8) {
                        Text(emptyTitle).font(Gate.Font.brand(size: 24, width: 120)).foregroundStyle(Gate.Text.primary)
                        Text(emptyMessage).font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 160)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 5), alignment: .leading, spacing: 14) {
                        ForEach(takes) { take in card(take) }
                    }
                    Text(footnote).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                }
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { DailiesSelectionBar(model: model, ids: takes.map(\.assetID).filter(selection.contains), available: !takes.isEmpty, selecting: selecting, showMove: $showMove) { if let id = selection.first { model.openTakeID = id } } }
        .modifier(DailiesGridKeys(model: model, order: takes.map(\.assetID), columns: 5, selection: $selection, anchor: $anchor, selecting: $selecting, showMove: $showMove))
        .focused($focused)
        .onAppear { focused = true }
    }

    private func card(_ take: TakeInfo) -> some View {
        let id = take.assetID, dragging = preview.draggingTakeID == id, order = takes.map(\.assetID)
        let payload = selection.contains(id) ? order.filter(selection.contains).joined(separator: "\n") : id
        return VStack(alignment: .leading, spacing: 8) {
            DailiesTakePicture(model: model, take: take, selected: selection.contains(id), selecting: selecting, showsNumber: false)
                .draggable(payload) { DailiesTakeThumb(asset: model.asset(id), art: preview.art[id] ?? model.dailiesArt(id), preview: model.isPreview).frame(width: 168, height: 94.5).clipShape(RoundedRectangle(cornerRadius: 7)).rotationEffect(.degrees(-3)).opacity(0.92) }
            Text(model.dailiesCaption(take)).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineSpacing(1.8).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if dragging { Text("Being dragged").font(Gate.Font.small).foregroundStyle(Gate.Text.disabled).frame(height: 22) }
            else { footer(take).frame(minHeight: 22) }
        }
        .opacity(dragging ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { focused = true; DailiesGridKeys.click(id, order: order, selecting: &selecting, selection: &selection, anchor: &anchor) { model.openTakeID = $0 } }
        .contextMenu { DailiesTakeMenu(model: model, ids: selection.contains(id) ? order.filter(selection.contains) : [id]) { model.openTakeID = id } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selection.contains(id) ? .isSelected : [])
        .accessibilityAction(named: "Not usable") { model.setUnusable(id, true) }
    }
}

/// "◆ Probably 4 … Move", or "No guess · room tone".
struct DailiesGuessRow: View {
    var model: FilmModel
    var take: TakeInfo
    var body: some View {
        if let scene = model.scene(take.guessSceneID) {
            HStack(spacing: 6) {
                GemMark(size: 6.4)
                Text("Probably \(scene.number)").foregroundStyle(Gate.Voice.agent).lineLimit(1)
                Spacer(minLength: 6)
                Button("Move") { model.moveTake(take.assetID, to: scene.id) }
                    .buttonStyle(.gate(.normal, .small)).help("Move to \(scene.label), the editor's guess")
                    .accessibilityLabel("Move to scene \(scene.number) (editor's guess)")
            }
            .font(Gate.Font.small)
        } else {
            Text((["No guess"] + take.flags.prefix(1).map { $0.lowercased() }).joined(separator: " \u{00B7} ")).font(Gate.Font.small).foregroundStyle(Gate.Text.disabled).lineLimit(1)
        }
    }
}

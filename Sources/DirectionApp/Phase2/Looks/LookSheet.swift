import SwiftUI
import AppKit
import DirectionCore
import DirectionMedia

/// Frame 63: the Look sheet. The picture with the selected look on the left, the looks and filters on
/// the right, Apply to and the buttons in the foot (open-questions 20). Every change previews at once;
/// nothing changes the film until Use This Look.
struct LookSheet: View {
    @Bindable var model: FilmModel
    @FocusState private var focused: Bool
    private var looks: LooksModel { model.looks }

    var body: some View {
        AttachedSheet(width: 1120, onDismiss: cancel) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    view.frame(width: 760, height: 665).background(Gate.Surface.canvas)
                    panel.frame(width: 360, height: 665, alignment: .top).overlay(alignment: .leading) { Gate.Line.subtle.frame(width: 1) }
                }
                foot
            }
            .frame(height: 720)
        }
        .focusable().focused($focused).focusEffectDisabled()
        // `\` held shows the picture without the look.
        .onKeyPress(KeyEquivalent("\\"), phases: [.down, .repeat, .up]) { press in
            guard !TextInput.hasFocus || press.phase == .up else { return .ignored }
            let held = press.phase != .up
            if looks.comparing != held { looks.comparing = held }
            return .handled
        }
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look")
        .accessibilityAddTraits(.isModal)
    }

    private func cancel() { looks.close(model) }

    // MARK: The picture

    private var view: some View {
        VStack(spacing: 0) {
            LookPicture(image: looks.comparing ? looks.rendered.plain : looks.rendered.picture, art: art(looks.largeStill ?? currentSceneID), radius: Gate.Radius.frame, hairline: false)
                .frame(width: 720, height: 405)
                .accessibilityLabel(looks.comparing ? "The picture without the look" : "The picture with \(draftName)")
            HStack(spacing: 8) { Text("Hold"); Kbd("\\"); Text("to compare") }
                .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                .frame(height: 22).padding(.top, 12).padding(.bottom, 18)
            HStack(alignment: .top, spacing: 8) {
                ForEach(stillItems, id: \.id) { s in
                    Button { looks.largeStill = looks.largeStill == s.id ? nil : s.id; looks.renderDraft(sync: model.isPreview) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            LookPicture(image: looks.rendered.stills[s.id], art: art(s.id), radius: Gate.Radius.frame, selected: looks.largeStill == s.id)
                                .aspectRatio(16 / 9, contentMode: .fit)
                            Text(s.label).font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.tertiary).lineLimit(1).truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(s.label), still")
                }
            }
            .frame(width: 720)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentSceneID: String? { model.stripScene(at: model.position)?.id }
    private var stillItems: [(id: String, label: String)] {
        if !looks.stills.isEmpty { return looks.stills.map { ($0.id, $0.label) } }
        return model.stripScenes.prefix(5).map { ($0.id, $0.label) }
    }
    /// Before frames arrive, the scene's stand-in.
    private func art(_ sceneID: String?) -> FootageArt { model.stripScenes.first { $0.id == sceneID }?.art ?? model.stripScene(at: model.position)?.art ?? .dusk }
    private var draftName: String { looks.draft.isNone ? "no look" : looks.draft.name }

    // MARK: The panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                SectionLabel("Looks")
                Spacer(minLength: 0)
                Text("Strength").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                LookSlider(value: Binding(get: { looks.draft.strength }, set: { looks.setStrength($0) }), label: "Strength")
                    .frame(width: 100).padding(.trailing, 6).disabled(looks.draft.lut == nil)
                Text(percent(looks.draft.strength)).font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(Gate.Text.secondary)
            }
            .frame(height: 18)
            ForEach(Array(tileGroups.enumerated()), id: \.offset) { i, group in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        if group.byEditor { GemMark(size: 6).frame(width: 6, height: 6) }
                        SectionLabel(group.name)
                    }
                    .frame(height: 11)
                    tiles(group, withNone: i == 0)
                }
            }
            filters
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
    }

    /// The editor's looks first, then the Looks folder; with no looks yet, None sits alone under the folder's label.
    private var tileGroups: [LookGroup] { looks.groups.isEmpty ? [LookGroup(name: LooksLibrary.folderGroup, looks: [])] : looks.groups }

    private func tiles(_ group: LookGroup, withNone: Bool) -> some View {
        let items: [LookEntry?] = (withNone ? [nil] : []) + group.looks.map { Optional($0) }
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min(items.count, $0 + 3)]) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { j, entry in
                        if j > 0 { Spacer(minLength: 0) }
                        tile(entry, editor: group.byEditor)
                    }
                    if row.count < 3 { ForEach(0..<(3 - row.count), id: \.self) { _ in Spacer(minLength: 0); Color.clear.frame(width: 104, height: 1) } }
                }
                .frame(width: 319)
            }
        }
    }

    private func tile(_ entry: LookEntry?, editor: Bool) -> some View {
        let id = entry?.id, on = looks.selectedID == id
        let current = looks.currentTileID == id, broken = entry?.problem != nil
        let name = entry?.name ?? "None"
        return Button { looks.select(entry) } label: {
            VStack(alignment: .leading, spacing: 4) {
                LookPicture(image: looks.rendered.tiles[id ?? "none"], art: art(currentSceneID), radius: 8, selected: on, dimmed: broken)
                    .frame(width: 104, height: 58.5)
                    .overlay(alignment: .topTrailing) { if editor && entry != nil { GemMark(size: 6).shadow(color: .black.opacity(0.5), radius: 0.5).padding(5) } }
                    .overlay(alignment: .topLeading) { if current { CurrentChip().padding(5) } }
                let lines = Self.wrapped(name, width: 104)
                Text(lines.joined(separator: "\n")).font(Gate.Font.small).foregroundStyle(broken ? Gate.Text.tertiary : on ? Gate.Text.primary : Gate.Text.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(width: 104, height: 14.4 * CGFloat(min(2, lines.count)), alignment: .topLeading)
                if broken { Text("Can\u{2019}t read this LUT").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(width: 104, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(broken)
        .help(entry?.problem ?? entry?.settings.note ?? "")
        .accessibilityLabel(broken ? "\(name), can\u{2019}t read this LUT" : "\(name), look")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Tile names wrap word by word at 104 pt, like the frame; SwiftUI would push a lone last word down a line.
    static func wrapped(_ text: String, width: CGFloat) -> [String] {
        let font = NSFont.systemFont(ofSize: 12)
        func fits(_ s: String) -> Bool { (s as NSString).size(withAttributes: [.font: font]).width <= width }
        var lines: [String] = []
        for word in text.split(separator: " ").map(String.init) {
            if let last = lines.last, fits(last + " " + word) { lines[lines.count - 1] = last + " " + word } else { lines.append(word) }
        }
        return lines.isEmpty ? [text] : lines
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Filters").frame(height: 10.5)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(LookFilter.allCases, id: \.self) { f in
                    filterRow(f)
                    if looks.isOn(f), !f.options.isEmpty {
                        LookSegmented(options: f.options.map { ($0, LookFilter.optionLabel($0)) }, selection: Binding(get: { looks.option(f) }, set: { looks.setOption(f, $0) }))
                            .padding(.leading, 42).padding(.top, 2).padding(.bottom, 4)
                            .accessibilityLabel("\(f.label) \(f == .letterbox ? "ratio" : f == .grain ? "size" : "colors")")
                    }
                }
            }
        }
    }

    private func filterRow(_ f: LookFilter) -> some View {
        let on = looks.isOn(f)
        return HStack(spacing: 10) {
            // GateSwitch draws its knob at the trailing edge of a wider box.
            GateSwitch(isOn: Binding(get: { on }, set: { looks.setOn(f, $0) })).frame(width: 32, alignment: .trailing)
            Text(f.label).lineLimit(1).frame(width: on && f.hasAmount ? 92 : nil, alignment: .leading)
            if on && f.hasAmount {
                LookSlider(value: Binding(get: { looks.amount(f) }, set: { looks.setAmount(f, $0) }), label: f.label).padding(.trailing, 6)
                Text(percent(looks.amount(f))).font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(Gate.Text.secondary).frame(width: 30, alignment: .trailing)
            } else { Spacer(minLength: 0) }
        }
        .font(.system(size: 12.5)).foregroundStyle(on ? Gate.Text.primary : Gate.Text.secondary)
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(f.label)
        .accessibilityValue(on ? (f.hasAmount ? "on, \(Int((looks.amount(f) * 100).rounded())) percent" : "on, \(looks.option(f))") : "off")
        .accessibilityAction { looks.setOn(f, !on) }
        .accessibilityAdjustableAction { direction in
            guard on, f.hasAmount else { return }
            looks.setAmount(f, looks.amount(f) + (direction == .increment ? 0.05 : -0.05))
        }
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    // MARK: The foot

    private var foot: some View {
        HStack(spacing: 8) {
            Text("Apply to").font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary)
            GateSelect(options: applyOptions, selection: Binding(get: { looks.applyTo }, set: { looks.setApplyTo($0) }))
            if let id = looks.applyTo, looks.sceneHasOwnLook(id), let scene = model.scene(id) {
                HStack(spacing: 0) {
                    Text("Scene \(scene.number) has its own look \u{00B7} ").foregroundStyle(Gate.Text.tertiary)
                    Button { looks.chooseFilmLook() } label: { Text("Use the film\u{2019}s look").underline().foregroundStyle(Gate.Text.primary) }.buttonStyle(.plain)
                }
                .font(Gate.Font.small)
            }
            Spacer(minLength: 8)
            Button("Cancel", action: cancel).buttonStyle(.gate).keyboardShortcut(.cancelAction)
            Button("Use This Look") { looks.use(model) }.buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
        .overlay(alignment: .top) { Gate.Line.subtle.frame(height: 1) }
    }

    /// Whole film, the scene under the playhead, then every scene.
    private var applyOptions: [(String?, String)] {
        var out: [(String?, String)] = [(nil, "Whole film")]
        let here = model.dailies.scene(for: PictureContextMenu.takeUnderPlayhead(model)) ?? model.scene(currentSceneID)
        if let here { out.append((here.id, "Scene \(here.number) \(here.title)")) }
        for s in model.scenes where s.id != here?.id { out.append((s.id, "Scene \(s.number) \(s.title)")) }
        if let id = looks.applyTo, !out.contains(where: { $0.0 == id }), let s = model.scene(id) { out.append((id, "Scene \(s.number) \(s.title)")) }
        return out
    }
}

/// One picture in the sheet: a rendered frame, or the footage stand-in until it's ready.
private struct LookPicture: View {
    var image: CGImage?
    var art: FootageArt
    var radius: CGFloat
    var selected = false
    var dimmed = false
    var hairline = true
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            Gate.Surface.canvas
            if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill) }
            else { FootageArtView(art: art) }
        }
        .opacity(dimmed ? 0.45 : 1)
        .clipShape(shape)
        .overlay { if hairline && !selected { shape.strokeBorder(Gate.Line.subtle, lineWidth: 1) } }
        // `.look-tile.on`: a 1.5 pt text-1 ring with a dark line inside it.
        .overlay { if selected { shape.strokeBorder(Gate.Text.primary, lineWidth: 1.5).overlay(shape.inset(by: 1.5).strokeBorder(Color.black.opacity(0.45), lineWidth: 1)) } }
    }
}

/// The "Current" chip on the film's look (`.chip.ui`, small).
private struct CurrentChip: View {
    var body: some View {
        Text("Current").font(.system(size: 10, weight: .medium)).foregroundStyle(Gate.Text.secondary)
            .padding(.horizontal, 5).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 4).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
    }
}

/// `.slider`: a 4 pt track, steel-8 fill and a 16 pt steel-9 knob. Drag or click anywhere on it.
struct LookSlider: View {
    @Binding var value: Double
    var label: String
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), x = CGFloat(min(1, max(0, value))) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Gate.Surface.hover).frame(height: 4)
                Capsule().fill(Gate.Steel.ramp[8]).frame(width: x, height: 4)
                Circle().fill(Gate.Steel.ramp[9]).frame(width: 16, height: 16).shadow(color: .black.opacity(0.7), radius: 1.5, y: 1).offset(x: x - 8)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in value = Double(min(1, max(0, v.location.x / w))) })
        }
        .frame(height: 18)
        .opacity(enabled ? 1 : Gate.Component.Button.disabledOpacity)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { d in value = min(1, max(0, value + (d == .increment ? 0.05 : -0.05))) }
    }
}

/// The small `.seg` under a filter row (`.filter-sub .seg`): 20 pt segments, 11.5 pt.
private struct LookSegmented: View {
    let options: [(String, String)]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(selection == value ? Gate.Text.primary : Gate.Text.tertiary)
                        .padding(.horizontal, 10).frame(height: 20)
                        .background { if selection == value { RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle, lineWidth: 1)).shadow(color: .black.opacity(0.5), radius: 1, y: 1) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 9).fill(Gate.Surface.canvas).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
        .fixedSize()
    }
}

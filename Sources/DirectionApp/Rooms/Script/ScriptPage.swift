import SwiftUI
import AppKit
import DirectionCore

// The script page: a 700 pt column of 30 pt rows. Line number 40 · 14 · text · 14 · coverage 112.
// Recipes: design/spec/css/start.css (Script).

enum ScriptMetrics {
    static let column: CGFloat = 700
    static let number: CGFloat = 40
    static let gap: CGFloat = 14
    static let coverage: CGFloat = 112
    static let coverageColumn: CGFloat = 16
    static let speaker: CGFloat = 96
    static let row: CGFloat = 30
    /// Where the text column starts and ends inside a row.
    static let textStart = number + gap
    static var textEnd: CGFloat { column - coverage - gap }
}

// MARK: Line row

/// One line of the cut. Rows have no gaps, so coverage bars run continuously.
struct ScriptLineRow: View, Equatable {
    enum Selection: Equatable { case single, top, middle, bottom }
    var line: ScriptLine
    var coverage: [ScriptCoverage]
    var showsSpeakerColumn: Bool
    var current = false
    var selection: Selection?
    var hovered = false
    /// The grip stays while its line is being dragged.
    var dragging = false
    var found = false
    var struck: ScriptMarks.Tag?
    var hold: ScriptMarks.Edge?
    var movedAfter: Int?
    var tags: [ScriptMarks.Tag] = []
    var shake = 0
    var accessibility: String
    var onTap: (Bool) -> Void = { _ in }
    var onNumber: () -> Void = {}
    var onTag: (String) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }
    var onGrip: (DragGesture.Value?) -> Void = { _ in }

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.line == b.line && a.coverage == b.coverage && a.showsSpeakerColumn == b.showsSpeakerColumn && a.current == b.current && a.selection == b.selection && a.hovered == b.hovered && a.dragging == b.dragging
            && a.found == b.found && a.struck == b.struck && a.hold == b.hold && a.movedAfter == b.movedAfter && a.tags == b.tags && a.shake == b.shake && a.accessibility == b.accessibility
    }

    var body: some View {
        HStack(alignment: .center, spacing: ScriptMetrics.gap) {
            number
            text
            CoverageBars(marks: coverage)
        }
        .frame(width: ScriptMetrics.column, height: ScriptMetrics.row)
        .background { if current || found || hovered { RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(current || found ? 0.05 : 0.03)) } }
        .overlay(alignment: .topLeading) { if let hold { HoldBracket(edge: hold).offset(x: ScriptMetrics.textStart - 8) } }
        .overlay(alignment: .leading) { gutterTags }
        .contentShape(Rectangle())
        .onTapGesture { onTap(NSEvent.modifierFlags.contains(.shift)) }
        .onHover(perform: onHover)
        .modifier(ShakeEffect(shakes: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : CGFloat(shake)))
        .animation(gateAnimation(.linear(duration: 0.36)), value: shake)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selection != nil ? [.isButton, .isSelected] : .isButton)
    }

    private var number: some View {
        ZStack(alignment: .trailing) {
            if hovered || dragging {
                Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                    .frame(width: 14, height: ScriptMetrics.row).contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named(ScriptPageSpace.name)).onChanged { onGrip($0) }.onEnded { _ in onGrip(nil) })
                    .help("Drag to move this line")
            }
            Text("\(line.number)").font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit()
                .foregroundStyle(current ? Gate.Text.primary : Gate.Text.disabled)
                .onTapGesture(perform: onNumber)
                .help("Other readings (R)")
        }
        .frame(width: ScriptMetrics.number, height: ScriptMetrics.row, alignment: .trailing)
    }

    private var text: some View {
        HStack(alignment: .center, spacing: 0) {
            if let speaker = line.speaker {
                Text(speaker).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.55).foregroundStyle(Gate.Text.tertiary)
                    .lineLimit(1).frame(width: ScriptMetrics.speaker, alignment: .leading)
            } else if showsSpeakerColumn || line.kind == .action {
                Color.clear.frame(width: ScriptMetrics.speaker, height: 1)
            }
            Text(line.text).font(.system(size: 15)).italic(line.kind == .action)
                .foregroundStyle(movedAfter != nil ? Gate.Text.disabled : struck != nil || line.kind == .action ? Gate.Text.tertiary : Gate.Text.primary)
                .lineLimit(1).truncationMode(.tail)
                .overlay(alignment: .leading) { if struck != nil { StrikeLine() } }
            if let movedAfter {
                Text("\u{2192} after \(movedAfter)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Voice.director).padding(.leading, 10).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ScriptMetrics.row)
        .background(alignment: .leading) {
            if let selection {
                UnevenRoundedRectangle(topLeadingRadius: selection == .single || selection == .top ? 4 : 0, bottomLeadingRadius: selection == .single || selection == .bottom ? 4 : 0,
                                       bottomTrailingRadius: selection == .single || selection == .bottom ? 4 : 0, topTrailingRadius: selection == .single || selection == .top ? 4 : 0)
                    .fill(Gate.Voice.directorWash).padding(.leading, -8)
            }
        }
    }

    @ViewBuilder private var gutterTags: some View {
        if !tags.isEmpty {
            HStack(spacing: 3) {
                ForEach(tags, id: \.self) { tag in
                    NoteNumberTag(number: tag.number).onTapGesture { onTag(tag.noteID) }.help("Note \(tag.number)")
                }
            }
            .fixedSize()
            .offset(x: -34)
        }
    }
}

/// The amber number tag in the gutter: "5".
struct NoteNumberTag: View {
    var number: Int
    var suffix: String? = nil
    var body: some View {
        Text(suffix.map { "\(number) \u{00B7} \($0)" } ?? "\(number)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced)).monospacedDigit()
            .foregroundStyle(Gate.Voice.directorInk).padding(.horizontal, 5).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(Gate.Voice.director))
            .fixedSize()
    }
}

/// A 2 pt amber line through struck text; draws left to right.
private struct StrikeLine: View {
    @State private var drawn: CGFloat = 1
    var body: some View {
        GeometryReader { g in
            Rectangle().fill(Gate.Voice.director).frame(width: g.size.width * drawn, height: 2).position(x: g.size.width * drawn / 2, y: g.size.height / 2 + 1)
        }
        .allowsHitTesting(false)
    }
}

/// Amber bracket at x 46 with 6 pt caps on the first and last held lines.
private struct HoldBracket: View {
    var edge: ScriptMarks.Edge
    var body: some View {
        let top: CGFloat = edge == .top || edge == .single ? 6 : 0
        let bottom: CGFloat = edge == .bottom || edge == .single ? 6 : 0
        Path { p in
            if top > 0 { p.move(to: .init(x: 7, y: top)); p.addLine(to: .init(x: 4, y: top)); p.addQuadCurve(to: .init(x: 1, y: top + 3), control: .init(x: 1, y: top)) }
            else { p.move(to: .init(x: 1, y: 0)) }
            p.addLine(to: .init(x: 1, y: ScriptMetrics.row - bottom - (bottom > 0 ? 3 : 0)))
            if bottom > 0 { p.addQuadCurve(to: .init(x: 4, y: ScriptMetrics.row - bottom), control: .init(x: 1, y: ScriptMetrics.row - bottom)); p.addLine(to: .init(x: 7, y: ScriptMetrics.row - bottom)) }
        }
        .stroke(Gate.Voice.director, style: .init(lineWidth: 2))
        .frame(width: 8, height: ScriptMetrics.row)
        .allowsHitTesting(false)
    }
}

/// One 2 pt bar per take: steel on camera, dashed off camera, amber for the take in the cut.
struct CoverageBars: View {
    var marks: [ScriptCoverage]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(marks.prefix(7).enumerated()), id: \.offset) { _, mark in
                ZStack {
                    switch mark {
                    case .none: Color.clear
                    case .onCamera: Gate.Steel.ramp[6].frame(width: 2)
                    case .inCut: Gate.Voice.director.frame(width: 2)
                    case .offCamera: DashedBar().frame(width: 2)
                    }
                }
                .frame(width: ScriptMetrics.coverageColumn)
            }
        }
        .frame(width: ScriptMetrics.coverage, alignment: .leading)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// 3 on, 3 off. Rows are 30 pt, a multiple of 6, so dashes line up across rows.
struct DashedBar: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height { context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: min(3, size.height - y))), with: .color(Gate.Steel.ramp[6])); y += 6 }
        }
    }
}

/// "2A" over its takes, then the take numbers, in 16 pt columns.
struct CoverageHeader: View {
    var columns: [ScriptColumn]
    var body: some View {
        let groups = columns.reduce(into: [(String, Int)]()) { out, c in
            if let last = out.last, last.0 == c.setup { out[out.count - 1].1 += 1 } else { out.append((c.setup, 1)) }
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    Text(g.0).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.tertiary)
                        .frame(width: CGFloat(g.1) * ScriptMetrics.coverageColumn, height: 10).padding(.bottom, 3)
                        .overlay(alignment: .bottom) { Gate.Line.strong.frame(height: 1) }
                }
            }
            HStack(spacing: 0) {
                ForEach(columns) { c in
                    Text(c.take).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled).frame(width: ScriptMetrics.coverageColumn, height: 10)
                }
            }
        }
        .frame(width: ScriptMetrics.coverage, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coverage: " + groups.map { "\($0.0), \($0.1) takes" }.joined(separator: "; "))
    }
}

// MARK: Headings

/// Scene number, slugline in mono caps, the scene's title, and on the right either a
/// note ("Voice-over, no picture coverage") or the scene's coverage columns.
struct ScriptSceneHeading: View, Equatable {
    var scene: ScriptScene
    var showsColumns: Bool
    nonisolated static func == (a: Self, b: Self) -> Bool { a.scene == b.scene && a.showsColumns == b.showsColumns }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScriptMetrics.gap) {
            Text("\(scene.number)").font(Gate.Font.label).tracking(0.74).foregroundStyle(Gate.Text.disabled)
                .frame(width: ScriptMetrics.number, alignment: .trailing)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if scene.locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Gate.Text.tertiary) }
                Text(scene.slugline ?? scene.title.uppercased()).font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(0.52).foregroundStyle(Gate.Text.secondary).lineLimit(1)
                if scene.slugline != nil { Text(scene.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Gate.Text.disabled).lineLimit(1).padding(.leading, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if scene.voiceOverOnly {
                Text("Voice-over, no picture coverage").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary)
                    .multilineTextAlignment(.trailing).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .frame(width: ScriptMetrics.coverage, alignment: .trailing)
            } else {
                // The scene's own columns, when they aren't already at the top of the page.
                Color.clear.frame(width: ScriptMetrics.coverage, height: 1)
                    .overlay(alignment: .bottomLeading) { if showsColumns && !scene.columns.isEmpty { CoverageHeader(columns: scene.columns).padding(.bottom, -3) } }
            }
        }
        .padding(.top, 17).padding(.bottom, 7)
        .frame(width: ScriptMetrics.column)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The amber 2 pt insertion line with a dot and its tag: "9 · line 16 here".
struct InsertionLine: View {
    var tag: ScriptMarks.Tag?
    var movingNumber: Int
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Gate.Voice.director).frame(height: 2)
            Circle().fill(Gate.Voice.director).frame(width: 8, height: 8).offset(x: -4)
            if let tag { NoteNumberTag(number: tag.number, suffix: "line \(movingNumber) here").frame(maxWidth: .infinity, alignment: .trailing) }
            else { NoteNumberTag(number: movingNumber, suffix: "here").frame(maxWidth: .infinity, alignment: .trailing) }
        }
        .frame(width: ScriptMetrics.column - ScriptMetrics.textStart - ScriptMetrics.coverage, height: 16)
        .allowsHitTesting(false)
    }
}

// MARK: Selection toolbar

/// Glass, radius 10, at the right end of the selection: Strike, Hold, Move, Readings.
/// The gesture already made on the selection shows its label.
struct SelectionToolbar<MoveMenu: View>: View {
    var struck: Bool
    var held: Bool
    var canReadings: Bool
    var strike: () -> Void
    var hold: () -> Void
    var readings: () -> Void
    @ViewBuilder var moveMenu: MoveMenu
    var body: some View {
        HStack(spacing: 2) {
            tool("strikethrough", struck ? "Struck" : nil, help: "Strike (\u{232B})", action: strike)
            tool("curlybraces", held ? "Held" : nil, help: "Hold (H)", action: hold)
            Menu { moveMenu } label: { Image(systemName: "arrow.up.and.down").font(.system(size: 13, weight: .medium)).frame(width: 26, height: 26).contentShape(Rectangle()) }
                .menuStyle(.button).buttonStyle(.gate(.ghost, .small, icon: true)).menuIndicator(.hidden).fixedSize()
                .help("Move after another line (or drag the line)").accessibilityLabel("Move")
            tool("quote.opening", nil, help: "Other readings (R)", action: readings).disabled(!canReadings)
        }
        .padding(4)
        .frame(height: 36)
        .gateGlass(10)
    }
    @ViewBuilder private func tool(_ icon: String, _ label: String?, help: String, action: @escaping () -> Void) -> some View {
        if let label {
            Button(action: action) { HStack(spacing: 5) { Image(systemName: icon).font(.system(size: 13, weight: .medium)); Text(label) } }
                .buttonStyle(PressedToolStyle()).help(help)
        } else {
            Button(action: action) { Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 26, height: 26) }
                .buttonStyle(.gate(.ghost, .small, icon: true)).help(help).accessibilityLabel(help)
        }
    }
}

/// `.btn.sm.s-press`: a small raised button that stays pressed.
private struct PressedToolStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Gate.Surface.panel).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
            .offset(y: 0.5)
            .contentShape(Rectangle())
    }
}

enum ScriptPageSpace { static let name = "scriptPage" }

/// One horizontal shake when a gesture is refused.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat { get { shakes } set { shakes = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(shakes * .pi * 4), y: 0))
    }
}

import SwiftUI
import AppKit
import DirectionCore

// Small pieces the Cut room's sheet draws in several places. Recipes: gate.css, css/notes.css, css/changes.css.

/// `.chip.k`: a quiet label chip with a hairline and no fill (kinds, "From screening").
struct LabelChip: View {
    let text: String
    var icon: String? = nil
    init(_ text: String, icon: String? = nil) { self.text = text; self.icon = icon }
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 7).frame(height: Gate.Size.chip)
        .overlay(RoundedRectangle(cornerRadius: Gate.Radius.chip).strokeBorder(Gate.Line.subtle, lineWidth: 1))
    }
}

/// A permanent note number: amber for the director's notes, steel for notes from outside people.
struct NoteNumber: View {
    var note: ReviewComment
    var size: CGFloat = 14
    var body: some View {
        Text(note.number.map(String.init) ?? "–")
            .font(.system(size: size, weight: .semibold, design: .monospaced)).monospacedDigit()
            .foregroundStyle(note.isOutside ? Gate.Text.secondary : Gate.Voice.director)
            .lineLimit(1).fixedSize()
    }
}

/// Lays children out in rows, wrapping between them; chips never wrap inside themselves.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

extension View {
    /// CSS line-height: the extra leading split above, below and between lines.
    func lineHeight(_ size: CGFloat, _ multiple: CGFloat, mono: Bool = false) -> some View {
        let extra = max(0, size * multiple - SwiftUILineHeight.of(size))
        return lineSpacing(extra).padding(.vertical, extra / 2)
    }
}

/// SwiftUI lays SF Pro and SF Mono lines out on whole points (13 pt → 16). Measured on macOS 26.
enum SwiftUILineHeight {
    static func of(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<11.75: 14
        case ..<12.75: 15
        case ..<13.75: 16
        case ..<14.5: 17
        default: ceil(NSFont.systemFont(ofSize: size).ascender - NSFont.systemFont(ofSize: size).descender)
        }
    }
}

extension AnyTransition {
    /// Notices slide down 8 pt and fade in; with Reduce Motion they only fade.
    @MainActor static var noticeArrival: AnyTransition {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .opacity : .offset(y: -8).combined(with: .opacity)
    }
}

/// `.notice`: a block at the top of the panel. Editor voice is prism-edged; can't and stopped are alert.
enum NoticeTone { case plain, voice, cant, error }

struct Notice<Content: View>: View {
    var tone: NoticeTone = .plain
    /// Panel notices sit 16 pt in from the sides with 12 pt above and below.
    var inset = true
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                switch tone {
                case .plain: shape.fill(Gate.Surface.panel).overlay(shape.strokeBorder(Gate.Line.subtle, lineWidth: 1))
                case .voice: shape.fill(Gate.Surface.panel).overlay(shape.strokeBorder(Gate.Voice.prism, lineWidth: 1))
                case .cant: shape.fill(Gate.Surface.panel).overlay(shape.strokeBorder(Gate.State.alert.opacity(0.45), lineWidth: 1))
                case .error: shape.fill(Gate.Surface.panel).overlay(shape.fill(Gate.State.alert.opacity(0.07))).overlay(shape.strokeBorder(Gate.State.alert.opacity(0.45), lineWidth: 1))
                }
            }
            .padding(.horizontal, inset ? 16 : 0).padding(.vertical, inset ? 12 : 0)
    }
}

/// `.notice p` with its `small` second line.
struct NoticeText: View {
    var text: String
    var small: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).lineHeight(13, 1.45).fixedSize(horizontal: false, vertical: true)
            if let small, !small.isEmpty { Text(small).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// A take still for a choice: the take's poster frame, or its scene's stand-in.
struct TakeThumb: View {
    var model: FilmModel
    var assetID: String?
    var fallbackScene: Int = 2
    var body: some View {
        let scene = assetID.flatMap { model.dailies.scene(for: $0) }?.number ?? fallbackScene
        Thumbnail(path: model.asset(assetID)?.thumbnailPath, art: FootageArt.forScene(scene))
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// The sheet's and panel's `more` button.
struct MoreMenu<Items: View>: View {
    var label = "More"
    @ViewBuilder var items: Items
    var body: some View {
        Menu { items } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.secondary)
                .frame(width: Gate.Size.controlSmall, height: Gate.Size.controlSmall).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.gate(.ghost, .small, icon: true)).menuIndicator(.hidden).fixedSize()
        .help(label).accessibilityLabel(label)
    }
}

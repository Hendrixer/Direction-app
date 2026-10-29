import SwiftUI
import AppKit

// Small pieces shared by the system views (Share, Settings, command menu, banners).
// Recipes: design/spec/gate.css (.modal, .set-*, .pop, .lrow, .kbd.s) and css/system.css.

// MARK: Accessibility-aware materials

/// Increase Contrast: hairlines use line-2 instead of line.
struct SystemHairline: View {
    var vertical = false
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        (contrast == .increased ? Gate.Line.strong : Gate.Line.subtle).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// `.set-card`: panel fill, radius 10, inset hairline.
struct SystemCardBackground: View {
    var radius: CGFloat = Gate.Radius.card
    var fill: Color = Gate.Surface.panel
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(contrast == .increased ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1))
    }
}

/// `.pop` and `.cmd`: panel fill, line-2 ring, a 6% top lip and a deep shadow.
struct SystemPopBackground: View {
    var radius: CGFloat = 12
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Gate.Surface.panel)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Gate.Line.strong, lineWidth: 1))
            .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1).padding(.horizontal, radius).padding(.top, 1) }
            .shadow(color: .black.opacity(0.9), radius: 30, y: 24)
    }
}

// MARK: Sheets

/// A sheet attached under the titlebar (or under a banner), over a scrim that starts at the
/// same edge, so the titlebar stays live. Bottom corners only, radius 14. esc closes.
struct SystemSheet<Content: View>: View {
    var width: CGFloat = 560
    var top: CGFloat = Gate.Size.titlebar
    var label: String
    var onDismiss: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 0, style: .continuous)
        ZStack(alignment: .top) {
            Gate.Surface.scrim.padding(.top, top).contentShape(Rectangle()).onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(width: width)
                .background(Gate.Surface.ground)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Gate.Line.strong, lineWidth: 1))
                .shadow(color: .black.opacity(0.9), radius: 40, y: 30)
                .padding(.top, top)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isModal)
                .onExitCommand(perform: onDismiss)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
    }
}

/// `.modal-head` with a brand-m (Archivo 17) title.
struct SystemSheetHead<Extra: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var extra: Extra
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.45, size: 12).fixedSize(horizontal: false, vertical: true) }
            extra
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 6)
    }
}

extension SystemSheetHead where Extra == EmptyView {
    init(title: String, subtitle: String?) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// `.modal-foot`: hairline on top, padding 14/22/18.
struct SystemSheetFoot<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { SystemHairline() }
    }
}

// MARK: Settings rows

/// `.label` above a `.set-card`, with an optional `.set-note` under it.
struct SettingsGroup<Content: View>: View {
    var label: String
    var note: AnyView? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.label` is 10.5 on a 10.5 line box; SF's taller box is taken out of the padding.
            SectionLabel(label).padding(.top, 13).padding(.bottom, 5.5)
            VStack(spacing: 0) { content }
                .background(SystemCardBackground())
                .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous))
            if let note { note.padding(.top, 8).padding(.horizontal, 2) }
        }
        .padding(.top, 2).padding(.bottom, 6)
    }
}

/// `.set-note`.
struct SettingsNote: View {
    var text: Text
    init(_ string: String) { text = Text(string) }
    init(_ text: Text) { self.text = text }
    var body: some View { text.font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.45, size: 11.5).fixedSize(horizontal: false, vertical: true) }
}

extension View {
    /// A CSS line-height: grows SF's natural line box (about 1.19 × size) to `ratio` × size,
    /// as extra line spacing between lines and half-leading above and below.
    func cssLineHeight(_ ratio: CGFloat, size: CGFloat) -> some View {
        let extra = max(0, size * ratio - size * 1.19)
        return lineSpacing(extra).padding(.vertical, extra / 2)
    }
}

/// `.set-row`: label (and sub-label) on the left, the control on the right. Hairline above all but the first.
struct SettingsRow<Control: View>: View {
    var label: String
    var detail: String? = nil
    var first = false
    var minHeight: CGFloat = 44
    @ViewBuilder var control: Control
    /// The command menu opens Settings at a row and flashes it for 1 s.
    @AppStorage(SettingsKey.settingsFlash) private var flash = ""
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13)
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { control }.fixedSize()
                .accessibilityLabel(label)
                .accessibilityHint(detail ?? "")
        }
        .opacity(enabled ? 1 : 0.5)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: minHeight)
        .background(flash == label ? Gate.Surface.hover : .clear)
        .overlay(alignment: .top) { if !first { SystemHairline() } }
        .accessibilityElement(children: .contain)
        .task(id: flash) {
            guard flash == label else { return }
            try? await Task.sleep(for: .seconds(1))
            withAnimation(Gate.Motion.settle) { flash = "" }
        }
    }
}

/// A Gate switch on its own (no label), for the right side of a row.
struct GateSwitch: View {
    @Binding var isOn: Bool
    var body: some View { Toggle("", isOn: $isOn).toggleStyle(GateSwitchStyle()).labelsHidden().fixedSize() }
}

/// `.stepper`: a value and − / + segments.
struct GateStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        HStack(spacing: 0) {
            Text(format(value)).font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(Gate.Text.primary).padding(.horizontal, 10)
            segment("−", disabled: value <= range.lowerBound) { value = max(range.lowerBound, value - step) }
            segment("+", disabled: value >= range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .frame(height: Gate.Size.control)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.control).fill(Gate.Surface.sunken).overlay(RoundedRectangle(cornerRadius: Gate.Radius.control).strokeBorder(Gate.Line.strong, lineWidth: 1)))
        .opacity(enabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { d in
            switch d { case .increment: value = min(range.upperBound, value + step); case .decrement: value = max(range.lowerBound, value - step); @unknown default: break }
        }
    }
    private func segment(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol).font(.system(size: 13)).foregroundStyle(Gate.Text.tertiary).frame(width: 22).frame(maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled)
        .overlay(alignment: .leading) { Gate.Line.subtle.frame(width: 1) }
    }
}

// MARK: Keys

/// `.kbd.s`: 18 pt key caps for hints in footers and notes.
struct SmallKbd: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Gate.Text.secondary)
            .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [Gate.Surface.hover, Gate.Surface.raised], startPoint: .top, endPoint: .bottom)).shadow(color: .black.opacity(0.8), radius: 0, y: 1))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
    }
}

/// A row of key caps: ⌘ ⇧ P.
struct KeyCaps: View {
    var keys: [String]
    var small = false
    var dimmed = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                if small { SmallKbd(k) } else { Kbd(k) }
            }
        }
        .opacity(dimmed ? 0.45 : 1)
        .accessibilityElement()
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

// MARK: Misc

/// `.chip.k`: a quiet label chip in the UI font, outlined, no fill.
struct OutlineChip: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary).lineLimit(1).fixedSize()
            .padding(.horizontal, 7).frame(height: Gate.Size.chip)
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.chip).strokeBorder(Gate.Line.subtle, lineWidth: 1))
    }
}

/// A neutral initials avatar (`.av`), steel, never amber.
struct InitialsAvatar: View {
    var initials: String
    var size: CGFloat = 22
    var body: some View {
        Text(initials).font(.system(size: size * 0.38, weight: .semibold)).tracking(0.2).foregroundStyle(Gate.Text.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(Gate.Surface.hover)).overlay(Circle().strokeBorder(Gate.Line.strong, lineWidth: 1))
    }
}

/// The 14 pt `.spinner`: a line-2 ring with a text-1 top arc.
struct RingSpinner: View {
    var size: CGFloat = 14
    @State private var angle = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(Gate.Line.strong, lineWidth: 1.5)
            Circle().trim(from: 0, to: 0.25).stroke(Gate.Text.primary, style: .init(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(angle - 90))
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 } }
        .accessibilityLabel("Working")
    }
}

/// One line of text in several weights and colors: "**You're offline.** You can watch…".
struct TextRun {
    var text: String
    var color: Color = Gate.Text.primary
    var weight: Font.Weight = .regular
    init(_ text: String, _ color: Color = Gate.Text.primary, _ weight: Font.Weight = .regular) { self.text = text; self.color = color; self.weight = weight }

    static func line(_ runs: [TextRun], size: CGFloat) -> Text {
        var out = AttributedString()
        for r in runs {
            var piece = AttributedString(r.text)
            piece.font = .system(size: size, weight: r.weight)
            piece.foregroundColor = r.color
            out.append(piece)
        }
        return Text(out)
    }
}

/// Snapshot state for the system overlays, keyed by the film model so it never leaks between frames.
@MainActor
enum SystemPreview {
    static var commandQuery: [ObjectIdentifier: String] = [:]
    static var relink: [ObjectIdentifier: RelinkSearch.Snapshot] = [:]
}

enum SystemSupport {
    /// Copies plain text to the general pasteboard.
    @MainActor static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Whether this process is a bundled app (UserNotifications needs one; snapshots aren't).
    static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Byte counts as the Finder shows them: "61.4 GB".
    static func bytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: bytes)
    }
}

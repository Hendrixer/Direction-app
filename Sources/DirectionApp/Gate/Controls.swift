import SwiftUI
import DirectionCore

// MARK: Buttons

enum GateButtonKind { case normal, steel, ghost, danger
    /// `.btn.ghost.danger`: a text button in the alert color (Stop the editor, frame 57).
    case ghostDanger
}
enum GateButtonSize { case regular, large, small }

/// Raised, steel (one per window state), ghost and danger buttons. 28 pt, radius 8.
struct GateButtonStyle: ButtonStyle {
    var kind: GateButtonKind = .normal
    var size: GateButtonSize = .regular
    var iconOnly = false
    func makeBody(configuration: Configuration) -> some View { GateButtonBody(configuration: configuration, kind: kind, size: size, iconOnly: iconOnly) }
}

private struct GateButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: GateButtonKind, size: GateButtonSize, iconOnly: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var height: CGFloat { switch size { case .regular: Gate.Size.control; case .large: Gate.Size.controlLarge; case .small: Gate.Size.controlSmall } }
    var radius: CGFloat { switch size { case .regular: Gate.Radius.control; case .large: 10; case .small: 6 } }
    var font: Font { switch size { case .regular: .system(size: 12.5, weight: kind == .steel ? .semibold : .medium); case .large: .system(size: 13, weight: kind == .steel ? .semibold : .medium); case .small: .system(size: 11.5, weight: .medium) } }
    var paddingX: CGFloat { iconOnly ? 0 : size == .large ? 16 : size == .small ? 8 : 11 }
    var pressed: Bool { configuration.isPressed }
    var foreground: Color {
        switch kind {
        case .steel: Gate.Component.Button.steelInk
        case .ghost: hovered ? Gate.Text.primary : Gate.Text.secondary
        case .danger, .ghostDanger: Gate.State.alert
        case .normal: Gate.Text.primary
        }
    }
    var body: some View {
        configuration.label
            .font(font).foregroundStyle(foreground).labelStyle(GateLabelStyle())
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, paddingX)
            .frame(minWidth: iconOnly ? height : nil, minHeight: height, maxHeight: height)
            .background { background }
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .offset(y: pressed && kind != .ghost && kind != .ghostDanger ? 0.5 : 0)
            .opacity(enabled ? 1 : Gate.Component.Button.disabledOpacity)
            .onHover { hovered = $0 }
            .animation(gateAnimation(Gate.Motion.snap), value: hovered)
    }
    @ViewBuilder var background: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch kind {
        case .steel:
            let top = pressed ? Gate.Component.Button.steelBottom : hovered ? Gate.Component.Button.steelHoverTop : Gate.Component.Button.steelTop
            let bottom = pressed ? Color(oklch: 0.96, 0.002, 265) : hovered ? Gate.Component.Button.steelHoverBottom : Gate.Component.Button.steelBottom
            shape.fill(LinearGradient(stops: [.init(color: top, location: 0), .init(color: bottom, location: 0.92)], startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
                .overlay(alignment: .top) { shape.stroke(Color.white, lineWidth: 1).mask(VStack(spacing: 0) { Color.white.frame(height: 1); Spacer(minLength: 0) }).padding(.horizontal, 1) }
                .overlay(alignment: .bottom) { shape.stroke(Color.black.opacity(0.22), lineWidth: 1).mask(VStack(spacing: 0) { Spacer(minLength: 0); Color.white.frame(height: 1) }).padding(.horizontal, 1) }
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        case .ghost, .ghostDanger:
            shape.fill(hovered ? Gate.Surface.raised : .clear)
        case .normal, .danger:
            shape.fill(pressed ? Gate.Surface.panel : hovered ? Gate.Surface.hover : Gate.Surface.raised)
                .overlay(shape.strokeBorder(Gate.Line.subtle, lineWidth: 1))
                .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1).padding(.horizontal, radius / 2).padding(.top, 1) }
        }
    }
}

struct GateLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 12, weight: .medium)).imageScale(.medium); configuration.title }
    }
}

extension ButtonStyle where Self == GateButtonStyle {
    static var gate: GateButtonStyle { .init() }
    static var steel: GateButtonStyle { .init(kind: .steel) }
    static var ghost: GateButtonStyle { .init(kind: .ghost) }
    static func gate(_ kind: GateButtonKind = .normal, _ size: GateButtonSize = .regular, icon: Bool = false) -> GateButtonStyle { .init(kind: kind, size: size, iconOnly: icon) }
}

/// Inline key hint inside a button: "Add ↩".
struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 11, weight: .medium)).opacity(0.55) }
}

/// Mono count tag inside a button: "Turn over [2]".
struct CountTag: View {
    let text: String
    var onSteel = false
    init(_ text: String, onSteel: Bool = false) { self.text = text; self.onSteel = onSteel }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold, design: .monospaced)).monospacedDigit()
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(onSteel ? Color.black.opacity(0.12) : Color.white.opacity(0.08)))
    }
}

// MARK: Chips, keys, counts

enum ChipStyle { case plain, director, agent, ok, bad, label }

struct Chip: View {
    let text: String
    var style: ChipStyle = .plain
    var icon: String? = nil
    var mono = true
    init(_ text: String, style: ChipStyle = .plain, icon: String? = nil, mono: Bool = true) { self.text = text; self.style = style; self.icon = icon; self.mono = mono }
    var colors: (Color, Color?) {
        switch style {
        case .plain: (Gate.Text.secondary, Gate.Surface.raised)
        case .director: (Gate.Voice.director, Gate.Voice.directorWash)
        case .agent: (Gate.Voice.agent, Gate.Voice.agentWash)
        case .ok: (Gate.State.approve, Gate.State.approveWash)
        case .bad: (Gate.State.alert, Gate.State.alertWash)
        case .label: (Gate.Text.tertiary, nil)
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .semibold)) }
            Text(text).font(style == .label || !mono ? .system(size: 11, weight: .medium) : Gate.Font.mono)
        }
        .foregroundStyle(colors.0).lineLimit(1).fixedSize()
        .padding(.horizontal, 7).frame(height: Gate.Size.chip)
        .background {
            if let fill = colors.1 {
                RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(fill)
                    .overlay { if style == .plain { RoundedRectangle(cornerRadius: Gate.Radius.chip).strokeBorder(Gate.Line.subtle, lineWidth: 1) } }
            } else {
                // Label chips (.chip.k): no fill, the hairline only.
                RoundedRectangle(cornerRadius: Gate.Radius.chip).strokeBorder(Gate.Line.subtle, lineWidth: 1)
            }
        }
    }
}

struct Kbd: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Gate.Text.secondary)
            .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Gate.Surface.hover, Gate.Surface.raised], startPoint: .top, endPoint: .bottom)).shadow(color: .black.opacity(0.8), radius: 0, y: 1))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
    }
}

struct Avatar: View {
    let person: Person
    var size: CGFloat = 22
    var body: some View {
        Text(person.initials).font(.system(size: size * 0.43, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            .frame(width: size, height: size).background(Circle().fill(Gate.Surface.hover)).overlay(Circle().strokeBorder(Gate.Line.strong, lineWidth: 1))
            .accessibilityLabel(person.name)
    }
}

// MARK: Fields

/// Single-line input: sunken, 28 pt, focus ring. Use on a TextField: `.gateField(focused:)`.
extension View {
    func gateField(focused: Bool = false, error: Bool = false) -> some View {
        textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
            .padding(.horizontal, 10).frame(minHeight: Gate.Size.control)
            .background(GateFieldBackground(focused: focused, error: error))
    }
}

struct GateFieldBackground: View {
    var focused = false
    var error = false
    var body: some View {
        RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(Gate.Surface.sunken)
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(error ? Gate.State.alert : focused ? Gate.Text.secondary : Gate.Line.strong, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: Gate.Radius.control + 3, style: .continuous).fill(error ? Gate.State.alertWash : Color.white.opacity(0.08)).padding(-3).opacity(focused || error ? 1 : 0))
    }
}

/// Multi-line note field with a placeholder.
struct GateTextArea: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 64
    var focused: FocusState<Bool>.Binding? = nil
    var onSubmit: (() -> Void)? = nil
    @FocusState private var ownFocus: Bool
    var isFocused: Bool { focused?.wrappedValue ?? ownFocus }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty { Text(placeholder).font(Gate.Font.body).foregroundStyle(Gate.Text.disabled).padding(.horizontal, 11).padding(.vertical, 9).allowsHitTesting(false) }
            editor
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
        .background(GateFieldBackground(focused: isFocused))
    }
    @ViewBuilder var editor: some View {
        let base = TextField("", text: $text, axis: .vertical).textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
            .lineSpacing(2).padding(.horizontal, 11).padding(.vertical, 9)
            .onSubmit { onSubmit?() }
        if let focused { base.focused(focused) } else { base.focused($ownFocus) }
    }
}

// MARK: Segmented, switch, check, radio

struct GateSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    /// An image before an option's title, such as a program's icon.
    var images: [Value: NSImage] = [:]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                Button { selection = value } label: {
                    HStack(spacing: 6) {
                        if let image = images[value] { Image(nsImage: image).resizable().interpolation(.high).frame(width: 14, height: 14).opacity(selection == value ? 1 : 0.7) }
                        Text(title)
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(selection == value ? Gate.Text.primary : Gate.Text.tertiary)
                        .padding(.horizontal, 11).frame(height: 24)
                        .background { if selection == value { RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle, lineWidth: 1)).shadow(color: .black.opacity(0.5), radius: 1, y: 1) } }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 9).fill(Gate.Surface.canvas).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
    }
}

/// Never colored: off is a steel track, on is a steel-9 track with a dark knob.
struct GateSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Gate.Steel.ramp[9] : Gate.Surface.hover)
                    .overlay { if !configuration.isOn { Capsule().strokeBorder(Gate.Line.strong, lineWidth: 1) } }
                Circle().fill(configuration.isOn ? Gate.Steel.ramp[2] : Gate.Steel.ramp[8]).frame(width: 14, height: 14).shadow(color: .black.opacity(0.6), radius: 1, y: 1).padding(2)
            }
            .frame(width: 32, height: 18)
            .onTapGesture { withAnimation(gateAnimation(Gate.Motion.snap)) { configuration.isOn.toggle() } }
        }
    }
}

struct GateCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(configuration.isOn ? Gate.Steel.ramp[9] : Gate.Surface.sunken)
                    .overlay { if !configuration.isOn { RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.strong, lineWidth: 1) } }
                    .overlay { if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Gate.Steel.ramp[1]) } }
                    .frame(width: 15, height: 15)
                configuration.label.font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct RadioDot: View {
    var on: Bool
    var body: some View {
        Circle().fill(on ? Gate.Steel.ramp[9] : Gate.Surface.sunken)
            .overlay { if !on { Circle().strokeBorder(Gate.Line.strong, lineWidth: 1) } }
            .overlay { if on { Circle().fill(Gate.Steel.ramp[1]).padding(4.5) } }
            .frame(width: 15, height: 15)
    }
}

/// Feeling, Story, Pace, Picture, Sound. The editor's suggestion shows as an ion outline.
struct KindPicker: View {
    @Binding var kind: NoteKind?
    var suggested: NoteKind? = nil
    var body: some View {
        HStack(spacing: 3) {
            ForEach(NoteKind.allCases, id: \.self) { k in
                Button { kind = kind == k ? nil : k } label: {
                    HStack(spacing: 4) {
                        if suggested == k && kind != k { GemMark(size: 5, solid: true) }
                        Text(k.label)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(kind == k ? Gate.Text.primary : suggested == k ? Gate.Voice.agent : Gate.Text.tertiary)
                    .padding(.horizontal, 7).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(kind == k ? Gate.Surface.raised : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(kind == k ? Gate.Line.strong : suggested == k ? Gate.Voice.agent.opacity(0.4) : Gate.Line.subtle, lineWidth: 1))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(kind == k ? .isSelected : [])
            }
        }
    }
}

/// A pop-up button in Gate colors.
struct GateSelect<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    /// Text-3 label, for selects inside a quiet row (the composer's anchor).
    var muted = false
    /// A wider select keeps its chevron at the right edge (the Version select, frame 56).
    var minWidth: CGFloat? = nil
    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in Button(options[i].1) { selection = options[i].0 } }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == selection }?.1 ?? "").font(.system(size: 12.5))
                if minWidth != nil { Spacer(minLength: 0) }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Gate.Text.tertiary)
            }
            .foregroundStyle(muted ? Gate.Text.tertiary : Gate.Text.primary).padding(.leading, 10).padding(.trailing, 8).frame(minWidth: minWidth, minHeight: Gate.Size.control, maxHeight: Gate.Size.control)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.control).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: Gate.Radius.control).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

// MARK: Progress

struct GateProgress: View {
    var value: Double?
    var agent = false
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Gate.Surface.hover)
                if let value {
                    Capsule().fill(agent ? AnyShapeStyle(Gate.Voice.prism) : AnyShapeStyle(Gate.Steel.ramp[8])).frame(width: proxy.size.width * max(0, min(1, value)))
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Gate.Motion.shimmerPeriod) / Gate.Motion.shimmerPeriod
                        Capsule().fill(Gate.Voice.prism).frame(width: proxy.size.width * 0.3).offset(x: proxy.size.width * (t * 1.3 - 0.3))
                    }.clipShape(Capsule())
                }
            }
        }.frame(height: 4)
    }
}

struct GateSpinner: View {
    var body: some View { ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 14, height: 14) }
}

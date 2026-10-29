import SwiftUI

/// A sheet attached under the titlebar over a 55% scrim. Glide in, esc closes, ⌘↩ confirms.
struct AttachedSheet<Content: View>: View {
    var width: CGFloat = 560
    var center = false
    var onDismiss: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: center ? .center : .top) {
            Gate.Surface.scrim.ignoresSafeArea().onTapGesture(perform: onDismiss)
            VStack(spacing: 0) { content }
                .frame(width: width)
                .background(Gate.Surface.ground)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: center ? 14 : 0, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: center ? 14 : 0))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: center ? 14 : 0, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: center ? 14 : 0).strokeBorder(Gate.Line.strong, lineWidth: 1))
                .shadow(color: .black.opacity(0.9), radius: 40, y: 30)
                .padding(.top, center ? 0 : Gate.Size.titlebar)
                .onExitCommand(perform: onDismiss)
        }
        .transition(.opacity)
    }
}

struct SheetHeader: View {
    var title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary)
            if let subtitle { Text(subtitle).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 6)
    }
}

struct SheetFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 8) { leading; Spacer(minLength: 8); trailing }
            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 18).hairlineBorder(.top)
    }
}

/// Popover card: panel fill, radius 12, deep shadow. Settle in.
struct PopoverCard<Content: View>: View {
    var width: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6).frame(width: width)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Gate.Surface.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Gate.Line.strong, lineWidth: 1))
            .shadow(color: .black.opacity(0.9), radius: 30, y: 24)
    }
}

struct Toast: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var detail: String?
    var editor = false
    var actionTitle: String?
    var glass = false
    /// What the action button does. Without one, the window decides (a ready cut opens Changes).
    var run: (@MainActor () -> Void)? = nil
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

struct ToastView: View {
    var toast: Toast
    var action: (() -> Void)?
    var dismiss: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            if toast.editor { GemMark(size: 7) } else { PinMark() }
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                if let detail = toast.detail { Text(detail).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
            }
            Spacer(minLength: 8)
            if let title = toast.actionTitle, let action { Button(title, action: action).buttonStyle(.gate(.ghost, .small)) }
            else { Button("Dismiss", action: dismiss).buttonStyle(.gate(.ghost, .small)) }
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .frame(minWidth: 320, maxWidth: 440)
        .background {
            if toast.glass { GlassBackground(radius: 12) }
            else { RoundedRectangle(cornerRadius: 12).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)).shadow(color: .black.opacity(0.8), radius: 20, y: 20) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Full-width line under the titlebar: offline, missing footage.
struct Banner<Trailing: View>: View {
    var icon: String
    var title: String
    var detail: String
    var alert = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(alert ? Gate.State.alert : Gate.Text.secondary)
            (Text(title).fontWeight(.semibold) + Text(" ") + Text(detail).foregroundColor(Gate.Text.secondary)).font(.system(size: 12.5)).lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).frame(height: 36)
        .background(alert ? Gate.State.alert.opacity(0.14) : Gate.Surface.panel)
        .hairlineBorder(.bottom)
    }
}

/// Archivo title, one sentence, one action.
struct EmptyStateView<Actions: View>: View {
    var art: Image?
    var title: String
    var message: String
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 14) {
            if let art { art.resizable().scaledToFit().frame(width: 96).shadow(color: .black.opacity(0.8), radius: 15, y: 20) }
            Text(title).font(Gate.Font.brand(size: 24, width: 120)).foregroundStyle(Gate.Text.primary)
            Text(message).font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary).multilineTextAlignment(.center).frame(maxWidth: 360)
            HStack(spacing: 8) { actions }.padding(.top, 4)
        }.padding(40)
    }
}

// MARK: Editor pill

enum EditorPillState: Equatable {
    case ready, waiting, readingBack(String), readBackReady, working(String, Double?), asks(Int), cant(Int), stopped, offline, paused, assembling(String, Double?), cutReady(String), needsFootage
    var text: String {
        switch self {
        case .ready: "Ready"
        case .waiting: "Waiting for the editor"
        case .readingBack(let s), .cutReady(let s): s
        case .readBackReady: "Read-back ready"
        case .working(let s, _), .assembling(let s, _): s
        case .asks(let n): n == 1 ? "1 question" : "\(n) questions"
        case .cant(let n): "Can't do \(n)"
        case .stopped: "Stopped"
        case .needsFootage: "Waiting for footage"
        case .offline: "Offline"
        case .paused: "Paused"
        }
    }
}

/// Always in the titlebar, always truthful. Click opens the editor popover.
struct EditorPill: View {
    var state: EditorPillState
    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .offline: Image(systemName: "wifi.slash").font(.system(size: 10, weight: .semibold))
            case .stopped, .cant, .needsFootage: GemMark(size: 7, color: Gate.State.alert)
            case .ready, .paused, .waiting: GemMark(size: 7, color: Gate.Text.disabled)
            default: GemMark(size: 7)
            }
            Text(state.text)
            if case .working(_, let p) = state { meter(p) }
            if case .assembling(_, let p) = state { meter(p) }
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(foreground).lineLimit(1).fixedSize()
        .padding(.leading, 10).padding(.trailing, 11).frame(height: Gate.Size.pill)
        .background { background }
        .contentShape(Capsule())
        .accessibilityLabel("Editor: \(state.text)")
    }
    private func meter(_ p: Double?) -> some View {
        GateProgress(value: p, agent: true).frame(width: 40, height: 3)
    }
    private var foreground: Color {
        switch state {
        case .asks: Gate.Voice.agent
        case .cutReady, .readBackReady: Gate.Text.primary
        case .cant, .stopped, .needsFootage: Gate.State.alert
        case .working, .assembling, .readingBack: Gate.Text.primary
        case .offline, .paused: Gate.Text.tertiary
        default: Gate.Text.secondary
        }
    }
    @ViewBuilder private var background: some View {
        switch state {
        case .working, .assembling, .readingBack:
            Capsule().fill(Gate.Surface.panel).overlay(ShimmerBorder())
        case .asks, .readBackReady:
            Capsule().fill(Gate.Surface.panel).overlay(Capsule().strokeBorder(Gate.Voice.agent.opacity(0.45), lineWidth: 1))
        case .cutReady:
            Capsule().fill(Gate.Surface.panel).overlay(Capsule().strokeBorder(Gate.Line.strong, lineWidth: 1))
        case .cant, .stopped, .needsFootage:
            Capsule().fill(Gate.Surface.panel).overlay(Capsule().strokeBorder(Gate.State.alert.opacity(0.45), lineWidth: 1))
        default:
            Capsule().fill(Gate.Surface.panel).overlay(Capsule().strokeBorder(Gate.Line.subtle, lineWidth: 1))
        }
    }
}

/// The prism border that slides while the editor works (2.4 s loop). Static under Reduce Motion.
struct ShimmerBorder: View {
    var body: some View {
        if SettingsKey.reducesMotion {
            Capsule().strokeBorder(Gate.Voice.prism, lineWidth: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Gate.Motion.shimmerPeriod) / Gate.Motion.shimmerPeriod
                Capsule().strokeBorder(AngularGradient(colors: Gate.Voice.prismStops + [Gate.Voice.prismStops[0]], center: .center, angle: .degrees(t * 360)), lineWidth: 1)
            }
        }
    }
}

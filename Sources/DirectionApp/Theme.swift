import SwiftUI
import AppKit

/// Compatibility names bound to Gate's semantic tokens; no component invents a palette.
enum Palette {
    static let background = Gate.Surface.ground
    static let panel = Gate.Surface.panel
    static let raised = Gate.Surface.raised
    static let inset = Gate.Surface.sunken
    static let line = Gate.Line.subtle
    static let text = Gate.Text.primary
    static let muted = Gate.Text.secondary
    static let faint = Gate.Text.tertiary
    static let accent = Gate.Text.primary
    static let accentFill = Gate.Text.primary
    static let audio = Gate.Text.secondary
    static let marker = Gate.Voice.director
    static let spectrum = Gate.Voice.agentStroke
    static var spectral: LinearGradient { Gate.Voice.agentGradient }
    static var silver: LinearGradient { LinearGradient(colors: [Gate.Text.primary, Gate.Text.secondary], startPoint: .top, endPoint: .bottom) }
}

enum Metrics {
    static let sidebar: CGFloat = 366
    static let radius = Gate.Radius.panel
    static let inset = Gate.Space.s4
    static let control = Gate.Component.Button.height
}

@MainActor private enum SurfaceTexture {
    /// Generated once and tiled. Playback never regenerates a screen-sized noise field.
    static let grain: NSImage = {
        let side = 192
        var seed: UInt64 = 0xD1_2EC7_10
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let value = UInt8(truncatingIfNeeded: seed)
            pixels[index] = value; pixels[index + 1] = value; pixels[index + 2] = value; pixels[index + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }()
}

struct GrainOverlay: View {
    var opacity: Double = Gate.grain.window
    var body: some View {
        Image(nsImage: SurfaceTexture.grain).resizable(resizingMode: .tile)
            .interpolation(.none).blendMode(.screen).opacity(opacity)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct DirectionSurface: View {
    var cornerRadius: CGFloat = 12
    var elevated = false
    var accented = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(elevated ? Palette.raised : Palette.panel)
            .overlay { GrainOverlay().clipShape(shape) }
            .overlay { shape.strokeBorder(accented ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1) }
            .overlay(alignment: .top) {
                if elevated { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, cornerRadius) }
            }
            .allowsHitTesting(false)
    }
}

extension View {
    func directionSurface(cornerRadius: CGFloat = 12, elevated: Bool = false, accented: Bool = false) -> some View {
        background { DirectionSurface(cornerRadius: cornerRadius, elevated: elevated, accented: accented) }
    }
    func directionField(cornerRadius: CGFloat = 8) -> some View {
        background(Palette.inset, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct DirectionDivider: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(Palette.line)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

struct BrandIcon: View {
    var size: CGFloat = 36
    var body: some View {
        Group {
            if let icon = BrandAssets.icon { Image(nsImage: icon).resizable().interpolation(.high) }
            else { Image(systemName: "d.square").resizable().scaledToFit().foregroundStyle(Palette.silver) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct QuietButton: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Gate.Font.control)
            .padding(.horizontal, 12).frame(minHeight: Metrics.control)
            .foregroundStyle(prominent ? Gate.Component.Button.steelInk : Gate.Text.primary)
            .background {
                if prominent {
                    GateSteelSurface(pressed: configuration.isPressed, hovered: hovering)
                } else {
                    RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous)
                        .fill(configuration.isPressed ? Gate.Surface.panel : hovering ? Gate.Surface.hover : Gate.Surface.raised)
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1) }
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 8) }
                }
            }
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : Gate.Motion.snap, value: hovering)
    }
}

/// The guide's touching material: brushed silver, cached grain, and a bright top lip.
struct GateSteelSurface: View {
    var cornerRadius: CGFloat = Gate.Radius.control
    var pressed = false
    var hovered = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let top = pressed ? Gate.Component.Button.steelPressedTop : hovered ? Gate.Component.Button.steelHoverTop : Gate.Component.Button.steelTop
        let bottom = pressed ? Gate.Component.Button.steelPressedBottom : hovered ? Gate.Component.Button.steelHoverBottom : Gate.Component.Button.steelBottom
        shape.fill(LinearGradient(stops: [.init(color: top, location: 0), .init(color: bottom, location: 0.92)], startPoint: .top, endPoint: .bottom))
            .overlay { GrainOverlay(opacity: Gate.grain.steel).clipShape(shape) }
            .overlay { shape.strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5) }
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.9)).frame(height: 1).padding(.horizontal, cornerRadius) }
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.22)).frame(height: 1).padding(.horizontal, cornerRadius) }
            .allowsHitTesting(false)
    }
}

struct GhostButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Gate.Font.control).padding(.horizontal, 10).frame(minHeight: Metrics.control)
            .foregroundStyle(hovering ? Gate.Text.primary : Gate.Text.secondary)
            .background(hovering || configuration.isPressed ? Gate.Surface.raised : .clear, in: RoundedRectangle(cornerRadius: Gate.Radius.control))
            .opacity(enabled ? 1 : 0.4).onHover { hovering = $0 }
    }
}

struct GateGlassSurface: View {
    var cornerRadius: CGFloat = Gate.Radius.panel
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).fill(Gate.Material.glass) }
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Gate.Material.glassBorder, lineWidth: 1) }
            .overlay(alignment: .top) { Rectangle().fill(Gate.Material.glassTopLip).frame(height: 1).padding(.horizontal, cornerRadius) }
            .allowsHitTesting(false)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: Metrics.control, height: Metrics.control)
                .foregroundStyle(selected || hovering ? Palette.text : Palette.muted)
                .background {
                    if selected || hovering { RoundedRectangle(cornerRadius: 8).fill(Palette.raised) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .opacity(enabled ? 1 : 0.35)
        }.buttonStyle(.plain).help(label).accessibilityLabel(label).onHover { hovering = $0 }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View { Text(text).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) }
}

/// Non-drop frame count when paused; elapsed minutes/seconds during playback.
func timecode(_ seconds: Double, frameRate: Double = 30, frames: Bool = true) -> String {
    guard seconds.isFinite else { return frames ? "00:00:00" : "00:00" }
    let value = max(0, seconds)
    let rate = frameRate.isFinite && frameRate >= 1 && frameRate <= 240 ? frameRate : 30
    let nominal = Int(rate.rounded())
    let count = frames ? floor(value * rate + 0.000_000_1) : floor(value)
    guard count < Double(Int.max - 1024) else { return frames ? "--:--:--" : "--:--" }
    let total = Int(count)
    let elapsed = frames ? total / nominal : total
    let hours = elapsed / 3600
    let minute = elapsed / 60 % 60
    let second = elapsed % 60
    let base = hours > 0 ? String(format: "%02d:%02d:%02d", hours, minute, second)
                         : String(format: "%02d:%02d", minute, second)
    return frames ? base + String(format: ":%02d", total % nominal) : base
}

import SwiftUI
import AppKit

// Materials, marks and small shapes shared by every room. Recipes: design/spec/gate.css.

@MainActor private enum SurfaceTexture {
    /// Generated once and tiled, so playback never regenerates a screen-sized noise field.
    static let grain: NSImage = {
        let side = 180
        var seed: UInt64 = 0xD1_2EC7_10
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let value = UInt8(truncatingIfNeeded: seed)
            pixels[index] = value; pixels[index + 1] = value; pixels[index + 2] = value; pixels[index + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }()
}

/// 3.5% screen-blended noise over window chrome. Never drawn over the picture.
struct GrainOverlay: View {
    var opacity: Double = Gate.grain.window
    @AppStorage("filmGrain") private var enabled = true
    var body: some View {
        if enabled {
            Image(nsImage: SurfaceTexture.grain).resizable(resizingMode: .tile).interpolation(.none)
                .blendMode(.screen).opacity(opacity).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

// MARK: Surfaces

struct GlassBackground: View {
    var radius: CGFloat = 12
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Gate.Material.glass))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Gate.Material.glassBorder, lineWidth: 1))
            .overlay(alignment: .top) { RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Gate.Material.glassTopLip, lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08))) }
            .shadow(color: .black.opacity(0.7), radius: 20, y: 20)
    }
}

extension View {
    func gateGlass(_ radius: CGFloat = 12) -> some View { background(GlassBackground(radius: radius)) }
    /// Cards: panel fill with a hairline.
    func gatePanel(_ radius: CGFloat = Gate.Radius.card, fill: Color = Gate.Surface.panel) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill).overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
    }
    func gateWell(_ radius: CGFloat = Gate.Radius.card) -> some View { gatePanel(radius, fill: Gate.Surface.sunken) }
    /// A 1 pt prism edge: containers the editor authored (read-back).
    func prismEdge(_ radius: CGFloat = Gate.Radius.card, fill: Color = Gate.Surface.panel) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill).overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Gate.Voice.prism, lineWidth: 1)))
    }
    func hairlineBorder(_ edges: Edge.Set, color: Color = Gate.Line.subtle) -> some View {
        overlay(alignment: .top) { if edges.contains(.top) { color.frame(height: 1) } }
            .overlay(alignment: .bottom) { if edges.contains(.bottom) { color.frame(height: 1) } }
            .overlay(alignment: .leading) { if edges.contains(.leading) { color.frame(width: 1) } }
            .overlay(alignment: .trailing) { if edges.contains(.trailing) { color.frame(width: 1) } }
    }
}

struct Hairline: View {
    var vertical = false
    var body: some View { Gate.Line.subtle.frame(width: vertical ? 1 : nil, height: vertical ? nil : 1) }
}

/// White 8% 1 pt lines at 135°, 6 pt pitch: things the editor can't touch.
struct Hatching: View {
    var opacity: Double = 0.08
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width { path.move(to: .init(x: x, y: size.height)); path.addLine(to: .init(x: x + size.height, y: 0)); x += 6 }
            context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 1)
        }.allowsHitTesting(false)
    }
}

// MARK: Marks: two voices, two shapes

/// The director's mark: an amber teardrop pointing down.
struct PinMark: View {
    var size: CGFloat = 10
    var color: Color = Gate.Voice.director
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: size / 2, bottomLeadingRadius: 0, bottomTrailingRadius: size / 2, topTrailingRadius: size / 2)
            .fill(color).frame(width: size * 0.82, height: size * 0.82).rotationEffect(.degrees(-45)).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The editor's mark: a diamond, prism or solid ion.
struct GemMark: View {
    var size: CGFloat = 8
    var solid = false
    var color: Color? = nil
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5).fill(color.map(AnyShapeStyle.init) ?? (solid ? AnyShapeStyle(Gate.Voice.agent) : AnyShapeStyle(Gate.Voice.prism)))
            .frame(width: size, height: size).rotationEffect(.degrees(45)).frame(width: size + 2, height: size + 2)
            .accessibilityHidden(true)
    }
}

struct RingMark: View {
    var size: CGFloat = 10
    var body: some View { Circle().strokeBorder(Gate.Voice.director, lineWidth: 1.5).frame(width: size, height: size) }
}

/// The hand-drawn grease-pencil circle a director puts around a take.
struct HandCircle: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 38, sy = rect.height / 30
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(30, 5.5))
        path.addCurve(to: p(6.2, 6.6), control1: p(25, 1.8), control2: p(12, 1.6))
        path.addCurve(to: p(9.5, 24.6), control1: p(1, 11.2), control2: p(2.6, 21))
        path.addCurve(to: p(33.5, 21), control1: p(17.1, 28.6), control2: p(29.1, 27.2))
        path.addCurve(to: p(28.4, 6.4), control1: p(37.1, 15.9), control2: p(34.9, 9.2))
        return path
    }
}

struct HandCircleMark: View {
    var drawn: CGFloat = 1
    var body: some View {
        HandCircle().trim(from: 0, to: drawn).stroke(Gate.Voice.director, style: .init(lineWidth: 1.8, lineCap: .round)).frame(width: 38, height: 30)
    }
}

/// Small amber halo for a mark that just dropped (Settle).
struct FreshHalo: View {
    var body: some View { Circle().strokeBorder(Gate.Voice.director.opacity(0.45), lineWidth: 1.5).frame(width: 18, height: 18).shadow(color: Gate.Voice.director, radius: 4) }
}

// MARK: Text helpers

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(Gate.Font.label).tracking(0.74).foregroundStyle(Gate.Text.disabled).lineLimit(1) }
}

extension View {
    func brandText(_ font: Font) -> some View { self.font(font).foregroundStyle(Gate.Text.primary) }
}

/// Reduce Motion aware animation.
@MainActor func gateAnimation(_ animation: Animation) -> Animation? {
    SettingsKey.reducesMotion ? Gate.Motion.reduced : animation
}

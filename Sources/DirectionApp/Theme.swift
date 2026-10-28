import SwiftUI
import AppKit

/// Strictly neutral working surfaces. Color belongs to footage and the approved icon.
enum Palette {
    static let background = Color(white: 0.035)
    static let panel = Color(white: 0.085)
    static let raised = Color(white: 0.145)
    static let inset = Color(white: 0.115)
    static let line = Color.white.opacity(0.075)
    static let text = Color(white: 0.93)
    static let muted = Color(white: 0.63)
    static let faint = Color(white: 0.40)
    static let accent = Color(white: 0.88)
    static let accentFill = Color(white: 0.91)
    static let audio = Color(white: 0.74)
    static let marker = Color(white: 0.80)
    static let spectrum: [Color] = [
        Color(white: 0.65),
        Color(white: 0.85),
        Color(white: 0.91),
        Color(white: 0.75),
        Color(white: 0.60),
    ]
    static var spectral: LinearGradient { LinearGradient(colors: spectrum, startPoint: .topLeading, endPoint: .bottomTrailing) }
    static var silver: LinearGradient { LinearGradient(colors: [Color(white: 0.98), Color(white: 0.75), Color(white: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

enum Metrics {
    static let sidebar: CGFloat = 366
    static let radius: CGFloat = 12
    static let inset: CGFloat = 20
    static let control: CGFloat = 34
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
    var opacity: Double = 0.045
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
            .overlay { if elevated { GrainOverlay(opacity: 0.025).clipShape(shape) } }
            .overlay { shape.strokeBorder(Color.white.opacity(elevated ? 0.10 : 0.045), lineWidth: 1) }
            .overlay { if accented { shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1) } }
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).frame(minHeight: Metrics.control)
            .foregroundStyle(prominent ? Color(white: 0.09) : Palette.text)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accentFill)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.raised)
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1) }
                }
            }
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(enabled ? 1 : 0.35)
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
    var body: some View { Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted) }
}

func timecode(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00.00" }
    let value = max(0, seconds)
    return String(format: "%02d:%05.2f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
}

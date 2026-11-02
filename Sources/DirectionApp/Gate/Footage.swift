import SwiftUI
import AppKit
import AVKit

// MARK: Timecode

enum Timecode {
    /// MM:SS:FF under an hour, H:MM:SS:FF over. Frames at the sequence rate.
    static func format(_ seconds: Double, fps: Double = 24) -> String {
        guard seconds.isFinite, seconds < 360_000 else { return "--:--:--" }
        let s = max(0, seconds), rate = fps.isFinite ? max(1, fps.rounded()) : 24
        let total = Int(s), frames = min(Int(rate) - 1, Int(((s - Double(total)) * rate + 1e-6).rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d:%02d", h, m, sec, frames) : String(format: "%02d:%02d:%02d", m, sec, frames)
    }
    /// 3:40, 0:46.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds < 360_000 else { return "–:––" }
        let s = Int(max(0, seconds).rounded()); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
    static func range(_ a: Double, _ b: Double, fps: Double = 24) -> String { "\(format(a, fps: fps))–\(format(b, fps: fps))" }
    /// −4.2 s with a true minus sign.
    static func delta(_ seconds: Double) -> String {
        let v = (seconds * 10).rounded() / 10
        return v == 0 ? "0.0 s" : (v < 0 ? "\u{2212}" : "+") + String(format: "%.1f s", abs(v))
    }
}

/// Timecode with a dim total: "01:12:08 / 3:40".
struct TimecodeLabel: View {
    var time: Double
    var total: Double?
    var fps: Double = 24
    var body: some View {
        HStack(spacing: 4) {
            Text(Timecode.format(time, fps: fps)).foregroundStyle(Gate.Text.primary)
            if let total { Text("/ \(Timecode.duration(total))").foregroundStyle(Gate.Text.disabled) }
        }.font(Gate.Font.timecode).lineLimit(1).fixedSize()
    }
}

// MARK: Footage placeholders

/// Stand-ins for real frames, used in previews and before thumbnails exist.
enum FootageArt: String, CaseIterable, Codable { case dusk, room, night, day, hands
    static func forScene(_ number: Int) -> FootageArt { [.night, .room, .dusk, .hands, .day][max(0, number - 1) % 5] }
}

struct FootageArtView: View {
    var art: FootageArt
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                switch art {
                case .dusk:
                    LinearGradient(stops: [.init(color: Color(oklch: 0.24, 0.06, 270), location: 0), .init(color: Color(oklch: 0.42, 0.11, 300), location: 0.38), .init(color: Color(oklch: 0.70, 0.15, 45), location: 0.64), .init(color: Color(oklch: 0.55, 0.13, 30), location: 1)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(oklch: 0.93, 0.09, 80), Color(oklch: 0.80, 0.15, 55).opacity(0.7), .clear], center: .init(x: 0.64, y: 0.62), startRadius: 0, endRadius: w * 0.16)
                    Ellipse().fill(Color(oklch: 0.10, 0.02, 280)).frame(width: w * 2.8, height: h * 1.1).position(x: w * 0.5, y: h * 1.32)
                    figure(x: 0.395, bottom: 0.30, width: 0.03, height: 0.16, color: Color(oklch: 0.07, 0.01, 280), in: g.size)
                case .room:
                    LinearGradient(colors: [Color(oklch: 0.30, 0.05, 50), Color(oklch: 0.18, 0.03, 40), Color(oklch: 0.12, 0.02, 40)], startPoint: .leading, endPoint: .trailing)
                    RadialGradient(colors: [Color(oklch: 0.85, 0.10, 75).opacity(0.9), .clear], center: .init(x: 0.3, y: 0.4), startRadius: 0, endRadius: w * 0.22)
                    figure(x: 0.69, bottom: 0, width: 0.22, height: 0.62, color: Color(oklch: 0.09, 0.01, 40), in: g.size)
                case .night:
                    LinearGradient(colors: [Color(oklch: 0.10, 0.03, 265), Color(oklch: 0.18, 0.05, 260), Color(oklch: 0.26, 0.06, 250)], startPoint: .top, endPoint: .bottom)
                    ForEach(0..<9, id: \.self) { i in
                        Rectangle().fill(Color(oklch: 0.08, 0.02, 265)).frame(width: w * 0.11, height: h * [0.3, 0.38, 0.33, 0.24, 0.36, 0.29, 0.4, 0.27, 0.34][i]).position(x: w * (CGFloat(i) * 0.115 + 0.05), y: h - h * [0.3, 0.38, 0.33, 0.24, 0.36, 0.29, 0.4, 0.27, 0.34][i] / 2)
                    }
                    Circle().fill(Color(oklch: 0.75, 0.14, 200)).frame(width: w * 0.024).position(x: w * 0.2, y: h * 0.7)
                    Circle().fill(Color(oklch: 0.80, 0.14, 60)).frame(width: w * 0.018).position(x: w * 0.34, y: h * 0.62)
                case .day:
                    LinearGradient(colors: [Color(oklch: 0.68, 0.03, 240), Color(oklch: 0.55, 0.03, 220), Color(oklch: 0.32, 0.03, 150)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(oklch: 0.80, 0.02, 240), .clear], center: .init(x: 0.5, y: 0.46), startRadius: 0, endRadius: w * 0.34)
                    figure(x: 0.5, bottom: 0.18, width: 0.12, height: 0.40, color: Color(oklch: 0.22, 0.02, 30), in: g.size)
                case .hands:
                    LinearGradient(stops: [.init(color: Color(oklch: 0.16, 0.01, 260), location: 0), .init(color: Color(oklch: 0.24, 0.02, 250), location: 0.58), .init(color: Color(oklch: 0.30, 0.01, 260), location: 0.6), .init(color: Color(oklch: 0.20, 0.01, 260), location: 1)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(oklch: 0.62, 0.07, 50), .clear], center: .init(x: 0.5, y: 0.64), startRadius: 0, endRadius: w * 0.4).scaleEffect(x: 1, y: 0.65)
                    RoundedRectangle(cornerRadius: 3).fill(Color(oklch: 0.12, 0.01, 260)).frame(width: w * 0.6, height: h * 0.16).position(x: w * 0.5, y: h * 0.70).rotation3DEffect(.degrees(40), axis: (1, 0, 0))
                }
            }.frame(width: w, height: h).clipped()
        }
        .clearOfGrain()
    }
    private func figure(x: CGFloat, bottom: CGFloat, width: CGFloat, height: CGFloat, color: Color, in size: CGSize) -> some View {
        let w = size.width * width, h = size.height * height
        return ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: w * 0.48, bottomLeadingRadius: w * 0.06, bottomTrailingRadius: w * 0.06, topTrailingRadius: w * 0.48).fill(color).frame(width: w, height: h)
            Circle().fill(color).frame(width: w * 0.64).offset(y: -w * 0.55)
        }.position(x: size.width * x, y: size.height * (1 - bottom) - h / 2)
    }
}

/// A take or scene thumbnail: the real poster frame when it exists, otherwise the stand-in.
struct Thumbnail: View {
    var path: String?
    var art: FootageArt = .room
    var body: some View {
        // Fill the space it's given, never grow past it.
        if let path, let image = ThumbnailCache.image(path) { Color.clear.overlay { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }.clipped().clearOfGrain() }
        else { FootageArtView(art: art) }
    }
}

@MainActor enum ThumbnailCache {
    private static var images: [String: NSImage] = [:]
    static func image(_ path: String) -> NSImage? {
        if let cached = images[path] { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        images[path] = image; return image
    }
}

// MARK: Picture

/// The video surface. Black, aspect-fit, never under grain.
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { let v = AVPlayerView(); v.player = player; v.controlsStyle = .none; v.videoGravity = .resizeAspect; v.allowsVideoFrameAnalysis = false; return v }
    func updateNSView(_ v: AVPlayerView, context: Context) { if v.player !== player { v.player = player } }
}

/// A frame-sized picture: the live player, or a still for previews.
struct PictureView: View {
    var player: AVPlayer?
    var still: FootageArt? = nil
    var aspect: CGFloat = 16 / 9
    var body: some View {
        ZStack {
            Gate.Surface.canvas
            if let still { FootageArtView(art: still) }
            else if let player { PlayerSurface(player: player).allowsHitTesting(false) }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
        .clearOfGrain()
    }
}

/// Glass timecode tag over the picture.
struct HUDTag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Gate.Font.timecodeSmall).foregroundStyle(Gate.Text.primary).padding(.horizontal, 8).padding(.vertical, 6).gateGlass(6) }
}

/// The director's region on a frame: amber 1.5 pt, everything outside dimmed.
struct RegionOverlay: View {
    var region: CGRect
    var label: String?
    var editing = false
    var dim = 0.35
    var body: some View {
        GeometryReader { g in
            let r = CGRect(x: region.minX * g.size.width, y: region.minY * g.size.height, width: region.width * g.size.width, height: region.height * g.size.height)
            ZStack(alignment: .topLeading) {
                Path { p in p.addRect(CGRect(origin: .zero, size: g.size)); p.addRect(r) }.fill(Color.black.opacity(dim), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: Gate.Radius.frame).strokeBorder(Gate.Voice.director, lineWidth: 1.5).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                if let label {
                    Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Voice.directorInk)
                        .padding(.horizontal, 6).padding(.vertical, 4).background(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2).fill(Gate.Voice.director))
                        .fixedSize().offset(x: r.minX, y: r.minY - 18)
                }
                if editing {
                    ForEach(Array(handlePoints(r).enumerated()), id: \.offset) { _, p in RoundedRectangle(cornerRadius: 1).fill(Gate.Voice.director).frame(width: 7, height: 7).position(p) }
                }
            }
        }.allowsHitTesting(false)
    }
    private func handlePoints(_ r: CGRect) -> [CGPoint] { [CGPoint(x: r.minX, y: r.minY), .init(x: r.midX, y: r.minY), .init(x: r.maxX, y: r.minY), .init(x: r.maxX, y: r.midY), .init(x: r.maxX, y: r.maxY), .init(x: r.midX, y: r.maxY), .init(x: r.minX, y: r.maxY), .init(x: r.minX, y: r.midY)] }
}

import Foundation
import CoreGraphics
import ImageIO
import DirectionCore

/// Something the editor should fix before placing a graphic (graphics.md › Tools).
public struct GraphicProblem: Codable, Sendable, Hashable {
    /// overflow, outside_title_safe, small_text, low_contrast, too_long, not_in_words
    public var code: String
    public var message: String
    public var word: String?
    /// Which still: "0%", "25%", "50%", "75%", "100%".
    public var at: String?
}

/// One of the five stills: 0, 25, 50, 75 and 100% through the graphic.
public struct GraphicStill: Codable, Sendable {
    public var at: String
    public var time: Double
    public var path: String
}

enum GraphicChecks {
    static let titleSafe = 0.9, smallestText = 24.0, contrast = 4.5

    /// Problems on one still. `picture` is the frame behind the graphic, when Direction knows where it plays.
    static func problems(_ inspection: GraphicInspection, at label: String, picture: CGImage?, words: [GraphicWord]) -> [GraphicProblem] {
        let W = inspection.width, H = inspection.height
        let safe = CGRect(x: W * (1 - titleSafe) / 2, y: H * (1 - titleSafe) / 2, width: W * titleSafe, height: H * titleSafe).insetBy(dx: -0.5, dy: -0.5)
        var out: [GraphicProblem] = []
        for t in inspection.texts {
            let q = quote(t.text), alpha = t.color.count > 3 ? t.color[3] : 1
            switch t.overflow {
            case "box": out.append(.init(code: "overflow", message: "\(q) doesn\u{2019}t fit its box (at \(label)).", word: t.word, at: label))
            case "picture": out.append(.init(code: "overflow", message: "\(q) runs off the picture (at \(label)).", word: t.word, at: label))
            default: break
            }
            if !safe.contains(CGRect(x: t.x, y: t.y, width: t.width, height: t.height)) {
                out.append(.init(code: "outside_title_safe", message: "\(q) is outside title safe, the middle 90% of the picture (at \(label)).", word: t.word, at: label))
            }
            let at1080 = t.fontSize * 1080 / max(1, H)
            if at1080 < smallestText - 0.01 {
                out.append(.init(code: "small_text", message: "\(q) is \(Self.number(at1080)) px at 1080p. Make text at least 24 px.", word: t.word, at: label))
            }
            if t.word == nil, t.text.unicodeScalars.contains(where: CharacterSet.letters.contains) {
                out.append(.init(code: "not_in_words", message: "\(q) is visible but isn\u{2019}t in words. Put every visible word in words so the director can change it, or mark the element with data-word.", word: nil, at: label))
            }
            // Contrast is for text that's there, not text fading in or out.
            if alpha >= 0.5, let ratio = contrastRatio(t, picture: picture, width: W, height: H), ratio < contrast {
                out.append(.init(code: "low_contrast", message: "\(q) has a contrast of \(String(format: "%.1f", ratio)):1 against the picture behind it (at \(label)). It needs 4.5:1.", word: t.word, at: label))
            }
        }
        return out
    }

    static func tooLong(_ words: [GraphicWord], resolved: [String: String]) -> [GraphicProblem] {
        words.compactMap { w in
            guard let max = w.maxLength, let text = resolved[w.key], text.count > max else { return nil }
            return .init(code: "too_long", message: "\(w.label) is \(text.count) characters; its max is \(max).", word: w.key, at: nil)
        }
    }

    /// The first of each problem, by kind and words.
    static func unique(_ problems: [GraphicProblem]) -> [GraphicProblem] {
        var seen = Set<String>()
        return problems.filter { seen.insert("\($0.code)|\($0.word ?? "")|\($0.message.components(separatedBy: " (at ").first ?? $0.message)").inserted }
    }

    // MARK: Contrast (WCAG relative luminance)

    /// The text's color over what's right behind it: its own backing, else the picture. nil when unknowable.
    static func contrastRatio(_ t: GraphicText, picture: CGImage?, width W: Double, height H: Double) -> Double? {
        guard let layers = t.backing else { return nil }
        var behind: [Double]?
        if layers.last.map({ $0.count > 3 && $0[3] >= 0.999 }) != true {
            guard let picture, let mean = average(picture, CGRect(x: t.x / W, y: t.y / H, width: t.width / W, height: t.height / H)) else { return nil }
            behind = mean
        }
        for layer in layers.reversed() where layer.count > 3 {
            let a = layer[3]
            behind = (0..<3).map { layer[$0] * a + (behind?[$0] ?? 0) * (1 - a) }
        }
        guard let bg = behind, t.color.count > 3 else { return nil }
        let a = t.color[3]
        let fg = (0..<3).map { t.color[$0] * a + bg[$0] * (1 - a) }
        let l1 = luminance(fg), l2 = luminance(bg)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    static func luminance(_ rgb: [Double]) -> Double {
        let c = rgb.map { v -> Double in let s = v / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    /// The mean sRGB color of a normalized, top-left-origin region of an image.
    static func average(_ image: CGImage, _ region: CGRect) -> [Double]? {
        let w = max(1, min(64, Int((region.width * Double(image.width)).rounded()))), h = max(1, min(64, Int((region.height * Double(image.height)).rounded())))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let iw = Double(image.width), ih = Double(image.height)
        // Draw the whole picture scaled so the region fills the small context.
        let sx = Double(w) / (region.width * iw), sy = Double(h) / (region.height * ih)
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: -region.minX * iw * sx, y: -(1 - region.maxY) * ih * sy, width: iw * sx, height: ih * sy))
        var sum = [0.0, 0.0, 0.0]
        for i in 0..<(w * h) { for k in 0..<3 { sum[k] += Double(bytes[i * 4 + k]) } }
        return sum.map { $0 / Double(w * h) }
    }

    // MARK: Stills

    /// A still the editor can look at: the frame over the picture behind it (or dark steel), at most 1280 wide.
    static func still(_ frame: GraphicImage, over picture: CGImage?, to url: URL) throws {
        guard let graphic = frame.cgImage else { throw DirectionError("graphic_still_failed", "Couldn't make the still.") }
        let scale = min(1, 1280 / Double(frame.width)), w = Int(Double(frame.width) * scale), h = Int(Double(frame.height) * scale)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DirectionError("graphic_still_failed", "Couldn't make the still.") }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        context.interpolationQuality = .high
        if let picture { context.draw(picture, in: rect) } else { context.setFillColor(CGColor(srgbRed: 0.1, green: 0.105, blue: 0.115, alpha: 1)); context.fill(rect) }
        context.draw(graphic, in: rect)
        guard let image = context.makeImage() else { throw DirectionError("graphic_still_failed", "Couldn't make the still.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MediaInspector.writePNG(image, to: url)
    }

    static func loadImage(_ url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    static func quote(_ text: String) -> String { "\u{201C}\(text.count > 40 ? String(text.prefix(39)) + "\u{2026}" : text)\u{201D}" }
    static func number(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }
}

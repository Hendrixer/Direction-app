import Foundation
import CoreImage
import CoreGraphics
import Vision
import Synchronization
import DirectionCore

/// Pixel grid (techniques.md, learned from Ryan Nangle's Final Cut Pro tutorial): a clip over another shows
/// only in the squares of a grid its subject fills, square by square as it moves, with grid lines over the
/// frame. Where Final Cut uses a magnetic mask, a feather and the pixelate effect, Direction finds the
/// subject with Vision (people and objects alike) fifteen times a second and keeps how much of each square
/// it fills, so playback only looks the numbers up.
public enum SubjectCells {
    public static let fps = 15.0

    /// How much of each square the subject fills, from `from` to `to` in the take's seconds: a header
    /// ("pixelGrid v1 cols rows fps t0") and a line per look, one hex digit (0–f) per square, top row first.
    public static func measure(_ a: MediaAsset, from: Double, to: Double, cols: Int, aspect: Double, cacheDirectory: URL) async throws -> String {
        let rows = max(1, Int((Double(cols) / max(0.1, aspect)).rounded()))
        let file = LayoutAnalysis.cache(a, "cells-\(cols)x\(rows)-\(Int(from * 1000))-\(Int(to * 1000))", cacheDirectory)
        if let saved = try? String(contentsOf: file, encoding: .utf8), saved.hasPrefix("pixelGrid v1") { return saved }
        let times = stride(from: max(0, from), through: max(from, to), by: 1 / fps).map { ($0 * 1000).rounded() / 1000 }
        let frames = try await LayoutAnalysis.frames(a, at: times, tolerance: 0.5 / fps)
        let lines: [String] = try await VisionWork.run {
            frames.map { f in (try? cells(in: f.image.image, cols: cols, rows: rows)) ?? String(repeating: "0", count: cols * rows) }
        }
        let text = "pixelGrid v1 \(cols) \(rows) \(fps) \(times.first ?? from)\n" + lines.joined(separator: "\n")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
        return text
    }

    /// One look: the subject's mask, averaged over each square.
    static func cells(in image: CGImage, cols: Int, rows: Int) throws -> String {
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let found = request.results?.first, !found.allInstances.isEmpty else { return String(repeating: "0", count: cols * rows) }
        let mask = try found.generateScaledMaskForImage(forInstances: found.allInstances, from: handler)
        CVPixelBufferLockBaseAddress(mask, .readOnly); defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask), stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float32>.size
        guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: Float32.self) else { return String(repeating: "0", count: cols * rows) }
        var sums = [Double](repeating: 0, count: cols * rows), counts = [Int](repeating: 0, count: cols * rows)
        for y in 0..<h {
            let row = min(rows - 1, y * rows / h)
            for x in 0..<w { let i = row * cols + min(cols - 1, x * cols / w); sums[i] += Double(base[y * stride + x]); counts[i] += 1 }
        }
        let digits = Array("0123456789abcdef")
        return String(zip(sums, counts).map { s, n in digits[min(15, Int((s / Double(max(1, n)) * 15).rounded()))] })
    }
}

enum PixelGrid {
    struct Track { let cols: Int, rows: Int, fps: Double, t0: Double, looks: [[UInt8]] }
    private static let tracks = Mutex<[Int: Track]>([:])
    private static let grids = Mutex<[String: CIImage]>([:])

    static func track(_ data: String) -> Track? {
        let key = data.hashValue ^ data.count
        if let t = tracks.withLock({ $0[key] }) { return t }
        let lines = data.split(separator: "\n").map(String.init)
        let head = lines.first?.split(separator: " ") ?? []
        guard head.count == 6, head[0] == "pixelGrid", let cols = Int(head[2]), let rows = Int(head[3]), let fps = Double(head[4]), let t0 = Double(head[5]) else { return nil }
        let looks = lines.dropFirst().map { line in line.map { UInt8($0.hexDigitValue ?? 0) } }.filter { $0.count == cols * rows }
        let t = Track(cols: cols, rows: rows, fps: fps, t0: t0, looks: looks)
        tracks.withLock { if $0.count > 32 { $0.removeAll() }; $0[key] = t }
        return t
    }

    /// The clip shown only in the squares its subject fills, with the grid's lines over the whole frame.
    static func apply(_ image: CIImage, _ e: ClipEffect, at t: Double?, bounds: CGRect) -> CIImage {
        guard let data = e.data, let track = track(data), !track.looks.isEmpty else { return image }
        let i = min(track.looks.count - 1, max(0, Int((((t ?? track.t0) - track.t0) * track.fps).rounded())))
        let threshold = max(0.05, e.number("threshold", at: nil, default: 0.35))
        // Each square's share of the subject, as a mask: full once it holds `threshold` of it.
        let bytes = track.looks[i].map { UInt8(min(255, Double($0) / 15 / threshold * 255)) }
        let cells = CIImage(bitmapData: Data(bytes), bytesPerRow: track.cols, size: CGSize(width: track.cols, height: track.rows), format: .L8, colorSpace: nil)
        // A bitmap's first row is its top, as the track's is.
        let mask = cells.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: bounds.width / CGFloat(track.cols), y: bounds.height / CGFloat(track.rows)))
            .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
            .cropped(to: bounds)
        let shown = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), "inputMaskImage": mask])
        let opacity = e.number("lines", at: nil, default: 0.6)
        guard opacity > 0 else { return shown }
        return lines(track.cols, track.rows, bounds: bounds, width: e.number("lineWidth", at: nil, default: 1.5) * bounds.height / 1080, color: e.params["lineColor"]?.string ?? "#141414", opacity: opacity).composited(over: shown)
    }

    /// The grid's lines over the frame, drawn once for each size.
    static func lines(_ cols: Int, _ rows: Int, bounds: CGRect, width: Double, color: String, opacity: Double) -> CIImage {
        let key = "\(cols)x\(rows) \(Int(bounds.width))x\(Int(bounds.height)) \(width) \(color) \(opacity)"
        if let g = grids.withLock({ $0[key] }) { return g.transformed(by: .init(translationX: bounds.minX, y: bounds.minY)) }
        let w = Int(bounds.width), h = Int(bounds.height)
        guard w > 0, h > 0, let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .empty() }
        let ink = ClipRendering.color(color) ?? CIColor(red: 0.08, green: 0.08, blue: 0.08)
        c.setFillColor(CGColor(red: ink.red, green: ink.green, blue: ink.blue, alpha: opacity))
        let lw = max(1, width)
        for k in 1..<cols { let x = (Double(k) * Double(w) / Double(cols) - lw / 2).rounded(); c.fill(CGRect(x: x, y: 0, width: lw, height: Double(h))) }
        for k in 1..<rows { let y = (Double(k) * Double(h) / Double(rows) - lw / 2).rounded(); c.fill(CGRect(x: 0, y: y, width: Double(w), height: lw)) }
        guard let made = c.makeImage() else { return .empty() }
        let image = CIImage(cgImage: made)
        grids.withLock { if $0.count > 16 { $0.removeAll() }; $0[key] = image }
        return image.transformed(by: .init(translationX: bounds.minX, y: bounds.minY))
    }
}

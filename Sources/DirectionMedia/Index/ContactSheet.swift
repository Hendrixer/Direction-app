import Foundation
import AppKit
import CoreGraphics
import CoreText
import DirectionCore

/// Step 3: a take's contact sheet. 16 frames evenly across the take in a 4 × 4 grid, 1600 px wide,
/// each cell labeled with its source timecode in SF Mono. The same grid draws `direction_watch`'s
/// filmstrip, labeled in cut time with the cuts marked.
public enum ContactSheet {
    public struct Layout: Sendable, Equatable {
        public var columns: Int
        public var rows: Int
        public var width: Int
        public var height: Int
        public var cells: [CGRect]
        public var times: [Double]
    }

    public static let width = 1600, padding = 8.0, gutter = 8.0

    /// Pure: where each of `frames` cells sits and which time it shows. Cells are centered in
    /// equal parts of the range, so the first isn't the slate's black and the last isn't the tail.
    public static func layout(frames: Int, start: Double, end: Double, aspect: Double) -> Layout {
        let n = max(1, frames)
        let columns = max(2, min(6, Int(Double(n).squareRoot().rounded(.up))))
        let rows = Int((Double(n) / Double(columns)).rounded(.up))
        let cellW = ((Double(width) - 2 * padding - Double(columns - 1) * gutter) / Double(columns)).rounded(.down)
        let cellH = (cellW / max(0.1, aspect)).rounded()
        let height = Int(2 * padding + Double(rows) * cellH + Double(rows - 1) * gutter)
        var cells: [CGRect] = [], times: [Double] = []
        let span = max(0, end - start)
        for i in 0..<n {
            let c = i % columns, r = i / columns
            // CoreGraphics' origin is bottom-left; row 0 is drawn at the top.
            cells.append(CGRect(x: padding + Double(c) * (cellW + gutter), y: Double(height) - padding - Double(r + 1) * cellH - Double(r) * gutter, width: cellW, height: cellH))
            times.append(start + (Double(i) + 0.5) * span / Double(n))
        }
        return Layout(columns: columns, rows: rows, width: width, height: height, cells: cells, times: times)
    }

    public static func aspect(_ asset: MediaAsset) -> Double {
        guard let v = asset.video.first, v.width > 0, v.height > 0 else { return 16 / 9 }
        return Double(v.width) / Double(v.height)
    }

    /// Renders a take's sheet to a JPEG. Returns the layout so callers can name each cell's time.
    @discardableResult
    public static func render(_ asset: MediaAsset, frames: Int = 16, range: ClosedRange<Double>? = nil, to output: URL) async throws -> Layout {
        let r = range ?? 0...asset.duration.seconds
        let layout = self.layout(frames: frames, start: r.lowerBound, end: r.upperBound, aspect: aspect(asset))
        let images = try await SourceFrames.images(asset, at: layout.times, maxDimension: Int(layout.cells[0].width * 1.0), tolerance: 0.05)
        let fps = asset.video.first?.frameRate ?? 24
        let image = try draw(layout, images: images, labels: layout.times.map { SourceTimecode.format($0, fps: fps) }, marks: [])
        try SourceFrames.writeJPEG(image, to: output, quality: 0.8)
        return layout
    }

    /// Draws cells with their labels. `marks` are cell indices that start after a cut.
    public static func draw(_ layout: Layout, images: [CGImage?], labels: [String], marks: Set<Int>, footer: String? = nil) throws -> CGImage {
        let footerHeight = footer == nil ? 0 : 44
        let h = layout.height + footerHeight
        guard let ctx = CGContext(data: nil, width: layout.width, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw DirectionError("image_write_failed", "Cannot draw the contact sheet.") }
        // Steel-0, the window canvas: the sheet reads like Direction's own picture area.
        ctx.setFillColor(CGColor(srgbRed: 0.035, green: 0.039, blue: 0.047, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: layout.width, height: h))
        ctx.translateBy(x: 0, y: CGFloat(footerHeight))
        let font = NSFont.monospacedSystemFont(ofSize: max(13, (layout.cells[0].width * 0.052).rounded()), weight: .medium) as CTFont
        for (i, cell) in layout.cells.enumerated() {
            if i < images.count, let image = images[i] {
                ctx.saveGState()
                ctx.clip(to: cell)
                // Aspect-fill the cell.
                let iw = Double(image.width), ih = Double(image.height)
                let scale = max(cell.width / iw, cell.height / ih)
                let w = iw * scale, hh = ih * scale
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(x: cell.midX - w / 2, y: cell.midY - hh / 2, width: w, height: hh))
                ctx.restoreGState()
            } else {
                ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.085, blue: 0.1, alpha: 1)); ctx.fill(cell)
            }
            if i < labels.count { tag(labels[i], in: cell, font: font, ctx: ctx) }
            if marks.contains(i) {
                ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
                ctx.fill(CGRect(x: cell.minX, y: cell.minY, width: 4, height: cell.height))
                tag("CUT", in: cell, font: font, ctx: ctx, top: true)
            }
        }
        if let footer {
            ctx.translateBy(x: 0, y: CGFloat(-footerHeight))
            let small = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular) as CTFont
            text(footer, at: CGPoint(x: padding + 4, y: 14), font: small, color: CGColor(srgbRed: 0.75, green: 0.76, blue: 0.79, alpha: 1), ctx: ctx, maxWidth: Double(layout.width) - 2 * padding)
        }
        guard let image = ctx.makeImage() else { throw DirectionError("image_write_failed", "Cannot draw the contact sheet.") }
        return image
    }

    /// A glass tag in a cell's corner, like the HUD timecode in Dailies.
    private static func tag(_ string: String, in cell: CGRect, font: CTFont, ctx: CGContext, top: Bool = false) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)]))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let padX = 8.0, padY = 5.0, inset = 8.0
        let box = CGRect(x: cell.minX + inset, y: top ? cell.maxY - inset - bounds.height - 2 * padY : cell.minY + inset, width: bounds.width + 2 * padX, height: bounds.height + 2 * padY)
        ctx.setFillColor(CGColor(srgbRed: 0.09, green: 0.095, blue: 0.11, alpha: 0.78))
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 5, cornerHeight: 5, transform: nil)); ctx.fillPath()
        ctx.textPosition = CGPoint(x: box.minX + padX - bounds.minX, y: box.minY + padY - bounds.minY)
        CTLineDraw(line, ctx)
    }

    private static func text(_ string: String, at point: CGPoint, font: CTFont, color: CGColor, ctx: CGContext, maxWidth: Double) {
        let attributed = NSAttributedString(string: string, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color])
        var line = CTLineCreateWithAttributedString(attributed)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth, let ellipsis = Optional(CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color]))) {
            line = CTLineCreateTruncatedLine(line, maxWidth, .end, ellipsis) ?? line
        }
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }
}

import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import DirectionCore

/// Previews for the library (techniques.md › The library): each transition, move and effect played on the
/// same made-up shots, drawn on this Mac (a sunset, a city at night, a figure walking, a screen with a
/// cursor), so the director sees what it does before naming it. Three seconds at 640×360, and a poster.
public enum LibraryPreviews {
    public static let version = 3
    static let w = 640, h = 360, fps: Int32 = 30, seconds = 4.0

    /// What a preview shows.
    public enum Subject: Sendable {
        /// A cut between two shots with this transition; `source` is its Metal, when it isn't a dissolve or dip.
        case transition(type: String, frames: Int, params: [String: JSONValue], source: String?)
        /// One of Direction's moves.
        case move(String)
        /// A built-in effect, or a technique's Metal effect, on one shot.
        case effect(name: String, params: [String: JSONValue], source: String?)
    }

    /// The preview for a library entry: Direction's own from its kind and name, a technique from its files.
    public static func subject(for entry: LibraryEntry) -> Subject? {
        // A sound or image shows itself.
        guard entry.item == nil else { return nil }
        if let t = entry.technique {
            if let tr = t.transition {
                let source = tr.file.flatMap { try? String(contentsOf: t.url.appendingPathComponent($0), encoding: .utf8) } ?? TransitionShader.builtIn(tr.type)
                var params = tr.params ?? [:]; if let f = tr.file { params["file"] = .string(f) }
                return .transition(type: tr.type, frames: tr.frames, params: params, source: source)
            }
            if let fx = t.effect {
                var params = fx.params ?? [:]; if let f = fx.file { params["file"] = .string(f) }
                return .effect(name: fx.name, params: params, source: fx.file.flatMap { try? String(contentsOf: t.url.appendingPathComponent($0), encoding: .utf8) })
            }
            return nil
        }
        let key = String(entry.id.dropFirst("builtin-".count))
        switch entry.kind {
        case "transition":
            let params: [String: JSONValue] = key == "whip" || key == "push" || key == "slide" ? ["x": .number(-1)] : [:]
            return .transition(type: key, frames: key.hasPrefix("dip") ? 20 : 18, params: params, source: TransitionShader.builtIn(key))
        case "move": return .move(key)
        default:
            var params: [String: JSONValue] = EditCatalog.filters.first { $0.kind == key }?.kind == "letterbox" ? [:] : ["amount": .number(0.8)]
            if let option = EditCatalog.filters.first(where: { $0.kind == key })?.options?.first { params["option"] = .string(option) }
            return .effect(name: "filter." + key, params: params, source: nil)
        }
    }

    /// Renders a preview to `destination` (an .mp4) and its poster beside it (the same name, .jpg).
    public static func render(_ subject: Subject, to destination: URL, cacheDirectory: URL) async throws {
        let shots = try await samples(cacheDirectory.appendingPathComponent("LibrarySamples-v\(version)"))
        var p = Project(name: "Preview")
        p.sequences[0].width = w; p.sequences[0].height = h; p.sequences[0].frameRate = .init(fps, 1)
        p.assets = [shots.warm, shots.cool, shots.figure, shots.screen]
        func clip(_ a: MediaAsset, _ start: Double, _ from: Double, _ to: Double, layer: Int = 0) -> Clip {
            Clip(assetID: a.id, name: a.name, layer: layer, start: .init(seconds: start), sourceRange: .init(start: from, end: to))
        }
        var ops: [EditOperation] = []
        switch subject {
        case .transition(let type, let frames, let params, let source):
            let a = clip(shots.warm, 0, 0.5, 2), b = clip(shots.cool, 1.5, 0.5, 2)
            p.sequences[0].clips = [a, b]
            var op = EditOperation(op: "transition"); op.editPoint = "\(a.id)|\(b.id)"; op.transitionType = type; op.frames = frames
            op.params = params.isEmpty ? nil : params
            if let source, type != "dissolve", !type.hasPrefix("dip") { op.resolved = .init(source: source) }
            ops = [op]
        case .move(let name):
            switch name {
            case "punchIn":
                p.sequences[0].clips = [clip(shots.figure, 0, 0.5, 1.5), clip(shots.figure, 1, 1.5, 2.5), clip(shots.figure, 2, 2.5, 3.5)]
                var op = EditOperation(op: "punchIn"); op.range = .init(start: 0, end: 3); op.scales = [1, 1.25]; op.resolved = .init(faces: [:]); ops = [op]
            case "emphasisPunch":
                p.sequences[0].clips = [clip(shots.figure, 0, 0.5, 3.5)]
                var op = EditOperation(op: "emphasisPunch"); op.range = .init(start: 1.2, end: 2.2); op.scale = 1.4; op.resolved = .init(faces: [:]); ops = [op]
            case "slowPush":
                p.sequences[0].clips = [clip(shots.warm, 0, 0.5, 3.5)]
                var op = EditOperation(op: "slowPush"); op.range = .init(start: 0, end: 3); op.scales = [1, 1.15]; op.longerThan = 1; op.resolved = .init(faces: [:]); ops = [op]
            default:
                p.sequences[0].clips = [clip(shots.screen, 0, 0, 3)]
                var op = EditOperation(op: "autoZoom"); op.range = .init(start: 0, end: 3); op.resolved = .init()
                op.resolved?.zoom = StyleMoves.standard.screenZoom
                op.resolved?.activity = [shots.screen.id: try await ScreenActivity.measure(shots.screen, from: 0, to: 3, cacheDirectory: cacheDirectory)]
                ops = [op]
            }
        case .effect(let name, let params, let source):
            if name == "pixelGrid" {
                // The figure shows square by square over the sunset.
                let over = clip(shots.figure, 0, 0.5, 3.5, layer: 1)
                p.sequences[0].clips = [clip(shots.warm, 0, 0.5, 3.5), over]
                var op = EditOperation(op: "addEffect"); op.effect = name; op.target = over.id; op.params = params.isEmpty ? nil : params
                op.resolved = .init()
                op.resolved?.data = try await SubjectCells.measure(shots.figure, from: 0.5, to: 3.5, cols: Int(params["cells"]?.double ?? 16), aspect: Double(w) / Double(h), cacheDirectory: cacheDirectory)
                ops = [op]
            } else {
                let shot = clip(shots.warm, 0, 0.5, 3.5)
                p.sequences[0].clips = [shot]
                var op = EditOperation(op: "addEffect"); op.effect = name; op.target = shot.id; op.params = params.isEmpty ? nil : params
                if let source { op.resolved = .init(source: source) }
                ops = [op]
            }
        }
        p = try EditReducer.apply(EditBatch(baseEditRevision: p.editRevision, operations: ops), to: p)
        let compiled = try await SequenceRenderer.compile(project: p, cacheDirectory: cacheDirectory)
        try? FileManager.default.removeItem(at: destination)
        _ = try await SequenceRenderer.export(compiled, to: destination, preset: "h264", range: .init(start: 0, end: 3))
        let poster = destination.deletingPathExtension().appendingPathExtension("jpg")
        try? FileManager.default.removeItem(at: poster)
        // Halfway through a transition shows both shots; a dip is all one color there, so a little before.
        let mid: Double = { if case .transition(let type, _, _, _) = subject { return type.hasPrefix("dip") ? 1.25 : 1.5 } else { return 1.6 } }()
        _ = try? await SequenceRenderer.frame(compiled, at: .init(seconds: mid), to: poster, maxDimension: w)
    }

    // MARK: The made-up shots

    struct Shots { let warm: MediaAsset, cool: MediaAsset, figure: MediaAsset, screen: MediaAsset }

    /// The four shots, made once into `folder`.
    static func samples(_ folder: URL) async throws -> Shots {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func shot(_ name: String, _ draw: @escaping @Sendable (CGContext, Double) -> Void) async throws -> MediaAsset {
            let url = folder.appendingPathComponent(name + ".mov")
            if !FileManager.default.fileExists(atPath: url.path) { try await write(url, draw) }
            var a = try await MediaInspector.inspect(url: url, thumbnailDirectory: folder)
            a.id = "sample-" + name
            return a
        }
        return Shots(warm: try await shot("sunset", sunset), cool: try await shot("city", city), figure: try await shot("figure", figure), screen: try await shot("screen", screen))
    }

    static func write(_ url: URL, _ draw: @escaping @Sendable (CGContext, Double) -> Void) async throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error ?? DirectionError("preview_failed", "Can't make a sample shot.") } }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("preview_failed", "Can't make a sample frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let c = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
                draw(c, Double(i) / Double(fps))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: fps)) else { throw writer.error ?? DirectionError("preview_failed", "Can't write a sample frame.") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("preview_failed", "Can't finish a sample shot.") }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temp, to: url)
    }

    static func gradient(_ c: CGContext, _ top: (Double, Double, Double), _ bottom: (Double, Double, Double)) {
        let colors = [CGColor(red: top.0, green: top.1, blue: top.2, alpha: 1), CGColor(red: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) { c.drawLinearGradient(g, start: CGPoint(x: 0, y: Double(h)), end: CGPoint(x: 0, y: 0), options: []) }
    }

    /// A sunset over hills, the sun sinking a little.
    @Sendable static func sunset(_ c: CGContext, _ t: Double) {
        gradient(c, (0.98, 0.62, 0.32), (0.45, 0.18, 0.42))
        c.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.62, alpha: 1)); c.fillEllipse(in: CGRect(x: 380 + t * 10, y: 120 - t * 6, width: 90, height: 90))
        for (k, shade) in [(0, 0.22), (1, 0.12)] {
            c.setFillColor(CGColor(red: shade + 0.05, green: shade * 0.6, blue: shade + 0.1, alpha: 1))
            c.beginPath(); c.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: 0.0, through: Double(w), by: 16) { c.addLine(to: CGPoint(x: x, y: 70 + Double(k) * -30 + 40 * sin(x / 90 + Double(k) * 2 + t * 0.2))) }
            c.addLine(to: CGPoint(x: Double(w), y: 0)); c.closePath(); c.fillPath()
        }
    }

    /// A city at night: buildings with lit windows, lights moving along a road.
    @Sendable static func city(_ c: CGContext, _ t: Double) {
        gradient(c, (0.05, 0.08, 0.22), (0.12, 0.2, 0.42))
        for b in 0..<9 {
            let x = Double(b) * 74 - 10, height = 120 + Double((b * 53) % 140)
            c.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1)); c.fill(CGRect(x: x, y: 40, width: 66, height: height))
            for wy in stride(from: 52.0, to: 40 + height - 12, by: 16) { for wx in stride(from: x + 8, to: x + 60, by: 14) where Int(wx + wy) % 3 != 0 {
                let lit = 0.5 + 0.5 * sin(wx * 0.37 + wy * 0.11 + t * 1.5)
                c.setFillColor(CGColor(red: 1, green: 0.82, blue: 0.45, alpha: 0.35 + 0.6 * lit)); c.fill(CGRect(x: wx, y: wy, width: 7, height: 8))
            } }
        }
        c.setFillColor(CGColor(gray: 0.08, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: 40))
        for k in 0..<5 { let x = (Double(k) * 160 + t * 140).truncatingRemainder(dividingBy: Double(w) + 40) - 20
            c.setFillColor(CGColor(red: 1, green: 0.3, blue: 0.25, alpha: 1)); c.fillEllipse(in: CGRect(x: x, y: 18, width: 10, height: 6)) }
    }

    /// A figure walking across a pale wall.
    @Sendable static func figure(_ c: CGContext, _ t: Double) {
        gradient(c, (0.86, 0.84, 0.8), (0.72, 0.7, 0.66))
        c.setFillColor(CGColor(gray: 0.5, alpha: 0.4)); c.fill(CGRect(x: 0, y: 0, width: w, height: 70))
        let x = 140 + t * 90, swing = sin(t * 7) * 18
        c.setFillColor(CGColor(red: 0.16, green: 0.22, blue: 0.38, alpha: 1))
        c.fillEllipse(in: CGRect(x: x - 22, y: 250, width: 44, height: 50))
        c.addPath(CGPath(roundedRect: CGRect(x: x - 34, y: 150, width: 68, height: 105), cornerWidth: 22, cornerHeight: 22, transform: nil)); c.fillPath()
        c.setLineWidth(20); c.setLineCap(.round); c.setStrokeColor(CGColor(red: 0.16, green: 0.22, blue: 0.38, alpha: 1))
        c.strokeLineSegments(between: [CGPoint(x: x - 12, y: 160), CGPoint(x: x - 12 + swing, y: 82), CGPoint(x: x + 12, y: 160), CGPoint(x: x + 12 - swing, y: 82)])
    }

    /// A window on a screen, a cursor moving to a field, then typing in it.
    @Sendable static func screen(_ c: CGContext, _ t: Double) {
        c.setFillColor(CGColor(gray: 0.16, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.setFillColor(CGColor(gray: 0.95, alpha: 1)); c.fill(CGRect(x: 40, y: 30, width: 560, height: 300))
        c.setFillColor(CGColor(gray: 0.85, alpha: 1)); c.fill(CGRect(x: 40, y: 300, width: 560, height: 30))
        for (k, width) in [180, 260, 220, 140].enumerated() { c.setFillColor(CGColor(gray: 0.78, alpha: 1)); c.fill(CGRect(x: 70, y: 250 - k * 26, width: width, height: 10)) }
        c.setStrokeColor(CGColor(red: 0.3, green: 0.5, blue: 0.95, alpha: 1)); c.setLineWidth(2); c.stroke(CGRect(x: 360, y: 90, width: 200, height: 30))
        // Still at first, so a zoom starts wide; then to the field, then typing in it.
        let typed = max(0, min(1, (t - 1.9) / 1.1))
        c.setFillColor(CGColor(gray: 0.2, alpha: 1)); c.fill(CGRect(x: 368, y: 100, width: 180 * typed, height: 10))
        let k = max(0, min(1, (t - 0.9) / 0.8))
        let p = CGPoint(x: 150 + k * 260, y: 230 - k * 120)
        c.setFillColor(CGColor(gray: 0.05, alpha: 1))
        c.beginPath(); c.move(to: CGPoint(x: p.x, y: p.y)); c.addLine(to: CGPoint(x: p.x, y: p.y - 18)); c.addLine(to: CGPoint(x: p.x + 5, y: p.y - 13)); c.addLine(to: CGPoint(x: p.x + 12, y: p.y - 13)); c.closePath(); c.fillPath()
    }
}

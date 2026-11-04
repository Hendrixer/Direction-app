import Foundation

/// The shape a film is cut in: the brief's Shape (start.md › 03). Without one, a film takes its footage's shape.
/// Changing it once there's a cut puts the shots in whole with black where they don't reach (the director's own
/// edit); filling the frame is the editor's, shot by shot (the `reframe` skill).
public enum FilmShape: String, Codable, CaseIterable, Sendable {
    case wide = "16:9", tall = "9:16", square = "1:1", feed = "4:5"

    public var label: String { rawValue }
    /// Width over height.
    public var ratio: Double {
        switch self { case .wide: 16.0 / 9; case .tall: 9.0 / 16; case .square: 1; case .feed: 4.0 / 5 }
    }

    /// The cut's size for footage of `footage`'s size: its short side stays the cut's short side, so 1920 × 1080
    /// footage cuts 9:16 at 1080 × 1920 and 4:5 at 1080 × 1350. Sizes are even.
    public func size(footage: (width: Int, height: Int)) -> (width: Int, height: Int) {
        let short = Double(max(2, min(footage.width, footage.height)))
        let w = ratio >= 1 ? short * ratio : short, h = ratio >= 1 ? short : short / ratio
        return (Self.even(w), Self.even(h))
    }

    /// The shape a frame of this size is, when it's one of these.
    public static func of(width: Int, height: Int) -> FilmShape? {
        guard width > 0, height > 0 else { return nil }
        let r = Double(width) / Double(height)
        return allCases.first { abs($0.ratio - r) / $0.ratio < 0.015 }
    }

    /// A frame's shape the way a director says it: "16:9", "9:16", "2.39:1".
    public static func label(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "" }
        let r = Double(width) / Double(height)
        let named: [(Double, String)] = [(16.0 / 9, "16:9"), (9.0 / 16, "9:16"), (1, "1:1"), (4.0 / 5, "4:5"), (4.0 / 3, "4:3"), (3.0 / 4, "3:4"),
                                         (2.39, "2.39:1"), (21.0 / 9, "21:9"), (2, "2:1"), (1.85, "1.85:1")]
        if let n = named.first(where: { abs($0.0 - r) / $0.0 < 0.015 }) { return n.1 }
        return r >= 1 ? String(format: "%.2f:1", r) : String(format: "1:%.2f", 1 / r)
    }

    static func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
}

extension Project {
    /// The first footage's picture size, which a film without a Shape takes.
    public func footageSize(film: URL) -> (width: Int, height: Int)? {
        guard let v = footage(film: film).first(where: { !$0.isImage && !$0.video.isEmpty })?.video.first, v.width > 0, v.height > 0 else { return nil }
        return (v.width / 2 * 2, v.height / 2 * 2)
    }
}

extension ProjectStore {
    /// The cut's size for `shape` (nil: the footage's own), or nil before there's footage.
    public func cutSize(for shape: FilmShape?) throws -> (width: Int, height: Int)? {
        guard let footage = try read().footageSize(film: url) else { return nil }
        return shape.map { $0.size(footage: footage) } ?? footage
    }

    /// Changes the film's shape to the brief's. Before anything is cut, the cut-to-be takes the new size. Once
    /// there's a cut, the latest one changes as the director's own edit: every shot whole, with black where it
    /// doesn't reach. Filling the frame is a note for the editor. Returns the edit, when one was made.
    @discardableResult
    public func reshape(_ shape: FilmShape?) throws -> EditResult? {
        guard let size = try cutSize(for: shape) else { return nil }
        let p = try read(), label = FilmShape.label(width: size.width, height: size.height)
        guard let cut = try cuts().first else {
            guard p.sequences.contains(where: { $0.width != size.width || $0.height != size.height }) else { return nil }
            guard p.sequences.allSatisfy({ $0.clips.isEmpty }) else { throw DirectionError("editor_working", "The editor is cutting the assembly. Change the shape once it\u{2019}s done.") }
            _ = try update(expectedRevision: p.editRevision, key: UUID().uuidString, request: Data("shape:\(size.width)x\(size.height)".utf8), summary: "Shape: \(label)") { q in
                for i in q.sequences.indices { q.sequences[i].width = size.width; q.sequences[i].height = size.height }
            }
            return nil
        }
        let s = try p.sequence(cut.sequenceID)
        guard s.width != size.width || s.height != size.height else { return nil }
        var op = EditOperation(op: "format"); op.width = size.width; op.height = size.height
        return try directorEdit([op], summary: "Shape: \(label)", expectedRevision: p.editRevision)
    }
}

/// How a picture sits in a frame of another shape, in the transform's own terms (scale over the fitted picture).
public enum FrameFill {
    /// The scale at which a `source`-sized picture covers a `frame`-sized frame: 1 when it's the same shape,
    /// about 3.16 for 16:9 footage in a 9:16 frame.
    public static func cover(source: (width: Int, height: Int), frame: (width: Int, height: Int)) -> Double {
        let pw = Double(max(1, source.width)), ph = Double(max(1, source.height)), w = Double(max(1, frame.width)), h = Double(max(1, frame.height))
        let fit = min(w / pw, h / ph)
        return max(w / (pw * fit), h / (ph * fit))
    }
    /// The scale past which the picture shows bigger than it was shot (softer): 1.78 for 1920 × 1080 footage in a
    /// 1080 × 1920 frame, 3.56 for 3840 × 2160.
    public static func sharp(source: (width: Int, height: Int), frame: (width: Int, height: Int)) -> Double {
        1 / min(Double(max(1, frame.width)) / Double(max(1, source.width)), Double(max(1, frame.height)) / Double(max(1, source.height)))
    }
}

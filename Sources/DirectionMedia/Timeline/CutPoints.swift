import Foundation
@preconcurrency import AVFoundation
import Vision
import ImageIO
import DirectionCore

/// Where a take is good to cut (agent-timeline.md › Cut points), measured so the editor chooses between them
/// instead of guessing a time: blinks (a cut on a blink reads as a natural break), peaks of action (a cut inside a
/// movement hides itself) and pauses between words. Measured on this Mac with Vision, 20 s of a take at a time and
/// only where asked, and kept in the film's cache, so an hour of interviews is never looked at all at once.
public enum CutPoints {
    /// Raised when what's measured changes, so a take is looked at again.
    public static let version = 2
    /// Seconds of a take measured and kept at a time.
    static let chunk = 20.0
    /// Seconds between the frames looked at; every frame around a blink.
    static let step = 0.1
    /// The longer side of the frames Vision reads.
    static let size = 960

    public struct Blink: Codable, Hashable, Sendable {
        /// Take seconds: the eyes most closed, and the blink from closing to open again.
        public var t: Double
        public var start: Double
        public var end: Double
        /// How far the eyes closed, 0–1 of open.
        public var depth: Double
        /// Where the face is across the picture as shown, 0 left to 1 right.
        public var x: Double
        public init(t: Double, start: Double, end: Double, depth: Double, x: Double) { self.t = t; self.start = start; self.end = end; self.depth = depth; self.x = x }
    }

    /// A peak of movement: where the picture changes fastest. Take seconds; strength 0–1.
    public struct Action: Codable, Hashable, Sendable {
        public var t: Double
        public var strength: Double
        public init(t: Double, strength: Double) { self.t = t; self.strength = strength }
    }

    /// A gap between words, take seconds; whether the words before it end a sentence.
    public struct Pause: Codable, Hashable, Sendable {
        public var start: Double
        public var end: Double
        public var afterSentence: Bool
        public var middle: Double { (start + end) / 2 }
    }

    /// What was found over a stretch of a take.
    public struct Measured: Codable, Sendable {
        public var blinks: [Blink] = []
        public var actions: [Action] = []
        /// Seconds where a face was turned to the camera and near enough to see its eyes: blinks could be found there.
        public var faceSeconds: Double = 0
        /// The most faces whose eyes could be seen at once.
        public var faces: Int = 0
        public init() {}
    }

    /// One frame's look at a face.
    public struct EyeSample: Sendable {
        public var t: Double
        /// How open the eyes are (their height over their width), when the face could be judged.
        public var open: Double?
        public var x: Double
        public var y: Double
        /// The face's height, a share of the picture's.
        public var h: Double
        public var yaw: Double
        public var pitch: Double
        public init(t: Double, open: Double?, x: Double, y: Double = 0.5, h: Double = 0.3, yaw: Double = 0, pitch: Double = 0) { self.t = t; self.open = open; self.x = x; self.y = y; self.h = h; self.yaw = yaw; self.pitch = pitch }
    }

    // MARK: Measuring

    /// The blinks and peaks of action between `from` and `to` (take seconds), measured where they weren't yet.
    public static func measure(_ asset: MediaAsset, from: Double, to: Double, cacheDirectory: URL) async throws -> Measured {
        let length = asset.duration.seconds
        guard !asset.video.isEmpty, !asset.isImage, length > 0 else { return Measured() }
        let a = max(0, from), b = min(length, to)
        guard b > a else { return Measured() }
        let file = cacheFile(asset, cacheDirectory)
        var kept = Self.read(file)
        var out = Measured()
        for index in Int(a / chunk)...Int(max(a, b - 1e-6) / chunk) {
            try Task.checkCancellation()
            let piece: Chunk
            if let had = kept[String(index)] { piece = had } else {
                piece = try await measureChunk(asset, from: Double(index) * chunk, to: min(length, Double(index + 1) * chunk))
                kept = Self.read(file)
                kept[String(index)] = piece
                write(kept, to: file)
            }
            out.blinks += piece.blinks.filter { $0.t >= a && $0.t <= b }
            out.actions += piece.actions.filter { $0.t >= a && $0.t <= b }
            // A chunk's face time, in the share of it asked for.
            let lo = max(a, Double(index) * chunk), hi = min(b, Double(index + 1) * chunk), span = min(length, Double(index + 1) * chunk) - Double(index) * chunk
            out.faceSeconds += span > 0 ? piece.faceSeconds * (hi - lo) / span : 0
            out.faces = max(out.faces, piece.faces)
        }
        return out
    }

    /// What one stretch of a take holds, as kept.
    struct Chunk: Codable, Sendable {
        var blinks: [Blink]
        var actions: [Action]
        var faceSeconds: Double
        var faces: Int
    }

    struct Kept: Codable { var version: Int; var chunks: [String: Chunk] }

    static func cacheFile(_ a: MediaAsset, _ directory: URL) -> URL {
        let key = AudioProcessor.digest(Data("\(a.path):\(a.fileSize):\(a.modifiedAt):cutpoints-v\(version)".utf8))
        return directory.appendingPathComponent("CutPoints").appendingPathComponent(key + ".json")
    }
    private static let lock = NSLock()
    static func read(_ file: URL) -> [String: Chunk] {
        lock.withLock { (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) }.flatMap { $0.version == version ? $0.chunks : nil } ?? [:] }
    }
    static func write(_ chunks: [String: Chunk], to file: URL) {
        lock.withLock {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(Kept(version: version, chunks: chunks)).write(to: file, options: .atomic)
        }
    }

    /// The reader and what Vision needs to know of the picture, handed to Vision's own threads.
    private final class Reading: @unchecked Sendable {
        let reader: AVAssetReader, output: AVAssetReaderTrackOutput, orientation: CGImagePropertyOrientation, fps: Double, name: String
        init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, orientation: CGImagePropertyOrientation, fps: Double, name: String) { self.reader = reader; self.output = output; self.orientation = orientation; self.fps = fps; self.name = name }
    }

    /// Reads one stretch frame by frame (a little either side, so a blink at its edge is seen whole): Vision looks at
    /// the faces every `step`, and at every frame from just before an eye starts to close until it's open again; the
    /// picture's movement is measured every `step`.
    static func measureChunk(_ asset: MediaAsset, from: Double, to: Double) async throws -> Chunk {
        let access = try MediaAccess(assets: [asset]); defer { withExtendedLifetime(access) {} }
        let source = AVURLAsset(url: try MediaInspector.checkedURL(asset))
        guard let track = try await source.loadTracks(withMediaType: .video).first else { return Chunk(blinks: [], actions: [], faceSeconds: 0, faces: 0) }
        let (natural, transform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let fps = Double(rate) > 1 ? Double(rate) : max(1, asset.video.first?.frameRate ?? 30)
        let scale = min(1, Double(size) / max(1, max(natural.width, natural.height)))
        let w = max(2, Int((natural.width * scale / 2).rounded()) * 2), h = max(2, Int((natural.height * scale / 2).rounded()) * 2)
        let reader = try AVAssetReader(asset: source)
        let pad = 0.6
        reader.timeRange = CMTimeRange(start: CMTime(seconds: max(0, from - pad), preferredTimescale: 600), end: CMTime(seconds: to + pad, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw DirectionError("frame_unreadable", "Couldn\u{2019}t read \(asset.name): \(reader.error?.localizedDescription ?? "the reader didn\u{2019}t start").") }
        let reading = Reading(reader: reader, output: output, orientation: orientation(transform), fps: fps, name: asset.name)
        defer { ReadStall.cancel(reader) }
        let found = try await VisionWork.run { try look(reading) }
        try ReadStall.check(reader, asset.name)
        try Task.checkCancellation()
        // A read that failed or was stopped partway is said, never kept as if the stretch had nothing in it.
        guard reader.status == .completed else { throw DirectionError("frame_unreadable", "Couldn\u{2019}t read \(asset.name) through: \(reader.error?.localizedDescription ?? "the reader stopped partway").") }
        let tracks = found.tracks.map { $0.sorted { $0.t < $1.t } }.filter { $0.contains { $0.open != nil } }
        let blinks = tracks.flatMap { blinks(in: $0) }.filter { $0.t >= from && $0.t < to }.sorted { $0.t < $1.t }
        let actions = actions(in: found.energy).filter { $0.t >= from && $0.t < to }
        let judged = Set(tracks.flatMap { $0.filter { $0.open != nil && $0.t >= from && $0.t < to }.map { Int(($0.t / step).rounded()) } })
        return Chunk(blinks: blinks, actions: actions, faceSeconds: min(to - from, Double(judged.count) * step), faces: found.faces)
    }

    /// The faces each frame looked at, by face, and the picture's movement every `step`.
    private struct Looked { var tracks: [[EyeSample]]; var energy: [(t: Double, e: Double)]; var faces: Int }

    private static func look(_ r: Reading) throws -> Looked {
        let every = max(1, Int((r.fps * step).rounded()))
        var tracks: [[EyeSample]] = [], energy: [(t: Double, e: Double)] = [], faces = 0
        var lastGrey: [Float]?
        // The frames since the last one looked at, so a blink's start isn't missed; copies, as the reader reuses its own.
        var skipped: [(t: Double, buffer: CVPixelBuffer)] = []
        var n = 0, close = false, closeSince = 0.0, openAgain = 0, lastT = 0.0
        func add(_ samples: [EyeSample]) {
            for (s, k) in zip(samples, match(samples, to: tracks)) { if let k { tracks[k].append(s) } else { tracks.append([s]) } }
            faces = max(faces, samples.filter { $0.open != nil }.count)
        }
        /// A face's eyes are closing: open less than 0.8 of how open they've been lately.
        func closing(_ samples: [EyeSample]) -> Bool {
            zip(samples, match(samples, to: tracks)).contains { s, k in
                guard let o = s.open, let k else { return false }
                let recent = tracks[k].suffix(40).compactMap(\.open)
                guard recent.count >= 6 else { return false }
                return o < median(recent) * 0.8
            }
        }
        while let sample = r.output.nextSampleWaiting(of: r.reader) {
            defer { n += 1 }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let regular = n % every == 0
            if regular {
                let grey = thumbnail(buffer)
                // The change since the last look happened between the two: it's stamped halfway.
                if let lastGrey { energy.append(((t + lastT) / 2, Double(zip(grey, lastGrey).reduce(Float(0)) { $0 + abs($1.0 - $1.1) }) / Double(grey.count))) }
                lastGrey = grey; lastT = t
            }
            guard regular || close else {
                if let copy = copy(buffer) { skipped.append((t, copy)); if skipped.count > every { skipped.removeFirst() } }
                continue
            }
            let now = eyes(buffer, t: t, orientation: r.orientation), shutting = closing(now)
            if !close && shutting {
                // Back to the frames skipped since the last look, then every frame until the eyes are open again.
                for (st, sb) in skipped { add(eyes(sb, t: st, orientation: r.orientation)) }
                close = true; closeSince = t; openAgain = 0
            }
            add(now)
            skipped.removeAll()
            if close {
                openAgain = shutting ? 0 : openAgain + 1
                if openAgain >= 3 || t - closeSince > 0.8 { close = false }
            }
        }
        return Looked(tracks: tracks, energy: energy, faces: faces)
    }

    static func distance(_ a: EyeSample, _ b: EyeSample) -> Double { hypot(a.x - b.x, a.y - b.y) }

    /// Which face track each of one frame's faces carries on (nil: a face of its own), one to one: the closest
    /// pairs first, within 0.15 of the picture, and a track takes at most one face a frame. Two faces close
    /// together stay two tracks.
    static func match(_ samples: [EyeSample], to tracks: [[EyeSample]]) -> [Int?] {
        var out = [Int?](repeating: nil, count: samples.count), taken = Set<Int>()
        let pairs = samples.indices.flatMap { i in tracks.indices.compactMap { k -> (i: Int, k: Int, d: Double)? in
            guard let last = tracks[k].last, last.t < samples[i].t else { return nil }
            let d = distance(last, samples[i])
            return d < 0.15 ? (i, k, d) : nil
        } }.sorted { $0.d < $1.d }
        for p in pairs where out[p.i] == nil && !taken.contains(p.k) { out[p.i] = p.k; taken.insert(p.k) }
        return out
    }

    /// Each face in the frame with how open its eyes are: judged only when it faces the camera (turned less than
    /// about 35° and tipped less than about 30°), is wholly in the picture, at least 50 pixels tall here, and Vision
    /// is sure of its outline, so a turned, distant, cut-off or murky head never reads as closed eyes.
    static func eyes(_ buffer: CVPixelBuffer, t: Double, orientation: CGImagePropertyOrientation) -> [EyeSample] {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
        let rects = VNDetectFaceRectanglesRequest()
        rects.revision = VNDetectFaceRectanglesRequestRevision3
        guard (try? handler.perform([rects])) != nil, let found = rects.results, !found.isEmpty else { return [] }
        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = found
        try? handler.perform([landmarks])
        let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let size = rotated ? CGSize(width: CVPixelBufferGetHeight(buffer), height: CVPixelBufferGetWidth(buffer)) : CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        return (landmarks.results ?? found).map { f in
            let box = f.boundingBox, yaw = f.yaw?.doubleValue ?? 0, pitch = f.pitch?.doubleValue ?? 0
            var open: Double?
            let whole = box.minX >= 0.01 && box.maxX <= 0.99 && box.minY >= 0.01 && box.maxY <= 0.99
            if whole, Double(box.height) * size.height >= 50, abs(yaw) <= 0.6, abs(pitch) <= 0.5, (f.landmarks?.confidence ?? 0) >= 0.5, let l = f.landmarks?.leftEye, let r = f.landmarks?.rightEye {
                let a = eyeOpen(l.pointsInImage(imageSize: size)), b = eyeOpen(r.pointsInImage(imageSize: size))
                if let a, let b { open = (a + b) / 2 }
            }
            return EyeSample(t: t, open: open, x: Double(box.midX), y: Double(1 - box.midY), h: Double(box.height), yaw: yaw, pitch: pitch)
        }
    }

    /// An eye's height over its width, from its outline.
    static func eyeOpen(_ points: [CGPoint]) -> Double? {
        guard points.count >= 4, let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max(), x1 - x0 > 1 else { return nil }
        return Double((y1 - y0) / (x1 - x0))
    }

    /// The picture as 64 × 36 grey, averaged a few pixels a square: enough to see movement, cheap every `step`.
    static func thumbnail(_ buffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return [] }
        var out = [Float](repeating: 0, count: 64 * 36)
        for y in 0..<36 { for x in 0..<64 {
            var s: Float = 0
            for dy in 0..<3 { for dx in 0..<3 {
                let px = min(w - 1, (x * 3 + dx) * w / 192), py = min(h - 1, (y * 3 + dy) * h / 108)
                let p = base + py * row + px * 4
                s += 0.114 * Float(p[0]) + 0.587 * Float(p[1]) + 0.299 * Float(p[2])
            } }
            out[y * 64 + x] = s / (9 * 255)
        } }
        return out
    }

    static func copy(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard CVPixelBufferCreate(nil, w, h, CVPixelBufferGetPixelFormatType(buffer), nil, &out) == kCVReturnSuccess, let out else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly); CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []); CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let from = CVPixelBufferGetBaseAddress(buffer), let to = CVPixelBufferGetBaseAddress(out) else { return nil }
        let a = CVPixelBufferGetBytesPerRow(buffer), b = CVPixelBufferGetBytesPerRow(out)
        for y in 0..<h { memcpy(to + y * b, from + y * a, min(a, b)) }
        return out
    }

    /// How the stored picture turns to be shown.
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }

    // MARK: Finding them

    /// Blinks in one face's samples (time order): a short dip in how open the eyes are, at least 45% shut against
    /// how open they've been over the 2 s around it (the upper quarter, so a stretch of looking down doesn't lower
    /// it), shut no longer than 0.45 s, open again 0.4 s before and within 0.6 s after, with the head still facing
    /// the same way and the same size. Looking down (the eyes lower slowly and stay low), a turned head or one moving
    /// toward the camera isn't one.
    public static func blinks(in samples: [EyeSample]) -> [Blink] {
        let judged = samples.filter { $0.open != nil }
        guard judged.count >= 8 else { return [] }
        let opens = judged.map { $0.open! }
        let base = judged.indices.map { i -> Double in
            let t = judged[i].t
            return quantile(judged.indices.filter { abs(judged[$0].t - t) <= 2 }.map { opens[$0] }, 0.75)
        }
        let drop = judged.indices.map { base[$0] > 0 ? (base[$0] - opens[$0]) / base[$0] : 0 }
        var out: [Blink] = []
        var i = 0
        while i < judged.count {
            guard drop[i] >= 0.3 else { i += 1; continue }
            var j = i
            while j + 1 < judged.count, drop[j + 1] >= 0.3, judged[j + 1].t - judged[j].t <= 0.15 { j += 1 }
            defer { i = j + 1 }
            let first = judged[i].t, last = judged[j].t
            guard i > 0, j + 1 < judged.count, let low = (i...j).max(by: { drop[$0] < drop[$1] }), drop[low] >= 0.45, last - first <= 0.45,
                  (0..<i).contains(where: { judged[$0].t >= first - 0.4 && drop[$0] <= 0.15 }),
                  let open = ((j + 1)..<judged.count).first(where: { judged[$0].t <= last + 0.6 && drop[$0] <= 0.2 }), judged[open].t <= last + 0.6 else { continue }
            // The head kept facing the same way, and stayed where it was.
            let a = judged[i - 1], b = judged[j + 1]
            guard first - a.t <= 0.35, b.t - last <= 0.5, abs(a.yaw - b.yaw) < 0.25, abs(a.pitch - b.pitch) < 0.25,
                  hypot(a.x - b.x, a.y - b.y) < max(0.05, a.h * 0.5), abs(b.h - a.h) < a.h * 0.15 else { continue }
            let blink = Blink(t: judged[low].t, start: (a.t + first) / 2, end: judged[open].t, depth: min(1, drop[low]), x: judged[low].x)
            if let previous = out.last, blink.start - previous.end < 0.1 { if blink.depth > previous.depth { out[out.count - 1] = blink }; continue }
            out.append(blink)
        }
        return out
    }

    /// Peaks of action in the picture's movement (mean change between frames `step` apart, 0–1): a local peak at
    /// least three times the take's usual movement, at least 0.5 s from a stronger one. A change of picture (a cut
    /// or a flash inside the take) isn't action.
    public static func actions(in energy: [(t: Double, e: Double)]) -> [Action] {
        guard energy.count >= 5 else { return [] }
        let changes = energy.filter { $0.e > 0.2 }.map(\.t)
        let raw = energy.map(\.e)
        let smooth = raw.indices.map { i in (raw[max(0, i - 1)] + 2 * raw[i] + raw[min(raw.count - 1, i + 1)]) / 4 }
        let floor = max(0.006, 3 * median(raw))
        var peaks: [Action] = []
        for i in smooth.indices where smooth[i] >= floor {
            let around = max(0, i - 2)...min(smooth.count - 1, i + 2)
            guard around.allSatisfy({ smooth[$0] <= smooth[i] }), !changes.contains(where: { abs($0 - energy[i].t) < 0.35 }) else { continue }
            let p = Action(t: energy[i].t, strength: min(1, smooth[i] / 0.04))
            if let last = peaks.last, p.t - last.t < 0.5 { if p.strength > last.strength { peaks[peaks.count - 1] = p }; continue }
            peaks.append(p)
        }
        return peaks
    }

    /// Gaps of at least `shortest` seconds between a take's words (source seconds) that reach into `from`–`to`;
    /// given the take's `length`, the quiet before its first word and after its last too.
    public static func pauses(_ words: [TranscriptWord], from: Double = 0, to: Double = .infinity, length: Double? = nil, atLeast shortest: Double = 0.25) -> [Pause] {
        let w = words.sorted { $0.range.start < $1.range.start }
        func ends(_ word: TranscriptWord) -> Bool { word.text.trimmingCharacters(in: .whitespaces).last.map { ".?!\u{2026}".contains($0) } ?? false }
        var all = zip(w, w.dropFirst()).map { a, b in Pause(start: a.range.end.seconds, end: b.range.start.seconds, afterSentence: ends(a)) }
        if let length, let first = w.first, let last = w.last {
            all.insert(Pause(start: 0, end: first.range.start.seconds, afterSentence: true), at: 0)
            all.append(Pause(start: last.range.end.seconds, end: length, afterSentence: true))
        }
        return all.filter { $0.end - $0.start >= shortest && $0.end >= from && $0.start <= to }
    }

    static func quantile(_ values: [Double], _ q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s[min(s.count - 1, Int((q * Double(s.count - 1)).rounded()))]
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

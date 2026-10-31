import Foundation

// Layouts (layouts.md): how a screen recording and a camera in sync share the frame. A layout is a
// stretch of ordinary synced clips over the story, the screen on V2 and the camera on V3, each carrying
// the layout it belongs to, so preview, export and every edit treat them like any other clip.

public struct FrameLayout: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case screenAndYou, you, screen, sideBySide
        public var label: String {
            switch self { case .screenAndYou: "Screen and you"; case .you: "You"; case .screen: "Screen"; case .sideBySide: "Side by side" }
        }
        var needsCamera: Bool { self != .screen }
        var needsScreen: Bool { self != .you }
    }
    public enum Corner: String, Codable, CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight
        public var label: String {
            switch self { case .topLeft: "top left"; case .topRight: "top right"; case .bottomLeft: "bottom left"; case .bottomRight: "bottom right" }
        }
        var right: Bool { self == .topRight || self == .bottomRight }
        var bottom: Bool { self == .bottomLeft || self == .bottomRight }
    }
    public enum Size: String, Codable, CaseIterable, Sendable {
        case small, medium, large
        public var label: String { switch self { case .small: "S"; case .medium: "M"; case .large: "L" } }
        /// The bubble's height, as a fraction of the frame's.
        public var height: Double { switch self { case .small: 0.22; case .medium: 0.28; case .large: 0.36 } }
    }
    public enum Shape: String, Codable, CaseIterable, Sendable {
        case circle, rounded, wide
        public var label: String { switch self { case .circle: "Circle"; case .rounded: "Rounded"; case .wide: "Wide" } }
        /// Width over height, in pixels.
        public var aspect: Double { self == .wide ? 16.0 / 9 : 1 }
        /// Corner radius, a fraction of the shorter side.
        public var radius: Double { switch self { case .circle: 0.5; case .rounded: 0.2; case .wide: 0.12 } }
    }
    public enum Screen: String, Codable, CaseIterable, Sendable {
        case full, framed
        public var label: String { self == .full ? "Full" : "Framed" }
    }

    public var kind: Kind
    public var corner: Corner
    public var size: Size
    public var shape: Shape
    public var screen: Screen
    public init(kind: Kind, corner: Corner = .bottomRight, size: Size = .medium, shape: Shape = .circle, screen: Screen = .full) {
        self.kind = kind; self.corner = corner; self.size = size; self.shape = shape; self.screen = screen
    }
    /// What Dailies offers first: the screen, with you in the bottom right.
    public static let standard = FrameLayout(kind: .screenAndYou)

    /// "Screen and you · bottom right", "Screen, framed", "You".
    public var label: String {
        switch kind {
        case .screenAndYou: "Screen and you \u{00B7} \(corner.label)" + (screen == .framed ? ", framed" : "")
        case .screen: screen == .framed ? "Screen, framed" : "Screen"
        case .you, .sideBySide: kind.label
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        corner = try c.decodeIfPresent(Corner.self, forKey: .corner) ?? .bottomRight
        size = try c.decodeIfPresent(Size.self, forKey: .size) ?? .medium
        shape = try c.decodeIfPresent(Shape.self, forKey: .shape) ?? .circle
        screen = try c.decodeIfPresent(Screen.self, forKey: .screen) ?? .full
    }
}

/// On a clip a layout placed: the layout and which take the clip shows in it.
public struct ClipLayout: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case screen, camera }
    public var layout: FrameLayout
    public var role: Role
    /// The director set it in the app. The editor changes it only for a note (`layout_is_yours`).
    public var byDirector: Bool?
    public init(layout: FrameLayout, role: Role, byDirector: Bool? = nil) { self.layout = layout; self.role = role; self.byDirector = byDirector }
}

/// Where the face is in a camera take, about once a second: its middle and height as fractions of the
/// picture (y down), in the take's own seconds.
public struct FaceTrack: Codable, Hashable, Sendable {
    public struct Sample: Codable, Hashable, Sendable {
        public var t: Double, x: Double, y: Double, h: Double
        public init(t: Double, x: Double, y: Double, h: Double) { self.t = t; self.x = x; self.y = y; self.h = h }
    }
    public var samples: [Sample]
    public init(samples: [Sample]) { self.samples = samples }
    /// The samples from `start` to `end`, with the ones either side so keys reach the edges.
    func within(_ start: Double, _ end: Double) -> [Sample] {
        let i = samples.lastIndex { $0.t <= start } ?? 0, j = samples.firstIndex { $0.t >= end } ?? samples.count - 1
        return samples.isEmpty ? [] : Array(samples[i...max(i, j)])
    }
}

/// What Direction's tools found for a layout: which takes in sync are cameras and which are screens,
/// and where the face is in each camera.
public struct LayoutMeasure: Codable, Hashable, Sendable {
    public var cameras: [String]
    public var screens: [String]
    public var faces: [String: FaceTrack]
    public init(cameras: [String], screens: [String], faces: [String: FaceTrack] = [:]) { self.cameras = cameras; self.screens = screens; self.faces = faces }
}

/// Rectangles and placements, as fractions of the frame or the picture with y down.
public enum LayoutGeometry {
    public struct Rect: Hashable, Sendable {
        public var x: Double, y: Double, w: Double, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
        var midX: Double { x + w / 2 }
        var midY: Double { y + h / 2 }
    }
    public struct Size: Hashable, Sendable {
        public var w: Double, h: Double
        public init(_ w: Double, _ h: Double) { self.w = w; self.h = h }
        var aspect: Double { w / max(1, h) }
    }
    /// Space from the frame's edges, a fraction of its height.
    static let margin = 0.04

    /// Where the camera goes in the frame for a layout.
    public static func cameraRect(_ l: FrameLayout, frame: Size) -> Rect {
        let m = margin * frame.h
        switch l.kind {
        case .you, .screen: return Rect(x: 0, y: 0, w: 1, h: 1)
        case .screenAndYou:
            let h = l.size.height * frame.h, w = h * l.shape.aspect
            return Rect(x: (l.corner.right ? frame.w - m - w : m) / frame.w, y: (l.corner.bottom ? frame.h - m - h : m) / frame.h, w: w / frame.w, h: h / frame.h)
        case .sideBySide:
            let left = split * frame.w + m / 2
            return Rect(x: left / frame.w, y: m / frame.h, w: (frame.w - m - left) / frame.w, h: (frame.h - 2 * m) / frame.h)
        }
    }
    /// Side by side: the screen takes the frame's left 64 %.
    static let split = 0.64

    /// Where the screen goes: the whole frame, or fitted inside a padded frame (framed), or the left of side by side.
    public static func screenRect(_ l: FrameLayout, frame: Size, screen: Size) -> Rect {
        let m = margin * frame.h
        guard l.kind == .sideBySide || (l.kind != .you && l.screen == .framed) else { return Rect(x: 0, y: 0, w: 1, h: 1) }
        let area = l.kind == .sideBySide ? Rect(x: m, y: m, w: split * frame.w - 1.5 * m, h: frame.h - 2 * m) : Rect(x: 1.5 * m, y: 1.5 * m, w: frame.w - 3 * m, h: frame.h - 3 * m)
        let fit = min(area.w / screen.w, area.h / screen.h), w = screen.w * fit, h = screen.h * fit
        return Rect(x: (area.x + (area.w - w) / 2) / frame.w, y: (area.y + (area.h - h) / 2) / frame.h, w: w / frame.w, h: h / frame.h)
    }

    /// The part of the camera's picture that fills `rect`: around the face, with it a little above the middle
    /// and about two fifths of the height. Without a face, the upper middle.
    public static func crop(face: FaceTrack.Sample?, height faceHeight: Double?, rect: Rect, frame: Size, source: Size) -> Rect {
        let aspect = rect.w * frame.w / max(1, rect.h * frame.h)
        var ch = min(1, max(0.3, (faceHeight ?? 0.28) / 0.4))
        var cw = ch * source.h * aspect / source.w
        if cw > 1 { cw = 1; ch = source.w / (aspect * source.h) }
        let fx = face?.x ?? 0.5, fy = face?.y ?? 0.4
        let x = min(1 - cw, max(0, fx - cw / 2)), y = min(1 - ch, max(0, fy + 0.08 * ch - ch / 2))
        return Rect(x: x, y: y, w: cw, h: ch)
    }

    /// The transform that puts `crop` of the picture exactly into `rect` of the frame: scale over the fitted
    /// picture, and x and y as fractions of the frame (the transform effect's own terms).
    public static func place(crop: Rect, into rect: Rect, frame: Size, source: Size) -> (scale: Double, x: Double, y: Double) {
        let fit = min(frame.w / source.w, frame.h / source.h)
        let scale = rect.w * frame.w / max(1e-6, crop.w * source.w * fit)
        let size = Size(source.w * fit * scale, source.h * fit * scale)
        let x = (rect.midX * frame.w - (frame.w - size.w) / 2 - crop.midX * size.w) / frame.w
        let y = (rect.midY * frame.h - (frame.h - size.h) / 2 - crop.midY * size.h) / frame.h
        return (scale, x, y)
    }

    /// One clip's transform: crop, scale, x and y, keyed to the face where the camera follows it.
    /// Keys are in the clip's source seconds; still faces give one key.
    public static func transform(crop: [(t: Double, crop: Rect)], into rect: Rect, frame: Size, source: Size) -> ClipEffect {
        func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
        let placed = crop.map { (t: $0.t, crop: $0.crop, place: place(crop: $0.crop, into: rect, frame: frame, source: source)) }
        let first = placed[0]
        var params: [String: JSONValue] = ["scale": .number(r(first.place.scale)),
                                           "crop": .object(["l": .number(r(first.crop.x)), "r": .number(r(max(0, 1 - first.crop.x - first.crop.w))), "t": .number(r(first.crop.y)), "b": .number(r(max(0, 1 - first.crop.y - first.crop.h)))])]
        guard placed.count > 1 else {
            params["x"] = .number(r(first.place.x)); params["y"] = .number(r(first.place.y))
            return ClipEffect(name: "transform", params: params)
        }
        var keys: [String: [Keyframe]] = [:]
        for p in placed {
            for (k, v) in [("x", p.place.x), ("y", p.place.y), ("crop.l", p.crop.x), ("crop.r", max(0, 1 - p.crop.x - p.crop.w)), ("crop.t", p.crop.y), ("crop.b", max(0, 1 - p.crop.y - p.crop.h))] {
                keys[k, default: []].append(Keyframe(t: r(p.t), v: r(v), ease: "smooth"))
            }
        }
        return ClipEffect(name: "transform", params: params, keys: keys)
    }

    /// Where the bubble's crop sits over a stretch of the camera: a key every two seconds where the face
    /// moved, eased, so leaning back carries the bubble with you without it twitching.
    public static func follow(_ track: FaceTrack?, from start: Double, to end: Double, rect: Rect, frame: Size, source: Size) -> [(t: Double, crop: Rect)] {
        let samples = track?.within(start, end) ?? []
        guard !samples.isEmpty else { return [(start, crop(face: nil, height: nil, rect: rect, frame: frame, source: source))] }
        // One size for the stretch, from the face's usual height; only the middle moves.
        let height = samples.map(\.h).sorted()[samples.count / 2]
        let xs = smooth(samples.map(\.x), 3), ys = smooth(samples.map(\.y), 3)
        var out: [(t: Double, crop: Rect)] = []
        for i in samples.indices {
            let c = crop(face: .init(t: samples[i].t, x: xs[i], y: ys[i], h: height), height: height, rect: rect, frame: frame, source: source)
            if let last = out.last {
                guard samples[i].t - last.t >= 2 - 1e-6 || i == samples.count - 1 else { continue }
                // Still: no key for a move nobody would see.
                guard abs(c.x - last.crop.x) > 0.015 || abs(c.y - last.crop.y) > 0.015 || i == samples.count - 1 else { continue }
            }
            out.append((samples[i].t, c))
        }
        if out.count == 2, abs(out[0].crop.x - out[1].crop.x) <= 0.015, abs(out[0].crop.y - out[1].crop.y) <= 0.015 { out.removeLast() }
        return out
    }

    static func smooth(_ v: [Double], _ radius: Int) -> [Double] {
        v.indices.map { i in let a = max(0, i - radius), b = min(v.count - 1, i + radius); return v[a...b].reduce(0, +) / Double(b - a + 1) }
    }

    /// The card effect a layout gives each clip: a circle or rounded corners, a thin edge and a soft shadow;
    /// a framed screen also gets its background.
    public static func card(_ l: FrameLayout, role: ClipLayout.Role) -> ClipEffect? {
        switch (role, l.kind) {
        case (.camera, .screenAndYou): return ClipEffect(name: "card", params: ["radius": .number(l.shape.radius), "edge": .number(0.35), "shadow": .number(0.6)])
        case (.camera, .sideBySide): return ClipEffect(name: "card", params: ["radius": .number(0.06), "edge": .number(0.2), "shadow": .number(0.5)])
        case (.screen, .sideBySide): return ClipEffect(name: "card", params: ["radius": .number(0.03), "edge": .number(0.2), "shadow": .number(0.5), "background": .string(background)])
        case (.screen, .screen), (.screen, .screenAndYou):
            return l.screen == .framed ? ClipEffect(name: "card", params: ["radius": .number(0.03), "edge": .number(0.2), "shadow": .number(0.55), "background": .string(background)]) : nil
        default: return nil
        }
    }
    /// Behind a framed screen: the dark of Direction's own frame.
    public static let background = "#16171A"
}

// MARK: - The layout edit function

extension EditWork {
    /// Carries out `layout` over `range`: what showed those moments from the story's own takes in sync (an
    /// earlier layout, a cutaway to the camera) makes way, and each stretch over a story clip gets the
    /// screen on V2 and the camera on V3 (or the one take a layout needs on V2), in sync, with their framing
    /// and card. Layouts sit just over the story; anything above moves up to make room.
    mutating func layout(_ op: EditOperation) throws -> Outcome {
        guard let spec = op.layout else { throw bad("layout is {kind: screenAndYou|you|screen|sideBySide, corner?, size?, shape?, screen?}.") }
        guard let raw = op.range else { throw bad("range is the stretch of the cut the layout covers, {start, end} in cut seconds.") }
        var r = snap(raw)
        if r.end > s.duration && r.end.seconds <= s.duration.seconds + frame { r.duration = s.duration - r.start }
        guard r.isValid, r.end <= s.duration else { throw bad("range must fall inside the cut, 0–\(String(format: "%.2f", s.duration.seconds)) s.") }
        guard let m = op.resolved?.layout else { throw bad("layout finds the camera, the screen and the face with Direction's tools; send it through direction_edit.") }
        let dailies = context?.dailies ?? Dailies()
        let stories = s.clips.filter { $0.kind == .video && $0.layer == 0 && $0.assetID != nil && $0.start < r.end && $0.end > r.start }.sorted { $0.start < $1.start }
        // What showed these moments before: an earlier layout, and picture in sync from the story's own takes.
        func sameMoment(_ c: Clip) -> Bool {
            guard c.kind == .video, c.layer > 0, c.start < r.end, c.end > r.start else { return false }
            if c.layout != nil { return true }
            guard c.synced == true, let id = c.assetID, let base = story(at: max(c.start, r.start)), let group = dailies.syncGroup(for: base.assetID) else { return false }
            return group.take(id) != nil
        }
        let before = s.clips.filter(sameMoment)
        var placed: [Clip] = [], warnings: [String] = []
        for story in stories {
            let start = max(story.start, r.start), seg = MediaRange(start: start, duration: min(story.end, r.end) - start)
            guard seg.duration.seconds > frame / 2 else { continue }
            guard story.hold == nil, story.speed == 1, let group = dailies.syncGroup(for: story.assetID) else {
                warnings.append("\(label(story)) at \(tc(seg.start)) isn\u{2019}t in sync with a camera and a screen, so it shows what it did.")
                continue
            }
            let takes = group.takes.compactMap { t in project.assets.first { $0.id == t.assetID && !$0.video.isEmpty } }
            let camera = takes.first { m.cameras.contains($0.id) }, screen = takes.first { m.screens.contains($0.id) }
            if (spec.kind.needsCamera && camera == nil) || (spec.kind.needsScreen && screen == nil) {
                warnings.append("There\u{2019}s no \(camera == nil ? "camera" : "screen recording") in sync with \(label(story)) at \(tc(seg.start)), so it shows what it did.")
                continue
            }
            do {
                if spec.kind.needsScreen, let screen { placed.append(try layoutClip(screen, .screen, spec, seg, m)) }
                if spec.kind.needsCamera, let camera { placed.append(try layoutClip(camera, .camera, spec, seg, m)) }
            } catch let e as DirectionError { warnings.append(e.message) }
        }
        guard !placed.isEmpty else { throw DirectionError("not_in_sync", warnings.first ?? "There\u{2019}s no story to lay out between \(tc(r.start)) and \(tc(r.end)).") }
        s.clips = s.clips.filter { !sameMoment($0) } + EditReducer.removing(r, from: before, ripple: false)
        // Layouts sit just over the story: what's in their way moves up, everything over it with it.
        let used = placed.map(\.layer).max() ?? 1
        let inWay = s.clips.contains { c in c.kind != .audio && c.layout == nil && (1...used).contains(c.layer) && placed.contains { $0.layer == c.layer && $0.start < c.end && $0.end > c.start } }
        if inWay { for i in s.clips.indices where s.clips[i].kind != .audio && s.clips[i].layer >= 1 && s.clips[i].layout == nil { s.clips[i].layer += used } }
        s.clips += placed
        return Outcome(summary: "Layout: \(spec.label), \(tc(r.start))–\(tc(r.end))", changes: [.init(before: (r.start.seconds, r.end.seconds), after: (r.start.seconds, r.end.seconds), tracks: Array(Set(placed.map(\.trackName))).sorted())],
                       clipIDs: placed.map(\.id), warnings: warnings)
    }

    /// One take of a layout over one stretch: in sync and silent, framed and carded for its part.
    func layoutClip(_ a: MediaAsset, _ role: ClipLayout.Role, _ spec: FrameLayout, _ seg: MediaRange, _ m: LayoutMeasure) throws -> Clip {
        let layer = role == .screen || !spec.kind.needsScreen ? 1 : 2
        var clip = Clip(assetID: a.id, name: a.name, kind: .video, layer: layer, start: seg.start, sourceRange: try syncedSource(a, at: seg.start, length: seg.duration))
        clip.synced = true
        for stream in a.audio { var settings = stream.settings; settings.muted = true; clip.audioOverrides[String(stream.id)] = settings }
        clip.layout = ClipLayout(layout: spec, role: role, byDirector: director ? true : nil)
        let frameSize = LayoutGeometry.Size(Double(s.width), Double(s.height))
        let source = LayoutGeometry.Size(Double(a.video[0].width), Double(a.video[0].height))
        let whole = LayoutGeometry.Rect(x: 0, y: 0, w: 1, h: 1)
        var effects: [ClipEffect] = []
        switch role {
        case .screen:
            let rect = LayoutGeometry.screenRect(spec, frame: frameSize, screen: source)
            if rect != whole { effects.append(LayoutGeometry.transform(crop: [(clip.sourceRange.start.seconds, whole)], into: rect, frame: frameSize, source: source)) }
        case .camera where spec.kind != .you:
            let rect = LayoutGeometry.cameraRect(spec, frame: frameSize)
            let crops = LayoutGeometry.follow(m.faces[a.id], from: clip.sourceRange.start.seconds, to: clip.sourceRange.end.seconds, rect: rect, frame: frameSize, source: source)
            effects.append(LayoutGeometry.transform(crop: crops, into: rect, frame: frameSize, source: source))
        case .camera: break
        }
        if let card = LayoutGeometry.card(spec, role: role) { effects.append(card) }
        clip.effects = effects.isEmpty ? nil : effects
        return clip
    }

    /// A layout the director set is theirs: the editor changes it only for a note.
    func checkLayoutLock(_ op: EditOperation) throws {
        guard !director, !forNote else { return }
        let mine = { (c: Clip) in c.layout?.byDirector == true }
        let fail = DirectionError("layout_is_yours", "The director set this layout. Change it only for a note that asks for it, and name the note.")
        switch op.type {
        case "layout":
            guard let r = op.range else { return }
            if s.clips.contains(where: { mine($0) && $0.start.seconds < r.end.seconds && $0.end.seconds > r.start.seconds }) { throw fail }
        case "addEffect", "setEffect", "removeEffect":
            if let id = op.target ?? op.clipID, s.clips.first(where: { $0.id == id }).map(mine) == true { throw fail }
            if let e = op.effectID, s.clips.contains(where: { mine($0) && $0.effect(e) != nil }) { throw fail }
        default:
            if let id = op.clipID, s.clips.first(where: { $0.id == id }).map(mine) == true { throw fail }
        }
    }
}

extension Sequence {
    /// The layout showing at a cut time, if one is.
    public func layout(at t: Double) -> FrameLayout? {
        clips.first { $0.layout != nil && $0.start.seconds <= t + 1e-9 && t < $0.end.seconds - 1e-9 }?.layout?.layout
    }
    /// Stretches of the cut with a layout, in order, joined where the same layout carries on.
    public var layoutSpans: [(start: Double, end: Double, layout: FrameLayout, byDirector: Bool)] {
        var out: [(start: Double, end: Double, layout: FrameLayout, byDirector: Bool)] = []
        for c in clips.filter({ $0.layout != nil }).sorted(by: { $0.start < $1.start }) {
            let l = c.layout!, a = c.start.seconds, b = c.end.seconds
            if let last = out.last, last.layout == l.layout, a <= last.end + 1e-6 { out[out.count - 1].end = max(last.end, b); continue }
            out.append((a, b, l.layout, l.byDirector == true))
        }
        return out
    }
}

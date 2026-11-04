import Foundation

// Layouts (layouts.md): how a screen recording and a camera in sync share the frame. A layout is a
// stretch of ordinary synced clips over the story, the screen on V2 and the camera on V3, each carrying
// the layout it belongs to, so preview, export and every edit treat them like any other clip. A layout
// owns only where its clips sit (a smaller screen's `place`, a bubble's transform, their `card`); the
// editor's zooms, blurs and freezes on them carry on when the layout changes. A style names its own
// layouts ("Showing", "Talking").

public struct FrameLayout: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case screenAndYou, you, screen, sideBySide
        public var label: String {
            switch self { case .screenAndYou: "Screen and you"; case .you: "You"; case .screen: "Screen"; case .sideBySide: "Side by side" }
        }
        /// In a frame taller than it's wide, side by side stacks: the screen over you.
        public func label(tall: Bool) -> String { self == .sideBySide && tall ? "Stacked" : label }
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
    /// A style's name for it: "Showing", "Talking".
    public var name: String?
    /// The bubble's edge color (#RRGGBB), drawn solid; without one, a thin light edge.
    public var edge: String?
    public init(kind: Kind, corner: Corner = .bottomRight, size: Size = .medium, shape: Shape = .circle, screen: Screen = .full, name: String? = nil, edge: String? = nil) {
        self.kind = kind; self.corner = corner; self.size = size; self.shape = shape; self.screen = screen; self.name = name; self.edge = edge
    }
    /// What Dailies offers first: the screen, with you in the bottom right.
    public static let standard = FrameLayout(kind: .screenAndYou)

    /// The same layout without its style's name: what the picker makes once the director changes a part.
    public var unnamed: FrameLayout { var l = self; l.name = nil; return l }

    /// A style's name, else "Screen and you · bottom right", "Screen, framed", "You".
    public var label: String {
        if let name, !name.isEmpty { return name }
        return plainLabel
    }
    /// What it is, whatever it's called: "Screen and you · bottom right".
    public var plainLabel: String {
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
        name = try c.decodeIfPresent(String.self, forKey: .name)
        edge = try c.decodeIfPresent(String.self, forKey: .edge)
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
            if stacks(frame) {
                let top = stackSplit(frame) * frame.h + m / 2
                return Rect(x: m / frame.w, y: top / frame.h, w: (frame.w - 2 * m) / frame.w, h: (frame.h - m - top) / frame.h)
            }
            let left = split * frame.w + m / 2
            return Rect(x: left / frame.w, y: m / frame.h, w: (frame.w - m - left) / frame.w, h: (frame.h - 2 * m) / frame.h)
        }
    }
    /// Side by side: the screen takes the frame's left 64 %.
    static let split = 0.64
    /// A frame taller than it's wide (9:16, 4:5) stacks side by side: the screen across the top, you under it.
    public static func stacks(_ frame: Size) -> Bool { frame.h > frame.w * 1.1 }
    /// Stacked: the top of the frame a 16:9 screen needs across its width, at most 64 % of it.
    static func stackSplit(_ frame: Size) -> Double {
        let m = margin * frame.h
        return min(split, ((frame.w - 2 * m) * 9 / 16 + 1.5 * m) / frame.h)
    }

    /// Where the screen goes: the whole frame, or fitted inside a padded frame (framed), or the left of side by side
    /// (its top, stacked).
    public static func screenRect(_ l: FrameLayout, frame: Size, screen: Size) -> Rect {
        let m = margin * frame.h
        guard l.kind == .sideBySide || (l.kind != .you && l.screen == .framed) else { return Rect(x: 0, y: 0, w: 1, h: 1) }
        let area = l.kind != .sideBySide ? Rect(x: 1.5 * m, y: 1.5 * m, w: frame.w - 3 * m, h: frame.h - 3 * m)
            : stacks(frame) ? Rect(x: m, y: m, w: frame.w - 2 * m, h: stackSplit(frame) * frame.h - 1.5 * m)
            : Rect(x: m, y: m, w: split * frame.w - 1.5 * m, h: frame.h - 2 * m)
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

    /// The `place` effect that puts `crop` of a take's picture (fractions of the picture) into `rect` of the
    /// frame, keyed where the crop moves. It acts after the clip's own transform and effects, so a zoom or
    /// a blur the editor put on the clip plays inside the layout's frame.
    public static func placement(crop: [(t: Double, crop: Rect)], into rect: Rect, frame: Size, source: Size) -> ClipEffect {
        func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
        // Where the fitted picture sits in the frame before anything moves it.
        let fit = min(frame.w / source.w, frame.h / source.h)
        let pw = source.w * fit / frame.w, ph = source.h * fit / frame.h, px = (1 - pw) / 2, py = (1 - ph) / 2
        func from(_ c: Rect) -> [(String, Double)] { [("fromX", px + c.x * pw), ("fromY", py + c.y * ph), ("fromW", c.w * pw), ("fromH", c.h * ph)] }
        var params: [String: JSONValue] = ["x": .number(r(rect.x)), "y": .number(r(rect.y)), "w": .number(r(rect.w)), "h": .number(r(rect.h))]
        for (k, v) in from(crop[0].crop) { params[k] = .number(r(v)) }
        guard crop.count > 1 else { return ClipEffect(name: "place", params: params) }
        var keys: [String: [Keyframe]] = [:]
        for c in crop { for (k, v) in from(c.crop) { keys[k, default: []].append(Keyframe(t: r(c.t), v: r(v), ease: "smooth")) } }
        return ClipEffect(name: "place", params: params, keys: keys)
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
        func edged(_ e: ClipEffect) -> ClipEffect { var e = e; if let c = l.edge { e.params["edgeColor"] = .string(c) }; return e }
        switch (role, l.kind) {
        case (.camera, .screenAndYou): return edged(ClipEffect(name: "card", params: ["radius": .number(l.shape.radius), "edge": .number(0.35), "shadow": .number(0.6)]))
        case (.camera, .sideBySide): return edged(ClipEffect(name: "card", params: ["radius": .number(0.06), "edge": .number(0.2), "shadow": .number(0.5)]))
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
        guard let spec = op.layout else {
            if let name = op.layoutName { throw bad("\(name) is one of the style's layouts, found by Direction's tools; send it through direction_edit.") }
            throw bad("layout is the name of one of the style's layouts, or {kind: screenAndYou|you|screen|sideBySide, corner?, size?, shape?, screen?}.")
        }
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
        // Their pieces inside the range carry on wherever the new layout shows the same take, so the
        // editor's zooms, blurs and freezes stay; only where they sit changes.
        func piece(_ c: Clip, _ o: MediaRange) -> Clip {
            guard o != c.range else { return c }
            var p = EditReducer.trimmed(c, to: o); p.id = newID("clip"); p.effects = EditReducer.reIDed(c.effects)
            return p
        }
        let inside = before.compactMap { c in c.range.intersection(r).map { piece(c, $0) } }
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
                for (role, take) in [(ClipLayout.Role.screen, spec.kind.needsScreen ? screen : nil), (.camera, spec.kind.needsCamera ? camera : nil)] {
                    guard let take else { continue }
                    var cursor = seg.start
                    for old in inside.filter({ $0.assetID == take.id && $0.start < seg.end && $0.end > seg.start }).sorted(by: { $0.start < $1.start }) {
                        guard let o = old.range.intersection(seg), o.start >= cursor else { continue }
                        if (o.start - cursor).seconds > frame / 2 { placed.append(try layoutClip(take, role, spec, MediaRange(start: cursor, duration: o.start - cursor), m)) }
                        placed.append(try relaid(piece(old, o), take, role, spec, m))
                        cursor = o.end
                    }
                    if (seg.end - cursor).seconds > frame / 2 { placed.append(try layoutClip(take, role, spec, MediaRange(start: cursor, duration: seg.end - cursor), m)) }
                }
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

    /// One take of a layout over one stretch: in sync and silent, placed and carded for its part.
    func layoutClip(_ a: MediaAsset, _ role: ClipLayout.Role, _ spec: FrameLayout, _ seg: MediaRange, _ m: LayoutMeasure) throws -> Clip {
        var clip = Clip(assetID: a.id, name: a.name, kind: .video, layer: Self.layoutLayer(role, spec), start: seg.start, sourceRange: try syncedSource(a, at: seg.start, length: seg.duration))
        clip.synced = true
        for stream in a.audio { var settings = stream.settings; settings.muted = true; clip.audioOverrides[String(stream.id)] = settings }
        clip.layout = ClipLayout(layout: spec, role: role, byDirector: director ? true : nil)
        let own = layoutEffects(a, role, spec, clip.sourceRange, m)
        clip.effects = own.isEmpty ? nil : own
        return clip
    }

    /// A clip that was already there, moved into the new layout. What the editor did to it stays: a zoom on
    /// the screen (its transform), masks, blurs, filters and its freeze. What placed it before goes: an
    /// earlier layout's place, card and bubble, or a bubble made by hand (a camera scaled down, a shader).
    func relaid(_ old: Clip, _ a: MediaAsset, _ role: ClipLayout.Role, _ spec: FrameLayout, _ m: LayoutMeasure) throws -> Clip {
        var c = old
        let effects = old.effects ?? [], before = old.layout
        let tr = effects.first { $0.name == "transform" }
        func placesCamera(_ l: FrameLayout) -> Bool { l.kind == .screenAndYou || l.kind == .sideBySide }
        let wasBubble = role == .camera && ((before.map { $0.role == .camera && placesCamera($0.layout) } ?? false) || (tr?.params["scale"]?.double ?? 1) < 0.99)
        // Layouts before `place` framed a smaller screen with its transform.
        let framedScreen = role == .screen && before != nil && !effects.contains { $0.name == "place" } && (before!.layout.kind == .sideBySide || before!.layout.screen == .framed)
        let bubble = role == .camera && placesCamera(spec)
        let kept = effects.filter { e in
            switch e.name {
            case "place", "card", "pin": return false
            case "transform": return !(wasBubble || framedScreen || bubble)
            case "shader": return !(wasBubble || bubble)
            default: return true
            }
        }
        c.layer = Self.layoutLayer(role, spec)
        c.layout = ClipLayout(layout: spec, role: role, byDirector: director ? true : nil)
        let own = layoutEffects(a, role, spec, old.sourceRange, m)
        // The layout's bubble transform goes first, where a transform belongs.
        let all = own.filter { $0.name == "transform" } + kept + own.filter { $0.name != "transform" }
        c.effects = all.isEmpty ? nil : all
        return c
    }

    static func layoutLayer(_ role: ClipLayout.Role, _ spec: FrameLayout) -> Int { role == .screen || !spec.kind.needsScreen ? 1 : 2 }

    /// What a layout puts on one take's clip: where it sits and its card. A smaller screen is placed after
    /// its own effects (`place`), so the editor's zoom plays inside it; a camera bubble is framed on the face
    /// by its transform, read from the take itself so it stays sharp.
    func layoutEffects(_ a: MediaAsset, _ role: ClipLayout.Role, _ spec: FrameLayout, _ source: MediaRange, _ m: LayoutMeasure) -> [ClipEffect] {
        let frameSize = LayoutGeometry.Size(Double(s.width), Double(s.height))
        let picture = LayoutGeometry.Size(Double(a.video[0].width), Double(a.video[0].height))
        let whole = LayoutGeometry.Rect(x: 0, y: 0, w: 1, h: 1)
        var effects: [ClipEffect] = []
        switch role {
        case .screen:
            let rect = LayoutGeometry.screenRect(spec, frame: frameSize, screen: picture)
            if rect != whole { effects.append(LayoutGeometry.placement(crop: [(source.start.seconds, whole)], into: rect, frame: frameSize, source: picture)) }
        case .camera where spec.kind != .you:
            let rect = LayoutGeometry.cameraRect(spec, frame: frameSize)
            let crops = LayoutGeometry.follow(m.faces[a.id], from: source.start.seconds, to: source.end.seconds, rect: rect, frame: frameSize, source: picture)
            effects.append(LayoutGeometry.transform(crop: crops, into: rect, frame: frameSize, source: picture))
        case .camera: break
        }
        if let card = LayoutGeometry.card(spec, role: role) { effects.append(card) }
        return effects
    }

    /// A layout the director set is theirs: where its clips sit changes only for a note. The editor can
    /// still zoom the screen, blur or mask what's private, and freeze it.
    func checkLayoutLock(_ op: EditOperation) throws {
        guard !director, !forNote else { return }
        let mine = { (c: Clip) in c.layout?.byDirector == true }
        let fail = DirectionError("layout_is_yours", "The director set this layout, so where its clips sit is theirs. Zoom, blur or freeze them if the style asks; change the layout only for a note that asks for it, and name the note.")
        /// The effects that place a clip in the director's layout: its place and card, and the transform on a bubble.
        func placing(_ name: String?, on c: Clip) -> Bool {
            guard let name else { return false }
            if name == "place" || name == "card" || name == "pin" { return true }
            return name == "transform" && c.layout?.role == .camera && c.layout?.layout.kind != .you
        }
        switch op.type {
        case "layout":
            guard let r = op.range else { return }
            if s.clips.contains(where: { mine($0) && $0.start.seconds < r.end.seconds && $0.end.seconds > r.start.seconds }) { throw fail }
        case "addEffect":
            if let id = op.target ?? op.clipID, let c = s.clips.first(where: { $0.id == id }), mine(c), placing(op.effect, on: c) { throw fail }
        case "setEffect", "removeEffect":
            if let e = op.effectID, let c = s.clips.first(where: { mine($0) && $0.effect(e) != nil }), placing(c.effect(e)?.name, on: c) { throw fail }
        case "reframe":
            if let id = op.clipID, let c = s.clips.first(where: { $0.id == id }), mine(c), placing("transform", on: c) { throw fail }
        case "freeze": return
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

import Foundation

// Screen zooms (agent-timeline.md › Moves): Screen Studio-style moves on a screen recording that Direction
// works out itself. It looks at what changes on screen about four times a second (the cursor moving, a
// click landing, typing), finds the moments where the change stays in one place long enough to watch,
// and writes eased zooms to them: in, a pan when the action moves to a new area, out when it's over.
// Big changes (a new page) end a moment. The keys go on the screen clip's own transform, so a layout's
// frame around it stays put.

/// What changed on a screen recording between one look and the next: how much (a fraction of the picture),
/// where its middle is and the box around it (fractions of the picture, y down). `t` is in the take's seconds.
public struct ActivitySample: Codable, Hashable, Sendable {
    public var t: Double
    public var amount: Double
    public var cx: Double, cy: Double
    public var x: Double, y: Double, w: Double, h: Double
    public init(t: Double, amount: Double, cx: Double = 0.5, cy: Double = 0.5, x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0) {
        self.t = t; self.amount = amount; self.cx = cx; self.cy = cy; self.x = x; self.y = y; self.w = w; self.h = h
    }
}

public enum ZoomPlanner {
    /// More of the picture than this changing at once is a new page, not something to look at.
    public static let pageChange = 0.2
    /// How far (a fraction of the picture) the action can wander and still be the same moment.
    static let reach = 0.18
    /// How long the screen can rest inside a moment.
    static let quiet = 1.5
    /// The fewest looks with something changing for a moment worth zooming to (about three quarters of a second).
    static let dwell = 3
    /// What the zoomed view leaves around the action, as a share of what it shows.
    static let fill = 0.55
    /// Moments closer than this pan from one to the next instead of zooming out and straight back in.
    static let together = 2.0

    /// A stretch where the action stays in one area: when, where (its middle) and how big, in picture fractions.
    public struct Moment: Hashable, Sendable {
        public var start: Double, end: Double
        public var cx: Double, cy: Double, w: Double, h: Double
        /// A new page came right after it: the view goes back out rather than panning on.
        public var newPage = false
        public init(start: Double, end: Double, cx: Double, cy: Double, w: Double, h: Double, newPage: Bool = false) { self.start = start; self.end = end; self.cx = cx; self.cy = cy; self.w = w; self.h = h; self.newPage = newPage }
    }

    /// The moments worth zooming to between `from` and `to` (take seconds), each held at least `hold` seconds.
    public static func moments(_ samples: [ActivitySample], from: Double, to: Double, hold: Double) -> [Moment] {
        var out: [Moment] = []
        var members: [ActivitySample] = []
        func close(newPage: Bool = false) {
            defer { members = [] }
            guard members.count >= dwell, let first = members.first, let last = members.last else { return }
            let n = Double(members.count)
            let cx = members.map(\.cx).reduce(0, +) / n, cy = members.map(\.cy).reduce(0, +) / n
            let x0 = members.map(\.x).min()!, y0 = members.map(\.y).min()!, x1 = members.map { $0.x + $0.w }.max()!, y1 = members.map { $0.y + $0.h }.max()!
            out.append(Moment(start: first.t, end: Swift.max(last.t, first.t + hold), cx: cx, cy: cy, w: Swift.min(1, x1 - x0), h: Swift.min(1, y1 - y0), newPage: newPage))
        }
        for s in samples.sorted(by: { $0.t < $1.t }) where s.t >= from - 1e-6 && s.t <= to + 1e-6 {
            if s.amount >= pageChange {
                close(newPage: true)
                if !out.isEmpty { out[out.count - 1].newPage = true; out[out.count - 1].end = Swift.min(out[out.count - 1].end, s.t) }
                continue
            }
            guard s.amount > 0 else {
                if let last = members.last, s.t - last.t > quiet { close() }
                continue
            }
            if let last = members.last {
                let n = Double(members.count), mx = members.map(\.cx).reduce(0, +) / n, my = members.map(\.cy).reduce(0, +) / n
                if hypot(s.cx - mx, s.cy - my) > reach || s.t - last.t > quiet { close() }
            }
            members.append(s)
        }
        close()
        // A moment ends where the next begins: the view pans on rather than holding over the next one.
        for i in out.indices.dropLast() where out[i].end > out[i + 1].start { out[i].end = out[i + 1].start }
        return out.map { var m = $0; m.end = Swift.min(m.end, to); return m }
    }

    /// How far to zoom for a moment: enough that the action fills about half the view, within the style's range.
    public static func scale(_ m: Moment, zoom: StyleMoves.Zoom) -> Double {
        let s = Swift.min(fill / Swift.max(m.w, 0.05), fill / Swift.max(m.h, 0.05))
        return (Swift.min(zoom.max, Swift.max(zoom.min, s)) * 100).rounded() / 100
    }

    /// Where a clip's picture sits for a view at `scale` centered on (cx, cy) of the take's picture: the
    /// transform's x and y, never past the picture's edges. `fitted` is how much of the frame the cropped
    /// picture fills at scale 1, and `crop` its l, r, t, b.
    public static func offset(cx: Double, cy: Double, scale: Double, fitted: (w: Double, h: Double), crop: (l: Double, r: Double, t: Double, b: Double)) -> (x: Double, y: Double) {
        let u = Swift.min(1, Swift.max(0, (cx - crop.l) / Swift.max(0.01, 1 - crop.l - crop.r))), v = Swift.min(1, Swift.max(0, (cy - crop.t) / Swift.max(0.01, 1 - crop.t - crop.b)))
        let coverX = fitted.w * scale, coverY = fitted.h * scale
        func clamp(_ x: Double, _ cover: Double) -> Double { let m = Swift.max(0, (cover - 1) / 2); return (Swift.min(m, Swift.max(-m, x)) * 10_000).rounded() / 10_000 }
        return (clamp(-(u - 0.5) * coverX, coverX), clamp(-(v - 0.5) * coverY, coverY))
    }

    /// Transform keys (scale, x, y in take seconds) for views of `moments` between `from` and `to`: in from
    /// the resting view, pans between moments close together, out again after. `rest` is the clip's own view.
    public static func keys(_ views: [(m: Moment, scale: Double)], from: Double, to: Double, zoom: StyleMoves.Zoom, rest: (scale: Double, x: Double, y: Double),
                            place: (Moment, Double) -> (x: Double, y: Double)) -> [String: [Keyframe]] {
        var scale: [Keyframe] = [], xs: [Keyframe] = [], ys: [Keyframe] = []
        func key(_ t: Double, _ v: (scale: Double, x: Double, y: Double)) {
            let t = (Swift.min(to, Swift.max(from, t)) * 1000).rounded() / 1000
            if let last = scale.last, t <= last.t + 1e-6 { scale.removeLast(); xs.removeLast(); ys.removeLast() }
            scale.append(.init(t: t, v: v.scale, ease: "smooth")); xs.append(.init(t: t, v: v.x, ease: "smooth")); ys.append(.init(t: t, v: v.y, ease: "smooth"))
        }
        let pan = 0.5
        var i = 0
        while i < views.count {
            // A group: moments close enough that zooming out between them would be a bounce.
            var j = i
            while j + 1 < views.count, !views[j].m.newPage, views[j + 1].m.start - views[j].m.end < Swift.max(together, zoom.in + zoom.out + 0.3) { j += 1 }
            let first = views[i]
            key(first.m.start - zoom.in, rest)
            var at = place(first.m, first.scale)
            key(first.m.start, (first.scale, at.x, at.y))
            for k in stride(from: i + 1, through: j, by: 1) {
                let v = views[k], next = place(v.m, v.scale)
                key(Swift.max(views[k - 1].m.start, v.m.start - pan), (views[k - 1].scale, at.x, at.y))
                key(v.m.start, (v.scale, next.x, next.y))
                at = next
            }
            let last = views[j]
            key(last.m.end, (last.scale, at.x, at.y))
            key(last.m.end + zoom.out, rest)
            i = j + 1
        }
        return scale.count < 2 ? [:] : ["scale": scale, "x": xs, "y": ys]
    }
}

extension EditWork {
    /// The clips showing a screen recording over `r`: a layout's screen, or the take on V1 where nothing covers it.
    func screenClips(_ r: MediaRange, assets: Set<String>, clipID: String?) -> [Int] {
        if let clipID, let i = s.clips.firstIndex(where: { $0.id == clipID }) { return [i] }
        let over = s.clips.indices.filter { i in
            let c = s.clips[i]
            return c.kind == .video && c.hold == nil && c.start < r.end && c.end > r.start && assets.contains(c.assetID ?? "")
        }
        let laid = over.filter { s.clips[$0].layout?.role == .screen }
        return laid.isEmpty ? over.filter { s.clips[$0].layer == 0 && !hidden(s.clips[$0]) } : laid
    }

    /// Writes zoom keys over one clip's stretch of `r`, replacing its own scale, x and y keys there.
    mutating func zoomKeys(_ i: Int, _ r: MediaRange, _ plan: ([ZoomPlanner.Moment]) -> [(m: ZoomPlanner.Moment, scale: Double)], moments: (Double, Double) -> [ZoomPlanner.Moment], zoom: StyleMoves.Zoom) -> Bool {
        let c = s.clips[i]
        guard let a = project.assets.first(where: { $0.id == c.assetID }), let v = a.video.first else { return false }
        let from = c.sourceTime(at: max(c.start, r.start)).seconds, to = c.sourceTime(at: min(c.end, r.end)).seconds
        var fx = c.effects?.first { $0.name == "transform" } ?? ClipEffect(name: "transform")
        let crop = (l: fx.params["crop"]?["l"].double ?? 0, r: fx.params["crop"]?["r"].double ?? 0, t: fx.params["crop"]?["t"].double ?? 0, b: fx.params["crop"]?["b"].double ?? 0)
        let cw = Double(v.width) * (1 - crop.l - crop.r), ch = Double(v.height) * (1 - crop.t - crop.b)
        let fit = min(Double(s.width) / cw, Double(s.height) / ch)
        let fitted = (w: cw * fit / Double(s.width), h: ch * fit / Double(s.height))
        let rest = (scale: fx.params["scale"]?.double ?? 1, x: fx.params["x"]?.double ?? 0, y: fx.params["y"]?.double ?? 0)
        // The zoom is on top of the clip's own view: 2× of a picture already at 1.1× is 2.2×.
        let views = plan(moments(from, to)).map { (m: $0.m, scale: $0.scale * rest.scale) }
        guard !views.isEmpty else { return false }
        let made = ZoomPlanner.keys(views, from: from, to: to, zoom: zoom, rest: rest) { m, scale in ZoomPlanner.offset(cx: m.cx, cy: m.cy, scale: scale, fitted: fitted, crop: crop) }
        guard !made.isEmpty else { return false }
        var keys = fx.keys ?? [:]
        for k in ["scale", "x", "y"] {
            let kept = (keys[k] ?? []).filter { $0.t < from - 1e-6 || $0.t > to + 1e-6 }
            // Where the clip had no keys of its own, the zoom's resting view is its still value.
            keys[k] = (kept + made[k]!.map { var f = $0; if k == "scale" { f.v = (f.v * 10_000).rounded() / 10_000 }; return f }).sorted { $0.t < $1.t }
        }
        fx.keys = keys
        setEffect(fx, on: i)
        return true
    }

    /// `autoZoom`: Screen Studio-style zooms over `range` of the screen recordings in it, to where the action is.
    mutating func autoZoom(_ op: EditOperation) throws -> Outcome {
        guard let raw = op.range else { throw bad("range is the stretch to zoom through, {start, end} in cut seconds.") }
        guard let activity = op.resolved?.activity else { throw bad("autoZoom looks at the screen with Direction's tools; send it through direction_edit.") }
        let zoom = op.resolved?.zoom ?? StyleMoves.standard.screenZoom!
        let r = snap(raw)
        let clips = screenClips(r, assets: Set(activity.keys), clipID: op.clipID)
        guard !clips.isEmpty else { throw bad("There's no screen recording showing between \(tc(r.start)) and \(tc(r.end)). Name its clipID.") }
        var zoomed: [Clip] = [], count = 0
        for i in clips {
            let samples = activity[s.clips[i].assetID ?? ""] ?? []
            var n = 0
            let did = zoomKeys(i, r, { ms in n = ms.count; return ms.map { ($0, op.scale ?? ZoomPlanner.scale($0, zoom: zoom)) } }, moments: { ZoomPlanner.moments(samples, from: $0, to: $1, hold: zoom.hold) }, zoom: zoom)
            if did { zoomed.append(s.clips[i]); count += n }
        }
        guard !zoomed.isEmpty else { throw bad("Nothing on screen between \(tc(r.start)) and \(tc(r.end)) stays in one place long enough to zoom to. Zoom to a place with zoomTo and focus {x, y} or {text}.") }
        return Outcome(summary: "Zoomed to \(count) moment\(count == 1 ? "" : "s") on screen \(tc(r.start))–\(tc(r.end))", changes: zoomed.map { .init(before: (max($0.start, r.start).seconds, min($0.end, r.end).seconds), after: (max($0.start, r.start).seconds, min($0.end, r.end).seconds), tracks: [$0.trackName]) }, clipIDs: zoomed.map(\.id))
    }

    /// `zoomTo`: one zoom over `range`: in at its start, out by its end, to the action there, a point, or words on screen.
    mutating func zoomTo(_ op: EditOperation) throws -> Outcome {
        guard let raw = op.range else { throw bad("range is when the zoom shows, {start, end} in cut seconds: in at the start, out by the end.") }
        let zoom = op.resolved?.zoom ?? StyleMoves.standard.screenZoom!
        let r = snap(raw)
        guard r.duration.seconds >= zoom.in + zoom.out + 0.3 else { throw bad("A zoom needs at least \(String(format: "%g", zoom.in + zoom.out + 0.3)) s: in over \(String(format: "%g", zoom.in)) s, a moment held, out over \(String(format: "%g", zoom.out)) s.") }
        if let s = op.scale { guard (1.05...4).contains(s) else { throw bad("scale is 1.05 to 4.") } }
        let activity = op.resolved?.activity ?? [:]
        let clips = screenClips(r, assets: Set(activity.keys).union(op.resolved?.assetID.map { [$0] } ?? []), clipID: op.clipID)
        guard let i = clips.first else { throw bad("There's no screen recording showing between \(tc(r.start)) and \(tc(r.end)). Name its clipID.") }
        let c = s.clips[i]
        // Where to look: a point given, words found on screen, or where the action is.
        let target: ZoomPlanner.Moment
        let from = c.sourceTime(at: max(c.start, r.start)).seconds, to = c.sourceTime(at: min(c.end, r.end)).seconds
        if let box = op.resolved?.box, box.count == 4 {
            target = .init(start: from, end: to, cx: box[0] + box[2] / 2, cy: box[1] + box[3] / 2, w: box[2], h: box[3])
        } else if let x = op.focus?["x"].double, let y = op.focus?["y"].double {
            guard (0...1).contains(x), (0...1).contains(y) else { throw bad("focus x and y are fractions of the picture, 0–1 from its top left.") }
            target = .init(start: from, end: to, cx: x, cy: y, w: 0.2, h: 0.2)
        } else {
            let samples = (activity[c.assetID ?? ""] ?? []).filter { $0.t >= from && $0.t <= to && $0.amount > 0 && $0.amount < ZoomPlanner.pageChange }
            guard !samples.isEmpty else { throw bad("Nothing changes on screen between \(tc(r.start)) and \(tc(r.end)). Give focus {x, y} or {text}.") }
            let n = Double(samples.count), x0 = samples.map(\.x).min()!, y0 = samples.map(\.y).min()!
            target = .init(start: from, end: to, cx: samples.map(\.cx).reduce(0, +) / n, cy: samples.map(\.cy).reduce(0, +) / n, w: samples.map { $0.x + $0.w }.max()! - x0, h: samples.map { $0.y + $0.h }.max()! - y0)
        }
        let scale = op.scale ?? ZoomPlanner.scale(target, zoom: zoom)
        var held = target; held.start = from + zoom.in; held.end = to - zoom.out
        guard zoomKeys(i, r, { _ in [(held, scale)] }, moments: { _, _ in [held] }, zoom: zoom) else { throw bad("Can't zoom \(label(c)) there.") }
        return Outcome(summary: "Zoomed \(String(format: "%g", scale))× on screen \(tc(r.start))–\(tc(r.end))", changes: [.init(before: (r.start.seconds, r.end.seconds), after: (r.start.seconds, r.end.seconds), tracks: [c.trackName])], clipIDs: [c.id])
    }
}

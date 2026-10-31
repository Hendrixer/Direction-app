import Foundation

// Moves (agent-timeline.md › Moves): what a style does to the picture that Direction can work out itself,
// so the editor names the moment and Direction writes the transform. Punch-ins change the framing on
// every jump cut, the emphasis punch cuts in on one line, the slow push creeps in across a long take. All
// of them frame on the face (from the same face tracks layouts use) and leave the picture covering the
// frame. Where a layout shows you full frame over the story (You, on V2), they frame that clip too, cut
// where the story cuts, since it's what plays.

extension EditWork {
    /// The talking picture on V1 over `r`, in order.
    func storyClips(_ r: MediaRange) -> [Clip] {
        s.clips.filter { $0.kind == .video && $0.layer == 0 && $0.assetID != nil && $0.start < r.end && $0.end > r.start }.sorted { $0.start < $1.start }
    }

    /// The transform that scales a take by `scale` with its face where `keepIn` puts it: thirds keeps the face
    /// where it was across the frame with the eyes on the upper third; center centers it. Never past the edges.
    func faceFraming(_ c: Clip, scale: Double, keepIn: String?, faces: [String: FaceTrack]?) -> (x: Double, y: Double) {
        guard let a = project.assets.first(where: { $0.id == c.assetID }), let v = a.video.first else { return (0, 0) }
        let w = Double(s.width), h = Double(s.height), pw = Double(v.width), ph = Double(v.height)
        let fit = min(w / pw, h / ph), coverX = pw * fit / w * scale, coverY = ph * fit / h * scale
        let samples = faces?[a.id]?.within(c.sourceRange.start.seconds, c.sourceRange.end.seconds) ?? []
        guard !samples.isEmpty else { return (0, 0) }
        let fx = samples.map(\.x).sorted()[samples.count / 2], fy = samples.map(\.y).sorted()[samples.count / 2]
        let target: (Double, Double) = keepIn == "center" ? (0.5, 0.5) : (0.5 + (fx - 0.5) * pw * fit / w, 0.38)
        func clamp(_ v: Double, _ cover: Double) -> Double { let m = max(0, (cover - 1) / 2); return (min(m, max(-m, v)) * 10_000).rounded() / 10_000 }
        return (clamp(target.0 - 0.5 - (fx - 0.5) * coverX, coverX), clamp(target.1 - 0.5 - (fy - 0.5) * coverY, coverY))
    }

    /// Sets a still framing on a clip's transform, keeping its other values (crop, rotation, opacity).
    mutating func setFraming(_ i: Int, scale: Double, at p: (x: Double, y: Double)) -> String {
        var fx = s.clips[i].effects?.first { $0.name == "transform" } ?? ClipEffect(name: "transform")
        fx.params["scale"] = .number((scale * 10_000).rounded() / 10_000); fx.params["x"] = .number(p.x); fx.params["y"] = .number(p.y)
        var keys = fx.keys ?? [:]
        for k in ["scale", "x", "y"] { keys[k] = nil }
        fx.keys = keys.isEmpty ? nil : keys
        setEffect(fx, on: i)
        return fx.id
    }

    /// What shows a story clip's moment full frame: a layout's camera in You over it, split first where the
    /// story clip starts and ends so each shot carries its own framing; else the clip itself, unless a layout
    /// covers it (it doesn't show there).
    mutating func fullFrame(_ c: Clip) -> [Int] {
        for t in [c.start, c.end] {
            while let i = s.clips.firstIndex(where: { youCamera($0) && $0.start.seconds < t.seconds - frame / 2 && $0.end.seconds > t.seconds + frame / 2 }) {
                let (l, r) = EditReducer.split(s.clips[i], at: t); s.clips.replaceSubrange(i...i, with: [l, r])
            }
        }
        let laid = s.clips.indices.filter { youCamera(s.clips[$0]) && s.clips[$0].start.seconds >= c.start.seconds - frame / 2 && s.clips[$0].end.seconds <= c.end.seconds + frame / 2 }
        if !laid.isEmpty { return laid }
        if hidden(c) { return [] }
        return s.clips.firstIndex { $0.id == c.id }.map { [$0] } ?? []
    }
    /// A story clip a layout covers all of: what plays there is the layout's.
    func hidden(_ c: Clip) -> Bool { s.clips.contains { $0.layer > 0 && $0.layout != nil && $0.start.seconds <= c.start.seconds + frame / 2 && $0.end.seconds >= c.end.seconds - frame / 2 } }
    func youCamera(_ c: Clip) -> Bool { c.layer > 0 && c.layout?.role == .camera && c.layout?.layout.kind == .you }

    /// A transform that moves on its own (a push, a follow) isn't framed over.
    func moving(_ c: Clip) -> Bool { c.effects?.first { $0.name == "transform" }?.keys.map { $0["scale"] != nil || $0["x"] != nil } ?? false }
    func scaleOf(_ c: Clip) -> Double { c.effects?.first { $0.name == "transform" }?.params["scale"]?.double ?? 1 }

    /// `punchIn`: on every jump cut over `range` (one take cut to itself), the framing changes to the next
    /// of `scales`, so no cut looks like a twitch; a cut to another take starts again from the first.
    mutating func punchIn(_ op: EditOperation) throws -> Outcome {
        guard let raw = op.range else { throw bad("range is the stretch whose jump cuts change framing, {start, end} in cut seconds.") }
        let scales = op.scales ?? StyleMoves.standard.punchIn!.scales
        guard scales.count >= 2, scales.allSatisfy({ (1...3).contains($0) }) else { throw bad("scales lists two or more framings from 1 to 3, like [1, 1.15].") }
        if let keep = op.keepIn { guard keep == "thirds" || keep == "center" else { throw bad("keepIn is thirds or center.") } }
        let r = snap(raw), story = storyClips(r)
        guard !story.isEmpty else { throw bad("There's no picture on V1 between \(tc(r.start)) and \(tc(r.end)).") }
        func jump(_ a: Clip, _ b: Clip) -> Bool { a.assetID == b.assetID && abs(a.end.seconds - b.start.seconds) < frame / 2 }
        // Carry on from the shot before the range, so its framing isn't repeated across the first cut.
        let before = s.clips.filter { $0.kind == .video && $0.layer == 0 && $0.assetID != nil && abs($0.end.seconds - story[0].start.seconds) < frame / 2 }.first
        var k = before.map { b in jump(b, story[0]) ? ((scales.firstIndex { abs($0 - scaleOf(b)) < 0.005 } ?? -1) + 1) % scales.count : 0 } ?? 0
        var framed: [Clip] = [], skipped: [String] = []
        for (n, c) in story.enumerated() {
            if n > 0 { k = jump(story[n - 1], c) ? (k + 1) % scales.count : 0 }
            guard !moving(c) else { skipped.append(label(c)); continue }
            for i in fullFrame(c) where !moving(s.clips[i]) {
                _ = setFraming(i, scale: scales[k], at: faceFraming(s.clips[i], scale: scales[k], keepIn: op.keepIn ?? "thirds", faces: op.resolved?.faces))
            }
            framed.append(c)
        }
        let changes = framed.map { LocalChange(before: ($0.start.seconds, $0.end.seconds), after: ($0.start.seconds, $0.end.seconds), tracks: [$0.trackName]) }
        return Outcome(summary: "Punched in on the cuts \(tc(r.start))–\(tc(r.end)): " + scales.map { String(format: "%g×", $0) }.joined(separator: ", "), changes: changes, clipIDs: framed.map(\.id),
                       warnings: skipped.isEmpty ? [] : ["\(skipped.joined(separator: ", ")) already move\(skipped.count == 1 ? "s" : ""), so I left \(skipped.count == 1 ? "it" : "them") as \(skipped.count == 1 ? "it is" : "they are")."])
    }

    /// `emphasisPunch`: cuts in to `scale` on the face for `range` (one line, on one shot) and back out
    /// after it: two cuts on the same take, nothing else moves.
    mutating func emphasisPunch(_ op: EditOperation) throws -> Outcome {
        guard let raw = op.range else { throw bad("range is the line to punch in on, {start, end} in cut seconds.") }
        let scale = op.scale ?? StyleMoves.standard.emphasisPunch!.scale
        guard (1.05...3).contains(scale) else { throw bad("scale is 1.05 to 3.") }
        let r = snap(raw)
        guard r.duration.seconds >= frame * 6 else { throw bad("Punch in on a line of at least a quarter of a second.") }
        guard let c = storyClips(r).first, c.start <= r.start, c.end >= r.end else { throw bad("The line from \(tc(r.start)) to \(tc(r.end)) has to sit inside one shot on V1. Punch in on each shot's part.") }
        guard !moving(c) else { throw bad("\(label(c)) already moves (a push or a follow). Take that off first, or punch in on another line.") }
        guard var i = s.clips.firstIndex(where: { $0.id == c.id }) else { throw bad("There's no shot there.") }
        // Cut in at the line's start and out at its end, unless it starts or ends with the shot.
        if r.start.seconds > c.start.seconds + frame / 2 {
            let (l, rest) = EditReducer.split(s.clips[i], at: r.start); s.clips.replaceSubrange(i...i, with: [l, rest]); i += 1
        }
        if r.end.seconds < s.clips[i].end.seconds - frame / 2 {
            let (mid, after) = EditReducer.split(s.clips[i], at: r.end); s.clips.replaceSubrange(i...i, with: [mid, after])
        }
        let punched = s.clips[i]
        for j in fullFrame(punched) {
            _ = setFraming(j, scale: scale, at: faceFraming(s.clips[j], scale: scale, keepIn: op.keepIn ?? "thirds", faces: op.resolved?.faces))
        }
        return Outcome(summary: "Punched in to \(String(format: "%g", scale))× on \(tc(r.start))–\(tc(r.end))", changes: [.init(before: (r.start.seconds, r.end.seconds), after: (r.start.seconds, r.end.seconds), tracks: [punched.trackName])], clipIDs: [punched.id])
    }

    /// `slowPush`: on each shot over `range` at least `longerThan` long that holds still, the framing creeps
    /// from the first of `scales` to the second across the shot, toward the face. A punched-in shot is left alone.
    mutating func slowPush(_ op: EditOperation) throws -> Outcome {
        guard let raw = op.range else { throw bad("range is the stretch whose long shots push in, {start, end} in cut seconds.") }
        let push = StyleMoves.standard.slowPush!
        let scales = op.scales ?? [push.from, push.to], longer = op.longerThan ?? push.longerThan
        guard scales.count == 2, scales.allSatisfy({ (1...3).contains($0) }), scales[1] > scales[0] else { throw bad("scales is where the push starts and ends, like [1, 1.05].") }
        guard longer >= 0, longer < 600 else { throw bad("longerThan is the shortest shot to push in on, in seconds.") }
        let r = snap(raw)
        var pushed: [Clip] = []
        for c in storyClips(r) where c.duration.seconds >= longer - 1e-6 && !moving(c) && abs(scaleOf(c) - scales[0]) < 0.005 {
            for i in fullFrame(c) where !moving(s.clips[i]) {
                let t = s.clips[i]
                let a = faceFraming(t, scale: scales[0], keepIn: op.keepIn ?? "thirds", faces: op.resolved?.faces)
                let b = faceFraming(t, scale: scales[1], keepIn: op.keepIn ?? "thirds", faces: op.resolved?.faces)
                var fx = t.effects?.first { $0.name == "transform" } ?? ClipEffect(name: "transform")
                let t0 = t.sourceRange.start.seconds, t1 = t.sourceRange.end.seconds
                fx.params["scale"] = .number(scales[0]); fx.params["x"] = .number(a.x); fx.params["y"] = .number(a.y)
                var keys = fx.keys ?? [:]
                keys["scale"] = [.init(t: t0, v: scales[0]), .init(t: t1, v: scales[1])]
                keys["x"] = [.init(t: t0, v: a.x), .init(t: t1, v: b.x)]
                keys["y"] = [.init(t: t0, v: a.y), .init(t: t1, v: b.y)]
                fx.keys = keys
                setEffect(fx, on: i)
            }
            pushed.append(c)
        }
        guard !pushed.isEmpty else { throw bad("No shot between \(tc(r.start)) and \(tc(r.end)) is \(String(format: "%g", longer)) s or longer and holding still at \(String(format: "%g", scales[0]))×.") }
        return Outcome(summary: "Pushed in \(String(format: "%g", scales[0]))× to \(String(format: "%g", scales[1]))× on \(pushed.count) long shot\(pushed.count == 1 ? "" : "s")", changes: pushed.map { .init(before: ($0.start.seconds, $0.end.seconds), after: ($0.start.seconds, $0.end.seconds), tracks: [$0.trackName]) }, clipIDs: pushed.map(\.id))
    }
}

import Foundation

/// Locks, checked one operation at a time so the error names it (agent-timeline.md › errors).
/// A lock keeps the cut, and color and sound stay open under it. A locked scene is its stretch of V1
/// and every picture over or under it; it may move whole when something before it changes length, but
/// what's in it and when may not change. After picture lock the same holds for the whole film, except
/// the graphics over the picture (captions, titles, lower thirds, credits), which finishing places.
enum TimelineLocks {
    static let afterPictureLock: Set<String> = ["balance", "matchBalance", "cameraLUT", "color", "gain", "fade", "duck", "audio", "placeMusic", "parts", "syncSound"]

    static func gate(_ op: EditOperation, _ w: EditWork, _ c: EditContext) throws {
        guard c.state.pictureLocked, !afterPictureLock.contains(op.type) else { return }
        if ["placeMade", "overwrite"].contains(op.type), op.track?.hasPrefix("A") == true { return }
        // Sound on a track of its own (music, effects) still moves, trims and splits; check keeps the picture.
        if ["remove", "move", "slip", "trim", "split"].contains(op.type), let id = op.clipID, w.s.clips.first(where: { $0.id == id })?.kind == .audio { return }
        if ["placeGraphic", "title"].contains(op.type) { return }
        if ["move", "remove"].contains(op.type), let id = op.clipID, let clip = w.s.clips.first(where: { $0.id == id }), isGraphic(clip, graphics(w.project)) { return }
        throw DirectionError("picture_locked", "Picture is locked. After picture lock only color, sound and the graphics over the picture change; the director can unlock picture from the Film menu.")
    }

    /// The film's checked graphics, by asset id.
    static func graphics(_ p: Project) -> Set<String> { Set(p.assets.filter { $0.graphic != nil }.map(\.id)) }
    /// A graphic over the picture: a title or a checked graphic on V2 or above. It sits over the cut
    /// without changing it, so picture lock leaves it open.
    static func isGraphic(_ c: Clip, _ graphics: Set<String>) -> Bool { c.layer > 0 && (c.kind == .title || c.assetID.map(graphics.contains) ?? false) }

    static func check(before: Project, after: Project, si: Int, context: EditContext) throws {
        let b = before.sequences[si], a = after.sequences[si]
        // Picture lock locks every scene with it, and the graphics over them stay open there too.
        let graphicsOpen = context.state.pictureLocked
        if graphicsOpen {
            guard samePicture(b, a, graphics: graphics(before).union(graphics(after))) else { throw DirectionError("picture_locked", "Picture is locked. Finishing changes color, sound and the graphics over the picture, not the cut.") }
        }
        let locked = context.dailies.lockedAssetIDs
        guard !locked.isEmpty else { return }
        for span in spans(b, locked) {
            let label = context.dailies.scene(for: span.assetID)?.label ?? "That scene"
            let fail = DirectionError("scene_locked", "\(label) is locked. The director has to unlock it first.")
            // The scene's own clips: all still there, cut the same, moved together if at all.
            var shift: Double?
            for id in span.clipIDs {
                guard let old = b.clips.first(where: { $0.id == id }), let new = a.clips.first(where: { $0.id == id }) else { throw fail }
                guard cut(old) == cut(new) else { throw fail }
                let d = new.start.seconds - old.start.seconds
                if let shift { guard abs(shift - d) < 1e-6 else { throw fail } } else { shift = d }
            }
            let d = shift ?? 0
            guard signature(b, before, span.start, span.end, graphicsOpen: graphicsOpen) == signature(a, after, span.start + d, span.end + d, graphicsOpen: graphicsOpen) else { throw fail }
        }
    }

    /// The same picture: every clip that isn't sound cut, placed and treated the same, in the same frame.
    /// Clips of `graphics` over the picture are left out.
    static func samePicture(_ b: Sequence, _ a: Sequence, graphics: Set<String>? = nil) -> Bool {
        func timing(_ s: Sequence) -> [String] { s.clips.filter { c in c.kind != .audio && !(graphics.map { isGraphic(c, $0) } ?? false) }.map { c in "\(c.id)|\(c.assetID ?? "")|\(c.start.seconds)|\(c.sourceRange.start.seconds)|\(c.sourceRange.duration.seconds)|\(c.speed)|\(c.layer)|\(c.hold?.seconds ?? -1)|\(json(c.effects))|\(json(c.transition))|\(c.blend ?? "")|\(c.aboveLook ?? false)|\(json(c.framing))" }.sorted() }
        return timing(b) == timing(a) && b.width == a.width && b.height == a.height && b.frameRate == a.frameRate
    }

    struct Span { var start: Double; var end: Double; var clipIDs: [String]; var assetID: String? }
    static func spans(_ s: Sequence, _ locked: Set<String>) -> [Span] {
        var out: [Span] = []
        for c in s.clips.filter({ $0.layer == 0 && ($0.assetID.map(locked.contains) ?? false) }).sorted(by: { $0.start < $1.start }) {
            if let last = out.last, c.start.seconds <= last.end + 1e-6 { out[out.count - 1].end = max(last.end, c.end.seconds); out[out.count - 1].clipIDs.append(c.id) }
            else { out.append(.init(start: c.start.seconds, end: c.end.seconds, clipIDs: [c.id], assetID: c.assetID)) }
        }
        return out
    }

    /// A clip as the cut has it, wherever it sits: its color and sound left out, since locks keep them open.
    static func cut(_ c: Clip) -> Clip {
        var x = c
        x.start = .zero; x.grade = ColorGrade(); x.audioOverrides = [:]
        x.gainDB = nil; x.gainKeys = nil; x.duckKeys = nil; x.fadeIn = nil; x.fadeOut = nil; x.synced = nil
        return x
    }

    static func json<T: Encodable>(_ v: T) -> String { (try? JSONEncoder.direction.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
    static func r(_ x: Double) -> Double { (x * 10_000).rounded() / 10_000 }

    /// The cut inside [ws, we), relative to ws: every picture there, from where in which take, how it's
    /// framed and joined, where its sound starts and ends, and what reaches in from the cuts at either
    /// edge. Color and sound-only clips are left out; they stay open, as the graphics over the picture do
    /// when `graphicsOpen`.
    static func signature(_ s: Sequence, _ p: Project, _ ws: Double, _ we: Double, graphicsOpen: Bool = false) -> [String] {
        var rows: [String] = []
        let open = graphicsOpen ? graphics(p) : nil
        func cut(_ c: Clip, _ source: Double) -> Double { c.hold != nil ? c.start.seconds : c.start.seconds + (source - c.sourceRange.start.seconds) / c.speed }
        func src(_ c: Clip, _ t: Double) -> Double { c.hold != nil ? c.sourceRange.start.seconds : c.sourceRange.start.seconds + (t - c.start.seconds) * c.speed }
        func windowed(_ keys: [Keyframe]?, _ c: Clip?) -> [Double] {
            guard let keys, !keys.isEmpty else { return [] }
            let at = { (t: Double) in c.map { src($0, t) } ?? t }
            var out = [Keyframe.value(keys, at: at(ws)) ?? 0, Keyframe.value(keys, at: at(we)) ?? 0]
            for k in keys { let t = c.map { cut($0, k.t) } ?? k.t; if t >= ws - 1e-6 && t <= we + 1e-6 { out += [r(t - ws), k.v] } }
            return out.map(r)
        }
        for c in s.clips where c.kind != .audio && !(open.map { isGraphic(c, $0) } ?? false) {
            let snd = c.soundRange
            let lo = min(c.start.seconds, snd.start.seconds), hi = max(c.end.seconds, snd.end.seconds)
            var f: [String: String] = ["track": c.trackName]
            if lo < we - 1e-6 && hi > ws + 1e-6 {
                let o0 = max(lo, ws)
                f["asset"] = c.assetID ?? ""; f["title"] = c.title ?? ""; f["at"] = "\(r(o0 - ws))"; f["len"] = "\(r(min(hi, we) - o0))"; f["src"] = "\(r(src(c, o0)))"
                f["speed"] = "\(c.speed)"; f["hold"] = "\(c.hold?.seconds ?? 0)"; f["framing"] = json(c.framing)
                f["blend"] = c.blend ?? ""; f["above"] = "\(c.aboveLook ?? false)"
                f["fx"] = json((c.effects ?? []).map { [$0.name, json($0.params), json($0.source ?? ""), json(($0.keys ?? [:]).mapValues { windowed($0, c) })] })
                if c.start.seconds >= ws - 1e-6 { f["in"] = json(c.transition) + "|\(c.soundLead ?? 0)" }
                if c.end.seconds <= we + 1e-6 { f["out"] = "\(c.soundTail ?? 0)" }
            } else if abs(c.start.seconds - we) < 1e-6, (c.transition?.before ?? 0) > 0 || (c.soundLead ?? 0) > 0 {
                f["edgeIn"] = json(c.transition) + "|\(c.soundLead ?? 0)"
            } else if abs(c.end.seconds - ws) < 1e-6, (c.soundTail ?? 0) > 0 {
                f["edgeOut"] = "\(c.soundTail ?? 0)"
            } else { continue }
            rows.append(json(f))
        }
        for (name, t) in s.tracks ?? [:] where !t.isEmpty && name.hasPrefix("V") {
            rows.append(json(["track": name, "fx": json((t.effects ?? []).map { [$0.name, json($0.params), json(($0.keys ?? [:]).mapValues { windowed($0, nil) })] }), "above": "\(t.aboveLook ?? false)"]))
        }
        return rows.sorted()
    }
}

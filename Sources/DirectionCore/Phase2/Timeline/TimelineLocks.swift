import Foundation

/// Locks, checked one operation at a time so the error names it (agent-timeline.md › errors).
/// A locked scene is its stretch of V1 and everything over or under it on every track; it may move
/// whole when something before it changes length, but nothing in it may change. After picture lock
/// only color and sound change.
enum TimelineLocks {
    static let afterPictureLock: Set<String> = ["balance", "matchBalance", "cameraLUT", "color", "gain", "fade", "duck", "audio", "placeMusic"]

    static func gate(_ op: EditOperation, _ w: EditWork, _ c: EditContext) throws {
        guard c.state.pictureLocked, !afterPictureLock.contains(op.type) else { return }
        if op.type == "placeMade", op.track?.hasPrefix("A") == true { return }
        if op.type == "remove", let id = op.clipID, w.s.clips.first(where: { $0.id == id })?.kind == .audio { return }
        throw DirectionError("picture_locked", "Picture is locked. After picture lock only color and sound change; the director can unlock picture from the Film menu.")
    }

    static func check(before: Project, after: Project, si: Int, context: EditContext) throws {
        let b = before.sequences[si], a = after.sequences[si]
        if context.state.pictureLocked {
            func timing(_ s: Sequence) -> [String] { s.clips.filter { $0.kind != .audio }.map { c in "\(c.id)|\(c.assetID ?? "")|\(c.start.seconds)|\(c.sourceRange.start.seconds)|\(c.sourceRange.duration.seconds)|\(c.speed)|\(c.layer)|\(c.hold?.seconds ?? -1)|\(json(c.effects))|\(json(c.transition))|\(c.blend ?? "")|\(c.aboveLook ?? false)|\(json(c.framing))" }.sorted() }
            guard timing(b) == timing(a), b.width == a.width, b.height == a.height, b.frameRate == a.frameRate else { throw DirectionError("picture_locked", "Picture is locked. Finishing changes color and sound, not timing.") }
        }
        let locked = context.dailies.lockedAssetIDs
        guard !locked.isEmpty else { return }
        for span in spans(b, locked) {
            let label = context.dailies.scene(for: span.assetID)?.label ?? "That scene"
            let fail = DirectionError("scene_locked", "\(label) is locked. The director has to unlock it first.")
            // The scene's own clips: all still there, unchanged, moved together if at all.
            var shift: Double?
            for id in span.clipIDs {
                guard let old = b.clips.first(where: { $0.id == id }), let new = a.clips.first(where: { $0.id == id }) else { throw fail }
                var x = old, y = new; x.start = .zero; y.start = .zero
                guard x == y else { throw fail }
                let d = new.start.seconds - old.start.seconds
                if let shift { guard abs(shift - d) < 1e-6 else { throw fail } } else { shift = d }
            }
            let d = shift ?? 0
            guard signature(b, before, span.start, span.end) == signature(a, after, span.start + d, span.end + d) else { throw fail }
        }
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

    static func json<T: Encodable>(_ v: T) -> String { (try? JSONEncoder.direction.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
    static func r(_ x: Double) -> Double { (x * 10_000).rounded() / 10_000 }

    /// Everything that plays inside [ws, we), on every track, relative to ws: what's there, from where in
    /// which take, how it looks and sounds, and what reaches in from the cuts at either edge.
    static func signature(_ s: Sequence, _ p: Project, _ ws: Double, _ we: Double) -> [String] {
        var rows: [String] = []
        func cut(_ c: Clip, _ source: Double) -> Double { c.hold != nil ? c.start.seconds : c.start.seconds + (source - c.sourceRange.start.seconds) / c.speed }
        func src(_ c: Clip, _ t: Double) -> Double { c.hold != nil ? c.sourceRange.start.seconds : c.sourceRange.start.seconds + (t - c.start.seconds) * c.speed }
        func windowed(_ keys: [Keyframe]?, _ c: Clip?) -> [Double] {
            guard let keys, !keys.isEmpty else { return [] }
            let at = { (t: Double) in c.map { src($0, t) } ?? t }
            var out = [Keyframe.value(keys, at: at(ws)) ?? 0, Keyframe.value(keys, at: at(we)) ?? 0]
            for k in keys { let t = c.map { cut($0, k.t) } ?? k.t; if t >= ws - 1e-6 && t <= we + 1e-6 { out += [r(t - ws), k.v] } }
            return out.map(r)
        }
        for c in s.clips {
            let a = c.assetID.flatMap { id in p.assets.first { $0.id == id } }
            let snd = c.soundRange
            let lo = min(c.start.seconds, snd.start.seconds), hi = max(c.end.seconds, snd.end.seconds)
            var f: [String: String] = ["track": c.trackName]
            if lo < we - 1e-6 && hi > ws + 1e-6 {
                let o0 = max(lo, ws)
                f["asset"] = c.assetID ?? ""; f["title"] = c.title ?? ""; f["at"] = "\(r(o0 - ws))"; f["len"] = "\(r(min(hi, we) - o0))"; f["src"] = "\(r(src(c, o0)))"
                f["speed"] = "\(c.speed)"; f["hold"] = "\(c.hold?.seconds ?? 0)"; f["grade"] = json(c.grade); f["framing"] = json(c.framing); f["audio"] = json(c.audioOverrides)
                f["blend"] = c.blend ?? ""; f["above"] = "\(c.aboveLook ?? false)"; f["gain"] = "\(c.gainDB ?? 0)"
                f["fx"] = json((c.effects ?? []).map { [$0.name, json($0.params), json($0.source ?? ""), json(($0.keys ?? [:]).mapValues { windowed($0, c) })] })
                f["gainKeys"] = json(windowed(c.gainKeys, c)); f["duckKeys"] = json(windowed(c.duckKeys, c))
                if c.start.seconds >= ws - 1e-6 { f["in"] = json(c.transition) + "|\(c.fadeIn ?? 0)|\(c.soundLead ?? 0)" }
                if c.end.seconds <= we + 1e-6 { f["out"] = "\(c.fadeOut ?? 0)|\(c.soundTail ?? 0)" }
                if let a { f["lut"] = a.cameraLUT ?? ""; f["streams"] = json(a.audio.map(\.settings)) }
            } else if abs(c.start.seconds - we) < 1e-6, (c.transition?.before ?? 0) > 0 || (c.soundLead ?? 0) > 0 {
                f["edgeIn"] = json(c.transition) + "|\(c.soundLead ?? 0)"
            } else if abs(c.end.seconds - ws) < 1e-6, (c.soundTail ?? 0) > 0 {
                f["edgeOut"] = "\(c.soundTail ?? 0)"
            } else { continue }
            rows.append(json(f))
        }
        for (name, t) in s.tracks ?? [:] where !t.isEmpty {
            rows.append(json(["track": name, "fx": json((t.effects ?? []).map { [$0.name, json($0.params), json(($0.keys ?? [:]).mapValues { windowed($0, nil) })] }), "gain": "\(t.gainDB ?? 0)", "keys": json(windowed(t.gainKeys, nil)), "above": "\(t.aboveLook ?? false)"]))
        }
        return rows.sorted()
    }
}

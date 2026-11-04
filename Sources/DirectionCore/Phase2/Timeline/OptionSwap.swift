import Foundation

// Use A / Use B (cut.md › 30). The editor delivers two ways as two revisions that differ only where
// the note is. Using the other one swaps those shots wherever they sit in the cut now, so changes the
// editor made for other notes, before or after, stay as they are.

enum OptionSwap {
    struct Result: Sendable {
        var sequence: Sequence
        /// Where the swapped shots start in the cut, how long they ran and how long they run now.
        var at: MediaTime
        var removed: MediaTime
        var inserted: MediaTime
    }

    /// A shot on V1 and what starts over it (a cutaway, its own sound). A ripple moves them together.
    struct Unit {
        var story: Clip
        var over: [Clip] = []
        var clips: [Clip] { [story] + over }
    }

    static let moved = DirectionError("option_moved", "The cut changed around this note since, so the other version can\u{2019}t go in by itself. Reply to ask the editor for it.")

    /// `head` is the cut now, `from` the version of it that's playing, `to` the version to put in. nil when
    /// the two versions play the same.
    static func swap(_ head: Sequence, from: Sequence, to: Sequence) throws -> Result? {
        let beds = bedTracks(head, from, to)
        let uf = units(from, beds: beds), ut = units(to, beds: beds)
        let shots = window(uf, ut), bedsDiffer = plain(from, beds) != plain(to, beds)
        guard shots != nil || bedsDiffer else { return nil }
        let fb = shots.map { bounds(uf, $0.0) } ?? (.zero, .zero), tb = shots.map { bounds(ut, $0.1) } ?? (.zero, .zero)
        // Nothing else changed since: the picked version exactly as the editor cut it.
        if head.clips == from.clips && head.tracks == from.tracks {
            var s = head; s.clips = to.clips; s.tracks = to.tracks
            return Result(sequence: s, at: fb.start, removed: fb.end - fb.start, inserted: tb.end - tb.start)
        }
        var clips = head.clips, at = MediaTime.zero, removed = MediaTime.zero, inserted = MediaTime.zero
        if let (wf, wt) = shots {
            // Find the playing version's shots in the cut, nearest where they were.
            let uh = units(head, beds: beds), keys = uh.map(key), want = uf[wf].map(key), k = want.count
            guard uh.count >= k else { throw moved }
            let found = (0...(uh.count - k)).filter { Array(keys[$0..<($0 + k)]) == want }
            guard let i = found.min(by: { abs((uh[$0].story.start - fb.start).seconds) < abs((uh[$1].story.start - fb.start).seconds) }) else { throw moved }
            let hb = bounds(uh, i..<(i + k))
            at = hb.start; removed = hb.end - hb.start; inserted = tb.end - tb.start
            let gone = Set(uh[i..<(i + k)].flatMap(\.clips).map(\.id)), later = Set(uh[(i + k)...].flatMap(\.clips).map(\.id))
            clips = clips.filter { !gone.contains($0.id) }.map { c in
                var c = c
                if later.contains(c.id) { c.start = c.start + inserted - removed }
                return c
            }
            clips += ut[wt].flatMap(\.clips).map { c in var c = c; c.start = c.start + at - tb.start; return c }
        }
        // A bed stays where it is, as it does when the editor trims, unless the versions differ in it.
        if bedsDiffer {
            guard plain(head, beds) == plain(from, beds) else { throw moved }
            clips = clips.filter { !beds.contains($0.trackName) } + to.clips.filter { beds.contains($0.trackName) }
        }
        var seen = Set<String>()
        for i in clips.indices where !seen.insert(clips[i].id).inserted { clips[i].id = newID("clip"); clips[i].effects = EditReducer.reIDed(clips[i].effects) }
        var s = head; s.clips = clips
        // Track keys are in cut seconds: they move with the swap when that's all the versions differ by.
        if rounded(EditWork.spliced(from.tracks, Splice(at: fb.start.seconds, removed: (fb.end - fb.start).seconds, inserted: inserted.seconds))) == rounded(to.tracks) {
            s.tracks = EditWork.spliced(head.tracks, Splice(at: at.seconds, removed: removed.seconds, inserted: inserted.seconds))
        } else if head.tracks == from.tracks { s.tracks = to.tracks }
        else if from.tracks != to.tracks { throw moved }
        return Result(sequence: s, at: at, removed: removed, inserted: inserted)
    }

    /// Tracks with a clip across a cut on V1, like a music bed. They're compared whole, not shot by shot:
    /// a ripple that shortens a shot cuts the bed under it, and one that lengthens it doesn't.
    static func bedTracks(_ versions: Sequence...) -> Set<String> {
        var names = Set<String>()
        for s in versions {
            let cuts = Set(s.clips.filter { $0.trackName == "V1" }.flatMap { [$0.start.seconds, $0.end.seconds] })
            for c in s.clips where c.trackName != "V1" && cuts.contains(where: { $0 > c.start.seconds + 1e-3 && $0 < c.end.seconds - 1e-3 }) { names.insert(c.trackName) }
        }
        return names
    }

    static func units(_ s: Sequence, beds: Set<String> = []) -> [Unit] {
        var units = s.clips.filter { $0.trackName == "V1" }.sorted { $0.start < $1.start }.map { Unit(story: $0) }
        guard !units.isEmpty else { return [] }
        for c in s.clips where c.trackName != "V1" && !beds.contains(c.trackName) { units[units.lastIndex { $0.story.start <= c.start } ?? 0].over.append(c) }
        return units
    }

    /// The shots where two versions differ, in each. Never empty in `a`, so it can be found again in a cut
    /// that changed elsewhere: a version that only adds shots takes in the one before (or after).
    static func window(_ a: [Unit], _ b: [Unit]) -> (Range<Int>, Range<Int>)? {
        let ka = a.map(key), kb = b.map(key)
        var p = 0, q = 0
        while p < ka.count && p < kb.count && ka[p] == kb[p] { p += 1 }
        while q < ka.count - p && q < kb.count - p && ka[ka.count - 1 - q] == kb[kb.count - 1 - q] { q += 1 }
        var ra = p..<(ka.count - q), rb = p..<(kb.count - q)
        if ra.isEmpty && rb.isEmpty { return nil }
        if ra.isEmpty {
            if p > 0 { ra = (p - 1)..<ra.upperBound; rb = (p - 1)..<rb.upperBound }
            else if q > 0 { ra = ra.lowerBound..<(ra.upperBound + 1); rb = rb.lowerBound..<(rb.upperBound + 1) }
            else { return nil }
        }
        return (ra, rb)
    }

    /// Where a run of shots starts on V1, and where what follows it starts.
    static func bounds(_ u: [Unit], _ r: Range<Int>) -> (start: MediaTime, end: MediaTime) {
        let before = r.lowerBound > 0 ? u[r.lowerBound - 1].story.end : .zero
        let start = r.isEmpty ? (r.lowerBound < u.count ? u[r.lowerBound].story.start : before) : u[r.lowerBound].story.start
        let end = r.upperBound < u.count ? u[r.upperBound].story.start : r.isEmpty ? start : u[r.upperBound - 1].story.end
        return (start, end)
    }

    /// A shot as it plays, wherever it sits.
    static func key(_ u: Unit) -> [Clip] { plain(u.clips, origin: u.story.start) }
    /// The clips on some tracks as they play.
    static func plain(_ s: Sequence, _ tracks: Set<String>) -> [Clip] { plain(s.clips.filter { tracks.contains($0.trackName) }, origin: .zero) }
    /// Clips comparable across revisions: no ids, times from `origin`, to the millisecond.
    static func plain(_ clips: [Clip], origin: MediaTime) -> [Clip] {
        func ms(_ t: MediaTime) -> MediaTime { MediaTime(value: Int64((t.seconds * 1_000).rounded()), timescale: 1_000) }
        return clips.map { c in
            var p = c
            p.id = ""; p.lineageID = ""
            p.effects = c.effects?.map { var e = $0; e.id = ""; return e }
            p.start = ms(c.start - origin); p.sourceRange = .init(start: ms(c.sourceRange.start), duration: ms(c.sourceRange.duration)); p.hold = c.hold.map(ms)
            return p
        }.sorted { ($0.trackName, $0.start.seconds, $0.sourceRange.start.seconds, $0.assetID ?? "") < ($1.trackName, $1.start.seconds, $1.sourceRange.start.seconds, $1.assetID ?? "") }
    }

    static func rounded(_ tracks: [String: TrackSettings]?) -> [String: TrackSettings]? {
        func r(_ k: [Keyframe]) -> [Keyframe] { k.map { Keyframe(t: ($0.t * 1_000).rounded() / 1_000, v: $0.v, ease: $0.ease) } }
        return tracks?.mapValues { t in
            var t = t
            t.gainKeys = t.gainKeys.map(r); t.effects = t.effects?.map { e in var e = e; e.keys = e.keys?.mapValues(r); return e }
            return t
        }
    }
}

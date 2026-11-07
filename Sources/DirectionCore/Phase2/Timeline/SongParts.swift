import Foundation

// A song's parts on the timeline (agent-timeline.md › Songs in parts): a library song's stems and full mix, each
// on a sound track of its own. Wherever two of a song's parts play at once, they play the same moment of it.
// Moving or slipping one part moves or slips the stretch of the song it's in, fading one fades every part on
// that edge, `parts` says where each part is heard, and an edit that would put them out of time is refused.

extension EditWork {
    /// The song a clip plays a part of.
    func song(of c: Clip) -> String? {
        guard c.kind == .audio, c.hold == nil, let song = assetOf(c)?.song, !song.isEmpty else { return nil }
        return song
    }
    /// Where the song's beginning falls in the cut: the same for every part playing the same moment of it.
    func songStart(_ c: Clip) -> Double { c.start.seconds - c.sourceRange.start.seconds / c.speed }
    func partName(_ c: Clip) -> String { assetOf(c)?.part ?? c.name }
    /// The film's parts of a song.
    func parts(of song: String) -> [MediaAsset] { project.assets.filter { $0.song == song } }

    /// The clips playing one stretch of a song with the clip at `i`: its parts at the same moment of the song,
    /// overlapping or touching one another.
    func stretch(of i: Int) -> [Int] {
        let c = s.clips[i]
        guard let g = song(of: c) else { return [i] }
        let o = songStart(c)
        let same = s.clips.indices.filter { k in song(of: s.clips[k]) == g && abs(songStart(s.clips[k]) - o) < 1e-4 && s.clips[k].speed == c.speed }
        var found: Set<Int> = [i], grew = true
        while grew {
            grew = false
            for k in same where !found.contains(k) {
                let x = s.clips[k]
                if found.contains(where: { j in x.start.seconds <= s.clips[j].end.seconds + frame / 2 && x.end.seconds >= s.clips[j].start.seconds - frame / 2 }) { found.insert(k); grew = true }
            }
        }
        return found.sorted()
    }

    /// Wherever two of a song's parts play at once, they play the same moment of it.
    func checkSongs() throws {
        let clips = s.clips.filter { song(of: $0) != nil }
        guard clips.count > 1 else { return }
        for (x, a) in clips.enumerated() {
            for b in clips[(x + 1)...] where song(of: a) == song(of: b) {
                let lo = max(a.start.seconds, b.start.seconds), hi = min(a.end.seconds, b.end.seconds)
                guard hi - lo > 1e-6, abs(songStart(a) - songStart(b)) > 1e-4 || a.speed != b.speed else { continue }
                throw DirectionError("not_in_sync", "That would put \(song(of: a)!)\u{2019}s \(partName(a)) out of time with its \(partName(b)) at \(tc(lo))\u{2013}\(tc(hi)). A song\u{2019}s parts move and slip together (move or slip any of them), and parts says where each is heard.")
            }
        }
    }

    /// A part of the film's copy of a song, by what it is ("Drums") or its name.
    func part(_ name: String, of song: String) throws -> MediaAsset {
        let all = parts(of: song), n = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard let p = all.first(where: { ($0.part ?? "").lowercased() == n || $0.name.lowercased() == n || ($0.name as NSString).deletingPathExtension.lowercased() == n }) else {
            throw bad("\(song) has no part called \(name); it has \(all.compactMap(\.part).joined(separator: ", ")). direction_import with library \"\(song)\" brings every part in.")
        }
        return p
    }

    /// `parts`: where each named part of a song is heard, in the stretch of it the clip is in. Each stretch is
    /// cut seconds; [] takes the part out. A part comes in and goes out over `frames` (2 by default) where the
    /// song plays on, so it doesn't click; on the song's own edges it keeps the fade it had.
    mutating func partsOp(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard let g = song(of: c) else { throw bad("\(label(c)) isn\u{2019}t a song in parts. parts takes a clip of a library song placed with placeMusic.") }
        guard c.speed == 1 else { throw bad("\(label(c)) plays at another speed; place \(g) again with placeMusic.") }
        guard let heard = op.heard, !heard.isEmpty else { throw bad("heard is {part: [{start, end}]}: where each part plays, in cut seconds; [] for nowhere.") }
        if let n = op.frames { guard n >= 0 else { throw bad("frames is how long a part takes to come in and go out, 0 or more.") } }
        let ramp = secs(op.frames ?? 2)
        let shift = c.start - c.sourceRange.start, o = shift.seconds
        let before = stretch(of: i).map { s.clips[$0] }
        let ducking = Array(Set(before.flatMap { $0.duckKeys ?? [] })).sorted { $0.t < $1.t }
        var done: [String] = [], changes: [LocalChange] = [], made: [String] = []
        var kept = Set(before.map(\.id))
        let named = try heard.map { (asset: try part($0.key, of: g), name: $0.key, stretches: $0.value) }.sorted { (Stems.rank($0.asset.part), $0.name) < (Stems.rank($1.asset.part), $1.name) }
        for (p, name, stretches) in named {
            let lo = max(0, o), hi = o + p.duration.seconds
            var spans: [(Double, Double)] = []
            for (k, r) in stretches.enumerated() {
                let a = snap(r.start).seconds, b = snap(r.end).seconds
                guard b > a else { throw bad("heard.\(name)[\(k)] needs a start and a later end.") }
                guard a >= lo - frame / 2, b <= hi + frame / 2 else { throw bad("Here \(g) plays from \(tc(lo)) to \(tc(hi)); \(p.part ?? name) can only be heard in that.") }
                spans.append((max(a, lo), min(b, hi)))
            }
            // Stretches that meet are one.
            var merged: [(Double, Double)] = []
            for sp in spans.sorted(by: { $0.0 < $1.0 }) { if let last = merged.last, sp.0 <= last.1 + 1e-6 { merged[merged.count - 1].1 = max(last.1, sp.1) } else { merged.append(sp) } }
            // Out with where it played, keeping how it was set.
            let old = s.clips.filter { kept.contains($0.id) && $0.assetID == p.id }
            let template = old.first
            for x in old { changes.append(.init(before: (x.start.seconds, x.end.seconds), after: (x.start.seconds, x.end.seconds), tracks: [x.trackName])) }
            s.clips.removeAll { x in old.contains { $0.id == x.id } }
            kept.subtract(old.map(\.id))
            // On its own track: where it was, or the first free one the song's other parts aren't on.
            let others = Set(s.clips.filter { kept.contains($0.id) }.map(\.layer))
            func fits(_ l: Int) -> Bool { merged.allSatisfy { free((true, l), MediaRange(start: $0.0, end: $0.1)) } }
            var layer = template?.layer ?? 1
            if !fits(layer) || (template == nil && others.contains(layer)) {
                layer = 1
                while (others.contains(layer) || !fits(layer)) && layer < 1_000 { layer += 1 }
            }
            for sp in merged {
                let start = snap(MediaTime(seconds: sp.0)), end = snap(MediaTime(seconds: sp.1))
                var piece = Clip(assetID: p.id, name: p.name, kind: .audio, layer: layer, start: start, sourceRange: .init(start: start - shift, duration: end - start))
                if piece.sourceRange.end > p.duration { piece.sourceRange.duration = p.duration - piece.sourceRange.start }
                if let t = template { piece.gainDB = t.gainDB; piece.gainKeys = t.gainKeys; piece.effects = EditReducer.reIDed(t.effects) }
                piece.duckKeys = ducking.isEmpty ? nil : ducking
                // On an edge it had, it keeps how its sound met the next (a fitted song's join, under a frame).
                let head = old.first { abs($0.start.seconds - piece.start.seconds) < frame / 2 }, tail = old.first { abs($0.end.seconds - piece.end.seconds) < frame / 2 }
                piece.fadeIn = head?.fadeIn; piece.soundLead = head?.soundLead; piece.joined = head?.joined
                piece.fadeOut = tail?.fadeOut; piece.soundTail = tail?.soundTail
                s.clips.append(piece); kept.insert(piece.id); made.append(piece.id)
                changes.append(.init(before: (sp.0, sp.1), after: (sp.0, sp.1), tracks: [piece.trackName]))
            }
            done.append(merged.isEmpty ? "\(p.part ?? name) out" : "\(p.part ?? name) " + merged.map { "\(tc($0.0))\u{2013}\(tc($0.1))" }.joined(separator: ", "))
        }
        // Where a part comes in or goes out while the song plays on, it ramps.
        let now = s.clips.filter { kept.contains($0.id) }
        if ramp > 0, let first = now.map(\.start.seconds).min(), let last = now.map(\.end.seconds).max() {
            for k in s.clips.indices where made.contains(s.clips[k].id) {
                let x = s.clips[k], room = x.duration.seconds / 2
                if x.start.seconds > first + frame / 2 { s.clips[k].fadeIn = min(ramp, room) }
                if x.end.seconds < last - frame / 2 { s.clips[k].fadeOut = min(ramp, room) }
            }
        }
        return .init(summary: "\(g): " + done.joined(separator: "; "), changes: changes, clipIDs: made)
    }

    /// The clips a sound edit on one part of a song takes in: every part in its stretch of the song.
    func withSong(_ i: Int) -> [Int] { song(of: s.clips[i]) == nil ? [i] : stretch(of: i) }
    /// "Neon Drive", for a summary of an edit that took a song's parts with it; the clip's own label otherwise.
    func songLabel(_ c: Clip, _ count: Int) -> String { count > 1 ? song(of: c)! : label(c) }
}

import Foundation
import DirectionCore
import DirectionMedia

// Where to cut (agent-timeline.md › Cut points): blinks, peaks of action and pauses, measured by Direction so the
// editor chooses a cut point by judgment instead of guessing a time, and split, trim and roll can snap to one.
extension ToolCatalog {
    static var cutPointDefinitions: [ToolDefinition] { [
        definition("direction_cut_points", "Where to cut, measured, so you choose a cut point instead of guessing a time: blinks (the eyes most closed; a cut on the outgoing person\u{2019}s blink reads as a natural break), peaks of action (the picture moving fastest; a cut inside a movement hides itself) and pauses between words (from the transcript). Give clipID with at for the points near a moment of a clip, clipID alone for those near its head and tail (for a trim), range for every shot of the story over a stretch, at alone for the shot under it, or assetID with sourceRange for a take before it\u{2019}s in the cut. Each point has t (cut seconds; with assetID, the take\u{2019}s), kind, strength 0\u{2013}1, who (left, middle, right) when more than one face is seen, from and to for a pause, and outside: true when it\u{2019}s in the take beyond the clip, where a trim can reach. Blinks are found only on a face turned to the camera and near enough to see its eyes; says tells you when there\u{2019}s none. Measured on this Mac the first time a stretch is asked for (a few seconds per 20 s of footage), then kept. split, trim and roll in direction_edit take snap: blink, action or pause, and land on the nearest one within 8 frames.", [
            "clipID": noted(string, "A clip in the cut (direction_timeline): its points near at, or near its head and tail without at."),
            "at": noted(number, "Cut seconds: the points near this moment, on clipID or the story\u{2019}s shot under it."),
            "range": noted(record(["start": number, "end": number], required: ["start", "end"]), "{start, end} in cut seconds: the points inside it, on every shot of the story."),
            "assetID": noted(string, "A take (direction_dailies): its points over sourceRange."),
            "sourceRange": noted(record(["start": number, "end": number], required: ["start", "end"]), "With assetID: {start, end} in the take\u{2019}s seconds, 5 minutes at most."),
            "within": noted(number, "Seconds either side of at, or of a clip\u{2019}s head and tail: 1 unless given, at most 10."),
            "kinds": noted(list(strings(["blink", "action", "pause"])), "Only these kinds; all three unless given."),
        ]),
    ] }
}

extension ToolRuntime {
    func invokeCutPoints(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        guard name == "direction_cut_points" else { return nil }
        let kinds = Set(a["kinds"].array?.compactMap(\.string) ?? ["blink", "action", "pause"])
        guard !kinds.isEmpty else { throw DirectionError("bad_argument", "kinds names at least one of blink, action and pause.") }
        let within = min(10, max(0.04, a["within"].double ?? 1))
        let p = try store.read(), s = try p.sequence(nil)
        let names = takeNames(p)
        func asset(_ id: String?) -> MediaAsset? { id.flatMap { id in p.assets.first { $0.id == id } } }
        func label(_ a: MediaAsset) -> String { names[a.id] ?? (a.name as NSString).deletingPathExtension }

        // A take before it's in the cut: its own seconds.
        if let id = a["assetID"].string {
            guard let take = asset(id) else { throw DirectionError("asset_not_found", "There\u{2019}s no take \(id). direction_dailies lists them.") }
            let from = a["sourceRange"]["start"].double ?? 0, to = a["sourceRange"]["end"].double ?? take.duration.seconds
            guard to > from else { throw DirectionError("bad_argument", "sourceRange is {start, end} in the take\u{2019}s seconds, end after start.") }
            try limit(to - from)
            let found = try await cutPoints(take, from: from, to: to, kinds: kinds, name: label(take))
            let points = found.points.map { $0.json(cut: { $0 }, outside: nil) }
            var value: [String: JSONValue] = ["take": .string(label(take)), "points": .array(Array(points.prefix(80))), "says": .string(found.says(kinds, found.points.map(\.kind), where: "over \(cutSeconds(from))\u{2013}\(cutSeconds(to)) of \(label(take))"))]
            if points.count > 80 { value["more"] = .number(Double(points.count - 80)) }
            return ToolResponse(.object(value))
        }

        // Shots in the cut: a clip, the shot under at, or every shot of the story over range.
        let story = s.storyLayer
        let shots = s.clips.filter { $0.kind == .video && $0.layer == story && $0.hold == nil && asset($0.assetID).map { !$0.video.isEmpty && !$0.isImage && $0.graphic == nil } == true }.sorted { $0.start < $1.start }
        var asked: [(clip: Clip, windows: [(Double, Double)], inside: Bool)] = []
        var place: String
        if let r = a["range"] != .null ? (a["range"]["start"].double, a["range"]["end"].double) : nil {
            guard let start = r.0, let end = r.1, end > start else { throw DirectionError("bad_argument", "range is {start, end} in cut seconds.") }
            for c in shots where c.start.seconds < end && c.end.seconds > start {
                asked.append((c, [(max(start, c.start.seconds), min(end, c.end.seconds))], true))
            }
            place = "over \(cutSeconds(start))\u{2013}\(cutSeconds(end))"
            guard !asked.isEmpty else { throw DirectionError("bad_argument", "There\u{2019}s no shot of a take on the story over \(cutSeconds(start))\u{2013}\(cutSeconds(end)).") }
        } else {
            let clip: Clip
            if let id = a["clipID"].string {
                guard let c = s.clips.first(where: { $0.id == id }) else { throw DirectionError("clip_not_found", "There\u{2019}s no clip \(id) in the cut. direction_timeline lists them.") }
                guard c.hold == nil, asset(c.assetID).map({ !$0.video.isEmpty && !$0.isImage && $0.graphic == nil }) == true else { throw DirectionError("bad_argument", "\(id) isn\u{2019}t a shot of a take: cut points are in the footage.") }
                clip = c
            } else if let t = a["at"].double {
                guard let c = shots.first(where: { $0.start.seconds <= t + 1e-6 && t < $0.end.seconds }) else { throw DirectionError("bad_argument", "There\u{2019}s no shot of a take on the story at \(cutSeconds(t)).") }
                clip = c
            } else { throw DirectionError("bad_argument", "Give clipID, at, range, or assetID with sourceRange.") }
            if let t = a["at"].double {
                asked.append((clip, [(t - within, t + within)], false))
                place = "near \(cutSeconds(t))"
            } else {
                asked.append((clip, [(clip.start.seconds - within, clip.start.seconds + within), (clip.end.seconds - within, clip.end.seconds + within)], false))
                place = "near the head and tail of \(asset(clip.assetID).map(label) ?? clip.name)"
            }
        }
        // Cut seconds to the take's and back, beyond the clip too, where a trim reaches.
        func source(_ c: Clip, _ t: Double) -> Double { c.sourceRange.start.seconds + (t - c.start.seconds) * c.speed }
        func cut(_ c: Clip, _ t: Double) -> Double { c.start.seconds + (t - c.sourceRange.start.seconds) / c.speed }
        try limit(asked.reduce(0) { sum, x in sum + x.windows.reduce(0) { $0 + ($1.1 - $1.0) * x.clip.speed } })
        var points: [(t: Double, value: JSONValue)] = [], all = Found()
        for (c, windows, inside) in asked {
            guard let take = asset(c.assetID) else { continue }
            for (lo, hi) in windows {
                let found = try await cutPoints(take, from: source(c, lo), to: source(c, hi), kinds: kinds, name: label(take))
                all.add(found)
                for point in found.points {
                    let t = cut(c, point.t), out = !c.sourceRange.contains(MediaTime(seconds: point.t))
                    if inside && out { continue }
                    var value = point.json(cut: { cut(c, $0) }, outside: out)
                    if asked.count > 1, case .object(var o) = value { o["clipID"] = .string(c.id); value = .object(o) }
                    if !points.contains(where: { abs($0.t - t) < 1e-3 && $0.value["kind"] == value["kind"] }) { points.append((t, value)) }
                }
            }
        }
        if let at = a["at"].double { points.sort { abs($0.t - at) < abs($1.t - at) } } else { points.sort { $0.t < $1.t } }
        let shown = Array(points.prefix(80))
        var value: [String: JSONValue] = ["points": .array(shown.map(\.value)), "says": .string(all.says(kinds, points.compactMap { $0.value["kind"].string }, where: place))]
        if asked.count == 1 { value["clipID"] = .string(asked[0].clip.id); value["take"] = .string(asset(asked[0].clip.assetID).map(label) ?? asked[0].clip.name) }
        if points.count > shown.count { value["more"] = .number(Double(points.count - shown.count)) }
        return ToolResponse(.object(value))
    }

    private func limit(_ seconds: Double) throws {
        guard seconds <= 300 else { throw DirectionError("bad_argument", "Ask for 5 minutes of footage or less at a time (sourceRange with assetID, or a shorter range); this asks for \(Int((seconds / 60).rounded(.up))) minutes.") }
    }

    /// Takes by the names Dailies gives them ("2A Take 3").
    func takeNames(_ p: Project) -> [String: String] {
        let dailies = (try? store.dailies()) ?? Dailies()
        return Dictionary(FootageNames.all(dailies, assets: p.assets).filter { $0.kind == .take }.compactMap { n in n.assetID.map { ($0, n.name) } }, uniquingKeysWith: { a, _ in a })
    }

    /// What was found over a stretch of a take, in the take's seconds.
    struct Found {
        struct Point { var t: Double; var kind: String; var strength: Double; var who: String?; var from: Double?; var to: Double?; var end: Double? }
        var points: [Point] = []
        var faceSeconds = 0.0, askedBlinks = false, words = true, take = ""
        mutating func add(_ other: Found) { faceSeconds += other.faceSeconds; askedBlinks = askedBlinks || other.askedBlinks; words = words && other.words; if take.isEmpty { take = other.take } }

        /// A line on what was found (`found`, the kinds of the points shown), and why a kind asked for has none.
        func says(_ kinds: Set<String>, _ found: [String], where place: String) -> String {
            let n = { (kind: String) in found.filter { $0 == kind }.count }
            func many(_ k: Int, _ one: String, _ several: String) -> String { "\(k) \(k == 1 ? one : several)" }
            var parts: [String] = []
            if kinds.contains("blink") { parts.append(many(n("blink"), "blink", "blinks")) }
            if kinds.contains("action") { parts.append(many(n("action"), "peak of action", "peaks of action")) }
            if kinds.contains("pause") { parts.append(many(n("pause"), "pause", "pauses")) }
            var text = (parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.joined()) + " " + place + "."
            if kinds.contains("blink") && n("blink") == 0 && faceSeconds < 0.5 { text += " No face there is turned to the camera and near enough to see its eyes, so there are no blinks to cut on." }
            if kinds.contains("pause") && n("pause") == 0 && !words { text += " \(take.isEmpty ? "The take" : take) has no transcript, so no pauses: direction_transcribe makes one." }
            return text
        }
    }

    /// The cut points of one stretch of a take (take seconds), sorted by time.
    func cutPoints(_ take: MediaAsset, from: Double, to: Double, kinds: Set<String>, name: String) async throws -> Found {
        var found = Found()
        found.take = name
        if kinds.contains("blink") || kinds.contains("action") {
            let m = try await CutPoints.measure(take, from: from, to: to, cacheDirectory: cacheDirectory)
            found.faceSeconds = m.faceSeconds; found.askedBlinks = kinds.contains("blink")
            func who(_ x: Double) -> String? { m.faces > 1 ? (x < 0.4 ? "left" : x > 0.6 ? "right" : "middle") : nil }
            if kinds.contains("blink") { found.points += m.blinks.map { .init(t: $0.t, kind: "blink", strength: $0.depth, who: who($0.x), end: $0.end) } }
            if kinds.contains("action") { found.points += m.actions.map { .init(t: $0.t, kind: "action", strength: $0.strength) } }
        }
        if kinds.contains("pause") {
            let words = TranscriptEditing.sourceWords(take.id, try store.transcripts())
            found.words = !words.isEmpty
            found.points += CutPoints.pauses(words, from: from, to: to).filter { $0.middle >= from && $0.middle <= to }.map { p in
                .init(t: p.middle, kind: "pause", strength: min(1, (p.end - p.start) / 0.8 + (p.afterSentence ? 0.2 : 0)), from: p.start, to: p.end)
            }
        }
        found.points.sort { $0.t < $1.t }
        return found
    }

    // MARK: Snapping an edit to one

    /// split, trim and roll with snap: the cut point moved to the nearest blink, peak of action or pause within 8
    /// frames, worked out on the cut as the operations before leave it, and said in the operation's result.
    func resolveSnap(_ op: inout EditOperation, _ p: Project, _ s: DirectionCore.Sequence) async throws {
        guard let kind = op.snap else { return }
        let frame = 1 / s.frameRate.value, reach = 8 * frame
        let names = takeNames(p)
        func clip(_ id: String?) -> Clip? { id.flatMap { id in s.clips.first { $0.id == id } } }
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in p.assets.first { $0.id == id } }.flatMap { $0.video.isEmpty || $0.isImage || $0.graphic != nil ? nil : $0 } }
        func label(_ c: Clip) -> String { c.assetID.flatMap { names[$0] } ?? (c.name as NSString).deletingPathExtension }
        func source(_ c: Clip, _ t: Double) -> Double { c.sourceRange.start.seconds + (t - c.start.seconds) * c.speed }
        func cut(_ c: Clip, _ t: Double) -> Double { c.start.seconds + (t - c.sourceRange.start.seconds) / c.speed }
        let noun = ["blink": "blink", "action": "peak of action", "pause": "pause"][kind] ?? kind
        enum Role { case head, tail, middle }
        /// Where in the take a point puts the cut: a blink's most closed frame (its end, eyes open again, for a
        /// head), a peak of action, or the nearest moment of a pause that's 3 frames clear of the words either side
        /// (a cut already in a pause stays where it is).
        func candidates(_ c: Clip, around t: Double, role: Role) async throws -> (times: [Double], found: Found)? {
            guard let a = asset(c), c.hold == nil else { return nil }
            let r = reach * c.speed
            let found = try await cutPoints(a, from: t - r - 0.6, to: t + r + 0.6, kinds: [kind], name: label(c))
            var times: [Double] = []
            for point in found.points {
                switch (point.kind, role) {
                case ("blink", .head): times.append(point.end ?? point.t)
                case ("pause", _):
                    guard let from = point.from, let to = point.to else { continue }
                    let margin = min(3 * frame * c.speed, (to - from) / 2)
                    times.append(min(max(t, from + margin), to - margin))
                default: times.append(point.t)
                }
            }
            return (times.filter { abs($0 - t) <= r + 1e-6 }.sorted { abs($0 - t) < abs($1 - t) }, found)
        }
        func none(_ found: Found?, _ who: String) -> String {
            var text = "No \(noun) within 8 frames in \(who), so the cut is where you asked."
            if kind == "blink", (found?.faceSeconds ?? 0) < 0.5 { text += " No face there is turned to the camera near enough to see its eyes." }
            if kind == "pause", found?.words == false { text += " \(who) has no transcript: direction_transcribe makes one." }
            return text
        }
        var said: String?
        switch op.type {
        case "split":
            guard let c = clip(op.clipID), let at = op.at?.seconds, let got = try await candidates(c, around: source(c, at), role: .middle) else { return }
            let (times, found) = got
            if let best = times.map({ cut(c, $0) }).first(where: { $0 > c.start.seconds + frame / 2 && $0 < c.end.seconds - frame / 2 }) {
                let moved = Int(((best - at) / frame).rounded())
                op.at = MediaTime(seconds: best)
                said = moved == 0 ? "The split is on a \(noun) already." : "Snapped the split to a \(noun) in \(label(c)) at \(cutSeconds(best)), \(abs(moved)) frame\(abs(moved) == 1 ? "" : "s") \(moved > 0 ? "later" : "earlier") than asked."
            } else { said = none(found, label(c)) }
        case "trim":
            guard let c = clip(op.clipID), let n = op.frames, n != 0, let edge = op.edge, edge == "head" || edge == "tail" else { return }
            let step = frame * c.speed, tail = edge == "tail"
            let now = tail ? c.sourceRange.end.seconds : c.sourceRange.start.seconds
            let target = tail ? now + Double(n) * step : now - Double(n) * step
            guard let got = try await candidates(c, around: target, role: tail ? .tail : .head) else { return }
            let (times, found) = got
            let options = times.map { t in Int(((tail ? t - now : now - t) / step).rounded()) }.filter { $0 != 0 && ($0 > 0) == (n > 0) }
            if let best = options.first {
                op.frames = best
                said = best == n ? "The \(edge) lands on a \(noun) already." : "Snapped \(label(c))\u{2019}s \(edge) to a \(noun): \(best > 0 ? "extended" : "trimmed") \(abs(best)) frame\(abs(best) == 1 ? "" : "s"), not \(abs(n))."
            } else { said = none(found, label(c)) }
        case "roll":
            guard let point = op.editPoint, let bar = point.firstIndex(of: "|"), let l = clip(String(point[..<bar])), let r = clip(String(point[point.index(after: bar)...])), let n = op.frames, n != 0 else { return }
            let at = r.start.seconds, target = at + Double(n) * frame
            // The outgoing shot's points first: a cut on its blink or its action; then the incoming one's.
            var options: [Int] = [], found: Found?
            for c in [l, r] {
                guard let got = try await candidates(c, around: source(c, target), role: .middle) else { continue }
                let times = got.times
                found = found ?? got.found
                options += times.map { Int(((cut(c, $0) - at) / frame).rounded()) }.filter { $0 != 0 && ($0 > 0) == (n > 0) }
            }
            if let best = options.min(by: { abs($0 - n) < abs($1 - n) }) {
                op.frames = best
                said = best == n ? "The cut lands on a \(noun) already." : "Snapped the cut to a \(noun): rolled \(abs(best)) frame\(abs(best) == 1 ? "" : "s") \(best > 0 ? "later" : "earlier"), not \(abs(n))."
            } else { said = none(found, "\(label(l)) or \(label(r))") }
        default: return
        }
        guard let said else { return }
        var resolved = op.resolved ?? ResolvedValues()
        resolved.warnings = (resolved.warnings ?? []) + [said]
        op.resolved = resolved
    }
}

/// Seconds as the editor reads them.
func cutSeconds(_ t: Double) -> String { String(format: "%.2f s", t) }

extension ToolRuntime.Found.Point {
    /// As the tool shows it: times in cut seconds (or the take's).
    func json(cut: (Double) -> Double, outside: Bool?) -> JSONValue {
        func r3(_ v: Double) -> JSONValue { .number((v * 1000).rounded() / 1000) }
        var o: [String: JSONValue] = ["t": r3(cut(t)), "kind": .string(kind), "strength": .number((strength * 100).rounded() / 100)]
        if let who { o["who"] = .string(who) }
        if let from { o["from"] = r3(cut(from)) }
        if let to { o["to"] = r3(cut(to)) }
        if outside == true { o["outside"] = .bool(true) }
        return .object(o)
    }
}

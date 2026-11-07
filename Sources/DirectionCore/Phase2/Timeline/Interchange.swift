import Foundation

/// The cut as other editing apps read it (issue #4): FCPXML 1.10, which Final Cut Pro and DaVinci Resolve open.
/// Export only, nothing comes back, and the director still never sees a timeline: it's how a colorist, a mixer
/// or an editor who finishes elsewhere picks the cut up.
///
/// What another app draws the same way goes across as itself: takes, made shots and graphics' renders at the
/// same frames, speed, reframes, opacity, crops, dissolves on V1, sound with its level, keys and fades, scenes
/// and notes as markers. What only Direction draws (titles, freezes, masks, blurs, layouts' cards, pins,
/// shaders, Direction's own transitions and dips) is rendered by Direction over that stretch, everything up
/// to that layer at once, and goes in on V1 in place of those pieces, so nothing is lost. Their sound stays.
public enum Interchange {
    // MARK: Time

    /// An exact time, as FCPXML writes it ("1001/30000s").
    public struct Rational: Hashable, Comparable, Sendable, CustomStringConvertible {
        public var n: Int64, d: Int64
        public init(_ n: Int64, _ d: Int64) {
            let g = Self.gcd(abs(n), abs(d))
            self.n = (d < 0 ? -n : n) / g; self.d = abs(d) / g
        }
        static func gcd(_ a: Int64, _ b: Int64) -> Int64 { var a = a, b = b; while b != 0 { (a, b) = (b, a % b) }; return max(1, a) }
        public static let zero = Rational(0, 1)
        public static func + (l: Self, r: Self) -> Self { let g = gcd(l.d, r.d); return Self(l.n * (r.d / g) + r.n * (l.d / g), l.d / g * r.d) }
        public static func - (l: Self, r: Self) -> Self { l + Self(-r.n, r.d) }
        public static func < (l: Self, r: Self) -> Bool { (l - r).n < 0 }
        public var seconds: Double { Double(n) / Double(d) }
        public var description: String { d == 1 ? "\(n)s" : "\(n)/\(d)s" }
        /// Whole frames at `rate` nearest `seconds`.
        public static func frames(_ seconds: Double, _ rate: FrameRate) -> Int64 { Int64((seconds * Double(rate.numerator) / Double(rate.denominator)).rounded()) }
        public static func of(frames: Int64, _ rate: FrameRate) -> Rational { Rational(frames * Int64(rate.denominator), Int64(rate.numerator)) }
        /// `seconds` on `rate`'s frame grid.
        public static func on(_ seconds: Double, _ rate: FrameRate) -> Rational { of(frames: frames(seconds, rate), rate) }
        /// The frame showing at `seconds`: the one at or before it, as a player shows it.
        public static func showing(_ seconds: Double, _ rate: FrameRate) -> Rational { of(frames: Int64((seconds * Double(rate.numerator) / Double(rate.denominator) + 1e-4).rounded(.down)), rate) }
        /// Whole frames that hold all of `seconds`.
        public static func covering(_ seconds: Double, _ rate: FrameRate) -> Rational { of(frames: Int64((seconds * Double(rate.numerator) / Double(rate.denominator) - 1e-4).rounded(.up)), rate) }
    }

    // MARK: Plan

    /// A stretch of the cut another app can't draw, rendered by Direction: every picture layer up to `upToLayer`
    /// from `start` to `end` (cut seconds, on whole frames), without the look.
    public struct Render: Hashable, Sendable {
        public var id: String
        public var start: Double
        public var end: Double
        public var upToLayer: Int
        /// What's in it that needed rendering, in plain words: "a title", "a blur and a mask".
        public var reasons: [String]
        /// The file's name: "03 Title 0-12-04".
        public var name: String
    }

    /// What goes across: renders to make, and what the read-me says didn't.
    public struct Plan: Sendable {
        public var renders: [Render]
        public var notes: [String]
    }

    /// One piece of the timeline: a clip, or part of one where a render covers the rest, or a render.
    struct Piece {
        var clip: Clip
        var picture: Bool
        var sound: Bool
        var render: Render?
        /// A dissolve into this piece that goes across as a transition.
        var dissolve: ClipTransition?
        /// Which lanes it goes in: "V1", "V2"… for picture; "A1", "A2"…, "V2 sound"… for sound on its own.
        var group: String
        var order: Int
    }

    static let blendModes = ["normal": 0, "screen": 10, "multiply": 4, "overlay": 14, "add": 8]

    /// Why a picture clip has to be rendered, in plain words; empty when it goes across as itself.
    static func reasons(_ c: Clip, in s: Sequence) -> [String] {
        guard c.kind != .audio else { return [] }
        var out: [String] = []
        if c.kind == .title { out.append("a title") }
        if c.hold != nil { out.append("a freeze") }
        if let b = c.blend, blendModes[b] == nil { out.append("a \(b) blend") }
        for e in c.effects ?? [] {
            switch e.name {
            case "transform":
                if ["crop.l", "crop.r", "crop.t", "crop.b"].contains(where: { e.keys?[$0] != nil }) { out.append("a moving crop") }
            case "mask": out.append("a mask")
            case "blur": out.append("a blur")
            case "sharpen": break // finishing, like the look's filters: the read-me lists it
            case "stabilize": out.append("steadying")
            case "pin": out.append("a picture pinned in perspective")
            case "place", "card": out.append("a framed picture")
            case "backdrop": out.append("a blurred backdrop")
            case "shader": out.append("a shader")
            case "pixelGrid": out.append("a pixel grid")
            case let n where n.hasPrefix("filter."): break // a look filter: the read-me lists it
            default: out.append(e.name)
            }
        }
        if let t = s.tracks?[c.trackName]?.effects, t.contains(where: { !isFinishing($0) }) { out.append("\(c.trackName)\u{2019}s effects") }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// A look filter or sharpening: finishing a colorist does in their own app, so it's listed, not rendered.
    static func isFinishing(_ e: ClipEffect) -> Bool { e.name.hasPrefix("filter.") || e.name == "sharpen" }
    static func finishingLabel(_ e: ClipEffect) -> String {
        e.name == "sharpen" ? "sharpening" : LookFilter(rawValue: String(e.name.dropFirst(7)))?.label.lowercased() ?? String(e.name.dropFirst(7))
    }

    /// A transition that goes across as a Cross Dissolve: a dissolve on V1 with something before it.
    static func portable(_ t: ClipTransition, _ c: Clip, story: Int) -> Bool { t.type == "dissolve" && c.layer == story && c.kind != .audio && c.start.seconds > 1e-6 }

    public static func audible(_ c: Clip, _ asset: MediaAsset?) -> Bool {
        guard c.hold == nil, c.kind != .title, let a = asset, !a.audio.isEmpty, !a.isImage else { return false }
        return a.audio.contains { !(c.audioOverrides[String($0.id)] ?? $0.settings).muted }
    }

    /// What needs rendering, and what won't go across.
    public static func plan(project: Project, sequence s: Sequence, looks: LookContext? = nil, dailies: Dailies = .init()) -> Plan {
        func take(_ c: Clip) -> String? { c.assetID.flatMap { dailies.takes[$0] }.flatMap { t in t.code.map { [t.setupCode, $0].compactMap { $0 }.joined(separator: " ") } } }
        let rate = s.frameRate
        func frameAligned(_ t: Double) -> Double { Rational.on(t, rate).seconds }
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in project.assets.first { $0.id == id } } }
        let picture = s.clips.filter { $0.kind != .audio }
        let story = picture.map(\.layer).min() ?? 0
        var wanted: [Render] = []
        for c in picture {
            let why = reasons(c, in: s)
            if !why.isEmpty { wanted.append(Render(id: "", start: c.start.seconds, end: c.end.seconds, upToLayer: c.layer, reasons: why, name: "")) }
            if let t = c.transition, !portable(t, c, story: story) {
                let kind = t.type == "dissolve" ? "a dissolve" : t.isDip ? (t.type == "dipToWhite" ? "a dip to white" : "a dip to black") : "a \(t.type == "shader" ? (t.file.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "shader") : t.type) transition"
                wanted.append(Render(id: "", start: max(0, c.start.seconds - t.before), end: min(s.duration.seconds, c.start.seconds + t.after), upToLayer: c.layer, reasons: [kind], name: ""))
            }
        }
        // Stretches that overlap or meet become one; one that cuts a dissolve kept on V1 in half takes the whole dissolve.
        var merged: [Render] = []
        var changed = true
        var list = wanted.map { r in var r = r; r.start = frameAligned(r.start); r.end = frameAligned(r.end); return r }.filter { $0.end > $0.start }
        while changed {
            changed = false
            merged = []
            for r in list.sorted(by: { $0.start < $1.start }) {
                if let last = merged.last, r.start <= last.end + 1e-9 {
                    merged[merged.count - 1].end = max(last.end, r.end); merged[merged.count - 1].upToLayer = max(last.upToLayer, r.upToLayer)
                    merged[merged.count - 1].reasons += r.reasons.filter { !last.reasons.contains($0) }
                    changed = true
                } else { merged.append(r) }
            }
            for i in merged.indices {
                for c in picture where c.layer <= merged[i].upToLayer {
                    guard let t = c.transition, portable(t, c, story: story) else { continue }
                    let a = c.start.seconds - t.before, b = c.start.seconds + t.after
                    if a < merged[i].end - 1e-9 && b > merged[i].start + 1e-9 && (a < merged[i].start - 1e-9 || b > merged[i].end + 1e-9) {
                        merged[i].start = min(merged[i].start, frameAligned(a)); merged[i].end = max(merged[i].end, frameAligned(b)); changed = true
                    }
                }
            }
            list = merged
        }
        let renders = merged.enumerated().map { k, r in
            var r = r
            r.id = "render-\(k + 1)"
            let first = r.reasons.first.map { $0.split(separator: " ").dropFirst().joined(separator: " ").capitalizedFirst } ?? "Render"
            r.name = String(format: "%02d ", k + 1) + first + " " + CutTimecode.string(r.start, rate: rate.value).replacingOccurrences(of: ":", with: "-")
            return r
        }

        // What doesn't go across, for the read-me.
        var notes: [String] = []
        /// Wholly inside a render, which has everything it does.
        func rendered(_ c: Clip) -> Bool { renders.contains { r in c.layer <= r.upToLayer && c.start.seconds >= r.start - 1e-9 && c.end.seconds <= r.end + 1e-9 } }
        let balanced = s.clips.filter { c in c.kind == .video && c.grade != ColorGrade() && !rendered(c) }
        if !balanced.isEmpty { notes.append("\(balanced.count == 1 ? "One shot has" : "\(balanced.count) shots have") Direction\u{2019}s balance (exposure, contrast, color) in the cut. The timeline has the shots as they were shot" + (renders.isEmpty ? "." : "; the renders have it.")) }
        let processed = Set(s.clips.compactMap { c -> String? in
            guard let a = asset(c) else { return nil }
            return a.audio.contains { (c.audioOverrides[String($0.id)] ?? $0.settings).effects.isActive } ? (c.kind == .audio ? c.trackName : "A1") : nil
        })
        if !processed.isEmpty { notes.append("Some sound on \(processed.sorted().joined(separator: " and ")) has Direction\u{2019}s EQ, compressor or limiter. The sound stems have it; the timeline\u{2019}s clips don\u{2019}t.") }
        let partlyMuted = s.clips.filter { c in
            guard c.kind != .title, let a = asset(c), a.audio.count > 1 else { return false }
            let muted = a.audio.filter { (c.audioOverrides[String($0.id)] ?? $0.settings).muted }.count
            return muted > 0 && muted < a.audio.count
        }
        if !partlyMuted.isEmpty { notes.append("\(partlyMuted.count == 1 ? "One clip plays" : "\(partlyMuted.count) clips play") only some of its sound tracks in the cut; the timeline brings all of them. The sound stems have it as the cut plays it.") }
        // Several sound tracks in one clip at different levels or fades: the timeline gives them all the first one's.
        let uneven = s.clips.filter { c in
            guard c.kind != .title, let a = asset(c) else { return false }
            let playing = a.audio.map { c.audioOverrides[String($0.id)] ?? $0.settings }.filter { !$0.muted }
            return Set(playing.map { [$0.gainDB, $0.fadeIn, $0.fadeOut] }).count > 1
        }
        if !uneven.isEmpty { notes.append("\(uneven.count == 1 ? "One clip has" : "\(uneven.count) clips have") sound tracks at different levels; the timeline sets them all to the first one\u{2019}s. The sound stems have them as the cut plays them.") }
        let ducked = (s.tracks ?? [:]).filter { $0.value.ducked != nil }.map(\.key).sorted()
        if !ducked.isEmpty { notes.append("Ducking on \(listed(ducked)) is in each clip\u{2019}s volume keys.") }
        if let film = looks?.look.film, !film.isNone, !film.active.isEmpty {
            notes.append("The look also has \(listed(film.active.map { $0.filter.label.lowercased() })), which the LUT doesn\u{2019}t carry.")
        }
        for (name, t) in (s.tracks ?? [:]).sorted(by: { $0.key < $1.key }) {
            let finishing = (t.effects ?? []).filter(isFinishing)
            let on = s.clips.filter { $0.trackName == name }
            if !finishing.isEmpty, !on.isEmpty { notes.append("\(name) has \(listed(finishing.map(finishingLabel))) over all of it" + (on.contains(where: rendered) ? ", except in the renders, which already have it." : ".")) }
        }
        var byFilter: [String: [String]] = [:]
        for c in s.clips.sorted(by: { $0.start < $1.start }) where !rendered(c) { for e in (c.effects ?? []).filter(isFinishing) { byFilter[finishingLabel(e), default: []].append(take(c) ?? c.name) } }
        for (label, shots) in byFilter.sorted(by: { $0.key < $1.key }) {
            notes.append("\(shots.count == 1 ? "One shot has" : "\(shots.count) shots have") \(label) (\(listed(Array(Set(shots)).sorted()))).")
        }
        return Plan(renders: renders, notes: notes)
    }

    // MARK: Pieces

    /// The cut as pieces: clips, the parts of clips no render covers, the renders, and sound on its own where
    /// the picture was split or plays a J- or L-cut.
    static func pieces(project: Project, sequence s: Sequence, renders: [Render]) -> [Piece] {
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in project.assets.first { $0.id == id } } }
        var out: [Piece] = []
        var order = 0
        let story = s.clips.filter { $0.kind != .audio }.map(\.layer).min() ?? 0
        func add(_ p: Piece) { var p = p; p.order = order; order += 1; out.append(p) }
        /// A clip's sound as the renderer plays it: a J-cut starts no earlier than the cut or the file does, and an
        /// L-cut ends where the file does.
        func fitted(_ c: Clip) -> Clip {
            var c = c
            if let lead = c.soundLead, lead > 0 { c.soundLead = min(lead, c.start.seconds, c.sourceRange.start.seconds / c.speed) }
            if let tail = c.soundTail, tail > 0, let a = asset(c) { c.soundTail = max(0, min(tail, (a.duration.seconds - c.sourceRange.end.seconds) / c.speed)) }
            return c
        }
        for c in s.clips.sorted(by: { ($0.layer, $0.start.seconds, $0.id) < ($1.layer, $1.start.seconds, $1.id) }) {
            // Sound the cut doesn't play (every stream muted) doesn't go across to play there.
            if c.kind == .audio { if audible(c, asset(c)) { add(Piece(clip: fitted(c), picture: false, sound: true, render: nil, dissolve: nil, group: c.trackName, order: 0)) }; continue }
            // The parts of the clip outside every render that takes its layer.
            var parts: [(Double, Double)] = [(c.start.seconds, c.end.seconds)]
            for r in renders where c.layer <= r.upToLayer {
                parts = parts.flatMap { p -> [(Double, Double)] in
                    guard r.start < p.1 - 1e-9 && r.end > p.0 + 1e-9 else { return [p] }
                    return [(p.0, r.start), (r.end, p.1)].filter { $0.1 - $0.0 > 1e-9 }
                }
            }
            let whole = parts.count == 1 && abs(parts[0].0 - c.start.seconds) < 1e-9 && abs(parts[0].1 - c.end.seconds) < 1e-9
            let hasSound = audible(c, asset(c)) && (c.layer == 0 || c.kind == .video)
            let split = (c.soundLead ?? 0) != 0 || (c.soundTail ?? 0) != 0
            // A dissolve in Final Cut crossfades the sound under it too, where Direction cuts the sound at the edit:
            // the sound of a shot on either side of one goes on its own.
            let dissolveIn = c.transition.map { portable($0, c, story: story) } ?? false
            let dissolveOut = s.clips.contains { $0.layer == c.layer && $0.kind != .audio && abs($0.start.seconds - c.end.seconds) < 1e-6 && ($0.transition.map { [d = $0] t in portable(t, d, story: story) } ?? false) }
            let soundAlong = hasSound && whole && !split && !dissolveIn && !dissolveOut
            for p in parts {
                var piece = c
                piece.start = .init(seconds: p.0)
                if c.hold == nil { piece.sourceRange = .init(start: c.sourceTime(at: .init(seconds: p.0)), duration: MediaTime(seconds: (p.1 - p.0) * c.speed)) }
                let keepsCut = abs(p.0 - c.start.seconds) < 1e-9
                let dissolve = keepsCut ? c.transition.flatMap { portable($0, c, story: story) ? $0 : nil } : nil
                add(Piece(clip: piece, picture: true, sound: soundAlong, render: nil, dissolve: dissolve, group: "V\(c.layer + 1)", order: 0))
            }
            if hasSound && !soundAlong {
                add(Piece(clip: fitted(c), picture: false, sound: true, render: nil, dissolve: nil, group: c.layer == 0 ? "A1" : "V\(c.layer + 1) sound", order: 0))
            }
        }
        for r in renders {
            var c = Clip(id: r.id, assetID: nil, name: r.name, kind: .video, layer: story, start: .init(seconds: r.start), sourceRange: .init(start: .zero, duration: .init(seconds: r.end - r.start)))
            c.lineageID = r.id
            add(Piece(clip: c, picture: true, sound: false, render: r, dissolve: nil, group: "V\(story + 1)", order: 0))
        }
        return out
    }

    // MARK: FCPXML

    /// What Direction read from a file for the timeline that the film doesn't keep: where its timecode starts.
    public struct SourceFacts: Sendable, Hashable {
        public var timecodeStart: Double
        public init(timecodeStart: Double = 0) { self.timecodeStart = timecodeStart }
    }

    public struct Input: Sendable {
        public var project: Project
        public var sequence: Sequence
        public var filmName: String
        public var cutName: String
        public var dailies: Dailies
        public var notes: [ReviewComment]
        public var plan: Plan
        /// Render id → the file Direction rendered it to.
        public var rendered: [String: URL]
        /// Asset id → what was read from the file.
        public var sources: [String: SourceFacts]
        public init(project: Project, sequence: Sequence, filmName: String, cutName: String, dailies: Dailies = .init(), notes: [ReviewComment] = [], plan: Plan, rendered: [String: URL], sources: [String: SourceFacts] = [:]) {
            self.project = project; self.sequence = sequence; self.filmName = filmName; self.cutName = cutName; self.dailies = dailies; self.notes = notes; self.plan = plan; self.rendered = rendered; self.sources = sources
        }
    }

    /// Final Cut Pro's Cross Dissolve.
    static let crossDissolveUID = "FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265"

    public static func fcpxml(_ input: Input) throws -> String {
        let p = input.project, s = input.sequence, rate = s.frameRate
        guard s.duration > .zero else { throw DirectionError("empty_sequence", "There\u{2019}s nothing in this cut to export.") }
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in p.assets.first { $0.id == id } } }
        func frames(_ t: Double) -> Int64 { Rational.frames(t, rate) }
        func time(_ f: Int64) -> Rational { Rational.of(frames: f, rate) }
        let total = frames(s.duration.seconds)

        // Resources: the cut's format, each file's, and the effects used.
        let resources = XMLElement(name: "resources")
        var nextID = 1
        func rid() -> String { defer { nextID += 1 }; return "r\(nextID)" }
        var formats: [String: String] = [:]
        func format(width: Int, height: Int, rate: FrameRate?) -> String {
            let key = "\(width)x\(height)@\(rate.map { "\($0.numerator)/\($0.denominator)" } ?? "still")"
            if let id = formats[key] { return id }
            let id = rid(); formats[key] = id
            var attrs: [(String, String)] = [("id", id)]
            if let rate { attrs.append(("frameDuration", Rational(Int64(rate.denominator), Int64(rate.numerator)).description)) } else { attrs.append(("name", "FFVideoFormatRateUndefined")) }
            attrs += [("width", "\(width)"), ("height", "\(height)"), ("colorSpace", "1-1-1 (Rec. 709)")]
            resources.addChild(element("format", attrs))
            return id
        }
        let sequenceFormat = format(width: s.width, height: s.height, rate: rate)

        /// A file in the timeline: its id, format, frame grid and where its own time starts.
        struct Source { var id: String; var format: String?; var grid: FrameRate; var start: Rational; var duration: Rational; var hasVideo: Bool; var hasAudio: Bool; var still: Bool }
        var sources: [String: Source] = [:]
        func source(path: String, key: String, name: String, a: MediaAsset?, renderDuration: Double? = nil) -> Source {
            if let known = sources[key] { return known }
            let id = rid()
            let video = a?.video.first, still = a?.isImage == true
            let grid = renderDuration != nil || still ? rate : video.flatMap { $0.frameRate > 1 ? FrameRate.nearest($0.frameRate) : nil } ?? rate
            let hasVideo = renderDuration != nil || video != nil || still
            let fmt: String? = renderDuration != nil ? sequenceFormat : still ? format(width: video?.width ?? s.width, height: video?.height ?? s.height, rate: nil) : video.map { format(width: $0.width, height: $0.height, rate: grid) }
            let start = still ? Rational.zero : Rational.on(input.sources[a?.id ?? ""]?.timecodeStart ?? 0, grid)
            let duration = still ? Rational.zero : Rational.covering(renderDuration ?? a?.duration.seconds ?? 0, grid)
            var attrs: [(String, String)] = [("id", id), ("name", name), ("start", start.description), ("duration", duration.description), ("hasVideo", hasVideo ? "1" : "0")]
            if let fmt { attrs.append(("format", fmt)) }
            if hasVideo { attrs.append(("videoSources", "1")) }
            let audio = renderDuration == nil && !still ? a?.audio ?? [] : []
            attrs.append(("hasAudio", audio.isEmpty ? "0" : "1"))
            if let first = audio.first {
                attrs += [("audioSources", "\(audio.count)"), ("audioChannels", "\(max(1, first.channels))"), ("audioRate", "\(Int(first.sampleRate.rounded()))")]
            }
            let e = element("asset", attrs)
            e.addChild(element("media-rep", [("kind", "original-media"), ("src", URL(fileURLWithPath: path).standardizedFileURL.absoluteString)]))
            resources.addChild(e)
            let made = Source(id: id, format: fmt, grid: grid, start: start, duration: duration, hasVideo: hasVideo, hasAudio: !audio.isEmpty, still: still)
            sources[key] = made
            return made
        }
        var dissolveEffect: String?
        func crossDissolve() -> String {
            if let dissolveEffect { return dissolveEffect }
            let id = rid(); dissolveEffect = id
            resources.addChild(element("effect", [("id", id), ("name", "Cross Dissolve"), ("uid", crossDissolveUID)]))
            return id
        }

        func soundRange(_ piece: Piece) -> (start: Double, end: Double) {
            piece.picture ? (piece.clip.start.seconds, piece.clip.end.seconds) : (piece.clip.soundRange.start.seconds, piece.clip.soundRange.end.seconds)
        }

        // MARK: One clip
        func clipElement(_ piece: Piece, offset: Rational, duration: Rational, lane: Int?) throws -> (XMLElement, Rational) {
            let c = piece.clip
            if let r = piece.render {
                guard let url = input.rendered[r.id] else { throw DirectionError("render_missing", "The render for \(r.name) is missing.") }
                let src = source(path: url.path, key: "render:" + r.id, name: r.name, a: nil, renderDuration: r.end - r.start)
                var attrs = [("ref", src.id), ("offset", offset.description), ("name", r.name), ("start", "0s"), ("duration", duration.description), ("format", sequenceFormat), ("tcFormat", "NDF")]
                if let lane { attrs.insert(("lane", "\(lane)"), at: 1) }
                return (element("asset-clip", attrs), .zero)
            }
            guard let a = asset(c) else { throw DirectionError("missing_asset", "Missing source for \(c.name).") }
            let src = source(path: a.path, key: a.id, name: a.name, a: a)
            let speed = c.speed
            // Where this piece starts in the file's own time, and in the clip's time after any change of speed.
            let sourceStart = piece.picture ? c.sourceRange.start.seconds : c.sourceRange.start.seconds - (c.soundLead ?? 0) * speed
            let fileTime = src.start + (piece.picture ? Rational.showing(max(0, sourceStart), src.grid) : Rational.on(max(0, sourceStart), src.grid))
            // A slowed clip's own time is on whole frames after the change of speed, not before it.
            let local = speed == 1 ? fileTime : Rational.on((src.start.seconds + max(0, sourceStart)) / speed, src.grid)
            func localTime(source t: Double) -> Rational { speed == 1 || src.still ? src.start + Rational.on(t, src.grid) : Rational.on((src.start.seconds + t) / speed, src.grid) }
            func localTime(cut t: Double) -> Rational { localTime(source: c.sourceRange.start.seconds + (t - c.start.seconds) * speed) }
            let name = take(c) ?? c.title ?? a.graphic ?? c.name
            var attrs: [(String, String)] = []
            if let lane { attrs.append(("lane", "\(lane)")) }
            attrs += [("offset", offset.description), ("name", name), ("start", local.description), ("duration", duration.description)]
            let e: XMLElement
            if src.still {
                e = element("video", [("ref", src.id)] + attrs)
            } else {
                e = element("asset-clip", [("ref", src.id)] + attrs)
                if let f = src.format { e.addAttribute(attribute("format", f)) }
                e.addAttribute(attribute("tcFormat", "NDF"))
                if piece.picture && !piece.sound && src.hasAudio { e.addAttribute(attribute("srcEnable", "video")) }
                if !piece.picture && src.hasVideo { e.addAttribute(attribute("srcEnable", "audio")) }
                if piece.sound { e.addAttribute(attribute("audioRole", role(piece))) }
            }
            if speed != 1 && !src.still {
                let map = XMLElement(name: "timeMap")
                let length = src.start + src.duration
                map.addChild(element("timept", [("time", "0s"), ("value", "0s"), ("interp", "linear")]))
                map.addChild(element("timept", [("time", Rational.on(length.seconds / speed, src.grid).description), ("value", length.description), ("interp", "linear")]))
                e.addChild(map)
            }
            if piece.picture { for x in picture(c, a, localTime: { localTime(source: $0) }) { e.addChild(x) } }
            if piece.sound, !src.still, let v = volume(piece, a, localTime: { localTime(cut: $0) }) { e.addChild(v) }
            return (e, local)
        }

        func take(_ c: Clip) -> String? { c.assetID.flatMap { input.dailies.takes[$0] }.flatMap { t in t.code.map { [t.setupCode, $0].compactMap { $0 }.joined(separator: " ") } } }
        /// Final Cut's roles: music for songs and A2, effects for the rest of A3 and up, dialogue for voices and takes.
        func role(_ piece: Piece) -> String {
            guard piece.clip.kind == .audio, piece.group != "A1" else { return "dialogue" }
            return asset(piece.clip)?.song != nil || piece.group == "A2" ? "music" : "effects"
        }

        /// Crop, fit or fill, transform and opacity, with keys, in the DTD's order.
        func picture(_ c: Clip, _ a: MediaAsset, localTime: (Double) -> Rational) -> [XMLElement] {
            var out: [XMLElement] = []
            let tr = c.effect("transform") ?? c.effects?.first { $0.name == "transform" }
            let f = c.framing
            let w = Double(a.video.first?.width ?? s.width), h = Double(a.video.first?.height ?? s.height)
            let cl = tr?.number("crop.l", at: nil, default: 0) ?? 0, cr = tr?.number("crop.r", at: nil, default: 0) ?? 0
            let ct = tr?.number("crop.t", at: nil, default: 0) ?? 0, cb = tr?.number("crop.b", at: nil, default: 0) ?? 0
            if cl + cr + ct + cb > 0 {
                let crop = element("adjust-crop", [("mode", "trim")])
                func pct(_ v: Double, _ side: Double) -> String { number(v * side / h * 100) }
                crop.addChild(element("trim-rect", [("left", pct(cl, w)), ("top", pct(ct, h)), ("right", pct(cr, w)), ("bottom", pct(cb, h))]))
                out.append(crop)
            }
            if !f.fit { out.append(element("adjust-conform", [("type", "fill")])) }
            // Direction moves by a share of the frame's width and height, down and clockwise; FCPXML by a
            // share of its height, up and counterclockwise.
            func position(_ t: Double?) -> String { number((f.offsetX + (tr?.number("x", at: t, default: 0) ?? 0)) * Double(s.width) / Double(s.height) * 100) + " " + number(-(f.offsetY + (tr?.number("y", at: t, default: 0) ?? 0)) * 100) }
            func scale(_ t: Double?) -> String { let v = number(f.scale * (tr?.number("scale", at: t, default: 1) ?? 1)); return "\(v) \(v)" }
            func rotation(_ t: Double?) -> String { number(-(tr?.number("rotation", at: t, default: 0) ?? 0)) }
            func opacity(_ t: Double?) -> String { number(f.opacity * (tr?.number("opacity", at: t, default: 1) ?? 1)) }
            let keys = tr?.keys ?? [:]
            let moved = position(nil) != "0 0" || scale(nil) != "1 1" || rotation(nil) != "0" || ["x", "y", "scale", "rotation"].contains { keys[$0] != nil }
            if moved {
                let t = element("adjust-transform", [("position", position(nil)), ("scale", scale(nil)), ("rotation", rotation(nil))])
                for (name, params, value) in [("position", ["x", "y"], position), ("scale", ["scale"], scale), ("rotation", ["rotation"], rotation)] as [(String, [String], (Double?) -> String)] {
                    let times = Set(params.flatMap { keyTimes(keys[$0] ?? [], frame: c.speed / rate.value) }).sorted()
                    guard !times.isEmpty else { continue }
                    t.addChild(param(name, times.map { (localTime($0), value($0)) }))
                }
                out.append(t)
            }
            let mode = c.blend.flatMap { blendModes[$0] } ?? 0
            if opacity(nil) != "1" || keys["opacity"] != nil || mode != 0 {
                var attrs = [("amount", opacity(nil))]
                if mode != 0 { attrs.append(("mode", "\(mode)")) }
                let b = element("adjust-blend", attrs)
                if let k = keys["opacity"], !k.isEmpty { b.addChild(param("amount", keyTimes(k, frame: c.speed / rate.value).map { (localTime($0), opacity($0)) })) }
                out.append(b)
            }
            return out
        }

        /// The clip's level as the cut plays it: the stream's, the clip's, its keys and ducking, the track's and
        /// the mix's, with its fades.
        func volume(_ piece: Piece, _ a: MediaAsset, localTime: (Double) -> Rational) -> XMLElement? {
            let c = piece.clip
            let stream = a.audio.first { !(c.audioOverrides[String($0.id)] ?? $0.settings).muted }.map { c.audioOverrides[String($0.id)] ?? $0.settings } ?? AudioSettings()
            let track = s.tracks?[c.kind == .audio ? c.trackName : c.layer == 0 ? "A1" : "-"]
            let from = soundRange(piece).start, to = soundRange(piece).end
            func sourceTime(_ t: Double) -> Double { c.sourceRange.start.seconds + (t - c.start.seconds) * c.speed }
            func cutTime(_ src: Double) -> Double { c.start.seconds + (src - c.sourceRange.start.seconds) / c.speed }
            func dB(_ t: Double) -> Double {
                stream.gainDB + (c.gainDB ?? 0) + (c.gainKeys.flatMap { Keyframe.value($0, at: sourceTime(t)) } ?? 0) + (c.duckKeys.flatMap { Keyframe.value($0, at: sourceTime(t)) } ?? 0)
                    + (track?.gainDB ?? 0) + (track?.gainKeys.flatMap { Keyframe.value($0, at: t) } ?? 0) + (s.mixGainDB ?? 0)
            }
            var times = Set<Double>()
            for list in [c.gainKeys ?? [], c.duckKeys ?? []] { for t in keyTimes(list, frame: c.speed / rate.value) { times.insert(cutTime(t)) } }
            for t in keyTimes(track?.gainKeys ?? [], frame: 1 / rate.value) { times.insert(t) }
            let inside = times.filter { $0 > from + 1e-6 && $0 < to - 1e-6 }.sorted()
            let fadeIn = min(max(c.fadeIn ?? 0, stream.fadeIn), (to - from) / 2), fadeOut = min(max(c.fadeOut ?? 0, stream.fadeOut), (to - from) / 2)
            let level = dB(from)
            guard !inside.isEmpty || abs(level) > 0.005 || fadeIn > 0 || fadeOut > 0 else { return nil }
            let v = element("adjust-volume", [("amount", decibels(level))])
            if !inside.isEmpty || fadeIn > 0 || fadeOut > 0 {
                let pm = element("param", [("name", "amount")])
                if fadeIn > 0 { pm.addChild(element("fadeIn", [("type", "linear"), ("duration", Rational.on(fadeIn, rate).description)])) }
                if fadeOut > 0 { pm.addChild(element("fadeOut", [("type", "linear"), ("duration", Rational.on(fadeOut, rate).description)])) }
                if !inside.isEmpty {
                    let anim = XMLElement(name: "keyframeAnimation")
                    for t in [from] + inside + [to] { anim.addChild(element("keyframe", [("time", localTime(t).description), ("value", decibels(dB(t)))])) }
                    pm.addChild(anim)
                }
                v.addChild(pm)
            }
            return v
        }

        /// Straight lines between keys, as Direction draws them (holds and eases are keyed in by keyTimes).
        func param(_ name: String, _ points: [(Rational, String)]) -> XMLElement {
            let pm = element("param", [("name", name)])
            let anim = XMLElement(name: "keyframeAnimation")
            for (t, v) in points { anim.addChild(element("keyframe", [("time", t.description), ("value", v), ("interp", "linear"), ("curve", "linear")])) }
            pm.addChild(anim)
            return pm
        }


        // The pieces, in lanes: V1's first lane is the spine; every other lane is anchored to it.
        let pieces = Self.pieces(project: p, sequence: s, renders: input.plan.renders).filter { frames($0.clip.end.seconds) > frames($0.clip.start.seconds) || $0.render != nil }
        func lanes(_ items: [Piece]) -> [[Piece]] {
            var out: [[Piece]] = []
            for it in items.sorted(by: { (frames($0.clip.start.seconds), $0.order) < (frames($1.clip.start.seconds), $1.order) }) {
                let a = frames(soundRange(it).start), b = frames(soundRange(it).end)
                if let k = out.firstIndex(where: { lane in lane.allSatisfy { frames(soundRange($0).end) <= a || frames(soundRange($0).start) >= b } }) { out[k].append(it) } else { out.append([it]) }
                out = out.map { $0.sorted { frames(soundRange($0).start) < frames(soundRange($1).start) } }
            }
            return out
        }
        // Picture composites as Direction draws it: every layer under the look, bottom up, then the layers above
        // the look (graphics, by default), bottom up, over all of them.
        func overLook(_ piece: Piece) -> Bool { piece.render == nil && (piece.clip.aboveLook ?? s.tracks?[piece.clip.trackName]?.aboveLook ?? false) }
        let pictureGroups = Set(pieces.filter(\.picture).map { Pair(overLook($0), $0.clip.layer) }).sorted { ($0.a ? 1 : 0, $0.b) < ($1.a ? 1 : 0, $1.b) }
        var spine: [Piece] = []
        var above: [[Piece]] = []
        for group in pictureGroups {
            let ls = lanes(pieces.filter { $0.picture && Pair(overLook($0), $0.clip.layer) == group })
            for (k, lane) in ls.enumerated() { if group == pictureGroups.first && k == 0 { spine = lane } else { above.append(lane) } }
        }
        // Sound on its own, A1 first, then music and effects, then the sound of shots above V1.
        func soundOrder(_ g: String) -> (Int, Int) { g.hasPrefix("A") ? (0, Int(g.dropFirst()) ?? 0) : (1, Int(g.dropFirst().prefix { $0.isNumber }) ?? 0) }
        var below: [(group: String, lane: [Piece])] = []
        for g in Set(pieces.filter { !$0.picture }.map(\.group)).sorted(by: { soundOrder($0) < soundOrder($1) }) {
            for lane in lanes(pieces.filter { !$0.picture && $0.group == g }) { below.append((g, lane)) }
        }

        // The spine: V1 with gaps, to the end of the cut.
        struct Slot { var offset: Int64; var duration: Int64; var local: Rational; var element: XMLElement }
        var slots: [Slot] = []
        let spineElement = XMLElement(name: "spine")
        var cursor: Int64 = 0
        func gap(_ length: Int64) {
            guard length > 0 else { return }
            let g = element("gap", [("name", "Gap"), ("offset", time(cursor).description), ("start", "0s"), ("duration", time(length).description)])
            spineElement.addChild(g); slots.append(Slot(offset: cursor, duration: length, local: .zero, element: g)); cursor += length
        }
        var clipElements: [String: (element: XMLElement, local: Rational, offset: Int64)] = [:]
        for piece in spine {
            let a = frames(piece.clip.start.seconds), b = frames(piece.clip.end.seconds)
            guard b > a else { continue }
            if a > cursor { gap(a - cursor) }
            if let t = piece.dissolve, !slots.isEmpty {
                let before = min(frames(t.before), slots.last!.duration), after = min(frames(t.after), b - a)
                if before + after > 0 {
                    let tr = element("transition", [("name", "Cross Dissolve"), ("offset", time(a - before).description), ("duration", time(before + after).description)])
                    tr.addChild(element("filter-video", [("ref", crossDissolve()), ("name", "Cross Dissolve")]))
                    spineElement.addChild(tr)
                }
            }
            let (e, local) = try clipElement(piece, offset: time(a), duration: time(b - a), lane: nil)
            spineElement.addChild(e); slots.append(Slot(offset: a, duration: b - a, local: local, element: e)); cursor = b
            clipElements[piece.clip.id] = (e, local, a)
        }
        let end = max(total, (above.flatMap { $0 } + below.flatMap(\.lane)).map { frames(soundRange($0).end) }.max() ?? 0)
        if end > cursor { gap(end - cursor) }

        /// The spine element at a frame (the last one past the end), and that frame in its own time.
        func anchor(_ f: Int64) -> (element: XMLElement, at: Rational) {
            let slot = slots.first { f >= $0.offset && f < $0.offset + $0.duration } ?? (f < 0 ? slots.first! : slots.last!)
            return (slot.element, slot.local + time(f - slot.offset))
        }
        var anchored: [(XMLElement, XMLElement)] = []
        for (k, lane) in above.enumerated() {
            for piece in lane {
                let a = frames(piece.clip.start.seconds), b = frames(piece.clip.end.seconds)
                guard b > a else { continue }
                let parent = anchor(a)
                let (e, _) = try clipElement(piece, offset: parent.at, duration: time(b - a), lane: k + 1)
                anchored.append((parent.element, e))
            }
        }
        for (k, entry) in below.enumerated() {
            for piece in entry.lane {
                let a = frames(soundRange(piece).start), b = frames(soundRange(piece).end)
                guard b > a else { continue }
                let parent = anchor(max(0, a))
                let (e, _) = try clipElement(piece, offset: parent.at, duration: time(b - a), lane: -(k + 1))
                anchored.append((parent.element, e))
            }
        }
        // Anchored clips go after a clip's adjustments and before its markers (the DTD's order).
        for (parent, child) in anchored { parent.addChild(child) }

        // Scenes and the director's notes, as markers on V1.
        func marker(at t: Double, length: Double, value: String, note: String?) {
            let f = frames(t)
            guard f >= 0, f < max(1, end) else { return }
            let parent = anchor(f)
            var attrs = [("start", parent.at.description), ("duration", time(max(1, frames(length))).description), ("value", value)]
            if let note, !note.isEmpty { attrs.append(("note", note)) }
            parent.element.addChild(element("marker", attrs))
        }
        let story = s.clips.filter { $0.layer == 0 && $0.kind != .audio }.sorted { $0.start < $1.start }
        var scenes: [(scene: DailiesScene, start: Double, end: Double)] = []
        for c in story {
            guard let sc = input.dailies.scene(for: c.assetID) else { continue }
            if let l = scenes.last, l.scene.id == sc.id, abs(l.end - c.start.seconds) < 1e-6 { scenes[scenes.count - 1].end = c.end.seconds } else { scenes.append((sc, c.start.seconds, c.end.seconds)) }
        }
        for x in scenes { marker(at: x.start, length: 0, value: "Scene \(x.scene.number)" + (x.scene.title.isEmpty ? "" : ": \(x.scene.title)"), note: nil) }
        for n in input.notes where n.visibleToEditor && n.number != nil && n.sequenceID == s.id {
            guard let t = ReviewAnchoring.markerTime(n, in: s, revision: p.editRevision) else { continue }
            marker(at: t, length: n.range?.duration.seconds ?? 0, value: "Note \(n.number!)", note: n.text)
        }

        let sequence = element("sequence", [("format", sequenceFormat), ("duration", time(end).description), ("tcStart", "0s"), ("tcFormat", "NDF"), ("audioLayout", "stereo"), ("audioRate", "48k")])
        sequence.addChild(spineElement)
        let project = element("project", [("name", "\(input.filmName) \u{2013} \(input.cutName)")])
        project.addChild(sequence)
        let event = element("event", [("name", input.filmName)])
        event.addChild(project)
        let library = XMLElement(name: "library")
        library.addChild(event)
        let root = element("fcpxml", [("version", "1.10")])
        root.addChild(resources)
        root.addChild(library)
        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"; doc.characterEncoding = "UTF-8"
        doc.dtd = XMLDTD()
        doc.dtd?.name = "fcpxml"
        return doc.xmlString(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
    }

    /// Times to key so Final Cut's straight lines follow Direction's keys: each key, then a frame before the next
    /// after a hold, and three between after a smooth one. `frame` is a frame in the keys' own time.
    static func keyTimes(_ keys: [Keyframe], frame: Double) -> [Double] {
        let k = keys.sorted { $0.t < $1.t }
        var out: [Double] = []
        for (i, key) in k.enumerated() {
            out.append(key.t)
            guard i + 1 < k.count else { continue }
            let span = k[i + 1].t - key.t
            guard span > frame * 1.5 else { continue }
            if key.ease == "hold" { out.append(k[i + 1].t - frame) }
            else if key.ease == "smooth" { for j in 1...3 { out.append(key.t + span * Double(j) / 4) } }
        }
        return out
    }

    /// "a, b and c".
    static func listed(_ items: [String]) -> String { items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last! }

    static func element(_ name: String, _ attrs: [(String, String)]) -> XMLElement {
        let e = XMLElement(name: name)
        for (k, v) in attrs { e.addAttribute(attribute(k, v)) }
        return e
    }
    static func attribute(_ name: String, _ value: String) -> XMLNode { XMLNode.attribute(withName: name, stringValue: value) as! XMLNode }
    public static func number(_ v: Double) -> String {
        let r = (v * 10_000).rounded() / 10_000
        return r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
    }
    static func decibels(_ v: Double) -> String { number(max(-96, v)) + "dB" }

    // MARK: Read me

    /// What's in the folder and what didn't go across, for whoever opens it.
    public static func readMe(filmName: String, cutName: String, timeline: String, plan: Plan, stems: [String], looks: [String], cameraLUTs: [String]) -> String {
        var lines = ["\(filmName) \u{2013} \(cutName)", "", "Open \(timeline) in Final Cut Pro (File \u{203A} Import \u{203A} XML) or DaVinci Resolve (File \u{203A} Import \u{203A} Timeline). Keep this folder together: the timeline points at the renders and sound in it, and at the original footage where it is on this Mac.", ""]
        lines += ["What\u{2019}s here", "- The cut, at the same frames: takes, made shots, graphics (with see-through backgrounds), speed changes, reframes, dissolves, sound levels and fades, and the scenes and notes as markers."]
        if !plan.renders.isEmpty {
            lines.append("- Renders: \(plan.renders.count == 1 ? "one stretch" : "\(plan.renders.count) stretches") only Direction draws, rendered with everything below it and placed on V1 in its place. Their sound is still in the timeline.")
            for r in plan.renders { lines.append("    \(r.name): \(r.reasons.joined(separator: ", "))") }
        }
        if !stems.isEmpty { lines.append("- Sound: the cut\u{2019}s mix and each track on its own, as the cut plays them (\(stems.joined(separator: ", "))). Together the tracks make the mix.") }
        if !looks.isEmpty { lines.append("- The look as LUTs (\(looks.joined(separator: ", "))). Put the film\u{2019}s on everything under the graphics; the timeline\u{2019}s shots don\u{2019}t have it.") }
        if !cameraLUTs.isEmpty { lines.append("- Camera LUTs for log footage (\(cameraLUTs.joined(separator: ", "))): put each on the shots it\u{2019}s named for, before the look. The renders already have them.") }
        if !plan.notes.isEmpty { lines += ["", "What didn\u{2019}t go across"] + plan.notes.map { "- " + $0 } }
        return lines.joined(separator: "\n") + "\n"
    }
}

struct Pair: Hashable { var a: Bool; var b: Int; init(_ a: Bool, _ b: Int) { self.a = a; self.b = b } }

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

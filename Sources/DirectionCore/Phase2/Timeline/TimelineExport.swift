import Foundation

/// The cut as the editor reads it: OpenTimelineIO JSON and a compact outline (agent-timeline.md › Reading).
/// Read-only. Every item carries its id in `metadata.direction.id`, and operations refer to those ids.
public struct TimelineDocument: Sendable {
    public var otio: JSONValue
    public var outline: String
}

public enum TimelineExport {
    public struct Input: Sendable {
        public var project: Project
        public var sequence: Sequence
        public var cutName: String
        public var dailies: Dailies
        public var notes: [ReviewComment]
        public var looks: LookContext?
        public var range: MediaRange?
        public init(project: Project, sequence: Sequence, cutName: String, dailies: Dailies = .init(), notes: [ReviewComment] = [], looks: LookContext? = nil, range: MediaRange? = nil) { self.project = project; self.sequence = sequence; self.cutName = cutName; self.dailies = dailies; self.notes = notes; self.looks = looks; self.range = range }
    }

    struct Item { var start: Double; var end: Double; var json: JSONValue; var transition: JSONValue?; var clip: Clip }

    public static func document(_ input: Input) -> TimelineDocument {
        let s = input.sequence, rate = s.frameRate.value
        func rt(_ seconds: Double) -> JSONValue { .object(["OTIO_SCHEMA": .string("RationalTime.1"), "rate": .number(rate), "value": .number((seconds * rate * 1_000_000).rounded() / 1_000_000)]) }
        func tr(_ start: Double, _ duration: Double) -> JSONValue { .object(["OTIO_SCHEMA": .string("TimeRange.1"), "start_time": rt(start), "duration": rt(duration)]) }
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in input.project.assets.first { $0.id == id } } }
        func cutKeys(_ keys: [String: [Keyframe]]?, _ c: Clip?) -> JSONValue {
            guard let keys, !keys.isEmpty else { return .null }
            return .object(keys.mapValues { list in .array(list.map { k in
                let t = c.map { $0.start.seconds + (k.t - $0.sourceRange.start.seconds) / $0.speed } ?? k.t
                var o: [String: JSONValue] = ["t": .number((t * 1_000).rounded() / 1_000), "v": .number(k.v)]; if let e = k.ease { o["ease"] = .string(e) }; return .object(o)
            }) })
        }
        func effect(_ e: ClipEffect, _ c: Clip?) -> JSONValue {
            var d: [String: JSONValue] = ["id": .string(e.id), "params": .object(e.params)]
            let keys = cutKeys(e.keys, c); if keys != .null { d["keys"] = keys }
            return .object(["OTIO_SCHEMA": .string("Effect.1"), "name": .string(e.id), "effect_name": .string(e.name), "metadata": .object(["direction": .object(d)])])
        }
        func take(_ c: Clip) -> String? { c.assetID.flatMap { input.dailies.takes[$0] }.flatMap { t in t.code.map { [t.setupCode, $0].compactMap { $0 }.joined(separator: " ") } } }
        func audible(_ c: Clip) -> Bool {
            guard c.hold == nil, let a = asset(c), !a.audio.isEmpty else { return false }
            return a.audio.contains { !(c.audioOverrides[String($0.id)] ?? $0.settings).muted }
        }
        func clip(_ c: Clip, sound: Bool, track: String) -> JSONValue {
            let a = asset(c)
            let start = sound ? c.sourceRange.start.seconds - (c.soundLead ?? 0) * c.speed : c.sourceRange.start.seconds
            let duration = sound ? c.soundRange.duration.seconds : c.duration.seconds
            let reference: JSONValue
            if c.kind == .title { reference = .object(["OTIO_SCHEMA": .string("GeneratorReference.1"), "name": .string("title"), "generator_kind": .string("direction.title"), "parameters": .object(["text": .string(c.title ?? c.name)]), "available_range": .null, "metadata": .object([:])]) }
            else if let g = a?.graphic { reference = .object(["OTIO_SCHEMA": .string("GeneratorReference.1"), "name": .string(g), "generator_kind": .string("direction.graphic"), "parameters": .object(["graphicID": .string(g), "assetID": .string(a?.id ?? "")]), "available_range": tr(0, a?.duration.seconds ?? duration), "metadata": .object([:])]) }
            else if let a { reference = .object(["OTIO_SCHEMA": .string("ExternalReference.1"), "name": .string(a.name), "target_url": .string(URL(fileURLWithPath: a.path).absoluteString), "available_range": tr(0, a.duration.seconds), "metadata": .object(["direction": .object(["assetID": .string(a.id)])])]) }
            else { reference = .object(["OTIO_SCHEMA": .string("MissingReference.1"), "name": .string(""), "available_range": .null, "metadata": .object([:])]) }
            var effects: [JSONValue] = sound ? [] : (c.effects ?? []).map { effect($0, c) }
            if c.speed != 1 && c.hold == nil { effects.append(.object(["OTIO_SCHEMA": .string("LinearTimeWarp.1"), "name": .string(""), "effect_name": .string("LinearTimeWarp"), "time_scalar": .number(c.speed), "metadata": .object([:])])) }
            if let h = c.hold, !sound { effects.append(.object(["OTIO_SCHEMA": .string("FreezeFrame.1"), "name": .string(""), "effect_name": .string("FreezeFrame"), "time_scalar": .number(0), "metadata": .object(["direction": .object(["seconds": .number(h.seconds)])])])) }
            var d: [String: JSONValue] = ["id": .string(c.id), "track": .string(track), "kind": .string(c.kind == .title ? "title" : a?.graphic != nil ? "graphic" : a?.madeID != nil ? "made" : c.kind == .audio ? "sound" : "take")]
            if let a { d["assetID"] = .string(a.id) }
            if let t = take(c) { d["take"] = .string(t) }
            if let n = input.dailies.scene(for: c.assetID)?.number { d["scene"] = .number(Double(n)) }
            if sound { d["linked"] = .string("picture") }
            if c.synced == true { d["synced"] = .bool(true) }
            if let m = a?.madeID { d["madeID"] = .string(m) }
            if let g = a?.graphic { d["graphic"] = .string(g) }
            if !sound {
                if c.grade != ColorGrade() { d["balance"] = (try? .wrapping(c.grade)) ?? .null }
                if c.framing != Framing() { d["framing"] = (try? .wrapping(c.framing)) ?? .null }
                if let b = c.blend { d["blend"] = .string(b) }
                if let al = c.aboveLook { d["aboveLook"] = .bool(al) }
                if let lut = a?.cameraLUT { d["cameraLUT"] = .string(lut) }
            }
            if sound || c.kind == .audio || audible(c) {
                if let g = c.gainDB { d["gainDB"] = .number(g) }
                let gk = cutKeys(c.gainKeys.map { ["dB": $0] }, c)["dB"]; if gk != .null { d["gainKeys"] = gk }
                let dk = cutKeys(c.duckKeys.map { ["dB": $0] }, c)["dB"]; if dk != .null { d["duckKeys"] = dk }
                if let v = c.fadeIn { d["fadeIn"] = .number(v) }; if let v = c.fadeOut { d["fadeOut"] = .number(v) }
                if let v = c.soundLead { d["soundLead"] = .number(v) }; if let v = c.soundTail { d["soundTail"] = .number(v) }
            }
            return .object(["OTIO_SCHEMA": .string("Clip.2"), "name": .string(c.title ?? take(c) ?? a?.graphic ?? c.name), "source_range": tr(start, duration), "media_references": .object(["DEFAULT_MEDIA": reference]), "active_media_reference_key": .string("DEFAULT_MEDIA"), "effects": .array(effects), "markers": .array([]), "enabled": .bool(true), "metadata": .object(["direction": .object(d)])])
        }
        func transition(_ c: Clip) -> JSONValue? {
            guard let t = c.transition else { return nil }
            return .object(["OTIO_SCHEMA": .string("Transition.1"), "name": .string(t.type), "transition_type": .string(t.type == "dissolve" ? "SMPTE_Dissolve" : "Direction_" + t.type), "in_offset": rt(t.before), "out_offset": rt(t.after), "metadata": .object(["direction": .object(["type": .string(t.type), "frames": .number(Double(t.frames)), "clipID": .string(c.id), "params": t.params.map(JSONValue.object) ?? .null, "file": t.file.map(JSONValue.string) ?? .null])])])
        }
        func overlaps(_ a: Double, _ b: Double) -> Bool { input.range.map { a < $0.end.seconds && b > $0.start.seconds } ?? true }
        func lanes(_ items: [Item]) -> [[Item]] {
            var out: [[Item]] = []
            for it in items.sorted(by: { $0.start < $1.start }) { if let k = out.firstIndex(where: { ($0.last?.end ?? 0) <= it.start + 1e-9 }) { out[k].append(it) } else { out.append([it]) } }
            return out.isEmpty ? [[]] : out
        }
        func track(_ name: String, _ kind: String, _ items: [Item], lane: Int, markers: [JSONValue] = []) -> JSONValue {
            var children: [JSONValue] = [], t = 0.0
            for it in items where overlaps(it.start, it.end) {
                if it.start > t + 1e-9 { children.append(.object(["OTIO_SCHEMA": .string("Gap.1"), "name": .string(""), "source_range": tr(0, it.start - t), "effects": .array([]), "markers": .array([]), "enabled": .bool(true), "metadata": .object([:])])) }
                if let x = it.transition { children.append(x) }
                children.append(it.json); t = it.end
            }
            let settings = s.tracks?[name]
            var d: [String: JSONValue] = ["track": .string(name)]
            if lane > 0 { d["lane"] = .number(Double(lane + 1)) }
            if let al = settings?.aboveLook { d["aboveLook"] = .bool(al) }
            if let g = settings?.gainDB { d["gainDB"] = .number(g) }
            if let k = settings?.gainKeys { d["gainKeys"] = cutKeys(["dB": k], nil)["dB"] }
            if let duck = settings?.ducked { d["ducked"] = (try? .wrapping(duck)) ?? .null }
            return .object(["OTIO_SCHEMA": .string("Track.1"), "name": .string(name), "kind": .string(kind), "children": .array(children), "source_range": .null, "effects": .array((settings?.effects ?? []).map { effect($0, nil) }), "markers": .array(lane == 0 ? markers : []), "enabled": .bool(true), "metadata": .object(["direction": .object(d)])])
        }

        // Scenes are stretches of V1 by take; their markers sit on V1.
        let story = s.clips.filter { $0.layer == 0 && $0.kind != .audio }.sorted { $0.start < $1.start }
        var scenes: [(scene: DailiesScene, start: Double, end: Double, last: String)] = []
        for c in story { guard let sc = input.dailies.scene(for: c.assetID) else { continue }; if let l = scenes.last, l.scene.id == sc.id, abs(l.end - c.start.seconds) < 1e-6 { scenes[scenes.count - 1].end = c.end.seconds; scenes[scenes.count - 1].last = c.id } else { scenes.append((sc, c.start.seconds, c.end.seconds, c.id)) } }
        let sceneMarkers: [JSONValue] = scenes.filter { overlaps($0.start, $0.end) }.map { x in .object(["OTIO_SCHEMA": .string("Marker.2"), "name": .string("Scene \(x.scene.label)"), "marked_range": tr(x.start, x.end - x.start), "color": .string(x.scene.locked ? "PURPLE" : "GREEN"), "comment": .string(""), "metadata": .object(["direction": .object(["scene": .object(["number": .number(Double(x.scene.number)), "title": .string(x.scene.title), "locked": .bool(x.scene.locked)])])])]) }
        let noteMarkers: [JSONValue] = input.notes.filter { $0.visibleToEditor && $0.number != nil && $0.sequenceID == s.id }.compactMap { n in
            guard let t = ReviewAnchoring.markerTime(n, in: s, revision: input.project.editRevision), overlaps(t, t + max(n.range?.duration.seconds ?? 0, 1e-6)) else { return nil }
            var note: [String: JSONValue] = ["number": .number(Double(n.number!)), "id": .string(n.id)]; if let k = n.kind { note["kind"] = .string(k.rawValue) }
            return .object(["OTIO_SCHEMA": .string("Marker.2"), "name": .string("Note \(n.number!)"), "marked_range": tr(t, n.range?.duration.seconds ?? 0), "color": .string("YELLOW"), "comment": .string(n.text), "metadata": .object(["direction": .object(["note": .object(note)])])])
        }

        // Video bottom first, then sound: A1 is V1's own sound plus sound-only clips on A1.
        var tracks: [JSONValue] = []
        let pictureLayers = Set(s.clips.filter { $0.kind != .audio }.map(\.layer)).union([0]).sorted()
        for layer in pictureLayers {
            let items = s.clips.filter { $0.kind != .audio && $0.layer == layer }.map { Item(start: $0.start.seconds, end: $0.end.seconds, json: clip($0, sound: false, track: "V\(layer + 1)"), transition: transition($0), clip: $0) }
            for (k, lane) in lanes(items).enumerated() { tracks.append(track("V\(layer + 1)", "Video", lane, lane: k, markers: layer == 0 ? sceneMarkers : [])) }
        }
        let soundLayers = Set(s.clips.filter { $0.kind == .audio }.map(\.layer)).union(story.contains(where: audible) ? [0] : []).sorted()
        for layer in soundLayers {
            var items = s.clips.filter { $0.kind == .audio && $0.layer == layer }.map { Item(start: $0.start.seconds, end: $0.end.seconds, json: clip($0, sound: false, track: "A\(layer + 1)"), transition: nil, clip: $0) }
            if layer == 0 { items += story.filter(audible).map { Item(start: $0.soundRange.start.seconds, end: $0.soundRange.end.seconds, json: clip($0, sound: true, track: "A1"), transition: nil, clip: $0) } }
            for (k, lane) in lanes(items).enumerated() { tracks.append(track("A\(layer + 1)", "Audio", lane, lane: k)) }
        }
        for layer in pictureLayers where layer > 0 {
            let items = s.clips.filter { $0.kind == .video && $0.layer == layer && audible($0) }.map { Item(start: $0.start.seconds, end: $0.end.seconds, json: clip($0, sound: true, track: "V\(layer + 1) sound"), transition: nil, clip: $0) }
            if !items.isEmpty { for (k, lane) in lanes(items).enumerated() { tracks.append(track("V\(layer + 1) sound", "Audio", lane, lane: k)) } }
        }

        let filmLook = input.looks?.look.film
        var meta: [String: JSONValue] = ["cut": .string(input.cutName), "editRevision": .number(Double(input.project.editRevision)), "sequenceID": .string(s.id), "width": .number(Double(s.width)), "height": .number(Double(s.height)), "rate": .number(rate), "look": filmLook.map { l in .object(["name": .string(l.name), "strength": .number(l.strength), "by": .string(l.by), "lut": l.lut.map(JSONValue.string) ?? .null]) } ?? .null]
        if let r = input.range { meta["range"] = .object(["start": .number(r.start.seconds), "end": .number(r.end.seconds)]) }
        let otio: JSONValue = .object(["OTIO_SCHEMA": .string("Timeline.1"), "name": .string(input.cutName), "global_start_time": rt(0), "metadata": .object(["direction": .object(meta)]), "tracks": .object(["OTIO_SCHEMA": .string("Stack.1"), "name": .string("tracks"), "children": .array(tracks), "source_range": .null, "effects": .array([]), "markers": .array(noteMarkers), "enabled": .bool(true), "metadata": .object([:])])])

        // The outline: one row per clip, top layer first, then sound.
        func tc(_ t: Double) -> String { CutTimecode.string(t, rate: rate) }
        let lastOfScene = Dictionary(scenes.map { ($0.last, $0.scene) }, uniquingKeysWith: { a, _ in a })
        func row(_ c: Clip) -> String? {
            guard overlaps(c.start.seconds, c.end.seconds) else { return nil }
            let a = asset(c), role = ["A1": "voice", "A2": "music", "A3": "effects"][c.trackName] ?? "sound"
            var parts = [c.trackName, "\(tc(c.start.seconds))–\(tc(c.end.seconds))", c.id]
            if c.kind == .title { parts.append("title \"\(c.title ?? c.name)\"") }
            else if let g = a?.graphic { parts.append("graphic \"\(g)\"") }
            else if a?.madeID != nil { parts.append((c.kind == .audio ? role : "shot") + " \"\(c.name)\" (made)") }
            else if c.kind == .audio { parts.append("\(role) \"\(c.name)\"") }
            else { parts.append(take(c) ?? c.name) }
            if c.kind != .title && a?.graphic == nil, a?.isImage != true {
                let srcEnd = c.hold == nil ? c.sourceRange.end.seconds : c.sourceRange.start.seconds
                parts.append("src \(tc(c.sourceRange.start.seconds))–\(tc(srcEnd))")
            }
            if c.synced == true { parts.append("in sync") }
            if let t = c.transition { parts.append("\(t.type == "shader" ? t.file ?? "shader" : t.type) \(t.frames)f in") }
            for e in c.effects ?? [] {
                switch e.name {
                case "transform": parts.append("reframe(\(String(format: "%g", e.number("scale", at: nil, default: 1)))\(e.keys?["x"] != nil ? ", keyed" : ""))")
                case "blur": parts.append("blur(\(String(format: "%g", e.number("radius", at: nil, default: 0))))")
                case "sharpen", "stabilize": parts.append("\(e.name)(\(String(format: "%g", e.number("amount", at: nil, default: e.name == "stabilize" ? 0.5 : 0))))")
                case "mask": parts.append("mask(\(e.params["shape"]?.string ?? "rect"))")
                case "shader": parts.append("shader(\(URL(fileURLWithPath: e.params["file"]?.string ?? "shader").deletingPathExtension().lastPathComponent))")
                default: parts.append(e.name + (e.params["amount"]?.double.map { "(\(String(format: "%g", $0)))" } ?? e.params["option"]?.string.map { "(\($0))" } ?? ""))
                }
            }
            if c.speed != 1 && c.hold == nil { parts.append("speed(\(String(format: "%g", c.speed))×)") }
            if let h = c.hold { parts.append("freeze(\(String(format: "%.1f", h.seconds)) s)") }
            if c.grade != ColorGrade() { parts.append("balance") }
            if let b = c.blend, b != "normal" { parts.append(b) }
            if let v = c.soundLead, v > 0 { parts.append("J \(Int((v * rate).rounded()))f") }
            if let v = c.soundTail, v > 0 { parts.append("L \(Int((v * rate).rounded()))f") }
            if let g = c.gainDB { parts.append(dbText(g)) }
            if c.fadeIn != nil || c.fadeOut != nil { parts.append("fade \(Int(((c.fadeIn ?? 0) * rate).rounded()))f/\(Int(((c.fadeOut ?? 0) * rate).rounded()))f") }
            if c.duckKeys != nil, let d = s.tracks?[c.trackName]?.ducked { parts.append("ducked \(dbText(d.dB)) under \(d.under)") }
            if c.aboveLook ?? s.tracks?[c.trackName]?.aboveLook ?? false { parts.append("above look") }
            if let sc = lastOfScene[c.id] { parts.append("‹scene \(sc.number)\(sc.locked ? " · locked" : "")›") }
            return parts.joined(separator: "  ")
        }
        let lookText: String
        if let l = filmLook { lookText = "look \"\(l.name)\" (film)" }
        else if let (id, l) = input.looks?.look.scenes.first, let n = input.dailies.scenes.first(where: { $0.id == id })?.number { lookText = "look \"\(l.name)\" (scene \(n))" }
        else { lookText = "no look" }
        var lines = ["\(input.cutName) · \(CutTimecode.length(s.duration.seconds, rate: rate)) · \(s.width)×\(s.height) · \(CutTimecode.rate(rate)) · \(lookText)"]
        for layer in pictureLayers.reversed() { lines += s.clips.filter { $0.kind != .audio && $0.layer == layer }.sorted { $0.start < $1.start }.compactMap(row) }
        for layer in Set(s.clips.filter { $0.kind == .audio }.map(\.layer)).sorted() { lines += s.clips.filter { $0.kind == .audio && $0.layer == layer }.sorted { $0.start < $1.start }.compactMap(row) }
        for (name, t) in (s.tracks ?? [:]).sorted(by: { $0.key < $1.key }) where !(t.effects ?? []).isEmpty || t.gainDB != nil {
            lines.append("\(name)  track  " + ((t.effects ?? []).map(\.name) + (t.gainDB.map { [dbText($0)] } ?? [])).joined(separator: "  "))
        }
        return TimelineDocument(otio: otio, outline: lines.joined(separator: "\n"))
    }
}

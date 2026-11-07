import Foundation
import DirectionCore
import DirectionMedia

// The mechanical finishing steps (finish.md › What Direction does itself): the mix to its loudness target,
// captions from the words, the credits roll. Each is an edit function in direction_edit, measured or made here
// before the batch runs, so it holds to the locks and lands as one revision like any other edit.
extension ToolCatalog {
    static var checkDefinitions: [ToolDefinition] { [
        definition("direction_check", "Check the cut the way it delivers, before you call finishing done: the mix against the loudness target and the \u{2212}1 dBTP ceiling, and the framing, looked at frame by frame: a crop that loses a face the take has or cuts through it, words in a tall or feed frame where the phone apps put their buttons and captions (the bottom fifth, the right eighth), words over a face. Each problem has its time. ready is the sound: sound can be marked done only when it\u{2019}s true. Framing problems are yours to fix, or to name in needsYou when they\u{2019}re meant.", ["revision": integer]),
    ] }
}

extension ToolRuntime {
    func invokeCheck(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        guard name == "direction_check" else { return nil }
        return ToolResponse(try await deliveryCheck(revision: a["revision"].int))
    }

    /// The whole mix at a revision against the loudness target.
    func loudnessVerdict(revision: Int? = nil) async throws -> (LoudnessCheck.Verdict, JSONValue) {
        let p = try store.read(revision: revision)
        let compiled = try await SequenceRenderer.compile(project: p, sequenceID: nil, cacheDirectory: cacheDirectory)
        // A cut with no sound at all is silent, not a failure: there's nothing to bring to the target.
        do {
            let m = try await SequenceRenderer.loudness(compiled)
            return (LoudnessCheck.verdict(integrated: m["integratedLUFS"].double, truePeak: m["truePeakDBTP"].double ?? -120), m)
        } catch let e as DirectionError where e.code == "no_audio" { return (.silent, .object([:])) }
    }

    /// What direction_check and the Deliver sheet show: the sound's verdict, and what the framing check found.
    public func deliveryCheck(revision: Int? = nil) async throws -> JSONValue {
        let p = try store.read(revision: revision), s = try p.sequence(nil), dailies = try store.dailies()
        let looks = try? store.lookContext()
        let compiled = try await SequenceRenderer.compile(project: p, sequenceID: s.id, cacheDirectory: cacheDirectory, looks: looks)
        let (verdict, m) = try await loudnessVerdict(revision: p.editRevision)
        // Takes by the names Dailies gives them ("2A Take 3"), the ones the director types in a note.
        let names = Dictionary(FootageNames.all(dailies, assets: p.assets).filter { $0.kind == .take }.compactMap { n in n.assetID.map { ($0, n.name) } }, uniquingKeysWith: { a, _ in a })
        let framing = try await FramingCheck.run(project: p, sequence: s, compiled: compiled, looks: looks, cacheDirectory: cacheDirectory, label: { c in
            c.assetID.flatMap { names[$0] } ?? (c.name as NSString).deletingPathExtension
        })
        return .object([
            "ready": .bool(verdict.isReady), "editRevision": .number(Double(p.editRevision)),
            "loudness": .object(["integratedLUFS": m["integratedLUFS"], "truePeakDBTP": m["truePeakDBTP"], "target": .number(SharedSettings.loudnessTarget), "ceiling": .number(SharedSettings.truePeakCeiling),
                                 "ready": .bool(verdict.isReady), "says": .string(verdict == .silent ? "There\u{2019}s no sound in the cut." : verdict.words ?? "On target."), "fix": verdict.isReady ? .null : .string("direction_edit with {op: \"loudness\"}")]),
            "framing": try .wrapping(framing.problems), "framesLookedAt": .number(Double(framing.frames)),
        ])
    }

    /// loudness: the mix measured as the operations before it leave it, and the target from Settings › Cutting.
    func resolveLoudness(_ op: inout EditOperation, _ p: Project, _ s: DirectionCore.Sequence) async throws {
        op.lufs = op.lufs ?? SharedSettings.loudnessTarget
        op.truePeak = op.truePeak ?? SharedSettings.truePeakCeiling
        let compiled = try await SequenceRenderer.compile(project: p, sequenceID: s.id, cacheDirectory: cacheDirectory)
        let m = try await SequenceRenderer.loudness(compiled)
        let peakAt = m["profile"]["peaks"].array?.first?["start"].double
        op.resolved = ResolvedValues()
        op.resolved?.loudness = MixLoudness(integratedLUFS: m["integratedLUFS"].double, truePeakDBTP: m["truePeakDBTP"].double ?? -120, mixGainDB: s.mixGainDB ?? 0, peakAt: peakAt)
    }

    /// captions: the cut's words (over range, or the whole cut) as caption graphics, a stretch of at most 110 s
    /// each, made from the style's captions graphic when it takes Direction's lines, or from Captions style.
    /// The range takes in every line it touches; lines outside it, and every line the director wrote, stay as
    /// they are, carried into the graphics that are made again (each graphic the range reaches) with the
    /// director's still marked as theirs. The graphics get names none has had, so nothing the cut or an earlier
    /// version shows changes until the batch goes in, and `revision` moves on with each one (the film changing
    /// meanwhile is stale). Checked only (`validateOnly`), nothing is made.
    func resolveCaptions(_ op: inout EditOperation, _ p: Project, _ s: DirectionCore.Sequence, revision: inout Int, validateOnly: Bool) async throws {
        let asked = op.range.map { ($0.start.seconds, $0.end.seconds) } ?? (0, s.duration.seconds)
        let laid = try laidCaptions(p, s)
        func overlaps(_ a: Double, _ b: Double, _ r: (Double, Double)) -> Bool { b > r.0 + 1e-6 && a < r.1 - 1e-6 }
        // Every graphic the range reaches, and the stretch they cover with it.
        var span = asked, reached: [LaidCaptions] = [], grew = true
        while grew {
            grew = false
            for l in laid where !reached.contains(where: { $0.clip.id == l.clip.id }) && overlaps(l.clip.start.seconds, l.clip.end.seconds, span) {
                reached.append(l); span = (min(span.0, l.clip.start.seconds), max(span.1, l.clip.end.seconds)); grew = true
            }
        }
        let shown = reached.flatMap(\.lines)
        // Whole lines: the range takes in each of the editor's lines it touches.
        var relay = asked
        grew = true
        while grew {
            grew = false
            for l in shown where !l.directors && overlaps(l.line.start, l.line.end, relay) && (l.line.start < relay.0 - 1e-6 || l.line.end > relay.1 + 1e-6) {
                relay = (min(relay.0, l.line.start), max(relay.1, l.line.end)); grew = true
            }
        }
        let kept = shown.filter { $0.directors || !overlaps($0.line.start, $0.line.end, relay) }
        let theirs = shown.filter(\.directors).map(\.line)
        let words = TranscriptEditing.words(in: s, transcripts: try store.transcripts()).filter { w in
            let mid = (w.range.start.seconds + w.range.end.seconds) / 2
            return w.range.start.seconds >= relay.0 - 1e-6 && w.range.end.seconds <= relay.1 + 1e-6 && !theirs.contains { mid >= $0.start && mid < $0.end }
        }
        guard !words.isEmpty || !reached.isEmpty else { throw DirectionError("no_words", "There are no words to caption\(op.range == nil ? "" : " there"): the takes in the cut have no transcript yet.") }
        let style = try store.style()
        let fit = Captions.fit(width: s.width, height: s.height, wordsAtATime: op.wordsAtATime ?? style?.tokens["captions"]["wordsAtATime"].int)
        // No caption past the picture, and none running into the next.
        let end = min(span.1, Self.pictureEnd(p, s))
        var lines = (kept + Captions.lines(words, wordsAtATime: fit.words, maxCharacters: fit.characters).map { (line: $0, directors: false) }).sorted { $0.line.start < $1.line.start }
        for i in lines.indices { lines[i].line.end = min(lines[i].line.end, end, i + 1 < lines.count ? lines[i + 1].line.start : .infinity) }
        lines = lines.filter { $0.line.end - $0.line.start > 0.05 }
        // The reducer takes out every captions graphic over this stretch.
        if op.range != nil { op.range = MediaRange(start: span.0, end: span.1) }
        op.resolved = ResolvedValues()
        op.resolved?.placed = []
        let stretches = Captions.stretches(lines.map(\.line))
        if validateOnly { op.resolved?.warnings = ["Checked without making the graphics: \(stretches.count == 1 ? "1 would" : "\(stretches.count) would") be laid."]; return }
        let template = try graphicTemplate(style: style, role: "captions", example: "captions-style", reads: "captions.js")
        var number = try firstFreeNumber("captions"), warnings: [String] = [], offset = 0
        for stretch in stretches {
            let flags = lines[offset..<offset + stretch.count].map(\.directors); offset += stretch.count
            guard let first = stretch.first, let last = stretch.last else { continue }
            let name = "captions-\(number)"; number += 1
            let duration = ((last.end - first.start) * 100).rounded() / 100
            let given: JSONValue = .object(["duration": .number(duration), "lines": .array(stretch.map { .string($0.text) }), "cues": .array(stretch.map { .number((($0.start - first.start) * 100).rounded() / 100) }),
                                            "directors": .array(flags.indices.filter { flags[$0] }.map { .number(Double($0)) })])
            let made = try await makeGraphic(name, from: template, script: "window.directionCaptions = \(String(decoding: try given.data(), as: UTF8.self));\n", file: "captions.js", revision: &revision)
            op.resolved?.placed?.append(.init(graphic: name, assetID: made.assetID, at: first.start, seconds: duration))
            warnings += made.problems.map { "\(name): \($0)" }
        }
        op.resolved?.warnings = warnings.isEmpty ? nil : Array(warnings.prefix(6))
    }

    /// credits: the director's credits, rolled on black after the last shot (or at `at`), for as long as they
    /// take to read. A graphic of its own each time, like captions.
    func resolveCredits(_ op: inout EditOperation, _ p: Project, _ s: DirectionCore.Sequence, revision: inout Int, validateOnly: Bool) async throws {
        guard let credits = try store.directingState().credits?.trimmingCharacters(in: .whitespacesAndNewlines), !credits.isEmpty else {
            throw DirectionError("bad_argument", "The director hasn\u{2019}t written credits yet (Finish \u{203A} Write credits); titles and credits are theirs.")
        }
        let lines = credits.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let duration = op.seconds ?? min(60, max(8, (Double(lines) * 0.9 + 3).rounded()))
        op.resolved = ResolvedValues()
        op.resolved?.placed = []
        if validateOnly { op.resolved?.warnings = ["Checked without making the credits graphic."]; return }
        let template = try graphicTemplate(style: try store.style(), role: "credits", example: "credits-roll", reads: "credits.js")
        let given: JSONValue = .object(["duration": .number(duration), "text": .string(credits)])
        let name = "credits-\(try firstFreeNumber("credits"))"
        let made = try await makeGraphic(name, from: template, script: "window.directionCredits = \(String(decoding: try given.data(), as: UTF8.self));\n", file: "credits.js", revision: &revision)
        let at = op.at?.seconds ?? Self.pictureEnd(p, s)
        op.resolved?.warnings = made.problems.isEmpty ? nil : made.problems.map { "credits: \($0)" }
        op.resolved?.placed = [.init(graphic: name, assetID: made.assetID, at: at, seconds: duration)]
    }

    /// A captions graphic laid in the cut: its clip, and its lines in cut time as they show, each marked when
    /// the director wrote it: their words in place of the page's (a line that differs, or every line when they
    /// changed how many there are), or a line of theirs the captions step carried over (captions.js directors).
    struct LaidCaptions { var clip: Clip; var lines: [(line: Captions.Line, directors: Bool)] }

    func laidCaptions(_ p: Project, _ s: DirectionCore.Sequence) throws -> [LaidCaptions] {
        let graphics = Dictionary(try store.graphics().compactMap { g in g.assetID.map { ($0, g) } }, uniquingKeysWith: { a, _ in a })
        func split(_ text: String?) -> [String] { (text ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        var out: [LaidCaptions] = []
        for c in s.clips.sorted(by: { $0.start < $1.start }) where c.layer > 0 {
            guard let id = c.assetID, let g = graphics[id], g.name.hasPrefix("captions-") else { continue }
            let shown = split(g.text("lines")), page = split(g.words.first { $0.key == "lines" }?.text)
            let theirs = g.directorWords["lines"] != nil
            let given = Self.captionsData(store.graphicsFolder.appendingPathComponent(g.name, isDirectory: true).appendingPathComponent("captions.js"))
            let speed = c.speed > 0 ? c.speed : 1, from = c.sourceRange.start.seconds
            var lines: [(line: Captions.Line, directors: Bool)] = []
            for (i, l) in Captions.timed(shown, cues: given?["cues"].array?.compactMap(\.double) ?? [], duration: given?["duration"].double ?? g.duration).enumerated() {
                let a = max(c.start.seconds, c.start.seconds + (l.start - from) / speed), b = min(c.end.seconds, c.start.seconds + (l.end - from) / speed)
                guard b - a > 0.05 else { continue }
                let carried = shown.count == page.count && (given?["directors"].array ?? []).contains { $0.int == i }
                lines.append((.init(text: l.text, start: (a * 1000).rounded() / 1000, end: (b * 1000).rounded() / 1000), carried || theirs && (shown.count != page.count || shown[i] != page[i])))
            }
            out.append(.init(clip: c, lines: lines))
        }
        return out
    }

    /// The captions the cut shows, for delivery's SRT and WebVTT: each captions graphic laid in it, its lines as
    /// the director left them at the times they show; with none laid, the cut's words as the captions step
    /// would lay them. language is the transcripts' ("en-US"), when they say.
    public func captionLines(revision: Int? = nil, sequenceID: String? = nil) throws -> (lines: [Captions.Line], language: String?) {
        let p = try store.read(revision: revision), s = try p.sequence(sequenceID)
        let transcripts = try store.transcripts(), used = Set(s.clips.compactMap(\.assetID))
        let language = Dictionary(grouping: transcripts.filter { used.contains($0.assetID) }, by: \.language).max { $0.value.count < $1.value.count }?.key
        var lines = try laidCaptions(p, s).flatMap { $0.lines.map(\.line) }
        if lines.isEmpty {
            let fit = Captions.fit(width: s.width, height: s.height, wordsAtATime: try store.style()?.tokens["captions"]["wordsAtATime"].int)
            let end = Self.pictureEnd(p, s)
            lines = Captions.lines(TranscriptEditing.words(in: s, transcripts: transcripts), wordsAtATime: fit.words, maxCharacters: fit.characters)
                .map { l in var l = l; l.end = min(l.end, end); return l }.filter { $0.end > $0.start }
        }
        return (lines.sorted { $0.start < $1.start }, language)
    }

    /// Writes the captions as SRT at url and WebVTT beside it (same name, .vtt), never over a file. Returns
    /// how many captions.
    public func writeCaptionFiles(revision: Int? = nil, sequenceID: String? = nil, to url: URL) throws -> Int {
        let lines = try captionLines(revision: revision, sequenceID: sequenceID).lines
        guard !lines.isEmpty else { throw DirectionError("no_words", "There are no words to caption: the takes in the cut have no transcript yet.") }
        try Data(Captions.srt(lines).utf8).write(to: url, options: .withoutOverwriting)
        try Data(Captions.webVTT(lines).utf8).write(to: url.deletingPathExtension().appendingPathExtension("vtt"), options: .withoutOverwriting)
        return lines.count
    }

    /// What a captions graphic was made from (its captions.js: duration, lines, cues).
    static func captionsData(_ url: URL) -> JSONValue? {
        guard let text = try? String(contentsOf: url, encoding: .utf8), let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(text[a...b].utf8))
    }

    /// Where the last shot ends: the cut's picture without the graphics over it, and without music or sound
    /// that rings on past it.
    static func pictureEnd(_ p: Project, _ s: DirectionCore.Sequence) -> Double {
        let graphics = Set(p.assets.filter { $0.graphic != nil }.map(\.id))
        return s.clips.filter { c in c.kind == .video && !(c.assetID.map(graphics.contains) ?? false) }.map(\.end.seconds).max() ?? 0
    }

    /// The page a step's graphic starts from: the style's own for that role when it reads Direction's file, or
    /// the example that ships with Direction.
    private func graphicTemplate(style: Style?, role: String, example: String, reads file: String) throws -> URL {
        if let style, let name = style.tokens["graphics"][role].string {
            let folder = style.url.appendingPathComponent("graphics/" + name, isDirectory: true)
            if let page = try? String(contentsOf: folder.appendingPathComponent("index.html"), encoding: .utf8), page.contains(file) { return folder }
        }
        return try GraphicResources.example(example).1
    }

    /// The first number after every stem-N graphic the film has had, or folder left: a step's graphic is never
    /// made over one the cut, an earlier version or the director's words still use.
    func firstFreeNumber(_ stem: String) throws -> Int {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: store.graphicsFolder.path)) ?? []
        let numbers = (try store.graphics().map(\.name) + folders).compactMap { name in name.hasPrefix(stem + "-") ? Int(name.dropFirst(stem.count + 1)) : nil }
        return (numbers.max() ?? 0) + 1
    }

    /// Writes Editor/Graphics/<name>/ from the template with the step's data file, checks and renders it. The
    /// film has to be at `revision` when it starts and only this graphic may move it on: anything else is stale.
    private func makeGraphic(_ name: String, from template: URL, script: String, file: String, revision: inout Int) async throws -> (assetID: String, problems: [String]) {
        let stale = DirectionError("stale_revision", "The film changed while Direction made the graphics. Read direction_timeline again and send the batch again.")
        guard try store.revision() == revision else { throw stale }
        let folder = store.graphicsFolder.appendingPathComponent(name, isDirectory: true), fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for path in try GraphicResources.files(in: template) where path != file {
            let to = folder.appendingPathComponent(path)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: template.appendingPathComponent(path), to: to)
        }
        try Data(script.utf8).write(to: folder.appendingPathComponent(file), options: .atomic)
        let result = try await GraphicMaker.make(store: store, name: name, noteID: nil, checkOnly: false, cacheDirectory: cacheDirectory)
        guard let id = result.graphic.assetID else { throw DirectionError("graphic_failed", "Direction couldn\u{2019}t render \(name).") }
        if let r = result.editRevision, r != revision { guard r == revision + 1 else { throw stale }; revision = r }
        return (id, result.problems.map(\.message))
    }
}

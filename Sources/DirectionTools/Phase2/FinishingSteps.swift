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
        let m = try await SequenceRenderer.loudness(compiled)
        return (LoudnessCheck.verdict(integrated: m["integratedLUFS"].double, truePeak: m["truePeakDBTP"].double ?? -120), m)
    }

    /// What direction_check and the Deliver sheet show: the sound's verdict, and what the framing check found.
    public func deliveryCheck(revision: Int? = nil) async throws -> JSONValue {
        let p = try store.read(revision: revision), s = try p.sequence(nil), dailies = try store.dailies()
        let compiled = try await SequenceRenderer.compile(project: p, sequenceID: s.id, cacheDirectory: cacheDirectory, looks: try? store.lookContext())
        let (verdict, m) = try await loudnessVerdict(revision: p.editRevision)
        let framing = try await FramingCheck.run(project: p, sequence: s, compiled: compiled, cacheDirectory: cacheDirectory, label: { c in
            c.assetID.flatMap { dailies.takes[$0] }.flatMap { t in t.code.map { [t.setupCode, $0].compactMap { $0 }.joined(separator: " ") } } ?? c.name
        })
        return .object([
            "ready": .bool(verdict.isReady), "editRevision": .number(Double(p.editRevision)),
            "loudness": .object(["integratedLUFS": m["integratedLUFS"], "truePeakDBTP": m["truePeakDBTP"], "target": .number(SharedSettings.loudnessTarget), "ceiling": .number(SharedSettings.truePeakCeiling),
                                 "ready": .bool(verdict.isReady), "says": .string(verdict.words ?? "On target."), "fix": verdict.isReady ? .null : .string("direction_edit with {op: \"loudness\"}")]),
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
    /// Returns the revision the last graphic left the film at.
    func resolveCaptions(_ op: inout EditOperation, _ p: Project, _ s: DirectionCore.Sequence) async throws -> Int? {
        let range = op.range.map { ($0.start.seconds, $0.end.seconds) } ?? (0, s.duration.seconds)
        let words = TranscriptEditing.words(in: s, transcripts: try store.transcripts()).filter { $0.range.start.seconds >= range.0 - 1e-6 && $0.range.end.seconds <= range.1 + 1e-6 }
        guard !words.isEmpty else { throw DirectionError("no_words", "There are no words to caption\(op.range == nil ? "" : " there"): the takes in the cut have no transcript yet.") }
        let style = try store.style()
        let fit = Captions.fit(width: s.width, height: s.height, wordsAtATime: op.wordsAtATime ?? style?.tokens["captions"]["wordsAtATime"].int)
        // No caption past the picture: the last one ends with the last shot.
        let end = min(range.1, Self.pictureEnd(p, s))
        let lines = Captions.lines(words, wordsAtATime: fit.words, maxCharacters: fit.characters).map { l in var l = l; l.end = min(l.end, end); return l }.filter { $0.end > $0.start }
        let stretches = Captions.stretches(lines)
        let template = try graphicTemplate(style: style, role: "captions", example: "captions-style", reads: "captions.js")
        // Names the captions left outside range still use stay theirs: the step takes the others, from 1.
        let kept = Set(s.clips.filter { c in c.layer > 0 && (c.end.seconds <= range.0 || c.start.seconds >= range.1) }
            .compactMap { c in c.assetID.flatMap { id in p.assets.first { $0.id == id }?.graphic } }.filter { $0.hasPrefix("captions-") })
        var names = (1...).lazy.map { "captions-\($0)" }.filter { !kept.contains($0) }.makeIterator()
        var placed: [PlacedGraphic] = [], revision: Int?, warnings: [String] = []
        for lines in stretches {
            guard let first = lines.first, let last = lines.last, let name = names.next() else { continue }
            let duration = ((last.end - first.start) * 100).rounded() / 100
            let given: JSONValue = .object(["duration": .number(duration), "lines": .array(lines.map { .string($0.text) }), "cues": .array(lines.map { .number((($0.start - first.start) * 100).rounded() / 100) })])
            let made = try await makeGraphic(name, from: template, script: "window.directionCaptions = \(String(decoding: try given.data(), as: UTF8.self));\n", file: "captions.js")
            placed.append(.init(graphic: name, assetID: made.assetID, at: first.start, seconds: duration))
            revision = made.revision; warnings += made.problems.map { "\(name): \($0)" }
        }
        op.resolved = ResolvedValues(warnings: warnings.isEmpty ? nil : Array(warnings.prefix(6)))
        op.resolved?.placed = placed
        return revision
    }

    /// credits: the director's credits, rolled on black after the last shot (or at `at`), for as long as they take to read.
    func resolveCredits(_ op: inout EditOperation, _ p: Project, _ s: DirectionCore.Sequence) async throws -> Int? {
        guard let credits = try store.directingState().credits?.trimmingCharacters(in: .whitespacesAndNewlines), !credits.isEmpty else {
            throw DirectionError("bad_argument", "The director hasn\u{2019}t written credits yet (Finish \u{203A} Write credits); titles and credits are theirs.")
        }
        let lines = credits.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let duration = op.seconds ?? min(60, max(8, (Double(lines) * 0.9 + 3).rounded()))
        let template = try graphicTemplate(style: try store.style(), role: "credits", example: "credits-roll", reads: "credits.js")
        let given: JSONValue = .object(["duration": .number(duration), "text": .string(credits)])
        let made = try await makeGraphic("credits", from: template, script: "window.directionCredits = \(String(decoding: try given.data(), as: UTF8.self));\n", file: "credits.js")
        let at = op.at?.seconds ?? Self.pictureEnd(p, s)
        op.resolved = ResolvedValues(warnings: made.problems.isEmpty ? nil : made.problems.map { "credits: \($0)" })
        op.resolved?.placed = [.init(graphic: "credits", assetID: made.assetID, at: at, seconds: duration)]
        return made.revision
    }

    /// Where the last shot ends: the cut without the graphics over it.
    static func pictureEnd(_ p: Project, _ s: DirectionCore.Sequence) -> Double {
        let graphics = Set(p.assets.filter { $0.graphic != nil }.map(\.id))
        return s.clips.filter { c in c.kind != .title && !(c.assetID.map(graphics.contains) ?? false) }.map(\.end.seconds).max() ?? 0
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

    /// Writes Editor/Graphics/<name>/ from the template with the step's data file, checks and renders it.
    private func makeGraphic(_ name: String, from template: URL, script: String, file: String) async throws -> (assetID: String, revision: Int?, problems: [String]) {
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
        return (id, result.editRevision, result.problems.map(\.message))
    }
}

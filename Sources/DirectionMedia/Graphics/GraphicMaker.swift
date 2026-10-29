import Foundation
import CryptoKit
import CoreGraphics
import DirectionCore

/// What `direction_graphic` hands back (graphics.md › Tools).
public struct GraphicResult: Sendable {
    public var graphic: Graphic
    public var problems: [GraphicProblem]
    public var consoleErrors: [String]
    /// Render plus snapshot time for each frame drawn, in milliseconds.
    public var frameMilliseconds: [Double]
    public var stills: [GraphicStill]
    public var movie: GraphicRender?
    public var cached: Bool
    public var editRevision: Int?
    /// Where the contrast check looked, or why it couldn't.
    public var picture: String
}

/// Checks and renders graphics: the editor's `direction_graphic` and the director's Words.
@MainActor
public enum GraphicMaker {
    static let stillPoints: [(String, Double)] = [("0%", 0), ("25%", 0.25), ("50%", 0.5), ("75%", 0.75), ("100%", 1)]

    /// Checks `Editor/Graphics/<name>/`, renders it to ProRes 4444 (unless `checkOnly`) and registers the
    /// render as an asset. Throws `words_are_yours` when the page changes words the director set.
    public static func make(store: ProjectStore, name: String, noteID: String?, checkOnly: Bool, cacheDirectory: URL) async throws -> GraphicResult {
        guard Graphic.isValidName(name) else { throw DirectionError("invalid_name", "Name a graphic like its folder: lowercase letters, digits and dashes, such as title or lower-third.") }
        let folder = store.graphicsFolder.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) else { throw DirectionError("graphic_not_found", "Write the graphic to \(folder.path)/index.html first. direction_graphic_examples has a starting point.") }
        let project = try store.read(), sequence = try project.sequence(nil)
        let existing = try store.graphic(name)

        let page = try GraphicPage(folder: folder, width: sequence.width, height: sequence.height)
        defer { page.close() }
        let declaration = try await page.open(words: existing?.directorWords ?? [:], seed: seed(name))
        try check(declaration)
        // The director's words stand unless a note asks for new ones.
        let standing = try store.checkGraphicWords(name, declared: declaration.words, noteID: noteID)
        if standing != (existing?.directorWords ?? [:]) { try await page.setWords(standing) }
        var graphic = Graphic(name: name, folder: folder.path, duration: declaration.duration, words: declaration.words, directorWords: standing,
                              directorChangedAt: standing.isEmpty ? nil : existing?.directorChangedAt, assetID: existing?.assetID, noteID: noteID, render: existing?.render)
        let resolved = graphic.resolvedWords
        let hash = try self.hash(folder: folder, words: resolved, sequence: sequence)
        let target = store.graphicRendersFolder.appendingPathComponent("\(name)-\(hash).mov")
        let cached = !checkOnly && FileManager.default.fileExists(atPath: target.path)
        let frames = frameCount(declaration.duration, sequence.frameRate), stills = stillIndices(frames)

        // The picture behind it, for contrast and for the stills.
        let behind = await pictureBehind(store: store, project: project, sequence: sequence, graphic: existing, noteID: noteID, times: stills.map { Double($0) / sequence.frameRate.value }, cacheDirectory: cacheDirectory)

        let writer = checkOnly || cached ? nil : try GraphicMovieWriter(url: store.graphicRendersFolder.appendingPathComponent(".\(name)-\(UUID().uuidString).mov"), width: sequence.width, height: sequence.height, frameRate: sequence.frameRate)
        var problems = GraphicChecks.tooLong(graphic.words, resolved: resolved), milliseconds: [Double] = [], shots: [GraphicStill] = []
        do {
            try FileManager.default.createDirectory(at: store.graphicRendersFolder, withIntermediateDirectories: true)
            let indices = writer == nil ? Array(Set(stills)).sorted() : Array(0..<frames)
            for i in indices {
                try Task.checkCancellation()
                let t = Double(i) * Double(sequence.frameRate.denominator) / Double(sequence.frameRate.numerator)
                let (image, ms) = try await page.frame(t)
                milliseconds.append((ms * 10).rounded() / 10)
                try await writer?.append(image)
                for (k, index) in stills.enumerated() where index == i {
                    let label = stillPoints[k].0, picture = behind.images[k]
                    problems += GraphicChecks.problems(try await page.inspect(), at: label, picture: picture, words: graphic.words)
                    let url = cacheDirectory.appendingPathComponent("Graphics").appendingPathComponent("\(name)-\(hash)-\(Int(stillPoints[k].1 * 100)).png")
                    try GraphicChecks.still(image, over: picture, to: url)
                    shots.append(.init(at: label, time: t, path: url.path))
                }
            }
            if let writer {
                try await writer.finish()
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: writer.url) }
                else { try FileManager.default.moveItem(at: writer.url, to: target) }
            }
        } catch { writer?.cancel(); throw error }
        let console = try await page.report().consoleErrors

        var editRevision: Int?
        if !checkOnly {
            let render = try await registered(target, hash: hash, frames: frames, sequence: sequence)
            let asset = try await MediaInspector.inspect(url: target, thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails"))
            var entry = asset; entry.name = name
            let (assetID, revision) = try store.registerGraphicAsset(name, entry)
            graphic.assetID = assetID; graphic.render = render; editRevision = revision
            try store.saveGraphic(graphic, summary: "The editor made the graphic \(name)")
        }
        return GraphicResult(graphic: graphic, problems: GraphicChecks.unique(problems), consoleErrors: console, frameMilliseconds: milliseconds, stills: shots.sorted { $0.time < $1.time },
                             movie: checkOnly ? nil : graphic.render, cached: cached, editRevision: editRevision, picture: behind.note)
    }

    /// The director's Words (frame 64): renders with these words, then saves them as the director's.
    /// Returns the graphic as it was, for undo.
    @discardableResult
    public static func changeWords(store: ProjectStore, name: String, words: [String: String]) async throws -> (before: Graphic, after: Graphic) {
        guard let g = try store.graphic(name) else { throw DirectionError("graphic_not_found", "There's no graphic called \(name).") }
        try g.validateDirectorWords(words)
        var mine = g.directorWords
        for (key, text) in words where text != g.text(key) { mine[key] = text }
        var next = g; next.directorWords = mine
        let render = try await movie(store: store, graphic: next)
        let after = try store.setDirectorWords(name, mine, render: render)
        return (g, after)
    }

    /// Undo for a words change: the earlier words, and their render from the cache when it's still there.
    public static func restoreWords(store: ProjectStore, _ before: Graphic) async throws {
        var render = before.render
        if render.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true { render = try await movie(store: store, graphic: before) }
        try store.restoreDirectorWords(before.name, before.directorWords, changedAt: before.directorChangedAt, render: render)
    }

    /// The movie for a graphic as it stands, from the cache or rendered now.
    static func movie(store: ProjectStore, graphic g: Graphic) async throws -> GraphicRender {
        let folder = URL(fileURLWithPath: g.folder, isDirectory: true), sequence = try store.read().sequence(nil)
        let hash = try self.hash(folder: folder, words: g.resolvedWords, sequence: sequence)
        let target = store.graphicRendersFolder.appendingPathComponent("\(g.name)-\(hash).mov")
        if FileManager.default.fileExists(atPath: target.path), let existing = g.render, existing.path == target.path { return existing }
        let page = try GraphicPage(folder: folder, width: sequence.width, height: sequence.height)
        defer { page.close() }
        let declaration = try await page.open(words: g.directorWords, seed: seed(g.name))
        try check(declaration)
        let frames = frameCount(declaration.duration, sequence.frameRate)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.createDirectory(at: store.graphicRendersFolder, withIntermediateDirectories: true)
            let writer = try GraphicMovieWriter(url: store.graphicRendersFolder.appendingPathComponent(".\(g.name)-\(UUID().uuidString).mov"), width: sequence.width, height: sequence.height, frameRate: sequence.frameRate)
            do {
                for i in 0..<frames { try await writer.append(try await page.frame(Double(i) * Double(sequence.frameRate.denominator) / Double(sequence.frameRate.numerator)).image) }
                try await writer.finish()
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: writer.url) } else { try FileManager.default.moveItem(at: writer.url, to: target) }
            } catch { writer.cancel(); throw error }
        }
        return try await registered(target, hash: hash, frames: frames, sequence: sequence)
    }

    // MARK: Parts

    static func check(_ d: GraphicDeclaration) throws {
        guard d.duration.isFinite, d.duration > 0, d.duration <= 120 else { throw DirectionError("invalid_graphic", "A graphic's duration is 0–120 seconds.") }
        guard d.words.count <= 40 else { throw DirectionError("invalid_graphic", "A graphic can have up to 40 words fields.") }
        for w in d.words {
            guard !w.key.isEmpty, w.key.count <= 40, w.label.count <= 60, w.text.count <= 4_000 else { throw DirectionError("invalid_graphic", "Word \(w.key) needs a short key, a label of up to 60 characters and text of up to 4,000.") }
            if let max = w.maxLength, max < 1 { throw DirectionError("invalid_graphic", "Word \(w.key)'s max must be at least 1.") }
        }
    }

    static func frameCount(_ duration: Double, _ rate: FrameRate) -> Int { max(1, Int((duration * rate.value).rounded())) }
    static func stillIndices(_ frames: Int) -> [Int] { stillPoints.map { Int((Double(frames - 1) * $0.1).rounded()) } }

    /// Math.random's seed: the same for a graphic every time it renders.
    static func seed(_ name: String) -> UInt32 { name.utf8.reduce(2_166_136_261) { ($0 ^ UInt32($1)) &* 16_777_619 } }

    /// Covers every file in the folder, the words, the picture format and the runtime itself.
    static func hash(folder: URL, words: [String: String], sequence: DirectionCore.Sequence) throws -> String {
        var h = SHA256()
        h.update(data: Data("direction-graphic-1\n\(GraphicResources.version)\n\(sequence.width)x\(sequence.height)@\(sequence.frameRate.numerator)/\(sequence.frameRate.denominator)\n".utf8))
        for path in try GraphicResources.files(in: folder) {
            h.update(data: Data(path.utf8 + [0])); h.update(data: try Data(contentsOf: folder.appendingPathComponent(path))); h.update(data: Data([0]))
        }
        h.update(data: try JSONSerialization.data(withJSONObject: words, options: [.sortedKeys]))
        return h.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func registered(_ url: URL, hash: String, frames: Int, sequence: DirectionCore.Sequence) async throws -> GraphicRender {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let asset = try await MediaInspector.inspect(url: url)
        return GraphicRender(path: url.standardizedFileURL.resolvingSymlinksInPath().path, hash: hash, duration: asset.duration, width: sequence.width, height: sequence.height, frameRate: sequence.frameRate, frames: frames,
                             fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
    }

    /// The cut under the graphic at each still: where it's placed, else the note's moment. The graphic
    /// itself is left out, so the check sees what the words sit on.
    static func pictureBehind(store: ProjectStore, project: Project, sequence: DirectionCore.Sequence, graphic: Graphic?, noteID: String?, times: [Double], cacheDirectory: URL) async -> (images: [CGImage?], note: String) {
        let none = [CGImage?](repeating: nil, count: times.count)
        var start: Double?
        if let id = graphic?.assetID, let clip = sequence.clips.first(where: { $0.assetID == id }) { start = clip.start.seconds - clip.sourceRange.start.seconds }
        else if let noteID, let note = try? store.comment(noteID) { start = note.range?.start.seconds ?? note.time?.seconds }
        guard let start else { return (none, "Contrast against the picture wasn\u{2019}t checked: the graphic isn\u{2019}t placed and its note has no moment. Text on its own backing was checked.") }
        var p = project
        if let id = graphic?.assetID, let i = p.sequences.firstIndex(where: { $0.id == sequence.id }) { p.sequences[i].clips.removeAll { $0.assetID == id } }
        do {
            let compiled = try await SequenceRenderer.compile(project: p, sequenceID: sequence.id, cacheDirectory: cacheDirectory, previewMaxDimension: 960)
            let duration = compiled.sequence.duration.seconds
            var images: [CGImage?] = []
            for t in times {
                let at = min(max(0, start + t), max(0, duration - 0.05))
                let url = cacheDirectory.appendingPathComponent("Graphics").appendingPathComponent("behind-\(UUID().uuidString).png")
                _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: at), to: url, maxDimension: 960)
                images.append(GraphicChecks.loadImage(url)); try? FileManager.default.removeItem(at: url)
            }
            return (images, "Contrast checked against the cut from \(GraphicTime.text(start)).")
        } catch {
            return (none, "Contrast against the picture wasn\u{2019}t checked: \(error.localizedDescription) Text on its own backing was checked.")
        }
    }
}

enum GraphicTime {
    /// "00:02:00": minutes, seconds, frames at 24.
    static func text(_ seconds: Double) -> String {
        let s = max(0, seconds), whole = Int(s)
        return String(format: "%02d:%02d:%02d", whole / 60, whole % 60, Int(((s - Double(whole)) * 24).rounded(.down)))
    }
}

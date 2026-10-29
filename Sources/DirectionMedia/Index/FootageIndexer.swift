import Foundation
import CoreGraphics
import DirectionCore

/// Looking at footage, take by take in the order the takes will be logged (footage-index.md ›
/// What runs when footage comes in). Shots, keyframes, the contact sheet, sounds and words come
/// first for every take, so the editor can log a take as soon as its shots exist; descriptions
/// follow behind, take by take, and each take's search rows are remade when its lines arrive.
public enum FootageIndexer {
    public struct Progress: Sendable {
        /// "Finding shots", "Describing", "Downloading Qwen3-VL 8B · 42%".
        public var step: String
        /// Takes finished (everything that can run has run).
        public var done: Int
        public var total: Int
        public var fraction: Double
    }

    public struct Options: Sendable {
        public var cacheDirectory: URL
        /// Look again at takes already done.
        public var force = false
        public var describer: (any ShotDescriber)?
        /// Why there's no describer, recorded on each take.
        public var describeSkipped: String?
        /// The local version to download before describing, if it isn't yet.
        public var download: SharedSettings.LookDetail?
        public init(cacheDirectory: URL, force: Bool = false, describer: (any ShotDescriber)? = nil, describeSkipped: String? = nil, download: SharedSettings.LookDetail? = nil) {
            self.cacheDirectory = cacheDirectory; self.force = force; self.describer = describer; self.describeSkipped = describeSkipped; self.download = download
        }
    }

    // MARK: The engine the director chose

    /// Tests look without describing, or with a stand-in, without touching Settings or the keychain.
    nonisolated(unsafe) public static var describerOverride: (@Sendable () -> (describer: (any ShotDescriber)?, skipped: String?, download: SharedSettings.LookDetail?))?

    /// Settings › Footage decides; the editor never does. Nothing is described when the chosen
    /// engine isn't ready, and nothing falls back to another engine (footage stays on this Mac).
    public static func chosenDescriber() -> (describer: (any ShotDescriber)?, skipped: String?, download: SharedSettings.LookDetail?) {
        if let override = describerOverride { return override() }
        if SharedSettings.lookOverride == "none" { return (nil, "Descriptions are off for this process.", nil) }
        switch SharedSettings.lookEngine {
        case .thisMac:
            let detail = SharedSettings.lookDetail
            switch VisionHelper.status(detail) {
            case .noPython: return (nil, "mlx-vlm isn't installed. Install it in Terminal with uv tool install mlx-vlm.", nil)
            case .needsMemory: return (nil, "\(detail.name) needs \(detail.minimumMemory >> 30) GB of memory or more.", nil)
            case .notDownloaded:
                guard VisionHelper.hasRoom(for: detail) else {
                    return (nil, "Only \(ByteCountFormatter.string(fromByteCount: VisionHelper.freeBytes(), countStyle: .file)) free on \(VisionHelper.volumeName()). \(detail.name) needs \(ByteCountFormatter.string(fromByteCount: detail.bytes, countStyle: .file)).", nil)
                }
                return (LocalDescriber(repo: detail.repo), nil, detail)
            case .downloaded: return (LocalDescriber(repo: detail.repo), nil, nil)
            }
        case .openRouter:
            guard OpenRouter.Key.read() != nil else { return (nil, "Add an OpenRouter key in Settings › Services.", nil) }
            return (OpenRouterDescriber(version: SharedSettings.lookOpenRouterVersion), nil, nil)
        }
    }

    // MARK: A whole film

    /// Indexes every take that needs it (or `assetIDs`), then picks up footage that arrived meanwhile.
    public static func run(store: ProjectStore, assetIDs: [String]? = nil, options: Options, report: @escaping @Sendable (Progress) -> Void) async throws -> JSONValue {
        var handled = Set<String>(), summary = Summary()
        var options = options
        if let detail = options.download {
            do {
                try await VisionHelper.download(detail) { f in report(Progress(step: "Downloading \(detail.name) \u{00B7} \(Int(f * 100))%", done: 0, total: 0, fraction: 0)) }
            } catch is CancellationError { throw CancellationError() }
            catch { options.describer = nil; options.describeSkipped = error.localizedDescription }
        }
        defer { if let d = options.describer { Task { await d.finish() } } }
        while true {
            let todo = try pending(store: store, assetIDs: assetIDs, force: options.force, engine: options.describer?.engine).filter { !handled.contains($0.id) }
            guard !todo.isEmpty else { break }
            handled.formUnion(todo.map(\.id))
            try await runBatch(todo, store: store, options: options, total: handled.count, offset: handled.count - todo.count, summary: &summary, report: report)
            if assetIDs != nil { break }
        }
        try refreshWords(store: store)
        return summary.json(engine: options.describer?.engine, skipped: options.describeSkipped)
    }

    struct Summary {
        var takes = 0, shots = 0, described = 0, sounds = 0, failed = 0
        func json(engine: String?, skipped: String?) -> JSONValue {
            .object(["takes": .number(Double(takes)), "shots": .number(Double(shots)), "described": .number(Double(described)), "sounds": .number(Double(sounds)), "failed": .number(Double(failed)),
                     "engine": engine.map(JSONValue.string) ?? .null, "descriptionsSkipped": skipped.map(JSONValue.string) ?? .null])
        }
    }

    /// Takes that need looking at, in footage order: new, changed, failed, or done but undescribed
    /// now that `engine` can describe them. A failed take is retried only when asked by name.
    public static func pending(store: ProjectStore, assetIDs: [String]?, force: Bool, engine: String?) throws -> [MediaAsset] {
        let assets = try store.read().assets, index = try store.indexTakes()
        return assets.filter { a in
            if let ids = assetIDs, !ids.contains(a.id) { return false }
            guard !a.isImage else { return false }
            guard let t = index[a.id] else { return true }
            if force || t.fingerprint != TakeIndex.fingerprint(a) { return true }
            switch t.state {
            case .waiting, .looking: return true
            case .failed: return assetIDs != nil
            case .done: return !a.video.isEmpty && t.needsDescriptions(by: engine)
            }
        }
    }

    private static func runBatch(_ todo: [MediaAsset], store: ProjectStore, options: Options, total: Int, offset: Int, summary: inout Summary, report: @escaping @Sendable (Progress) -> Void) async throws {
        let counter = Counter(done: offset)
        let describer = options.describer
        // Shots first for every take; each finished take is handed to the describer behind it.
        let (ready, feed) = AsyncStream<String>.makeStream()
        let first = Task { () throws -> [String: TakeIndex] in
            var out: [String: TakeIndex] = [:]
            for (i, asset) in todo.enumerated() {
                try Task.checkCancellation()
                report(Progress(step: "Finding shots", done: counter.value, total: total, fraction: Double(offset + i) / Double(max(1, total))))
                do {
                    var t = try await lookAt(asset, store: store, options: options)
                    if describer == nil { t.state = .done; t.step = nil; try store.saveTakeIndex(t, summary: "Looked at \(asset.name)"); counter.add() }
                    out[asset.id] = t
                    feed.yield(asset.id)
                } catch is CancellationError { feed.finish(); throw CancellationError() }
                catch {
                    if Task.isCancelled { feed.finish(); throw CancellationError() }
                    try? fail(asset, error, store: store); counter.add()
                }
            }
            feed.finish()
            return out
        }
        var described = 0
        if let describer {
            // A describer that can't run (the helper won't load, the key is refused) skips
            // descriptions; the take's shots, sheet and sounds still stand.
            var broken: String?
            for await id in ready {
                try Task.checkCancellation()
                guard let asset = todo.first(where: { $0.id == id }) else { continue }
                report(Progress(step: "Looking at footage", done: counter.value, total: total, fraction: Double(counter.value) / Double(max(1, total))))
                if let broken { try? skip(asset, broken, store: store) }
                else {
                    do { described += try await describe(asset, store: store, describer: describer, options: options) }
                    catch is CancellationError { first.cancel(); throw CancellationError() }
                    catch {
                        if Task.isCancelled { first.cancel(); throw CancellationError() }
                        if let e = error as? DirectionError, ["vision_helper_failed", "vision_helper_missing", "mlx_vlm_missing", "no_openrouter_key"].contains(e.code) || e.message.contains("(401)") { broken = e.message }
                        try? skip(asset, error.localizedDescription, store: store)
                    }
                }
                counter.add()
            }
        }
        let looked = try await first.value
        let index = try store.indexTakes()
        summary.takes += todo.count
        summary.shots += looked.values.reduce(0) { $0 + $1.shotCount }
        summary.described += described
        summary.sounds += try todo.reduce(0) { $0 + (try store.sounds(assetID: $1.id).count) }
        summary.failed += todo.filter { index[$0.id]?.state == .failed }.count
        report(Progress(step: "Looking at footage", done: counter.value, total: total, fraction: 1))
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var n: Int
        init(done: Int) { n = done }
        var value: Int { lock.withLock { n } }
        func add() { lock.withLock { n += 1 } }
    }

    /// Done without (some) descriptions, and why. The next job tries again.
    private static func skip(_ asset: MediaAsset, _ reason: String, store: ProjectStore) throws {
        guard var t = try store.takeIndex(asset.id) else { return }
        t.state = .done; t.step = nil; t.describeSkipped = reason
        t.described = try store.shots(assetID: asset.id).filter { $0.look != nil }.count
        try store.saveTakeIndex(t, summary: "Looked at \(asset.name)")
    }

    private static func fail(_ asset: MediaAsset, _ error: Error, store: ProjectStore) throws {
        var t = try store.takeIndex(asset.id) ?? TakeIndex(assetID: asset.id, state: .failed, fingerprint: TakeIndex.fingerprint(asset))
        t.state = .failed; t.step = nil; t.error = error.localizedDescription
        try store.saveTakeIndex(t, summary: "Couldn't look at \(asset.name)")
    }

    // MARK: One take, first pass

    /// Shots, keyframes, the contact sheet, sounds and words. Leaves the take `looking` until
    /// it's described (or `done` when there's nothing to describe with).
    public static func lookAt(_ asset: MediaAsset, store: ProjectStore, options: Options) async throws -> TakeIndex {
        var t = TakeIndex(assetID: asset.id, state: .looking, fingerprint: TakeIndex.fingerprint(asset))
        // A take already looked at whose file hasn't changed only needs describing.
        if let old = try store.takeIndex(asset.id), !options.force, old.fingerprint == t.fingerprint, old.firstPassDone {
            t = old; t.state = .looking; t.error = nil
            t.step = options.describer == nil ? nil : "describing"
            t.describeSkipped = options.describer == nil ? options.describeSkipped : nil
            try store.saveTakeIndex(t)
            return t
        }
        t.step = "shots"; try store.saveTakeIndex(t, summary: "Finding shots in \(asset.name)")
        let folder = store.indexFolder.appendingPathComponent("Keyframes").appendingPathComponent(asset.id)
        try? FileManager.default.removeItem(at: folder)
        var shots: [Shot] = [], prints: [String: [Float]] = [:]
        if !asset.video.isEmpty {
            let found = try await ShotDetector.detect(asset)
            for (i, r) in found.ranges.enumerated() {
                var shot = Shot(assetID: asset.id, number: i + 1, start: r.lowerBound, end: r.upperBound)
                // The middle sample's print stands for the shot in "more like this".
                if let s = found.samples.min(by: { abs($0.time - shot.middle) < abs($1.time - shot.middle) }) { prints[shot.id] = s.print }
                let images = try await SourceFrames.images(asset, at: keyframeTimes(shot), maxDimension: 672)
                for (k, image) in images.enumerated() {
                    let small = folder.appendingPathComponent("\(shot.number)-\(k + 1).jpg")
                    try SourceFrames.writeJPEG(SourceFrames.scaled(image, maxDimension: 320), to: small, quality: 0.75)
                    shot.keyframes.append(small.path)
                    if options.describer != nil { try SourceFrames.writeJPEG(image, to: describeFrame(shot, k, options), quality: 0.85) }
                }
                shots.append(shot)
            }
        } else if asset.duration.seconds > 0 {
            // Sound only: one stretch, so its sounds and words still have a shot to live on.
            shots = [Shot(assetID: asset.id, number: 1, start: 0, end: asset.duration.seconds)]
        }
        try store.replaceShots(assetID: asset.id, shots, prints: prints)
        t.shotCount = shots.count

        if !asset.video.isEmpty {
            t.step = "sheet"; try store.saveTakeIndex(t)
            let sheet = store.indexFolder.appendingPathComponent("\(asset.id).jpg")
            let layout = try await ContactSheet.render(asset, frames: 16, to: sheet)
            t.contactSheet = sheet.path; t.sheetTimes = layout.times
        }

        t.step = "sounds"; try store.saveTakeIndex(t)
        if !asset.audio.isEmpty {
            do {
                let (sounds, loudness) = try await SoundIndexer.analyze(asset, cacheDirectory: options.cacheDirectory.appendingPathComponent("Audio"))
                try store.replaceSounds(assetID: asset.id, sounds); t.loudness = loudness
            } catch is CancellationError { throw CancellationError() }
            catch { try store.replaceSounds(assetID: asset.id, []) }
        } else { try store.replaceSounds(assetID: asset.id, []) }

        t.step = "search"; try store.saveTakeIndex(t)
        let transcripts = try store.transcripts().filter { $0.assetID == asset.id }
        try store.replaceSearchRows(assetID: asset.id, searchRows(shots: shots, transcripts: transcripts))
        t.wordsFingerprint = TakeIndex.wordsFingerprint(transcripts)
        t.firstPassDone = true
        t.describeSkipped = options.describer == nil ? options.describeSkipped : nil
        t.step = options.describer == nil ? nil : "describing"
        try store.saveTakeIndex(t, summary: "Found \(shots.count) shots in \(asset.name)")
        return t
    }

    /// 10%, 50% and 90% of a shot.
    public static func keyframeTimes(_ shot: Shot) -> [Double] { [0.1, 0.5, 0.9].map { shot.start + $0 * shot.duration } }

    static func describeFrame(_ shot: Shot, _ k: Int, _ options: Options) -> URL {
        options.cacheDirectory.appendingPathComponent("IndexFrames").appendingPathComponent(shot.assetID).appendingPathComponent("\(shot.number)-\(k + 1).jpg")
    }

    // MARK: One take, descriptions

    /// Describes every shot without a look. Returns how many it described.
    @discardableResult
    public static func describe(_ asset: MediaAsset, store: ProjectStore, describer: any ShotDescriber, options: Options) async throws -> Int {
        var t = try store.takeIndex(asset.id) ?? TakeIndex(assetID: asset.id, state: .looking, fingerprint: TakeIndex.fingerprint(asset))
        let shots = try store.shots(assetID: asset.id)
        let todo = asset.video.isEmpty ? [] : shots.filter { $0.look == nil }
        t.state = .looking; t.step = "describing"; t.engine = describer.engine
        try store.saveTakeIndex(t, summary: "Looking at \(asset.name)")
        let lines = transcriptLines(try store.transcripts().filter { $0.assetID == asset.id })
        let frames = options.cacheDirectory.appendingPathComponent("IndexFrames").appendingPathComponent(asset.id)
        defer { try? FileManager.default.removeItem(at: frames) }
        let cents = SpendBox()
        var count = 0
        try await withThrowingTaskGroup(of: Shot?.self) { group in
            var queue = todo[...]
            func add() {
                guard let shot = queue.popFirst() else { return }
                group.addTask {
                    var paths = (0..<3).map { describeFrame(shot, $0, options) }
                    if !paths.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                        let images = try await SourceFrames.images(asset, at: keyframeTimes(shot), maxDimension: 672)
                        for (k, image) in images.enumerated() { try SourceFrames.writeJPEG(image, to: paths[k], quality: 0.85) }
                        paths = (0..<images.count).map { describeFrame(shot, $0, options) }
                    }
                    let words = lines.filter { $0.start >= shot.start - 0.2 && $0.start < shot.end }.map(\.text).joined(separator: " ")
                    do {
                        let result = try await describer.describe(DescribeRequest(images: paths, words: words))
                        if let s = result.spend { cents.add(s) }
                        var described = shot; described.look = result.look; described.engine = describer.engine
                        return described
                    } catch is CancellationError { throw CancellationError() }
                    catch let e as DirectionError where e.code == "description_invalid" { return nil }
                }
            }
            for _ in 0..<max(1, describer.concurrency) { add() }
            while let result = try await group.next() {
                if let shot = result { try store.updateShot(shot); count += 1 }
                add()
            }
        }
        let all = try store.shots(assetID: asset.id)
        try store.replaceSearchRows(assetID: asset.id, searchRows(shots: all, transcripts: try store.transcripts().filter { $0.assetID == asset.id }))
        t = try store.takeIndex(asset.id) ?? t
        t.described = all.filter { $0.look != nil }.count
        t.state = .done; t.step = nil; t.describeSkipped = nil; t.error = nil; t.triedEngine = describer.engine
        if cents.total > 0 { t.spend = (t.spend ?? 0) + cents.total }
        try store.saveTakeIndex(t, summary: "Looked at \(asset.name)")
        return count
    }

    final class SpendBox: @unchecked Sendable {
        private let lock = NSLock(); private var sum = 0.0
        func add(_ v: Double) { lock.withLock { sum += v } }
        var total: Double { lock.withLock { sum } }
    }

    // MARK: Words

    public struct Line: Sendable, Equatable { public var start: Double; public var end: Double; public var text: String }

    /// A take's dialogue as sentences: split at end punctuation or a pause over 1.2 s.
    public static func transcriptLines(_ transcripts: [SourceTranscript]) -> [Line] {
        guard let t = transcripts.max(by: { ($0.selectedAt ?? 0, $0.words.count) < ($1.selectedAt ?? 0, $1.words.count) }) else { return [] }
        var out: [Line] = [], current: [TranscriptWord] = []
        func flush() {
            guard let a = current.first, let b = current.last else { return }
            out.append(Line(start: a.range.start.seconds, end: b.range.end.seconds, text: current.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)))
            current = []
        }
        for w in t.words.sorted(by: { $0.range.start < $1.range.start }) {
            if let last = current.last, w.range.start.seconds - last.range.end.seconds > 1.2 { flush() }
            current.append(w)
            if let c = w.text.last, ".?!\u{2026}".contains(c) { flush() }
        }
        flush()
        return out
    }

    /// Search rows: each shot's description (with what's in it) and each line of dialogue, placed
    /// in the shot it starts in. Vectors come from Apple's sentence embeddings.
    public static func searchRows(shots: [Shot], transcripts: [SourceTranscript]) -> [IndexSearchRow] {
        var rows: [IndexSearchRow] = []
        for s in shots {
            guard let look = s.look else { continue }
            let extra = ([look.setting].compactMap { $0 } + look.people + [look.size, look.movement].compactMap { $0 } + look.flags).joined(separator: ", ")
            rows.append(IndexSearchRow(shotID: s.id, assetID: s.assetID, kind: .picture, text: look.description + (extra.isEmpty ? "" : " (\(extra))"), start: s.start, vector: FootageSearch.vector(look.description)))
        }
        for line in transcriptLines(transcripts) {
            guard let shot = shots.last(where: { $0.start <= line.start + 0.001 }) ?? shots.first else { continue }
            rows.append(IndexSearchRow(shotID: shot.id, assetID: shot.assetID, kind: .words, text: line.text, start: line.start, vector: FootageSearch.vector(line.text)))
        }
        return rows
    }

    /// Remakes search rows for takes whose transcript changed since they were looked at.
    /// Cheap when nothing changed; search calls it first so new words are found at once.
    public static func refreshWords(store: ProjectStore) throws {
        let index = try store.indexTakes()
        guard !index.isEmpty else { return }
        let byAsset = Dictionary(grouping: try store.transcripts(), by: \.assetID)
        for (id, var t) in index where t.shotCount > 0 && t.step != "shots" {
            let transcripts = byAsset[id] ?? []
            let fp = TakeIndex.wordsFingerprint(transcripts)
            guard fp != (t.wordsFingerprint ?? "") else { continue }
            try store.replaceSearchRows(assetID: id, searchRows(shots: try store.shots(assetID: id), transcripts: transcripts))
            t.wordsFingerprint = fp
            try store.saveTakeIndex(t, summary: "Made new words searchable")
        }
    }
}

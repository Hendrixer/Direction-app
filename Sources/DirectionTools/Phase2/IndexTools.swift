import Foundation
import Darwin
import CoreGraphics
import ImageIO
import DirectionCore
import DirectionMedia

// Looking at footage (specs/footage-index.md). Direction indexes footage itself, the same way every
// time; the editor reads the result and looks at real frames when it needs to.
extension ToolCatalog {
    static var indexDefinitions: [ToolDefinition] {
        let range = record(["start": number, "end": number], required: ["start", "end"])
        return [
            definition("direction_index", "Look at footage: find every shot, make each take's contact sheet, note the sounds, describe each shot and make it all searchable. Runs as a job (poll direction_job) at background priority, take by take in footage order; it starts by itself when footage arrives if Settings › Engines says so. How shots are described is the director's choice in Settings, not yours. assetIDs limits it to those takes (and retries failed ones); force looks again from scratch; cancel stops this process's index job. Returns the job and each state's count.", ["assetIDs": list(string), "force": bool, "cancel": bool], readOnly: false),
            definition("direction_shots", "Read the shots Direction found, in take order: source range (seconds and timecode), description, size, movement, people (what's visible, never names: map them to names yourself), setting, flags, the sounds in the shot, the gist of any text on screen (onScreen; direction_screen_text has all of it, with times), and small keyframe paths (10%, 50%, 90%). Filter by assetID or sceneID; page with offset and limit. Each take's index state is waiting, looking, done or failed. Log takes from these before watching anything.", ["assetID": string, "sceneID": string, "offset": integer, "limit": integer]),
            definition("direction_contact_sheet", "One image of a take: frames (4–36, default 16) evenly across it, or across range {start,end} in source seconds, each labeled with its source timecode, plus the time of each cell. Use it to see a whole take at a glance, then direction_frame with assetID and time for a real frame.", ["assetID": string, "range": range, "frames": integer], required: ["assetID"]),
            definition("direction_watch", "The closest thing to watching: a filmstrip of a passage of the cut, start to end in cut seconds (at revision, default the current edit), frames 8–24 (default 12), with timecodes, the words spoken in it, the sounds, and where the cuts fall. Watch every passage you changed before delivering a cut: changed: true (instead of start and end) watches each passage the open notes turnover changed that you haven't watched since, a filmstrip each (8 frames unless frames says), up to 8 in one call.", ["start": number, "end": number, "revision": integer, "sequenceID": string, "frames": integer, "changed": bool, "turnoverID": string]),
            definition("direction_screen_text", "Read the text on screen in a take over time (a screen recording, slides, a whiteboard, a sign), read by Apple's text recognition on this Mac when the footage was looked at: each stretch with its source range and its lines, top to bottom. A stretch spanning the whole shot is text that stayed on screen throughout (a window title, a slide's heading). range {start, end} in source seconds keeps the stretches that overlap it. Use it to cut to a screen recording when it shows what's being said, and to caption screen recordings by what they show.", ["assetID": string, "range": range], required: ["assetID"]),
            definition("direction_search_footage", "Search footage by what's in it (\"Maya laughing\", \"wide of the ridge at dusk\", \"the pricing slide\"): ranks shots by the meaning of their descriptions, lines and text on screen blended with exact words (0.6 meaning, 0.4 words), best shot per take first, with a score, why it matched (picture, words, both, or screen: text read off the picture, and then start–end is when that text is on screen), the matching text and keyframe paths. similarTo: a shotID ranks by how alike the pictures are instead. wordsOnly searches the transcripts alone. Runs on this Mac; the query never leaves it.", ["query": string, "sceneID": string, "circledOnly": bool, "wordsOnly": bool, "similarTo": string, "limit": integer]),
        ]
    }
}

extension ToolRuntime {
    func invokeIndex(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_index":
            if a["cancel"].bool == true {
                let cancelled = IndexJobs.cancel(store.url.path)
                return ToolResponse(.object(["cancellationRequested": .bool(cancelled), "states": try stateCounts()]))
            }
            let ids = a["assetIDs"].array?.compactMap(\.string)
            if let ids { let p = try store.read(); for id in ids { _ = try p.asset(id) } }
            let job = try startIndexJob(assetIDs: ids, force: a["force"].bool ?? false)
            let (_, skipped, _) = FootageIndexer.chosenDescriber()
            return ToolResponse(.object(["job": try .wrapping(job), "states": try stateCounts(), "engine": .string(SharedSettings.lookEngine == .thisMac ? "This Mac · mlx-vlm · \(SharedSettings.lookDetail.name)" : "OpenRouter · \(SharedSettings.lookOpenRouterVersion)"), "descriptionsSkipped": skipped.map(JSONValue.string) ?? .null]))

        case "direction_shots":
            autoIndexIfNeeded()
            let p = try store.read(), dailies = try store.dailies(), states = try indexStates()
            var assetIDs = p.assets.map(\.id)
            if let id = a["assetID"].string { _ = try p.asset(id); assetIDs = [id] }
            if let scene = a["sceneID"].string {
                guard dailies.scenes.contains(where: { $0.id == scene }) else { throw DirectionError("scene_not_found", "Scene \(scene) isn't logged.") }
                assetIDs = assetIDs.filter { dailies.take($0).sceneID == scene }
            }
            let order = Dictionary(uniqueKeysWithValues: assetIDs.enumerated().map { ($1, $0) })
            let all = try store.shots().filter { order[$0.assetID] != nil }.sorted { (order[$0.assetID]!, $0.number) < (order[$1.assetID]!, $1.number) }
            let offset = max(0, a["offset"].int ?? 0), limit = min(500, max(1, a["limit"].int ?? 100))
            let page = Array(all.dropFirst(offset).prefix(limit))
            let sounds = Dictionary(grouping: try store.sounds(), by: \.assetID)
            let screen = Dictionary(grouping: try store.screenText(), by: \.shotID)
            let assets = Dictionary(uniqueKeysWithValues: p.assets.map { ($0.id, $0) })
            let shots: [JSONValue] = page.map { s in shotJSON(s, asset: assets[s.assetID], dailies: dailies, sounds: sounds[s.assetID] ?? [], screen: screen[s.id] ?? []) }
            let takes: [JSONValue] = assetIDs.map { id in .object(["assetID": .string(id), "take": .string(label(id, dailies, assets)), "index": .string((states[id] ?? .waiting).rawValue)]) }
            let next = offset + page.count
            return ToolResponse(.object(["shots": .array(shots), "takes": .array(takes), "total": .number(Double(all.count)), "nextOffset": next < all.count ? .number(Double(next)) : .null]))

        case "direction_screen_text":
            autoIndexIfNeeded()
            let p = try store.read(), asset = try p.asset(a.requiredString("assetID"))
            var stretches = try store.screenText(assetID: asset.id)
            if a["range"] != .null {
                guard let s = a["range"]["start"].double, let e = a["range"]["end"].double, e > s else { throw DirectionError("invalid_range", "range is {start, end} in source seconds inside the take.") }
                stretches = stretches.filter { $0.end > s && $0.start < e }
            }
            let fps = asset.video.first?.frameRate ?? 24, index = try store.takeIndex(asset.id)
            let read = index.map { !FootageIndexer.needsScreenText($0) && $0.state == .done } ?? false
            let note: String = asset.video.isEmpty ? "\(asset.name) has no picture." : !read ? "Direction hasn\u{2019}t read this take\u{2019}s screen yet; it does when it looks at the footage." : stretches.isEmpty ? "No text on screen." : "Lines read top to bottom; a stretch spanning the shot stayed on screen throughout."
            let items: [JSONValue] = stretches.map { t in
                .object(["shotID": .string(t.shotID), "start": .number((t.start * 1000).rounded() / 1000), "end": .number((t.end * 1000).rounded() / 1000), "range": .string(SourceTimecode.range(t.start, t.end, fps: fps)), "lines": .array(t.lines.map(JSONValue.string))])
            }
            return ToolResponse(.object(["assetID": .string(asset.id), "take": .string(label(asset.id, try store.dailies(), [asset.id: asset])), "read": .bool(read), "stretches": .array(items), "note": .string(note)]))

        case "direction_contact_sheet":
            let p = try store.read(), asset = try p.asset(a.requiredString("assetID"))
            guard !asset.video.isEmpty else { throw DirectionError("no_picture", "\(asset.name) has no picture.") }
            let frames = a["frames"].int ?? 16
            guard (4...36).contains(frames) else { throw DirectionError("invalid_arguments", "frames is 4–36.") }
            var range: ClosedRange<Double>?
            if a["range"] != .null {
                guard let s = a["range"]["start"].double, let e = a["range"]["end"].double, s >= 0, e > s, e <= asset.duration.seconds + 0.001 else { throw DirectionError("invalid_range", "range is {start, end} in source seconds inside the take.") }
                range = s...min(e, asset.duration.seconds)
            }
            let fps = asset.video.first?.frameRate ?? 24
            let index = try store.takeIndex(asset.id)
            let path: String, times: [Double], layout: ContactSheet.Layout
            if range == nil, frames == 16, let sheet = index?.contactSheet, FileManager.default.fileExists(atPath: sheet), index?.fingerprint == TakeIndex.fingerprint(asset), let t = index?.sheetTimes, t.count == 16 {
                path = sheet; times = t; layout = ContactSheet.layout(frames: 16, start: 0, end: asset.duration.seconds, aspect: ContactSheet.aspect(asset))
            } else {
                let output = cacheDirectory.appendingPathComponent("Sheets").appendingPathComponent(newID("sheet") + ".jpg")
                layout = try await ContactSheet.render(asset, frames: frames, range: range, to: output)
                path = output.path; times = layout.times
            }
            let cells: [JSONValue] = times.enumerated().map { i, t in .object(["cell": .number(Double(i + 1)), "time": .number((t * 1000).rounded() / 1000), "timecode": .string(SourceTimecode.format(t, fps: fps))]) }
            return ToolResponse(.object(["assetID": .string(asset.id), "take": .string(label(asset.id, try store.dailies(), [asset.id: asset])), "columns": .number(Double(layout.columns)), "rows": .number(Double(layout.rows)), "cells": .array(cells), "path": .string(path), "order": .string("Cells read left to right, top to bottom.")]), imagePaths: [try pngCopy(path)])

        case "direction_watch":
            if a["changed"].bool == true { return try await watchChanged(a) }
            return try await watch(a)

        case "direction_search_footage":
            autoIndexIfNeeded()
            try FootageIndexer.refreshWords(store: store)
            let dailies = try store.dailies(), p = try store.read(), states = try indexStates()
            let options = FootageSearch.Options(sceneID: a["sceneID"].string, circledOnly: a["circledOnly"].bool ?? false, wordsOnly: a["wordsOnly"].bool ?? false, limit: min(100, max(1, a["limit"].int ?? 12)))
            let hits: [FootageSearch.Hit]
            if let similar = a["similarTo"].string { hits = try FootageSearch.similar(to: similar, store: store, dailies: dailies, options: options) }
            else { hits = try FootageSearch.search(try a.requiredString("query"), store: store, dailies: dailies, options: options) }
            let assets = Dictionary(uniqueKeysWithValues: p.assets.map { ($0.id, $0) })
            let results: [JSONValue] = hits.map { h in
                let fps = assets[h.assetID]?.video.first?.frameRate ?? 24
                let t = dailies.take(h.assetID)
                return .object(["shotID": .string(h.shotID), "assetID": .string(h.assetID), "take": .string(label(h.assetID, dailies, assets)), "sceneID": t.sceneID.map(JSONValue.string) ?? .null, "circled": .bool(t.circled),
                                "score": .number(h.score), "why": .string(h.why.rawValue), "text": .string(h.text), "matched": .array(h.matched.map(JSONValue.string)),
                                "start": .number(h.start), "end": .number(h.end), "range": .string(SourceTimecode.range(h.start, h.end, fps: fps)), "keyframes": .array(h.keyframes.map(JSONValue.string))])
            }
            let still = p.footage(film: store.url).filter { !$0.isImage && states[$0.id] != .done && states[$0.id] != .failed }.count
            return ToolResponse(.object(["results": .array(results), "stillLooking": .number(Double(still))]))

        default: return nil
        }
    }

    // MARK: direction_frame with an assetID

    /// A real frame of a take at a source time, not of the cut. Called from the top of the
    /// `direction_frame` case.
    func sourceFrame(_ a: JSONValue) async throws -> ToolResponse {
        let asset = try store.read().asset(a.requiredString("assetID"))
        let output = cacheDirectory.appendingPathComponent("Frames").appendingPathComponent(newID("frame") + ".png")
        let value = try await SourceFrames.frame(asset, at: a["time"].double ?? 0, to: output, maxDimension: min(1920, max(160, a["maxDimension"].int ?? 1280)))
        return ToolResponse(value, imagePaths: [output.path])
    }

    // MARK: Watching

    /// Every passage the open notes turnover changed that hasn't been watched since: a filmstrip each, in one answer.
    private func watchChanged(_ a: JSONValue) async throws -> ToolResponse {
        guard let t = try a["turnoverID"].string.flatMap({ id in try store.turnovers().first { $0.id == id } }) ?? store.turnovers().last(where: { $0.kind == "notes" && $0.state.isOpen }) else {
            throw DirectionError("no_turnover", "There\u{2019}s no notes turnover open to watch the changes of. Give start and end to watch a passage.")
        }
        let passages = try unwatched(turnoverID: t.id)
        guard !passages.isEmpty else { return ToolResponse(.object(["passages": .array([]), "watched": .string("Every passage you changed is watched.")])) }
        let most = 8, duration = try store.read().sequence(a["sequenceID"].string).duration.seconds
        var out: [JSONValue] = [], images: [String] = []
        for p in passages.prefix(most) {
            var args: [String: JSONValue] = ["start": .number(max(0, p.start - 0.5)), "end": .number(min(duration, max(p.end + 0.5, p.start + 1))), "frames": .number(Double(a["frames"].int ?? 8))]
            if let s = a["sequenceID"].string { args["sequenceID"] = .string(s) }
            let r = try await watch(.object(args))
            out.append(r.value); images += r.imagePaths
        }
        var value: [String: JSONValue] = ["passages": .array(out)]
        if passages.count > most { value["more"] = .string("\(passages.count - most) more not watched yet: call again.") }
        return ToolResponse(.object(value), imagePaths: images)
    }

    private func watch(_ a: JSONValue) async throws -> ToolResponse {
        let p = try store.read(revision: a["revision"].int), sequence = try p.sequence(a["sequenceID"].string)
        guard let start = a["start"].double, let end = a["end"].double, start >= 0, end > start else { throw DirectionError("invalid_range", "Provide start and end in cut seconds, with 0 ≤ start < end.") }
        let duration = sequence.duration.seconds
        guard start < duration else { throw DirectionError("invalid_range", "start is past the end of the cut (\(String(format: "%.2f", duration)) s).") }
        let stop = min(end, duration)
        let frames = a["frames"].int ?? 12
        guard (8...24).contains(frames) else { throw DirectionError("invalid_arguments", "frames is 8–24.") }
        let fps = sequence.frameRate.value
        let layout = ContactSheet.layout(frames: frames, start: start, end: stop, aspect: Double(sequence.width) / Double(max(1, sequence.height)))
        // As the director sees it: camera LUTs and the look (direction_frame does the same).
        let compiled = try await SequenceRenderer.compile(project: p, sequenceID: sequence.id, cacheDirectory: cacheDirectory, previewMaxDimension: 960, looks: try? store.lookContext())
        let folder = cacheDirectory.appendingPathComponent("Watch").appendingPathComponent(newID("watch"))
        defer { try? FileManager.default.removeItem(at: folder) }
        var images: [CGImage?] = []
        for (i, t) in layout.times.enumerated() {
            let png = folder.appendingPathComponent("\(i).png")
            _ = try await SequenceRenderer.frame(compiled, at: MediaTime(seconds: t), to: png, maxDimension: Int(layout.cells[0].width))
            images.append(CGImageSourceCreateWithURL(png as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        }
        // Cuts: where any picture clip starts or ends inside the passage.
        let edges = Set(sequence.clips.filter { $0.kind != .audio }.flatMap { [$0.start.seconds, $0.end.seconds] }).filter { $0 > start + 0.001 && $0 < stop - 0.001 }.sorted()
        var marks = Set<Int>()
        for c in edges { if let i = layout.times.firstIndex(where: { $0 >= c }) { marks.insert(i) } }
        // Words and sounds, in cut time.
        let words = TranscriptEditing.words(in: sequence, transcripts: try store.transcripts()).filter { $0.range.end.seconds > start && $0.range.start.seconds < stop }.sorted { $0.range.start < $1.range.start }
        let text = words.map(\.text).joined(separator: " ")
        let sounds = Dictionary(grouping: try store.sounds(), by: \.assetID)
        var heard: [(Double, Double, SoundKind)] = []
        for clip in sequence.clips where clip.kind != .title {
            guard let id = clip.assetID, let list = sounds[id], clip.end.seconds > start, clip.start.seconds < stop else { continue }
            for s in list {
                let a = clip.sequenceTime(at: MediaTime(seconds: s.start)).seconds, b = clip.sequenceTime(at: MediaTime(seconds: s.end)).seconds
                let lo = max(a, clip.start.seconds, start), hi = min(b, clip.end.seconds, stop)
                if hi - lo > 0.05 { heard.append((lo, hi, s.kind)) }
            }
        }
        heard.sort { $0.0 < $1.0 }
        let footer = text.isEmpty ? "No words in this passage." : "\u{201C}\(text)\u{201D}"
        let image = try ContactSheet.draw(layout, images: images, labels: layout.times.map { SourceTimecode.format($0, fps: fps) }, marks: marks, footer: footer)
        let output = cacheDirectory.appendingPathComponent("Watch").appendingPathComponent(newID("watch") + ".png")
        try MediaInspector.writePNG(image, to: output)
        try store.recordWatched(revision: p.editRevision, start: start, end: stop)
        let cells: [JSONValue] = layout.times.enumerated().map { i, t in .object(["cell": .number(Double(i + 1)), "time": .number((t * 1000).rounded() / 1000), "timecode": .string(SourceTimecode.format(t, fps: fps)), "afterCut": .bool(marks.contains(i))]) }
        return ToolResponse(.object([
            "revision": .number(Double(p.editRevision)), "start": .number(start), "end": .number(stop), "range": .string("\(SourceTimecode.format(start, fps: fps))\u{2013}\(SourceTimecode.format(stop, fps: fps))"),
            "cells": .array(cells), "cuts": .array(edges.map { .object(["time": .number(($0 * 1000).rounded() / 1000), "timecode": .string(SourceTimecode.format($0, fps: fps))]) }),
            "words": .string(text), "sounds": .array(heard.map { .object(["start": .number(($0.0 * 100).rounded() / 100), "end": .number(($0.1 * 100).rounded() / 100), "kind": .string($0.2.rawValue)]) }),
            "path": .string(output.path), "watched": .bool(true),
        ]), imagePaths: [output.path])
    }

    /// MCP sends every image as PNG, so a JPEG sheet goes out as a PNG copy in the cache.
    private func pngCopy(_ jpeg: String) throws -> String {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: jpeg) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DirectionError("image_unreadable", "Couldn't read the contact sheet.") }
        let output = cacheDirectory.appendingPathComponent("Sheets").appendingPathComponent(newID("sheet") + ".png")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MediaInspector.writePNG(image, to: output)
        return output.path
    }

    // MARK: States

    /// Each take's index state. A take left `looking` with no live index job is `waiting` again.
    func indexStates() throws -> [String: IndexState] {
        let takes = try store.indexTakes(), live = try liveIndexJob() != nil
        var out: [String: IndexState] = [:]
        for a in try store.read().footage(film: store.url) where !a.isImage {
            guard let t = takes[a.id], t.fingerprint == TakeIndex.fingerprint(a) else { out[a.id] = live ? .looking : .waiting; continue }
            out[a.id] = t.state == .looking && !live ? .waiting : t.state
        }
        return out
    }
    private func stateCounts() throws -> JSONValue {
        let states = try indexStates()
        return .object(Dictionary(uniqueKeysWithValues: IndexState.allCases.map { s in (s.rawValue, JSONValue.number(Double(states.values.filter { $0 == s }.count))) }))
    }

    private func label(_ id: String, _ dailies: Dailies, _ assets: [String: MediaAsset]) -> String {
        let t = dailies.take(id)
        let parts = [t.setupCode, t.code].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (assets[id]?.name ?? id) : parts.joined(separator: " ")
    }

    private func shotJSON(_ s: Shot, asset: MediaAsset?, dailies: Dailies, sounds: [IndexSound], screen: [ScreenText] = []) -> JSONValue {
        let fps = asset?.video.first?.frameRate ?? 24
        let inShot = sounds.filter { $0.end > s.start && $0.start < s.end && $0.kind != .silence }
        var value: [String: JSONValue] = [
            "id": .string(s.id), "assetID": .string(s.assetID), "number": .number(Double(s.number)),
            "start": .number((s.start * 1000).rounded() / 1000), "end": .number((s.end * 1000).rounded() / 1000), "range": .string(SourceTimecode.range(s.start, s.end, fps: fps)),
            "keyframes": .array(s.keyframes.map(JSONValue.string)),
            "sounds": .array(inShot.map { .object(["kind": .string($0.kind.rawValue), "start": .number(($0.start * 100).rounded() / 100), "end": .number(($0.end * 100).rounded() / 100)]) }),
        ]
        if let look = s.look {
            value["description"] = .string(look.description); value["size"] = look.size.map(JSONValue.string) ?? .null; value["movement"] = look.movement.map(JSONValue.string) ?? .null
            value["people"] = .array(look.people.map(JSONValue.string)); value["setting"] = look.setting.map(JSONValue.string) ?? .null
            value["flags"] = .array(look.flags.map(JSONValue.string)); value["describedWith"] = s.engine.map(JSONValue.string) ?? .null
        } else {
            // Not described (yet): the same keys, empty, so every shot reads the same way.
            for key in ["description", "size", "movement", "setting", "describedWith"] { value[key] = .null }
            value["people"] = .array([]); value["flags"] = .array([])
        }
        value["onScreen"] = screen.isEmpty ? .null : .string(ScreenText.gist(screen, words: 24))
        return .object(value)
    }

    // MARK: The index job

    /// The running index job in any process, if there is one. A job this process owns but no
    /// longer runs (it was cancelled mid-write) is marked interrupted.
    func liveIndexJob() throws -> JobRecord? {
        guard var job = try store.jobs().first(where: { $0.kind == "index" && !$0.isTerminal }) else { return nil }
        if job.ownerPID == getpid() && IndexJobs.current(store.url.path) != job.id {
            job.status = "interrupted"; job.phase = "The index job stopped"; job.updatedAt = Date().timeIntervalSince1970
            try store.saveJob(job); return nil
        }
        return job
    }

    /// Starts looking at footage, or returns the job already doing it (here or in another process).
    func startIndexJob(assetIDs: [String]?, force: Bool) throws -> JobRecord {
        if let live = try liveIndexJob() { return live }
        let store = store, cache = cacheDirectory, key = store.url.path
        let now = Date().timeIntervalSince1970
        let job = JobRecord(id: newID("job"), kind: "index", revision: try store.revision(), ownerPID: getpid(), status: "running", phase: "Looking at footage", progress: 0, result: nil, error: nil, createdAt: now, updatedAt: now)
        try store.saveJob(job)
        let saver = JobProgress(job: job, store: store)
        let task = Task.detached(priority: .background) {
            var finished = job
            do {
                let (describer, skipped, download) = FootageIndexer.chosenDescriber()
                let options = FootageIndexer.Options(cacheDirectory: cache, force: force, describer: describer, describeSkipped: skipped, download: download)
                finished.result = try await FootageIndexer.run(store: store, assetIDs: assetIDs, options: options) { saver.report($0) }
                try Task.checkCancellation()
                finished.status = "completed"; finished.phase = "Completed"; finished.progress = 1
            } catch {
                finished.status = Task.isCancelled || error is CancellationError ? "cancelled" : "failed"
                finished.error = error.localizedDescription; finished.phase = finished.status == "cancelled" ? "Cancelled" : "Failed"
            }
            finished.updatedAt = Date().timeIntervalSince1970
            saver.stop()
            try? store.saveJob(finished)
            IndexJobs.finished(key, job.id)
        }
        IndexJobs.started(key, job.id, task)
        return job
    }

    /// Footage arrived and Settings › Engines says to look at it: start, at most every few seconds.
    func autoIndexIfNeeded() {
        guard SharedSettings.lookAutomatically, IndexJobs.mayAutoStart(store.url.path) else { return }
        do {
            guard try liveIndexJob() == nil, try !FootageIndexer.pending(store: store, assetIDs: nil, force: false, engine: nil).isEmpty else { return }
            _ = try startIndexJob(assetIDs: nil, force: false)
        } catch {}
    }
}

/// Index jobs this process runs, by film. Separate from the runtime's own job table so other
/// areas' jobs are untouched; `direction_index` with cancel stops one.
enum IndexJobs {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: [String: (id: String, task: Task<Void, Never>)] = [:]
    nonisolated(unsafe) private static var attempts: [String: Date] = [:]

    nonisolated(unsafe) private static var early: Set<String> = []
    /// A job can finish before it's registered (nothing to look at); it isn't registered then.
    static func started(_ key: String, _ id: String, _ task: Task<Void, Never>) { lock.withLock { if early.remove(id) == nil { running[key] = (id, task) } } }
    static func finished(_ key: String, _ id: String) { lock.withLock { if running[key]?.id == id { running[key] = nil } else { early.insert(id) } } }
    static func current(_ key: String) -> String? { lock.withLock { running[key]?.id } }
    static func cancel(_ key: String) -> Bool { lock.withLock { running[key]?.task.cancel(); return running[key] != nil } }
    /// Waits for the film's index job in this process (tests, and the CLI before it exits).
    static func wait(_ key: String) async { if let t = lock.withLock({ running[key]?.task }) { await t.value } }
    static func mayAutoStart(_ key: String) -> Bool {
        lock.withLock {
            if let last = attempts[key], Date().timeIntervalSince(last) < 5 { return false }
            attempts[key] = Date(); return true
        }
    }
}

/// Saves the job's phase and progress as the index reports it, at most twice a second.
final class JobProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var job: JobRecord
    private let store: ProjectStore
    private var lastSave = Date.distantPast
    private var stopped = false
    init(job: JobRecord, store: ProjectStore) { self.job = job; self.store = store }
    func report(_ p: FootageIndexer.Progress) {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        let phase = p.total > 0 ? "\(p.step) \u{00B7} \(p.done) of \(p.total)" : p.step
        let changed = phase != job.phase
        job.phase = phase; job.progress = p.fraction; job.updatedAt = Date().timeIntervalSince1970
        guard changed || Date().timeIntervalSince(lastSave) > 0.5 else { return }
        lastSave = Date()
        try? store.saveJob(job)
    }
    func stop() { lock.withLock { stopped = true } }
}

extension ToolRuntime {
    /// The app's own way in (Film › Look at Footage, Try again, new footage): the same job as
    /// `direction_index`, without passing through the editor's tool calls.
    @discardableResult
    public func lookAtFootage(assetIDs: [String]? = nil, force: Bool = false) throws -> JobRecord {
        try startIndexJob(assetIDs: assetIDs, force: force)
    }
    /// Stops this process's index job for the film, if it runs one.
    @discardableResult
    public func stopLooking() -> Bool { IndexJobs.cancel(store.url.path) }
    /// Test hook: waits until this process's index job for the bound film is finished.
    public func waitForIndex() async { await IndexJobs.wait(store.url.path) }
}

import Testing
import Foundation
import CoreGraphics
import ImageIO
import DirectionCore
import DirectionMedia
import DirectionTools

/// Looking at footage (specs/footage-index.md): shots, contact sheets, search, both engines.
/// Serialized: some tests swap the shared settings, the describer and OpenRouter's transport.
@Suite(.serialized)
struct IndexTests {
    // MARK: Fixtures

    static func temp(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("direction-index-\(name)-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A clip with hard cuts and a cut to black and back, from ffmpeg's test sources:
    /// testsrc 0–2, red 2–3.5, SMPTE bars 3.5–6, black 6–7, testsrc2 7–9 (24 fps, 320 × 180).
    static func cuts(in folder: URL, audio: Bool = false) throws -> URL? {
        guard let ffmpeg = WhisperTranscriber.ffmpeg() else { return nil }
        let out = folder.appendingPathComponent("cuts.mov")
        let parts = ["testsrc=size=320x180:rate=24:duration=2", "color=c=0xC03020:size=320x180:rate=24:duration=1.5", "smptebars=size=320x180:rate=24:duration=2.5", "color=c=black:size=320x180:rate=24:duration=1", "testsrc2=size=320x180:rate=24:duration=2"]
        var args = ["-y", "-loglevel", "error"]
        for p in parts { args += ["-f", "lavfi", "-i", p] }
        if audio { args += ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=9"] }
        let chain = (0..<parts.count).map { "[\($0):v]" }.joined() + "concat=n=\(parts.count):v=1:a=0,format=yuv420p[v]"
        args += ["-filter_complex", chain, "-map", "[v]"]
        if audio { args += ["-map", "\(parts.count):a", "-c:a", "aac"] }
        args += ["-c:v", "libx264", "-preset", "ultrafast", "-g", "12", out.path]
        let p = Process(); p.executableURL = ffmpeg; p.arguments = args
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw DirectionError("fixture_failed", "ffmpeg couldn't make the test clip.") }
        return out
    }

    static func project(_ folder: URL) throws -> (ProjectStore, ToolRuntime) {
        let store = try ProjectStore.create(at: folder.appendingPathComponent("Index.direction"), name: "Index fixture")
        return (store, try ToolRuntime(store: store))
    }

    // MARK: Shots

    @Test func boundariesArePeaksAboveThresholdOrFadesAndShotsLastHalfASecond() {
        let times = stride(from: 0.0, to: 5, by: 0.25).map { $0 }
        var d = [Float](repeating: 0.05, count: times.count), luma = [Double](repeating: 0.5, count: times.count)
        d[1] = 0.8                   // 0.25 s: a peak, but the first shot would be too short
        d[4] = 0.9                   // 1.0 s: a hard cut
        d[5] = 0.6                   // its tail: not a peak
        d[6] = 0.7; d[7] = 0.7       // 1.5 s: a plateau peak 0.5 s on (allowed); 1.75 s too close
        d[12] = 0.3                  // 3.0 s: under the threshold
        for i in 14..<times.count { luma[i] = 0.01 }   // 3.5 s: a fade to black
        d[19] = 1.2                  // 4.75 s: too close to the end
        let cuts = ShotDetector.boundaries(times: times, distances: d, luma: luma, duration: 5)
        #expect(cuts.map { times[$0] } == [1.0, 1.5, 3.5])
        // A cut and a fade closer than 0.5 s keep the stronger one: the fade.
        var close = [Float](repeating: 0.05, count: times.count), dark = [Double](repeating: 0.5, count: times.count)
        close[4] = 0.9
        for i in 5..<times.count { dark[i] = 0.02 }
        #expect(ShotDetector.boundaries(times: times, distances: close, luma: dark, duration: 5).map { times[$0] } == [1.25])
    }

    @Test func findsHardCutsAndFadesInARealClip() async throws {
        let folder = try Self.temp("shots"); defer { try? FileManager.default.removeItem(at: folder) }
        guard let clip = try Self.cuts(in: folder) else { return }
        let asset = try await MediaInspector.inspect(url: clip)
        let result = try await ShotDetector.detect(asset)
        let cuts = result.ranges.dropFirst().map(\.lowerBound)
        let expected = [2.0, 3.5, 6.0, 7.0]
        #expect(cuts.count == expected.count, "cuts: \(cuts)")
        for (found, want) in zip(cuts, expected) { #expect(abs(found - want) <= 1.0 / 24 + 0.001, "cut at \(found), expected \(want)") }
        #expect(abs((result.ranges.last?.upperBound ?? 0) - 9) < 0.05)
        #expect(result.samples.count == 36)
    }

    // MARK: Contact sheets

    @Test func contactSheetIsAFourByFourGrid1600WideWithCenteredTimes() {
        let l = ContactSheet.layout(frames: 16, start: 0, end: 46, aspect: 16 / 9)
        #expect(l.columns == 4 && l.rows == 4 && l.width == 1600)
        #expect(l.cells.count == 16)
        #expect(l.cells[0].width == 390 && l.cells[0].height == 219)
        #expect(l.height == Int(8 * 2 + 219 * 4 + 8 * 3))
        // Row 0 is at the top of the image (CoreGraphics counts from the bottom).
        #expect(l.cells[0].maxY == Double(l.height) - 8 && l.cells[12].minY == 8)
        #expect(l.cells[1].minX == 406.0)
        #expect(abs(l.times[0] - 46.0 / 32) < 1e-9 && abs(l.times[15] - (46 - 46.0 / 32)) < 1e-9)
        #expect(ContactSheet.layout(frames: 36, start: 0, end: 10, aspect: 1.78).columns == 6)
        #expect(ContactSheet.layout(frames: 12, start: 0, end: 10, aspect: 1.78).rows == 3)
        #expect(ContactSheet.layout(frames: 4, start: 0, end: 10, aspect: 1.78).columns == 2)
        let ranged = ContactSheet.layout(frames: 4, start: 10, end: 14, aspect: 1.78)
        #expect(ranged.times == [10.5, 11.5, 12.5, 13.5])
    }

    @Test func rendersARealSheetAndShotsThroughTheTools() async throws {
        let folder = try Self.temp("sheet"); defer { try? FileManager.default.removeItem(at: folder) }
        guard let clip = try Self.cuts(in: folder, audio: true) else { return }
        let real = SharedSettings.defaults, suite = "dev.direction.tests.\(UUID().uuidString)"
        SharedSettings.defaults = UserDefaults(suiteName: suite)!
        defer { SharedSettings.defaults.removePersistentDomain(forName: suite); SharedSettings.defaults = real }
        SharedSettings.defaults.set(false, forKey: SharedSettings.IndexKey.automatic)
        // Nothing to describe with: an engine that isn't set up skips descriptions, never anything else.
        FootageIndexer.describerOverride = { (nil, "mlx-vlm isn't installed.", nil) }
        defer { FootageIndexer.describerOverride = nil }
        let (store, runtime) = try Self.project(folder)
        let imported = try await runtime.invoke("direction_import", arguments: .object(["path": .string(clip.path)]))
        let id = try #require(imported.value["asset"]["id"].string)
        let started = try await runtime.invoke("direction_index", arguments: .object(["assetIDs": .array([.string(id)])]))
        let jobID = try #require(started.value["job"]["id"].string)
        _ = try await runtime.waitForJob(jobID)
        let take = try #require(try store.takeIndex(id))
        #expect(take.state == .done && take.shotCount == 5)
        #expect(take.describeSkipped != nil)
        let sheetPath = try #require(take.contactSheet)
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: sheetPath) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1600 && image.height == ContactSheet.layout(frames: 16, start: 0, end: 9, aspect: 16 / 9).height)
        #expect(sheetPath.hasPrefix(store.indexFolder.path))

        let shots = try await runtime.invoke("direction_shots", arguments: .object(["assetID": .string(id)]))
        #expect(shots.value["shots"].array?.count == 5)
        #expect(shots.value["takes"].array?.first?["index"].string == "done")
        let first = try #require(shots.value["shots"].array?.first)
        #expect(first["range"].string == "00:00:00\u{2013}00:02:00")
        #expect(first["keyframes"].array?.count == 3)
        #expect(first["keyframes"].array?.allSatisfy { FileManager.default.fileExists(atPath: $0.string ?? "") } == true)

        let sheet = try await runtime.invoke("direction_contact_sheet", arguments: .object(["assetID": .string(id), "frames": .number(9), "range": .object(["start": .number(0), "end": .number(3)])]))
        #expect(sheet.imagePaths.count == 1 && sheet.value["cells"].array?.count == 9 && sheet.value["columns"].int == 3)
        #expect(sheet.value["cells"].array?.first?["timecode"].string == "00:00:04")

        let frame = try await runtime.invoke("direction_frame", arguments: .object(["assetID": .string(id), "time": .number(2.5), "maxDimension": .number(320)]))
        #expect(frame.value["source"].bool == true && frame.value["timecode"].string == "00:02:12" && frame.imagePaths.count == 1)
        let red = try meanColor(URL(fileURLWithPath: frame.imagePaths[0]))
        #expect(red.0 > 128 && red.1 < 90, "\(red)")

        let dailies = try await runtime.invoke("direction_dailies")
        #expect(dailies.value["assets"].array?.first?["index"].string == "done")

        // The cut: watch it, and the passage is recorded for the delivery check.
        var insert = EditOperation("insert"); insert.assetID = id
        _ = try store.apply(.init(baseEditRevision: try store.revision(), operations: [insert]))
        let watched = try await runtime.invoke("direction_watch", arguments: .object(["start": .number(1), "end": .number(5), "frames": .number(8)]))
        #expect(watched.imagePaths.count == 1 && watched.value["cells"].array?.count == 8)
        #expect(watched.value["cuts"].array?.isEmpty == true)
        #expect(try store.watchedRanges().last.map { $0.start == 1 && $0.end == 5 } == true)
    }

    final class Calls: @unchecked Sendable { private let lock = NSLock(); private var n = 0; func add() { lock.withLock { n += 1 } }; var count: Int { lock.withLock { n } } }

    struct StandIn: ShotDescriber {
        var broken = false
        var calls = Calls()
        var engine: String { "stand-in" }
        var concurrency: Int { 4 }
        func describe(_ request: DescribeRequest) async throws -> DescribeResult {
            if broken { throw DirectionError("vision_helper_failed", "mlx-vlm couldn't load the version.") }
            // Three frames, or just the middle one for a shot that doesn't move.
            #expect([1, 3].contains(request.images.count) && request.images.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
            calls.add()
            return DescribeResult(look: ShotLook(description: "Wide on a test pattern \(request.images[0].lastPathComponent).", size: "wide"))
        }
        func finish() async {}
    }

    @Test func describesEveryShotAndSkipsDescriptionsWhenTheEngineBreaks() async throws {
        let folder = try Self.temp("describe"); defer { try? FileManager.default.removeItem(at: folder) }
        guard let clip = try Self.cuts(in: folder) else { return }
        let (store, runtime) = try Self.project(folder)
        let asset = try await MediaInspector.inspect(url: clip)
        _ = try store.addAsset(asset, append: false, expectedRevision: try store.revision())
        let options = FootageIndexer.Options(cacheDirectory: runtime.cacheDirectory, describer: StandIn())
        let summary = try await FootageIndexer.run(store: store, options: options) { _ in }
        #expect(summary["described"].int == 5)
        let take = try #require(try store.takeIndex(asset.id))
        #expect(take.state == .done && take.described == 5 && take.triedEngine == "stand-in")
        #expect(try FootageSearch.search("test pattern", store: store).count == 5)
        // The 672 px frames the describer read are gone; the small keyframes stay with the film.
        #expect(!FileManager.default.fileExists(atPath: runtime.cacheDirectory.appendingPathComponent("IndexFrames/\(asset.id)").path))

        // Looked at again with an engine that can't run: shots stand, the take is done, and says why.
        let broken = FootageIndexer.Options(cacheDirectory: runtime.cacheDirectory, force: true, describer: StandIn(broken: true))
        _ = try await FootageIndexer.run(store: store, options: broken) { _ in }
        let again = try #require(try store.takeIndex(asset.id))
        #expect(again.state == .done && again.shotCount == 5 && again.described == 0)
        #expect(again.describeSkipped?.contains("couldn't load") == true)
    }

    /// Like This Mac's: batches of one-frame shots.
    struct Batched: ShotDescriber {
        var batches = Calls(), singles = Calls()
        var engine: String { "batched stand-in" }
        var concurrency: Int { 1 }
        var batchSize: Int { 8 }
        func describe(_ request: DescribeRequest) async throws -> DescribeResult { singles.add(); return DescribeResult(look: ShotLook(description: "Wide on a moving test pattern.", size: "wide")) }
        func describeBatch(_ requests: [DescribeRequest]) async throws -> [DescribeResult?] {
            batches.add()
            #expect(requests.allSatisfy { $0.images.count == 1 })
            return requests.map { DescribeResult(look: ShotLook(description: "Wide on a still test pattern \($0.images[0].lastPathComponent).", size: "wide")) }
        }
        func finish() async {}
    }

    @Test func shotsThatDontMoveAreDescribedTogether() async throws {
        let folder = try Self.temp("batch"); defer { try? FileManager.default.removeItem(at: folder) }
        guard let clip = try Self.cuts(in: folder) else { return }
        let (store, runtime) = try Self.project(folder)
        _ = try store.addAsset(try await MediaInspector.inspect(url: clip), append: false, expectedRevision: try store.revision())
        let describer = Batched()
        _ = try await FootageIndexer.run(store: store, options: FootageIndexer.Options(cacheDirectory: runtime.cacheDirectory, describer: describer)) { _ in }
        let shots = try store.shots()
        #expect(shots.count == 5 && shots.allSatisfy { $0.look != nil })
        // The still patterns (a colour, bars, black) go in one batch; a pattern whose counter changes
        // enough between its first and last frames goes on its own with three.
        #expect(describer.batches.count == 1 && describer.singles.count <= 2, "\(describer.batches.count) batches, \(describer.singles.count) singles")
        #expect(try store.takeIndex(shots[0].assetID)?.described == 5)
    }

    @Test func aSecondTakeOfTheSamePictureReusesItsDescriptions() async throws {
        let folder = try Self.temp("reuse"); defer { try? FileManager.default.removeItem(at: folder) }
        guard let clip = try Self.cuts(in: folder) else { return }
        let copy = folder.appendingPathComponent("second-take.mov")
        try FileManager.default.copyItem(at: clip, to: copy)
        let (store, runtime) = try Self.project(folder)
        for url in [clip, copy] { _ = try store.addAsset(try await MediaInspector.inspect(url: url), append: false, expectedRevision: try store.revision()) }
        let describer = StandIn()
        _ = try await FootageIndexer.run(store: store, options: FootageIndexer.Options(cacheDirectory: runtime.cacheDirectory, describer: describer)) { _ in }
        let shots = try store.shots()
        // Every shot has a line, but only the first take's were written by the describer.
        #expect(shots.count == 10 && shots.allSatisfy { $0.look != nil })
        #expect(describer.calls.count == 5, "\(describer.calls.count) calls")
        #expect(shots.filter { $0.engine?.contains("same picture as shot") == true }.count == 5)
    }

    // MARK: Search

    /// A film with three takes of shots and lines, made searchable the way the index does it.
    static func searchable(_ folder: URL) throws -> ProjectStore {
        let (store, _) = try project(folder)
        let takes: [(String, [(String, String)], [String])] = [
            ("take-a", [("Medium on Maya. She laughs and looks away.", "medium"), ("Wide on the window at dusk.", "wide")], ["I remember the first version."]),
            ("take-b", [("Close on hands typing on a keyboard.", "close")], ["We were all laughing at that bug."]),
            ("take-c", [("Wide on the ridge, wind in the grass.", "wide"), ("A woman smiles and giggles at the table.", "medium")], ["Look at that light."]),
        ]
        for (id, shots, lines) in takes {
            _ = try store.addAsset(MediaAsset(id: id, name: "\(id).mov", path: "/Volumes/Test/\(id).mov", duration: .init(seconds: 30), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 24)], audio: [.init(id: 2, index: 0, label: "Lav", channels: 1, sampleRate: 48_000)]), append: false, expectedRevision: try store.revision())
            let made = shots.enumerated().map { i, s in Shot(id: "\(id)-shot-\(i + 1)", assetID: id, number: i + 1, start: Double(i) * 10, end: Double(i + 1) * 10, look: ShotLook(description: s.0, size: s.1)) }
            try store.replaceShots(assetID: id, made)
            var words: [TranscriptWord] = []
            for (j, line) in lines.enumerated() {
                for (k, w) in line.split(separator: " ").enumerated() { words.append(TranscriptWord(id: "\(id)-w\(j)-\(k)", text: String(w), range: MediaRange(start: 2 + Double(j) * 5 + Double(k) * 0.3, end: 2 + Double(j) * 5 + Double(k) * 0.3 + 0.25))) }
            }
            try store.saveTranscript(SourceTranscript(assetID: id, audioTrackID: 2, words: words))
            try store.replaceSearchRows(assetID: id, FootageIndexer.searchRows(shots: made, transcripts: try store.transcripts().filter { $0.assetID == id }))
        }
        return store
    }

    @Test func searchBlendsMeaningAndExactWordsBestShotPerTakeFirst() throws {
        let folder = try Self.temp("search"); defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Self.searchable(folder)
        let hits = try FootageSearch.search("Maya laughing", store: store)
        #expect(hits.first?.shotID == "take-a-shot-1")
        #expect(hits.first?.why == .picture)
        #expect(hits.first?.matched == ["Maya", "laughs"])
        // A spoken line matches on words and comes back quoted.
        let spoken = try #require(hits.first { $0.assetID == "take-b" })
        #expect(spoken.why == .words && spoken.text == "\u{201C}We were all laughing at that bug.\u{201D}")
        // Meaning alone: a woman giggling is near "laughing" though no word matches.
        #expect(hits.contains { $0.shotID == "take-c-shot-2" })
        #expect(!hits.contains { $0.shotID == "take-a-shot-2" || $0.shotID == "take-c-shot-1" })
        // One shot per take before any second shot of the same take.
        let takes = hits.map(\.assetID)
        #expect(Array(takes.prefix(Set(takes).count)).count == Set(takes.prefix(Set(takes).count)).count)

        let wordsOnly = try FootageSearch.search("laughing", store: store, options: .init(wordsOnly: true))
        #expect(wordsOnly.map(\.assetID) == ["take-b"])
        var dailies = Dailies(); dailies.takes["take-b"] = { var t = TakeInfo(assetID: "take-b"); t.circled = true; return t }()
        let circled = try FootageSearch.search("Maya laughing", store: store, dailies: dailies, options: .init(circledOnly: true))
        #expect(circled.map(\.assetID) == ["take-b"])
        #expect(try FootageSearch.search("submarine periscope", store: store).isEmpty)
        #expect(FootageSearch.tokens("Maya, the laughing!") == ["maya", "laughing"])
    }

    @Test func searchIsFastForTwoThousandShots() throws {
        let folder = try Self.temp("speed"); defer { try? FileManager.default.removeItem(at: folder) }
        let (store, _) = try Self.project(folder)
        let subjects = ["Maya", "the team", "a man", "hands", "the ridge", "the street", "a car", "the window", "the office", "a laptop"]
        let actions = ["laughs", "looks away", "walks in", "types", "waits", "turns", "smiles", "sits down", "stands", "talks"]
        for t in 0..<100 {
            let id = "take-\(t)"
            _ = try store.addAsset(MediaAsset(id: id, name: "\(id).mov", path: "/Volumes/Test/\(id).mov", duration: .init(seconds: 60), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 24)]), append: false, expectedRevision: try store.revision())
            let shots = (0..<20).map { i in Shot(id: "\(id)-\(i)", assetID: id, number: i + 1, start: Double(i) * 3, end: Double(i + 1) * 3, look: ShotLook(description: "Medium on \(subjects[(t + i) % 10]). \(subjects[(t * 3 + i) % 10].capitalized) \(actions[(t + i * 7) % 10]).")) }
            try store.replaceShots(assetID: id, shots)
            try store.replaceSearchRows(assetID: id, FootageIndexer.searchRows(shots: shots, transcripts: []))
        }
        _ = try FootageSearch.search("warm up", store: store)
        let clock = ContinuousClock(), start = clock.now
        let hits = try FootageSearch.search("Maya laughing", store: store)
        let elapsed = clock.now - start
        #expect(!hits.isEmpty)
        #expect(elapsed < .milliseconds(300), "search took \(elapsed)")
    }

    // MARK: Engines

    @Test func descriptionsValidateAgainstTheShape() {
        let look = DescribePrompt.parse("```json\n{\"description\": \"Close-up on a kettle as steam rises past the window and the light fades slowly across the counter tops at dusk now\", \"size\": \"Close-up\", \"movement\": \"Locked\", \"people\": \"\", \"setting\": \"kitchen, dusk\", \"flags\": [\"blurry\", \"soft\"]}\n```")
        #expect(look?.size == "close" && look?.movement == "static" && look?.people == [] && look?.flags == ["soft"])
        #expect(look?.description.split(separator: " ").count == 18 && look?.description.hasSuffix("counter.") == true)
        // Over-long lines end at the last sentence that fits.
        #expect(DescribePrompt.parse("{\"description\": \"Wide on the ridge at dusk. Wind moves the grass while the light fades and the clouds roll in over the far hills slowly\"}")?.description == "Wide on the ridge at dusk.")
        #expect(DescribePrompt.parse("I can't tell.") == nil)
        #expect(DescribePrompt.parse("{\"size\": \"wide\"}") == nil)
    }

    @Test func openRouterSendsThreeKeyframesWithTheSchemaAndRetriesOnce() async throws {
        let folder = try Self.temp("openrouter"); defer { try? FileManager.default.removeItem(at: folder) }
        let frames = try (1...3).map { i -> URL in
            let url = folder.appendingPathComponent("\(i).jpg")
            let ctx = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.2 * Double(i), green: 0.3, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
            try SourceFrames.writeJPEG(ctx.makeImage()!, to: url)
            return url
        }
        let sent = Captured()
        let saved = OpenRouter.transport
        defer { OpenRouter.transport = saved }
        OpenRouter.transport = { request in
            let n = sent.add(request)
            let content = n == 1 ? "Sorry, here you go:" : "{\"description\": \"Wide on the ridge at dusk. Wind moves the grass.\", \"size\": \"wide\", \"movement\": \"static\", \"people\": [], \"setting\": \"ridge, dusk\", \"flags\": []}"
            let body = try JSONEncoder().encode(JSONValue.object(["choices": .array([.object(["message": .object(["content": .string(content)])])]), "usage": .object(["cost": .number(0.0012)])]))
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let describer = OpenRouterDescriber(version: "google/gemini-3.1-flash-lite", key: "test-key")
        let result = try await describer.describe(DescribeRequest(images: frames, words: "Look at that light."))
        #expect(result.look.description == "Wide on the ridge at dusk. Wind moves the grass." && result.look.size == "wide")
        #expect(abs((result.spend ?? 0) - 0.0024) < 1e-9)
        let requests = sent.all
        #expect(requests.count == 2)
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(requests[0].httpBody))
        #expect(requests[0].url?.path == "/api/v1/chat/completions" && requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(body["model"].string == "google/gemini-3.1-flash-lite" && body["temperature"].double == 0 && body["max_tokens"].int == 160)
        #expect(body["response_format"]["type"].string == "json_schema" && body["response_format"]["json_schema"]["schema"]["properties"]["size"]["enum"].array?.count == 4)
        let parts = try #require(body["messages"].array?.first?["content"].array)
        #expect(parts.count == 4 && parts[0]["text"].string?.contains("Look at that light.") == true)
        #expect(parts.dropFirst().allSatisfy { $0["type"].string == "image_url" && ($0["image_url"]["url"].string?.hasPrefix("data:image/jpeg;base64,") ?? false) })
        let retry = try JSONDecoder().decode(JSONValue.self, from: try #require(requests[1].httpBody))
        #expect(retry["messages"].array?.first?["content"].array?.first?["text"].string?.contains("wasn't that JSON") == true)
        #expect(describer.concurrency == 4)
    }

    final class Captured: @unchecked Sendable {
        private let lock = NSLock(); private var requests: [URLRequest] = []
        func add(_ r: URLRequest) -> Int { lock.withLock { requests.append(r); return requests.count } }
        var all: [URLRequest] { lock.withLock { requests } }
    }

    /// The real describe.py with a stand-in mlx_vlm on PYTHONPATH: the JSON-lines protocol,
    /// ids, errors, a library that prints to stdout, and a version that won't load.
    @Test func helperSpeaksJSONLinesWithIDsAndErrors() async throws {
        guard let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:)) else { return }
        let script = try #require(VisionHelper.script())
        let folder = try Self.temp("helper"); defer { try? FileManager.default.removeItem(at: folder) }
        let package = folder.appendingPathComponent("mlx_vlm")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try """
        import json
        class Result:
            def __init__(self, text): self.text = text
        def load(repo):
            print("noise on stdout while loading")
            if repo == "broken/version": raise RuntimeError("no such version")
            return object(), object()
        def generate(model, processor, prompt, image=None, max_tokens=0, temperature=None, verbose=False):
            print("more noise")
            if "explode" in prompt: raise ValueError("boom")
            return Result(json.dumps({"description": "Saw %d frames." % len(image or []), "size": "wide", "movement": "static", "people": [], "setting": "test", "flags": [], "temperature": temperature, "max_tokens": max_tokens}))
        """.write(to: package.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        try "def apply_chat_template(processor, config, prompt, num_images=0):\n    return prompt\n".write(to: package.appendingPathComponent("prompt_utils.py"), atomically: true, encoding: .utf8)
        let env = ["PYTHONPATH": folder.path]

        let helper = LocalVisionHelper(repo: "stand-in/version")
        await helper.configure(python: python, script: script, idleSeconds: 30, environment: env, timeout: 20)
        let text = try await helper.ask(images: [URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.jpg")], prompt: "describe", maxTokens: 160)
        let reply = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(reply["description"].string == "Saw 2 frames." && reply["temperature"].double == 0 && reply["max_tokens"].int == 160)
        await #expect(throws: DirectionError.self) { try await helper.ask(images: [], prompt: "explode", maxTokens: 10) }
        // The helper survives an error and answers the next request.
        let again = try await helper.ask(images: [URL(fileURLWithPath: "/tmp/a.jpg")], prompt: "describe", maxTokens: 160)
        #expect(again.contains("Saw 1 frames."))
        #expect(await helper.isRunning)
        await helper.stop()
        #expect(await !helper.isRunning)

        let broken = LocalVisionHelper(repo: "broken/version")
        await broken.configure(python: python, script: script, environment: env, timeout: 20)
        do { try await broken.start(); Issue.record("A version that won't load should throw") }
        catch let e as DirectionError { #expect(e.code == "vision_helper_failed" && e.message.contains("no such version")) }
    }

    @Test func soundsMergeIntoRunsAndQuietIsSilence() {
        let w: [SoundIndexer.Window] = [
            .init(start: 0, end: 1, label: "speech", confidence: 0.8), .init(start: 1, end: 2, label: "conversation", confidence: 0.6),
            .init(start: 2, end: 3, label: "laughter", confidence: 0.9), .init(start: 3, end: 4, label: "typing_computer_keyboard", confidence: 0.7),
            .init(start: 4, end: 5, label: "speech", confidence: 0.5), .init(start: 5, end: 6, label: "speech", confidence: 0.5),
        ]
        let runs = SoundIndexer.merge(w, loudness: [-20, -20, -18, -25, -20, -70], assetID: "t")
        #expect(runs.map(\.kind) == [.speech, .laughter, .speech, .silence])
        #expect(runs[0].start == 0 && runs[0].end == 2 && runs[2].end == 5)
        #expect(SoundIndexer.kind(for: "wind_noise_microphone") == .wind && SoundIndexer.kind(for: "car_passing_by") == .traffic && SoundIndexer.kind(for: "acoustic_guitar") == .music)
    }

    // MARK: The real thing

    /// One real local run: a small film looked at end to end, described by the Quick version.
    /// Needs mlx-vlm and Qwen2.5-VL 3B; run with DIRECTION_TEST_VLM=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIRECTION_TEST_VLM"] == "1"))
    func looksAtASmallFilmWithTheQuickVersion() async throws {
        let folder = try Self.temp("vlm"); defer { if ProcessInfo.processInfo.environment["DIRECTION_TEST_KEEP"] == nil { try? FileManager.default.removeItem(at: folder) } }
        let clip = try #require(try Self.cuts(in: folder, audio: true))
        let real = SharedSettings.defaults, suite = "dev.direction.tests.\(UUID().uuidString)"
        SharedSettings.defaults = UserDefaults(suiteName: suite)!
        defer { SharedSettings.defaults.removePersistentDomain(forName: suite); SharedSettings.defaults = real }
        SharedSettings.defaults.set("thisMac", forKey: SharedSettings.IndexKey.engine)
        SharedSettings.defaults.set("quick", forKey: SharedSettings.IndexKey.detail)
        SharedSettings.defaults.set(false, forKey: SharedSettings.IndexKey.automatic)
        let (store, runtime) = try Self.project(folder)
        _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(clip.path)]))
        let clock = ContinuousClock(), start = clock.now
        let started = try await runtime.invoke("direction_index")
        _ = try await runtime.waitForJob(try #require(started.value["job"]["id"].string))
        let elapsed = clock.now - start
        let shots = try store.shots()
        print("Looked at the film in \(elapsed):")
        for s in shots { print("  \(SourceTimecode.range(s.start, s.end)) [\(s.look?.size ?? "-") · \(s.look?.movement ?? "-")] \(s.look?.description ?? "(none)") \(s.look?.flags ?? [])") }
        #expect(shots.count == 5)
        #expect(shots.allSatisfy { $0.look != nil && $0.engine?.contains("Qwen2.5-VL-3B") == true })
        let take = try #require(try store.indexTakes().values.first)
        #expect(take.state == .done && take.described == 5)
        // A shot's own line finds it first: descriptions went into both FTS5 and the vectors.
        let line = try #require(shots[2].look?.description)
        let hits = try FootageSearch.search(line, store: store)
        print("Search “\(line)”: \(hits.map { "\($0.text) (\($0.score), \($0.why.rawValue))" })")
        #expect(hits.first?.shotID == shots[2].id)
        await LocalVisionHelper.shared(SharedSettings.lookDetail.repo).stop()
    }
}

@Test func aModelCountsAsDownloadedWhenItsShardsAreAllThere() {
    #expect(VisionHelper.shardsComplete(["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"]))
    #expect(!VisionHelper.shardsComplete(["model-00001-of-00002.safetensors"]))
    #expect(VisionHelper.shardsComplete(["model.safetensors"]))
    #expect(!VisionHelper.shardsComplete([]))
}

/// Until the director chooses, Best describes footage wherever it fits: it's faster than Standard there.
@Test func bestIsTheDefaultWhereItFits() {
    #expect(SharedSettings.defaultLookDetail(memory: 64 << 30) == "best")
    #expect(SharedSettings.defaultLookDetail(memory: 32 << 30) == "best")
    #expect(SharedSettings.defaultLookDetail(memory: 24 << 30) == "standard")
    #expect(SharedSettings.defaultLookDetail(memory: 16 << 30) == "standard")
}

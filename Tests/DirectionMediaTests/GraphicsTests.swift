import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
import DirectionMedia
import DirectionTools

/// A film with no footage, a sequence at the given format and a graphics folder (graphics.md).
struct GraphicsFixture: Sendable {
    let directory: URL
    let store: ProjectStore
    let runtime: ToolRuntime

    static func make(width: Int = 1920, height: Int = 1080, fps: Int32 = 30) throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direction-graphics-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try ProjectStore.create(at: directory.appendingPathComponent("Film.direction"), name: "Graphics fixture")
        var format = EditOperation("format"); format.width = width; format.height = height; format.frameRate = .init(fps, 1)
        _ = try store.apply(.init(baseEditRevision: store.revision(), operations: [format]))
        return .init(directory: directory, store: store, runtime: try ToolRuntime(store: store))
    }

    /// Writes `Editor/Graphics/<name>/index.html`.
    @discardableResult
    func write(_ name: String, _ html: String, files: [String: String] = [:]) throws -> URL {
        let folder = store.graphicsFolder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try html.write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        for (path, text) in files { try text.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        return folder
    }

    /// The shipped Title card example, at a chosen length.
    func titleCard(_ name: String = "title", seconds: Int = 4) throws {
        let (_, folder) = try GraphicResources.example("title-card")
        let html = try String(contentsOf: folder.appendingPathComponent("index.html"), encoding: .utf8).replacingOccurrences(of: "const duration = 4;", with: "const duration = \(seconds);")
        try write(name, html)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    /// A small page in the contract's shape.
    static func page(words: String = "{ title: { label: 'Title', text: 'Two years.', max: 40 } }", duration: Double = 1, style: String = "", body: String = "<h1 id=\"title\"></h1>", render: String = "title.textContent = words.title;", script: String = "") -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent} h1{position:absolute;left:0;right:0;top:700px;text-align:center;font:700 64px Archivo;color:#fff;margin:0} \(style)</style></head>
        <body>\(body)<script>\(script)
        direction.graphic({ duration: \(duration), words: \(words), render(t, words) { \(render) } });
        </script></body></html>
        """
    }
}

@MainActor
@Suite(.serialized)
struct GraphicsTests {
    @Test func titleCardRendersProRes4444WithAlphaAndTheRightFrameCount() async throws {
        let f = try GraphicsFixture.make(); defer { f.cleanup() }
        try f.titleCard(seconds: 2)
        let result = try await GraphicMaker.make(store: f.store, name: "title", noteID: nil, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)
        let movie = try #require(result.movie)
        #expect(movie.path.hasSuffix(".mov") && movie.path.contains("/Renders/Graphics/title-"))
        let asset = AVURLAsset(url: URL(fileURLWithPath: movie.path))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_AppleProRes4444)
        let depth = (CMFormatDescriptionGetExtensions(description) as NSDictionary?)?[kCMFormatDescriptionExtension_Depth] as? Int
        #expect(depth == 32)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1920, height: 1080))
        #expect(movie.frames == 60)
        #expect(try await frameAlphas(asset).count == 60)
        // Transparent around the words, opaque-ish on them, at the middle of the card.
        let middle = try await frameAlphas(asset)[30]
        #expect(middle.corner == 0)
        #expect(middle.maximum > 200)
        #expect(result.stills.count == 5)
        #expect(result.problems.isEmpty, "\(result.problems)")
        #expect(try f.store.graphicAssetID("title") == result.graphic.assetID)
        #expect(try f.store.read().assets.contains { $0.id == result.graphic.assetID && $0.path == movie.path })
        keep(result.stills.map(\.path) + [movie.path], as: "title-card")
    }

    /// DIRECTION_TEST_ARTIFACTS=<dir> keeps stills and movies for a look.
    func keep(_ paths: [String], as name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DIRECTION_TEST_ARTIFACTS"] else { return }
        let target = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for p in paths { let to = target.appendingPathComponent((p as NSString).lastPathComponent); try? FileManager.default.removeItem(at: to); try? FileManager.default.copyItem(atPath: p, toPath: to.path) }
    }

    /// Decodes every frame as BGRA and reads the alpha in a corner and its maximum.
    func frameAlphas(_ asset: AVURLAsset) async throws -> [(corner: UInt8, maximum: UInt8)] {
        let reader = try AVAssetReader(asset: asset)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); reader.startReading()
        var out: [(UInt8, UInt8)] = []
        while let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(buffer)
            var maximum: UInt8 = 0
            for y in Swift.stride(from: 0, to: CVPixelBufferGetHeight(buffer), by: 4) { for x in Swift.stride(from: 0, to: CVPixelBufferGetWidth(buffer), by: 4) { maximum = max(maximum, base[y * stride + x * 4 + 3]) } }
            out.append((base[3], maximum))
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        return out
    }
}

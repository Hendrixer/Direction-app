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

    /// The clock is Direction's: a page that reads every clock and random source still renders the same bytes.
    @Test func theVirtualClockMakesTwoRendersByteIdentical() async throws {
        let f = try GraphicsFixture.make(width: 640, height: 360, fps: 24); defer { f.cleanup() }
        let page = GraphicsFixture.page(
            words: "{ title: { label: 'Title', text: 'Same every time', max: 40 } }",
            duration: 1,
            style: "#dot{position:absolute;width:40px;height:40px;border-radius:20px;background:#fc6} #bar{position:absolute;left:0;top:20px;height:10px;background:#6cf;animation:grow 1s linear forwards} @keyframes grow{from{width:0}to{width:640px}}",
            body: "<h1 id=\"title\"></h1><div id=\"dot\"></div><div id=\"bar\"></div>",
            render: "title.textContent = words.title; dot.style.left = (performance.now() / 4) + 'px'; dot.style.top = (Date.now() % 1000) / 4 + 'px'; title.style.opacity = String(0.4 + Math.random() * 0.6); title.style.top = (100 + ticks) + 'px';",
            script: "let ticks = 0; const tick = () => { ticks += 1; requestAnimationFrame(tick); }; requestAnimationFrame(tick);")
        try f.write("clock", page)
        let first = try await GraphicMaker.make(store: f.store, name: "clock", noteID: nil, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)
        let path = try #require(first.movie?.path), bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        try FileManager.default.removeItem(atPath: path)
        let second = try await GraphicMaker.make(store: f.store, name: "clock", noteID: nil, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)
        #expect(second.cached == false)
        #expect(second.movie?.path == path)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == bytes)
        // And it does move: the first and last stills differ.
        #expect(try Data(contentsOf: URL(fileURLWithPath: first.stills[0].path)) != Data(contentsOf: URL(fileURLWithPath: first.stills[4].path)))
        // A third render with the same files and words comes from the cache.
        let third = try await GraphicMaker.make(store: f.store, name: "clock", noteID: nil, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)
        #expect(third.cached)
    }

    @Test(arguments: [
        ("fetch", "fetch('https://example.com/data.json').catch(() => {});", "https://example.com/data.json"),
        ("image", "const i = new Image(); i.src = 'https://example.com/photo.jpg'; document.body.appendChild(i);", "https://example.com/photo.jpg"),
        ("font", "", "https://fonts.example.com/face.woff2"),
    ])
    func aGraphicThatRequestsTheInternetFailsItsCheck(kind: String, script: String, url: String) async throws {
        let f = try GraphicsFixture.make(width: 640, height: 360); defer { f.cleanup() }
        let style = kind == "font" ? "@font-face{font-family:Web;src:url(https://fonts.example.com/face.woff2)} h1{font-family:Web}" : ""
        try f.write("online", GraphicsFixture.page(style: style, script: script))
        do {
            _ = try await GraphicMaker.make(store: f.store, name: "online", noteID: nil, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory)
            Issue.record("The check should fail")
        } catch let e as DirectionError {
            #expect(e.code == "graphic_internet")
            #expect(e.message.hasPrefix("Graphics can\u{2019}t use the internet") || e.message.hasPrefix("Graphics can't use the internet"))
            #expect(e.message.contains(url), "\(e.message)")
        }
    }

    @Test func wordsThatDontFitTheirBoxAreReported() async throws {
        let f = try GraphicsFixture.make(); defer { f.cleanup() }
        let html = GraphicsFixture.page(
            words: "{ name: { label: 'Name', text: 'Maya Okonkwo-Fitzgerald, Founder and Chief Executive Officer', max: 80 } }",
            style: ".box{position:absolute;left:200px;top:800px;width:420px;height:80px;white-space:nowrap;font:600 48px Archivo;color:#fff}",
            body: "<div class=\"box\" id=\"who\"></div>", render: "who.textContent = words.name;")
        try f.write("lower", html)
        let result = try await GraphicMaker.make(store: f.store, name: "lower", noteID: nil, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory)
        let overflow = try #require(result.problems.first { $0.code == "overflow" })
        #expect(overflow.word == "name")
        #expect(overflow.message.contains("doesn\u{2019}t fit its box"))
        #expect(result.movie == nil)
        // Fits once the box is wide enough.
        try f.write("lower", html.replacingOccurrences(of: "width:420px", with: "width:1500px"))
        let fixed = try await GraphicMaker.make(store: f.store, name: "lower", noteID: nil, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory)
        #expect(!fixed.problems.contains { $0.code == "overflow" })
    }

    @Test func smallTextTitleSafeContrastAndStrayWordsAreReported() async throws {
        let f = try GraphicsFixture.make(); defer { f.cleanup() }
        try f.write("checks", GraphicsFixture.page(
            words: "{ title: { label: 'Title', text: 'Tiny', max: 20 }, edge: { label: 'Edge', text: 'At the edge', max: 20 }, card: { label: 'Card', text: 'Grey on grey', max: 20 } }",
            style: "#title{font-size:14px;top:500px} #edge{position:absolute;left:10px;top:20px;font:600 40px Archivo;color:#fff} #card{position:absolute;left:600px;top:300px;padding:20px;background:#777;color:#999;font:600 40px Archivo} #stray{position:absolute;left:600px;top:400px;font:600 40px Archivo;color:#fff}",
            body: "<h1 id=\"title\"></h1><div id=\"edge\"></div><div id=\"card\"></div><div id=\"stray\">Directed by</div>",
            render: "title.textContent = words.title; edge.textContent = words.edge; card.textContent = words.card;"))
        let result = try await GraphicMaker.make(store: f.store, name: "checks", noteID: nil, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory)
        let codes = Dictionary(grouping: result.problems, by: \.code)
        #expect(codes["small_text"]?.first?.word == "title")
        #expect(codes["outside_title_safe"]?.contains { $0.word == "edge" } == true)
        #expect(codes["low_contrast"]?.first?.word == "card")
        #expect(codes["not_in_words"]?.first?.message.contains("Directed by") == true)
        #expect(result.stills.count == 5)
    }

    @Test func wordsLongerThanTheirMaxAreRefusedAndReported() async throws {
        let f = try GraphicsFixture.make(width: 640, height: 360); defer { f.cleanup() }
        try f.titleCard()
        _ = try await GraphicMaker.make(store: f.store, name: "title", noteID: nil, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)
        let long = String(repeating: "a", count: 41)
        await #expect(throws: DirectionError.self) { try await GraphicMaker.changeWords(store: f.store, name: "title", words: ["title": long]) }
        #expect(throws: DirectionError.self) { try f.store.setDirectorWords("title", ["title": long], render: nil) }
        // A page that declares words past their max is told so.
        try f.write("long", GraphicsFixture.page(words: "{ title: { label: 'Title', text: '\(long)', max: 40 } }"))
        let result = try await GraphicMaker.make(store: f.store, name: "long", noteID: nil, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory)
        #expect(result.problems.contains { $0.code == "too_long" && $0.word == "title" })
    }

    @Test func theDirectorsWordsAreLockedUnlessANoteNamesTheGraphic() async throws {
        let f = try GraphicsFixture.make(width: 640, height: 360); defer { f.cleanup() }
        let revision = try f.store.revision()
        let asked = try f.store.addComment(text: "Put a title over the cold open: two years.", sequenceID: nil, revision: revision)
        try f.titleCard()
        _ = try await GraphicMaker.make(store: f.store, name: "title", noteID: asked.id, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)

        // The director fixes the words; the graphic renders them and History says so.
        let (before, after) = try await GraphicMaker.changeWords(store: f.store, name: "title", words: ["title": "Two years, alone."])
        #expect(before.directorWords.isEmpty)
        #expect(after.resolvedWords["title"] == "Two years, alone.")
        #expect(after.render?.path != before.render?.path)
        #expect(try f.store.events().contains { $0.summary == "You changed the words of the title" })
        // Every revision plays the new render, so the cut on screen shows the new words without a new cut.
        #expect(try f.store.read(revision: revision + 1).assets.first { $0.id == after.assetID }?.path == after.render?.path)

        // Running the unchanged page again keeps the director's words.
        let again = try await GraphicMaker.make(store: f.store, name: "title", noteID: asked.id, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)
        #expect(again.graphic.resolvedWords["title"] == "Two years, alone.")

        // The editor changes them in its page: refused under the old note.
        let (_, folder) = try GraphicResources.example("title-card")
        let changed = try String(contentsOf: folder.appendingPathComponent("index.html"), encoding: .utf8).replacingOccurrences(of: "'Two years.'", with: "'Two years later.'")
        try f.write("title", changed)
        do {
            _ = try await GraphicMaker.make(store: f.store, name: "title", noteID: asked.id, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory)
            Issue.record("The director's words should be locked")
        } catch let e as DirectionError { #expect(e.code == "words_are_yours") }
        // A later note about something else doesn't unlock them either.
        let other = try f.store.addComment(text: "Music is too sure of itself here.", sequenceID: nil, revision: revision)
        await #expect(throws: DirectionError.self) { try await GraphicMaker.make(store: f.store, name: "title", noteID: other.id, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory) }
        // A note written after the change that names the graphic does.
        let named = try f.store.addComment(text: "Change the title to two years later.", sequenceID: nil, revision: revision)
        let allowed = try await GraphicMaker.make(store: f.store, name: "title", noteID: named.id, checkOnly: false, cacheDirectory: f.runtime.cacheDirectory)
        #expect(allowed.graphic.resolvedWords["title"] == "Two years later.")
        #expect(allowed.graphic.directorWords.isEmpty)

        // Undo puts the director's words back from the cache.
        try await GraphicMaker.restoreWords(store: f.store, after)
        #expect(try f.store.graphic("title")?.resolvedWords["title"] == "Two years, alone.")
    }

    /// The twelve examples ship clean: no problems, no console errors, every word in words.
    @Test(arguments: ["title-card", "lower-third", "chapter-card", "end-card", "quote", "kinetic-words", "counter", "map-line", "simple-chart", "logo-sting", "credits-roll", "captions-style"])
    func everyExampleChecksClean(example: String) async throws {
        let f = try GraphicsFixture.make(); defer { f.cleanup() }
        let (info, source) = try GraphicResources.example(example)
        let folder = f.store.graphicsFolder.appendingPathComponent(example, isDirectory: true)
        try FileManager.default.createDirectory(at: f.store.graphicsFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: folder)
        let result = try await GraphicMaker.make(store: f.store, name: example, noteID: nil, checkOnly: true, cacheDirectory: f.runtime.cacheDirectory)
        #expect(info.name == example)
        #expect(result.problems.isEmpty, "\(example): \(result.problems.map(\.message))")
        #expect(result.consoleErrors.isEmpty, "\(example): \(result.consoleErrors)")
        #expect(!result.graphic.words.isEmpty)
        #expect(result.stills.count == 5)
        keep(result.stills.map(\.path), as: "examples")
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

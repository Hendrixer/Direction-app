import Testing
import Foundation
import CoreImage
import CoreGraphics
import simd
import ImageIO
import DirectionCore
import DirectionMedia
@testable import DirectionTools

// Looks (specs/looks.md): the .cube parser, LUTs, the eleven filters, and the editor's make_look.

/// A dusk frame drawn in code: sky gradient, a bright sun, dark ground, a figure.
/// Set DIRECTION_LOOK_ARTIFACTS to a folder to see every filter on it.
enum LookFrame {
    static func make(width: Int = 768, height: Int = 432) -> CIImage {
        let space = CGColorSpace(name: CGColorSpace.itur_709)!
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let w = CGFloat(width), h = CGFloat(height)
        let sky = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.85, green: 0.48, blue: 0.30, alpha: 1), CGColor(red: 0.45, green: 0.30, blue: 0.55, alpha: 1), CGColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1)] as CFArray, locations: [0, 0.5, 1])!
        c.drawLinearGradient(sky, start: CGPoint(x: 0, y: h * 0.3), end: CGPoint(x: 0, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)); c.fillEllipse(in: CGRect(x: w * 0.6, y: h * 0.32, width: w * 0.08, height: w * 0.08))
        c.setFillColor(CGColor(red: 0.06, green: 0.05, blue: 0.08, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.3))
        c.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)); c.fill(CGRect(x: w * 0.38, y: h * 0.3, width: w * 0.03, height: h * 0.16))
        return CIImage(cgImage: c.makeImage()!)
    }

    static let context = CIContext(options: [.cacheIntermediates: false])
    /// RGBA floats in Rec. 709 values, top row first.
    static func pixels(_ image: CIImage) -> [Float] {
        let r = image.extent.integral, w = Int(r.width), h = Int(r.height)
        var out = [Float](repeating: 0, count: w * h * 4)
        context.render(image, toBitmap: &out, rowBytes: w * 16, bounds: r, format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.itur_709)!)
        return out
    }
    /// One pixel, with y up from the bottom like Core Image and Core Graphics.
    static func pixel(_ p: [Float], width: Int, _ x: Int, _ y: Int) -> SIMD3<Float> {
        let height = p.count / 4 / width, i = ((height - 1 - y) * width + x) * 4
        return SIMD3(p[i], p[i + 1], p[i + 2])
    }

    static func save(_ image: CIImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DIRECTION_LOOK_ARTIFACTS"] else { return }
        try? LookMaker.writePNG(image, to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"), colorSpace: CGColorSpace(name: CGColorSpace.itur_709))
    }
}

@Suite("Cube LUTs")
struct CubeLUTTests {
    @Test func parsesA3DCubeWithCommentsTitleAndDomain() throws {
        var text = "# made by hand\nTITLE \"Print film\"\nLUT_3D_SIZE 17\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n\n"
        text += CubeLUT.identity(size: 17).text.split(separator: "\n").dropFirst().joined(separator: "\n")
        let lut = try CubeLUT.parse(text)
        #expect(lut.kind == .threeD && lut.size == 17 && lut.values.count == 4913)
        #expect(lut.title == "Print film")
        #expect(lut.values[1] == SIMD3<Float>(0.0625, 0, 0))
    }

    @Test func parses1DCubes() throws {
        let invert = CubeLUT.make(size: 17, kind: .oneD) { SIMD3(repeating: 1) - $0 }
        let lut = try CubeLUT.parse(invert.text)
        #expect(lut.kind == .oneD && lut.size == 17 && lut.values.count == 17)
        #expect(abs(lut.sample(SIMD3(0.25, 0.5, 1)).x - 0.75) < 1e-5)
        // Resolve's input-range keyword works as the domain.
        let ranged = try CubeLUT.parse("LUT_1D_SIZE 17\nLUT_1D_INPUT_RANGE 0.0 0.5\n" + invert.text.split(separator: "\n").dropFirst().joined(separator: "\n"))
        #expect(ranged.domainMax == SIMD3(repeating: 0.5))
        #expect(abs(ranged.sample(SIMD3(repeating: 0.25)).x - 0.5) < 1e-5)
    }

    @Test(arguments: [
        ("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n", "size 2 is outside 17–65"),
        ("LUT_3D_SIZE 66\n", "size 66 is outside 17–65"),
        ("LUT_3D_SIZE 17\n0 0 0\n", "has 4913 values; this one has 1"),
        ("0 0 0\n", "no LUT_3D_SIZE or LUT_1D_SIZE"),
        ("LUT_3D_SIZE 17\nLUT_1D_SIZE 17\n", "both a 1D and a 3D size"),
        ("LUT_1D_SIZE 17\n0 0 0\n1.2 0 0\n", "line 3 has a value outside 0–1"),
        ("LUT_1D_SIZE 17\n0 0\n", "line 2 isn't three numbers"),
        ("LUT_1D_SIZE 17\nDOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\n" + String(repeating: "0 0 0\n", count: 17), "DOMAIN_MIN must be below DOMAIN_MAX"),
        ("LUT_1D_SIZE 17\n0 0 0\nTITLE \"late\"\n", "comes after the table"),
    ])
    func refusesInvalidFiles(text: String, reason: String) {
        do { _ = try CubeLUT.parse(text); Issue.record("Expected \(reason)") }
        catch let e as DirectionError { #expect(e.code == "lut_invalid"); #expect(e.message.contains(reason), "\(e.message)") }
        catch { Issue.record("\(error)") }
    }

    @Test func identityRoundTripsThroughTextAndCoreImage() throws {
        let identity = CubeLUT.identity(size: 33)
        let reread = try CubeLUT.parse(identity.text)
        #expect(zip(identity.values, reread.values).allSatisfy { simd_reduce_max(simd_abs($0 - $1)) < 1e-5 })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-lut-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("identity.cube")
        try identity.text.write(to: url, atomically: true, encoding: .utf8)
        let frame = LookFrame.make()
        let before = LookFrame.pixels(frame), after = LookFrame.pixels(LookPipeline.lut(frame, path: url.path, strength: 1))
        #expect(zip(before, after).map { abs($0 - $1) }.max()! < 1.5 / 255)
        // The same through a whole look, and a 1D LUT made into a cube.
        let one = dir.appendingPathComponent("one.cube")
        try CubeLUT.identity(size: 17, kind: .oneD).text.write(to: one, atomically: true, encoding: .utf8)
        let viaLook = LookFrame.pixels(LookPipeline.apply(LookSettings(name: "Plain", lut: one.path), to: frame, frameIndex: 0))
        #expect(zip(before, viaLook).map { abs($0 - $1) }.max()! < 1.5 / 255)
    }

    @Test func strengthMixesWithTheOriginalAndBadFilesAreNeverApplied() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-lut-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("invert.cube")
        try CubeLUT.make(size: 17) { SIMD3(repeating: 1) - $0 }.text.write(to: url, atomically: true, encoding: .utf8)
        let frame = LookFrame.make(), w = Int(frame.extent.width)
        let p0 = LookFrame.pixels(frame), full = LookFrame.pixels(LookPipeline.lut(frame, path: url.path, strength: 1)), half = LookFrame.pixels(LookPipeline.lut(frame, path: url.path, strength: 0.5))
        let x = 10, y = 10 // the dark ground
        #expect(abs(LookFrame.pixel(full, width: w, x, y).x - (1 - LookFrame.pixel(p0, width: w, x, y).x)) < 0.01)
        let mid = LookFrame.pixel(half, width: w, x, y).x
        #expect(mid > LookFrame.pixel(p0, width: w, x, y).x + 0.1 && mid < LookFrame.pixel(full, width: w, x, y).x - 0.1)
        let bad = dir.appendingPathComponent("bad.cube")
        try "LUT_3D_SIZE 8\n".write(to: bad, atomically: true, encoding: .utf8)
        #expect(LookPipeline.problem(bad.path)?.contains("Can't read this LUT") == true)
        #expect(LookFrame.pixels(LookPipeline.lut(frame, path: bad.path, strength: 1)) == p0)
    }
}

@Suite("Look filters")
struct LookFilterTests {
    let frame = LookFrame.make()
    var width: Int { Int(frame.extent.width) }
    func run(_ f: LookFilter, _ amount: Double = 1, option: String? = nil, frameIndex: Int = 0) -> [Float] {
        let out = LookPipeline.filter(frame, kind: f.rawValue, amount: amount, option: option, frameIndex: frameIndex)
        LookFrame.save(out, "filter-\(f.rawValue)\(option.map { "-" + $0 } ?? "")")
        #expect(out.extent == frame.extent)
        return LookFrame.pixels(out)
    }
    var original: [Float] { LookFrame.pixels(frame) }
    func px(_ p: [Float], _ x: Int, _ y: Int) -> SIMD3<Float> { LookFrame.pixel(p, width: width, x, y) }
    // Sample points on the 768 × 432 frame: dark sky up top, the sun's middle, just right of the sun, the ground.
    var sky: (Int, Int) { (120, 400) }
    var sun: (Int, Int) { (491, 169) }
    var nearSun: (Int, Int) { (530, 169) }
    var ground: (Int, Int) { (400, 40) }

    @Test func blackAndWhiteTakesOutColor() {
        let p = run(.blackAndWhite)
        for i in stride(from: 0, to: p.count, by: 4 * 37) { #expect(abs(p[i] - p[i + 1]) < 0.01 && abs(p[i + 1] - p[i + 2]) < 0.01) }
        LookFrame.save(frame, "original")
    }

    @Test func splitToneWarmsHighlightsAndCoolsShadows() {
        let o = original, p = run(.splitTone, option: "warmTeal")
        let bright = (120, 150)
        #expect(px(p, bright.0, bright.1).x - px(p, bright.0, bright.1).z > px(o, bright.0, bright.1).x - px(o, bright.0, bright.1).z)
        #expect(px(p, sky.0, sky.1).z - px(p, sky.0, sky.1).x > px(o, sky.0, sky.1).z - px(o, sky.0, sky.1).x)
        let cool = run(.splitTone, option: "coolAmber")
        #expect(px(cool, sky.0, sky.1).x - px(cool, sky.0, sky.1).z > px(o, sky.0, sky.1).x - px(o, sky.0, sky.1).z)
    }

    @Test func fadeLiftsBlacksAndKeepsWhite() {
        let o = original, p = run(.fade)
        #expect(px(p, ground.0, ground.1).x > px(o, ground.0, ground.1).x + 0.1)
        #expect(abs(px(p, sun.0, sun.1).x - px(o, sun.0, sun.1).x) < 0.03)
    }

    @Test func halationGlowsRedAroundHighlights() {
        let o = original, p = run(.halation)
        let before = px(o, nearSun.0, nearSun.1), d = px(p, nearSun.0, nearSun.1) - before
        // Screened light: each channel's gain over its headroom is the glow's color, red-orange.
        let gain = d / (SIMD3(repeating: 1) - before)
        #expect(d.x > 0.02 && gain.x > gain.y && gain.y > gain.z, "\(gain)")
        #expect(abs(px(p, ground.0, ground.1).x - px(o, ground.0, ground.1).x) < 0.01)
    }

    @Test func bloomGlowsNeutralFromBrightAreas() {
        let o = original, p = run(.bloom)
        let d = px(p, nearSun.0, nearSun.1) - px(o, nearSun.0, nearSun.1)
        #expect(d.x > 0.02 && d.z > 0.02)
    }

    @Test func softenSpreadsHighlightsNotShadows() {
        let o = original, p = run(.soften)
        #expect(px(p, nearSun.0, nearSun.1).y > px(o, nearSun.0, nearSun.1).y + 0.01)
        #expect(abs(px(p, ground.0, ground.1).x - px(o, ground.0, ground.1).x) < 0.01)
    }

    @Test func chromaticAberrationSplitsColorAtTheEdges() {
        // A white bar near the left edge: red and blue edges land on different columns.
        let space = CGColorSpace(name: CGColorSpace.itur_709)!
        let c = CGContext(data: nil, width: 384, height: 216, bitsPerComponent: 8, bytesPerRow: 384 * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 384, height: 216))
        c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 10, y: 0, width: 20, height: 216))
        let bar = CIImage(cgImage: c.makeImage()!)
        let p = LookFrame.pixels(LookPipeline.filter(bar, kind: "filter.chromaticAberration", amount: 1, option: nil, frameIndex: 0))
        let row = 100
        let red = (0..<60).first { LookFrame.pixel(p, width: 384, $0, row).x > 0.5 }!, blue = (0..<60).first { LookFrame.pixel(p, width: 384, $0, row).z > 0.5 }!
        #expect(red < blue)
        let center = LookFrame.pixel(LookFrame.pixels(bar), width: 384, 192, row)
        #expect(LookFrame.pixel(p, width: 384, 192, row) == center)
    }

    @Test func vignetteDarkensTheCorners() {
        let o = original, p = run(.vignette)
        #expect(px(p, 2, 429).z < px(o, 2, 429).z - 0.02)
        #expect(abs(px(p, 384, 216).x - px(o, 384, 216).x) < 0.01)
    }

    @Test func grainIsTheSameForTheSameFrameAndNewEveryFrame() {
        let o = original
        for size in LookFilter.grain.options {
            let a = run(.grain, 0.4, option: size, frameIndex: 120), b = run(.grain, 0.4, option: size, frameIndex: 120), c = run(.grain, 0.4, option: size, frameIndex: 121)
            #expect(a == b)
            #expect(a != c)
            #expect(a != o)
            let meanShift = zip(a, o).map { Double($0 - $1) }.reduce(0, +) / Double(a.count)
            #expect(abs(meanShift) < 0.01)
        }
    }

    @Test func gateWeaveDriftsLessThanAPixel() {
        let a = run(.gateWeave, frameIndex: 10), b = run(.gateWeave, frameIndex: 10), c = run(.gateWeave, frameIndex: 14)
        #expect(a == b && a != c)
        #expect(zip(a, original).map { abs($0 - $1) }.max()! < 0.9)
    }

    @Test func letterboxAddsBarsToTheRatio() {
        let p = run(.letterbox, option: "2.39")
        let bar = Int((432 - 768 / 2.39) / 2) // 55
        #expect(px(p, 100, 2) == .zero && px(p, 100, 429) == .zero)
        #expect(px(p, 100, bar + 2) == px(original, 100, bar + 2))
        #expect(px(run(.letterbox, option: "1.85"), 100, 2) == .zero)
    }

    @Test func aLookRunsTheLUTThenFiltersInOrderAndPicksTheScenesOwn() {
        let warm = LookSettings(name: "Warm", filters: ["splitTone": 1, "grain": 0.4, "vignette": 0.2, "halation": 0.3], options: ["grain": "fine"])
        let mono = LookSettings(name: "Mono", filters: ["blackAndWhite": 1])
        let context = LookContext(look: FilmLook(film: warm, scenes: ["scene-3": mono]), sceneForAsset: ["take-3": "scene-3", "take-1": "scene-1"])
        let film = LookPipeline.apply(frame, context: context, storyAssetID: "take-1", frameIndex: 4)
        let scene = LookFrame.pixels(LookPipeline.apply(frame, context: context, storyAssetID: "take-3", frameIndex: 4))
        LookFrame.save(film, "look-warm")
        #expect(LookFrame.pixels(film) == LookFrame.pixels(LookPipeline.apply(frame, context: context, storyAssetID: "take-1", frameIndex: 4)))
        #expect(abs(scene[0] - scene[1]) < 0.01)
        #expect(LookFrame.pixels(LookPipeline.apply(frame, context: nil, storyAssetID: "take-1", frameIndex: 4)) == original)
    }
}

@Suite("The editor's looks", .serialized)
struct MakeLookTests {
    @Test func makesALookFromAStillAndReturnsBeforeAndAfter() async throws {
        let fixture = try await MediaFixture.make()
        defer { fixture.cleanup() }
        let folder = fixture.directory.appendingPathComponent("Looks folder")
        SharedSettings.looksFolderOverride = folder
        defer { SharedSettings.looksFolderOverride = nil }
        let asset = try fixture.store.read().assets[0]
        _ = try await fixture.runtime.invoke("direction_log_dailies", arguments: .object([
            "scenes": .array([.object(["number": .number(1), "title": .string("Cold open")])]),
            "takes": .array([.object(["assetID": .string(asset.id), "sceneNumber": .number(1), "code": .string("T1")])]),
        ]))
        // A warm reference: amber light, deep brown shadows.
        let still = fixture.directory.appendingPathComponent("window light.png")
        let space = CGColorSpace(name: CGColorSpace.itur_709)!
        let c = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 256, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 0.95, green: 0.72, blue: 0.40, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 32, height: 36))
        c.setFillColor(CGColor(red: 0.30, green: 0.18, blue: 0.08, alpha: 1)); c.fill(CGRect(x: 32, y: 0, width: 32, height: 36))
        try LookMaker.writePNG(CIImage(cgImage: c.makeImage()!), to: still, colorSpace: space)

        let made = try await fixture.runtime.invoke("direction_make_look", arguments: .object([
            "name": .string("Window light"), "fromStill": .string(still.path), "strength": .number(0.9),
            "filters": .array([.object(["kind": .string("grain"), "amount": .number(0.4), "option": .string("fine")]), .object(["kind": .string("halation"), "amount": .number(0.3)])]),
            "note": .string("Warm, one source, a lot of shadow."),
        ]))
        #expect(made.imagePaths.count == 2)
        #expect(made.value["look"]["filters"]["grain"].double == 0.4)
        let lutPath = try #require(made.value["look"]["lut"].string)
        #expect(lutPath.hasPrefix(fixture.store.editorLooksFolder.path))
        let lut = try CubeLUT.load(URL(fileURLWithPath: lutPath))
        #expect(lut.size == 33 && lut.title == "Window light")
        let before = try meanColor(URL(fileURLWithPath: made.imagePaths[0])), after = try meanColor(URL(fileURLWithPath: made.imagePaths[1]))
        // Matched to an amber still, the frame gets warmer.
        #expect(after.0 - after.2 > before.0 - before.2 + 20)

        let listed = try await fixture.runtime.invoke("direction_looks")
        let editor = listed.value["available"].array?.first { $0["byEditor"].bool == true }
        #expect(editor?["looks"].array?.first?["name"].string == "Window light")
        #expect(editor?["looks"].array?.first?["look"]["note"].string == "Warm, one source, a lot of shadow.")
        #expect(try fixture.store.filmLook().film == nil)
    }

    @Test func validatesCubeTextAndNeverSetsTheLook() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-looks-" + UUID().uuidString + ".direction")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try ProjectStore.create(at: path, name: "Launch film")
        let runtime = try ToolRuntime(store: store)
        do { _ = try await runtime.invoke("direction_make_look", arguments: .object(["name": .string("Broken"), "cube": .string("LUT_3D_SIZE 9\n")])); Issue.record("A bad cube must be refused") }
        catch let e as DirectionError { #expect(e.code == "lut_invalid") }
        do { _ = try await runtime.invoke("direction_make_look", arguments: .object(["name": .string("Mine now"), "filters": .array([.object(["kind": .string("grain")])]), "apply": .bool(true)])); Issue.record("The editor can't set the look") }
        catch let e as DirectionError { #expect(e.code == "look_is_yours") }
        do { _ = try await runtime.invoke("direction_make_look", arguments: .object(["name": .string("Odd"), "filters": .array([.object(["kind": .string("grain"), "option": .string("huge")])])])); Issue.record("Unknown grain size") }
        catch let e as DirectionError { #expect(e.code == "bad_argument") }

        // Cube text from the editor, filters only, and no cut yet: saved, with no stills.
        let made = try await runtime.invoke("direction_make_look", arguments: .object(["name": .string("Teal & amber"), "cube": .string(CubeLUT.identity(size: 17).text), "filters": .array([.object(["kind": .string("letterbox"), "option": .string("2.39")])])]))
        #expect(made.value["lut"]["size"].double == 17)
        #expect(made.value["look"]["filters"]["letterbox"].double == 1)
        #expect(made.imagePaths.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.editorLooksFolder.appendingPathComponent("teal-amber.json").path))
        do { _ = try store.setLook(LookSettings(name: "Mine"), asDirector: false); Issue.record("Only the director sets the look") }
        catch let e as DirectionError { #expect(e.code == "look_is_yours") }
        #expect(try store.filmLook().film == nil)
    }

    @Test func listsTheLooksFolderByGroupWithoutCameraLUTs() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-looks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let folder = path.appendingPathComponent("Looks")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Camera"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Kodak"), withIntermediateDirectories: true)
        try CubeLUT.identity(size: 17).text.write(to: folder.appendingPathComponent("Print film.cube"), atomically: true, encoding: .utf8)
        try "LUT_3D_SIZE 12\n".write(to: folder.appendingPathComponent("Broken.cube"), atomically: true, encoding: .utf8)
        try CubeLUT.identity(size: 17).text.write(to: folder.appendingPathComponent("Kodak/2383.cube"), atomically: true, encoding: .utf8)
        try CubeLUT.identity(size: 17).text.write(to: folder.appendingPathComponent("Camera/Apple Log.cube"), atomically: true, encoding: .utf8)
        let groups = LooksLibrary.folderGroups(folder)
        #expect(groups.map(\.name) == [LooksLibrary.folderGroup, "Kodak"])
        #expect(Set(groups[0].looks.map(\.name)) == ["Print film", "Broken"])
        #expect(groups[0].looks.first { $0.name == "Broken" }?.problem?.contains("size 12") == true)
        #expect(groups[0].looks.first { $0.name == "Print film" }?.problem == nil)

        let store = try ProjectStore.create(at: path.appendingPathComponent("Film.direction"), name: "Film")
        SharedSettings.looksFolderOverride = folder
        defer { SharedSettings.looksFolderOverride = nil }
        let runtime = try ToolRuntime(store: store)
        let listed = try await runtime.invoke("direction_looks")
        #expect(listed.value["camera"]["installed"].array == [.string("Apple Log")])
        #expect(listed.value["filters"].array?.map { $0["kind"].string ?? "" } == LookFilter.allCases.map(\.rawValue))
        // A LUT from the folder by name, at a strength.
        let made = try await runtime.invoke("direction_make_look", arguments: .object(["name": .string("Print, softer"), "fromLUT": .string("Print film"), "strength": .number(0.6)]))
        #expect(made.value["look"]["strength"].double == 0.6)
    }

    @Test func aLUTDroppedIntoTheFolderIsSeenWithinTwoSeconds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-watch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Kodak"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (changes, signal) = AsyncStream<Void>.makeStream()
        let watcher = LooksWatcher(paths: [folder]) { signal.yield() }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        let dropped = Date()
        try CubeLUT.identity(size: 17).text.write(to: folder.appendingPathComponent("Kodak/2383.cube"), atomically: true, encoding: .utf8)
        let seen = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in changes { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(2)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(seen && Date().timeIntervalSince(dropped) < 2)
        #expect(LooksLibrary.folderGroups(folder).map(\.name) == ["Kodak"])
    }

    @Test func findsLogNamesInMetadata() {
        #expect(CameraLog.match("s-log3-cine") == "S-Log3")
        #expect(CameraLog.match("LogC3") == "LogC")
        #expect(CameraLog.match("V-Log") == "V-Log")
        #expect(CameraLog.match("AppleLog") == "Apple Log")
        #expect(CameraLog.match("ITU_R_709_2") == nil)
    }
}

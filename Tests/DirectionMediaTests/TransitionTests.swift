import Testing
import Foundation
import CoreImage
import ImageIO
import DirectionCore
@testable import DirectionMedia
import DirectionTools

/// Transitions drawn from both shots, a clip pinned into a screen, and zooming through one
/// (agent-timeline.md › Transitions, Pin, Zoom through), on the media fixture: red until 1.5 s, then blue.
@Suite(.serialized)
struct TransitionTests {
    @discardableResult
    func edit(_ f: MediaFixture, _ ops: [String]) async throws -> JSONValue {
        let operations = try ops.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        return try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Test"), "operations": .array(operations)])).value
    }
    func expectError(_ code: String, _ f: MediaFixture, _ ops: [String], contains text: String? = nil) async {
        do { _ = try await edit(f, ops); Issue.record("Expected \(code)") }
        catch let e as DirectionError { #expect(e.code == code, "\(e.code): \(e.message)"); if let text { #expect(e.message.contains(text), "\(e.message)") } }
        catch { Issue.record("Unexpected error: \(error)") }
    }
    /// The mean color of part of a frame: x and y as fractions from the top left.
    func color(_ f: MediaFixture, _ t: Double, _ x: ClosedRange<Double> = 0...1, _ y: ClosedRange<Double> = 0...1) async throws -> (r: Double, g: Double, b: Double) {
        let compiled = try await SequenceRenderer.compile(project: f.store.read(), sequenceID: nil, cacheDirectory: f.runtime.cacheDirectory, previewMaxDimension: nil, looks: nil)
        let url = f.directory.appendingPathComponent(UUID().uuidString + ".png")
        _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: t), to: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DirectionError("test_frame", "Cannot read test image.") }
        let w = Double(image.width), h = Double(image.height)
        let part = image.cropping(to: CGRect(x: x.lowerBound * w, y: y.lowerBound * h, width: (x.upperBound - x.lowerBound) * w, height: (y.upperBound - y.lowerBound) * h))!
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(part, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(bytes[0]), Double(bytes[1]), Double(bytes[2]))
    }
    func red(_ c: (r: Double, g: Double, b: Double)) -> Bool { c.r > c.b * 2 }
    func blue(_ c: (r: Double, g: Double, b: Double)) -> Bool { c.b > c.r * 2 }

    /// Two shots with handle on both sides: red 0–1 s, then blue 1–2 s, cut at 1.0.
    func twoShots(_ f: MediaFixture) async throws -> (String, String) {
        _ = try await edit(f, [#"{"op":"removeRange","range":{"start":1,"end":2}}"#])
        let clips = try f.store.read().sequences[0].clips.filter { $0.kind == .video && $0.layer == 0 }.sorted { $0.start < $1.start }
        return (clips[0].id, clips[1].id)
    }

    @Test func directionsOwnTransitionsDrawBothShotsAtOnce() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let (a, b) = try await twoShots(f)
        // A push to the left: halfway through, the old shot is on the left and the new one on the right.
        let pushed = try await edit(f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"push","frames":10,"params":{"x":-1}}"#])
        #expect(pushed["operations"].array?[0]["summary"].string?.hasPrefix("Pushed into") == true)
        let v1 = try await color(f, 0.8)
        let v2 = try await color(f, 1.2)
        #expect(red(v1) && blue(v2))
        let v3 = try await color(f, 1.0, 0...0.3)
        let v4 = try await color(f, 1.0, 0.7...1)
        #expect(red(v3) && blue(v4))
        let v5 = try await f.runtime.invoke("direction_timeline", arguments: .object(["outlineOnly": .bool(true)])).value["outline"].string
        #expect(v5?.contains("push 10f in") == true)
        // A wipe from the left brings the new shot in from that side.
        _ = try await edit(f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"wipe","frames":10}"#])
        let v6 = try await color(f, 1.0, 0...0.3)
        let v7 = try await color(f, 1.0, 0.7...1)
        #expect(blue(v6) && red(v7))
        // An iris opens from the middle.
        _ = try await edit(f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"iris","frames":10}"#])
        let v8 = try await color(f, 1.0, 0.4...0.6, 0.4...0.6)
        let v9 = try await color(f, 1.0, 0...0.1, 0...0.1)
        #expect(blue(v8) && red(v9))
        // Whip and zoom draw too, and end on the new shot.
        for type in ["whip", "zoom", "slide"] {
            _ = try await edit(f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"\#(type)","frames":10}"#])
            let mid = try await color(f, 1.0)
            #expect(mid.r > 20 && mid.b > 20, "\(type) shows both shots halfway")
            let v10 = try await color(f, 1.2)
            #expect(blue(v10))
        }
        await expectError("bad_argument", f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"push","frames":10,"params":{"x":3}}"#], contains: "push.x")
        await expectError("bad_argument", f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"push","frames":10,"params":{"spin":1}}"#], contains: "no parameter spin")
        await expectError("bad_argument", f, [#"{"op":"transition","editPoint":"|\#(a)","type":"push","frames":10}"#], contains: "needs a clip on each side")
    }

    @Test func theEditorsOwnTransitionIsCheckedThenDrawn() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let (a, b) = try await twoShots(f)
        let folder = f.store.url.appendingPathComponent("Editor/Transitions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        // direction: param edge 0 1 0.5
        // The new shot comes in from the top, a hard edge at `edge` of the way through.
        [[ stitchable ]] float4 drop(coreimage::sampler from, coreimage::sampler to, float progress, float edge, coreimage::destination dest) {
            float2 uv = direction::uv(from, dest);
            return uv.y > 1.0 - progress ? direction::at(to, uv) : direction::at(from, uv);
        }
        """.write(to: folder.appendingPathComponent("drop.metal"), atomically: true, encoding: .utf8)
        let catalog = try await f.runtime.invoke("direction_edit_catalog").value
        #expect(catalog["customTransitions"].array?.first?["file"].string == "Transitions/drop.metal" && catalog["customTransitions"].array?.first?["params"].array?.count == 1)
        _ = try await edit(f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"shader","frames":10,"params":{"file":"Transitions/drop.metal","edge":0.2}}"#])
        let v11 = try await color(f, 1.0, 0...1, 0...0.3)
        let v12 = try await color(f, 1.0, 0...1, 0.7...1)
        #expect(blue(v11) && red(v12))
        let t = try #require(try f.store.read().sequences[0].clips.first { $0.id == b }?.transition)
        #expect(t.type == "shader" && t.file == "Transitions/drop.metal" && t.params?["edge"]?.double == 0.2 && t.source?.contains("drop") == true)
        try "[[ stitchable ]] float4 bad(coreimage::sampler from, coreimage::sampler to, float progress) {\n    return nope;\n}\n".write(to: folder.appendingPathComponent("bad.metal"), atomically: true, encoding: .utf8)
        await expectError("shader_invalid", f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"shader","frames":10,"params":{"file":"Transitions/bad.metal"}}"#], contains: "line 2")
        await expectError("bad_argument", f, [#"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"shader","frames":10,"params":{"file":"Effects/drop.metal"}}"#])
        // The cut kept the one that worked.
        #expect(try f.store.read().sequences[0].clips.first { $0.id == b }?.transition?.file == "Transitions/drop.metal")
    }

    @Test func aPinnedClipSitsInItsCornersAndZoomThroughOpensItOut() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let (a, b) = try await twoShots(f)
        let asset = try f.store.read().assets[0].id
        // A blue picture pinned into the middle of the red shot.
        let placed = try await edit(f, [#"{"op":"cutaway","assetID":"\#(asset)","sourceRange":{"start":2,"duration":0.4},"at":0.1}"#])
        let over = try #require(placed["operations"].array?[0]["clipIDs"].array?.first?.string)
        _ = try await edit(f, [#"{"op":"pin","clipID":"\#(over)","corners":[[0.3,0.3],[0.7,0.3],[0.7,0.7],[0.3,0.7]]}"#])
        let v13 = try await color(f, 0.3, 0.4...0.6, 0.4...0.6)
        let v14 = try await color(f, 0.3, 0...0.2, 0...0.2)
        #expect(blue(v13) && red(v14))
        await expectError("bad_argument", f, [#"{"op":"pin","clipID":"\#(a)","corners":[[0.3,0.3],[0.7,0.3],[0.7,0.7],[0.3,0.7]]}"#], contains: "V2 or above")
        await expectError("bad_argument", f, [#"{"op":"pin","clipID":"\#(over)","corners":[[0.3,0.3],[0.7,0.3]]}"#], contains: "four")

        // Zooming through a screen in the middle of the red shot into the blue one.
        let zoomed = try await edit(f, [#"{"op":"zoomThrough","editPoint":"\#(a)|\#(b)","seconds":0.5,"corners":[[0.35,0.35],[0.65,0.35],[0.65,0.65],[0.35,0.65]]}"#])
        #expect(zoomed["operations"].array?[0]["summary"].string?.hasPrefix("Pushed into the screen") == true)
        let s = try f.store.read().sequences[0]
        let left = try #require(s.clips.first { $0.id == a })
        #expect(left.effects?.first { $0.name == "transform" }?.keys?["scale"]?.last?.v ?? 0 > 3)
        let held = try #require(s.clips.first { $0.hold != nil && $0.layer > 0 })
        #expect(held.effects?.contains { $0.name == "pin" && $0.keys?["tl.x"] != nil } == true && abs(held.start.seconds - 0.5) < 0.02)
        // As the push begins the new shot is in the screen; by the cut it fills the frame, and the cut is seamless.
        let v15 = try await color(f, 0.52, 0.45...0.55, 0.45...0.55)
        let v16 = try await color(f, 0.52, 0...0.15, 0...0.15)
        #expect(blue(v15) && red(v16))
        let v17 = try await color(f, 0.98, 0...0.15, 0...0.15)
        let v18 = try await color(f, 0.98)
        #expect(blue(v17) && blue(v18))
        let v19 = try await color(f, 1.05)
        #expect(blue(v19))
        await expectError("bad_argument", f, [#"{"op":"zoomThrough","editPoint":"\#(a)|\#(b)","corners":[[0.35,0.35],[0.65,0.35],[0.65,0.65],[0.35,0.65]]}"#], contains: "already has a transform")
    }

    @Test func theSkillsExampleTransitionCompilesAndRuns() throws {
        let skill = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../plugins/direction/skills/transitions/SKILL.md")
        let text = try String(contentsOf: skill, encoding: .utf8)
        let start = try #require(text.range(of: "```metal\n")), end = try #require(text.range(of: "```", range: start.upperBound..<text.endIndex))
        let source = text[start.upperBound..<end.lowerBound].split(separator: "\n", omittingEmptySubsequences: false).map { $0.hasPrefix("  ") ? String($0.dropFirst(2)) : String($0) }.joined(separator: "\n")
        #expect(try TransitionShader.check(source: source)["params"].array?.count == 1)
        for type in ["push", "slide", "whip", "zoom", "wipe", "iris"] { _ = try TransitionShader.check(source: try #require(TransitionShader.builtIn(type))) }
    }

    @Test func visionFindsAScreenAndSaysWhenThereIsNone() throws {
        func picture(_ draw: (CGContext) -> Void) -> CGImage {
            let c = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.setFillColor(CGColor(gray: 0.08, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            draw(c)
            return c.makeImage()!
        }
        // A bright screen from 0.25 to 0.75 across and 0.3 to 0.7 down (CGContext's y is up).
        let screen = picture { $0.setFillColor(CGColor(gray: 0.95, alpha: 1)); $0.fill(CGRect(x: 160, y: 108, width: 320, height: 144)) }
        let found = try #require(try TimelineAnalysis.quads(in: screen).first)
        #expect(abs(found[0].x - 0.25) < 0.03 && abs(found[0].y - 0.3) < 0.03 && abs(found[2].x - 0.75) < 0.03 && abs(found[2].y - 0.7) < 0.03)
        #expect(try TimelineAnalysis.quads(in: picture { _ in }).isEmpty)
    }

    @Test func aFreezeKeepsTheValuesItHadAndKeysPlayOverAHold() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let id = try f.store.read().sequences[0].clips[0].id
        _ = try await edit(f, [#"{"op":"addEffect","target":"\#(id)","effect":"transform","params":{},"keys":{"scale":[{"t":0,"v":1},{"t":1,"v":2}]}}"#])
        let frozen = try await edit(f, [#"{"op":"freeze","clipID":"\#(id)","at":0.5,"seconds":1}"#])
        let hold = try #require(try f.store.read().sequences[0].clips.first { $0.id == frozen["operations"].array?[0]["clipIDs"].array?.first?.string })
        let scale = try #require(hold.effects?.first { $0.name == "transform" })
        #expect(scale.keys == nil && abs((scale.params["scale"]?.double ?? 0) - 1.5) < 0.05)
    }
}

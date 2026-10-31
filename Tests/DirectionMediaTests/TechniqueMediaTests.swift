import Testing
import Foundation
import CoreImage
import AVFoundation
import DirectionCore
@testable import DirectionMedia
@testable import DirectionTools

/// Techniques (techniques.md): the pixel grid drawn from Direction's measurements, the subject found square by
/// square, and techniques saved, listed and used through the editor's tools.
@Suite(.serialized) struct TechniqueMediaTests {
    private func pixel(_ image: CIImage, _ x: Int, _ y: Int) -> [Double] {
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return px.map { Double($0) / 255 }
    }

    @Test func thePixelGridShowsTheClipOnlyInTheSquaresItsSubjectFills() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)
        // Two by two: the top left square full, the bottom right a quarter full, the rest empty.
        let fx = ClipEffect(name: "pixelGrid", params: ["threshold": .number(0.5), "lines": .number(1), "lineWidth": .number(4)], data: "pixelGrid v1 2 2 15.0 0\nf004")
        let out = PixelGrid.apply(red, fx, at: 0, bounds: bounds)
        // Core Image's y runs up: the top left square is x < 200, y > 100.
        #expect(pixel(out, 50, 150)[0] > 0.95 && pixel(out, 50, 150)[3] > 0.95)
        #expect(pixel(out, 50, 50)[3] < 0.05 && pixel(out, 250, 150)[3] < 0.05)
        // A quarter full, with half needed to show fully: half shown.
        #expect(abs(pixel(out, 350, 50)[3] - 4.0 / 15 / 0.5) < 0.05)
        // The lines cross the whole frame, over the empty squares too.
        #expect(pixel(out, 200, 50)[3] > 0.9 && pixel(out, 300, 100)[3] > 0.9 && pixel(out, 300, 100)[0] < 0.2)
        // Without its measurements, the clip shows as it is.
        #expect(pixel(PixelGrid.apply(red, ClipEffect(name: "pixelGrid"), at: 0, bounds: bounds), 50, 50)[3] > 0.95)
    }

    @Test func theSubjectIsFoundSquareBySquare() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-cells-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let movie = root.appendingPathComponent("Screen Recording.mov")
        try await writeScreenMovie(to: movie)
        let a = try await MediaInspector.inspect(url: movie, thumbnailDirectory: root)
        let data = try await SubjectCells.measure(a, from: 0, to: 1, cols: 8, aspect: 16.0 / 9, cacheDirectory: root)
        let lines = data.split(separator: "\n")
        // Fifteen looks a second, one hex digit for each of 8 × 5 squares (nothing to find before the cursor at 1 s).
        #expect(lines.first == "pixelGrid v1 8 5 15.0 0.0" && lines.count == 17 && lines.dropFirst().allSatisfy { $0.count == 40 })
        // Read again, it comes from what was kept.
        #expect(try await SubjectCells.measure(a, from: 0, to: 1, cols: 8, aspect: 16.0 / 9, cacheDirectory: root) == data)
    }

    @Test func aTechniqueIsSavedListedAndUsedByName() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let editor = f.store.url.appendingPathComponent("Editor/Techniques/flash")
        try FileManager.default.createDirectory(at: editor, withIntermediateDirectories: true)
        try Data(StyleToolTests.glint.utf8).write(to: editor.appendingPathComponent("glint.metal"))
        try MediaFixture.writeTone(to: editor.appendingPathComponent("tick.wav"), frequency: 2400, seconds: 0.2)
        let folder = SharedSettings.techniquesFolder
        try? FileManager.default.removeItem(at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }

        // A transition's Metal is compiled before it's kept; a broken one isn't.
        try Data("not metal".utf8).write(to: editor.appendingPathComponent("broken.metal"))
        do {
            _ = try await f.runtime.invoke("direction_save_technique", arguments: .object(["name": .string("Broken"), "kind": .string("transition"), "summary": .string("x"), "when": .string("y"), "transition": .object(["type": .string("shader"), "file": .string("t.metal"), "frames": .number(10)]),
                                                                                     "files": .array([.object(["from": .string("Techniques/flash/broken.metal"), "to": .string("t.metal")])])]))
            Issue.record("Broken Metal isn't kept")
        } catch let e as DirectionError { #expect(e.code == "shader_invalid") }

        let saved = try await f.runtime.invoke("direction_save_technique", arguments: .object([
            "name": .string("Warm glint"), "kind": .string("transition"), "summary": .string("A band of warm light sweeps across the cut."), "when": .string("Chapter changes."), "needs": .string("Handles both sides."),
            "transition": .object(["type": .string("shader"), "file": .string("glint.metal"), "frames": .number(10), "params": .object(["strength": .number(0.5)]), "sound": .string("sounds/tick.wav"), "soundDB": .number(-16)]),
            "variants": .array([.object(["name": .string("Strong"), "params": .object(["strength": .number(1)])]), .object(["name": .string("Long"), "frames": .number(14)])]),
            "source": .object(["title": .string("A tutorial"), "url": .string("https://example.com/v"), "author": .string("Someone")]),
            "files": .array([.object(["from": .string("Techniques/flash/glint.metal"), "to": .string("glint.metal")]), .object(["from": .string("Techniques/flash/tick.wav"), "to": .string("sounds/tick.wav")])]),
        ])).value
        #expect(saved["id"].string == "warm-glint" && saved["files"].array?.count == 2)
        let listed = try await f.runtime.invoke("direction_techniques").value["techniques"].array ?? []
        #expect(listed.map { $0["name"].string } == ["Warm glint"] && listed[0]["variants"].array?.count == 2)

        // Used by name at a cut: its Metal, the variant's length and settings, and its sound under the cut.
        let v1 = try #require(try f.store.read().sequences[0].clips.first { $0.layer == 0 && $0.kind == .video })
        func edit(_ ops: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.read().editRevision)), "summary": .string("Technique"), "operations": .array(ops)])).value
        }
        _ = try await edit([.object(["op": .string("split"), "clipID": .string(v1.id), "at": .number(1.5)])])
        let shots = try f.store.read().sequences[0].clips.filter { $0.layer == 0 && $0.kind == .video }.sorted { $0.start < $1.start }
        do { _ = try await edit([.object(["op": .string("technique"), "name": .string("Warm glint"), "editPoint": .string("\(shots[0].id)|\(shots[1].id)"), "variant": .string("Huge")])]); Issue.record("No such variant") }
        catch let e as DirectionError { #expect(e.message.contains("Strong, Long")) }
        let made = try await edit([.object(["op": .string("technique"), "name": .string("warm glint"), "editPoint": .string("\(shots[0].id)|\(shots[1].id)"), "variant": .string("Long")])])
        #expect(made["operations"].array?.first?["summary"].string?.contains("tick under it") == true)
        let p = try f.store.read()
        let cut = try #require(p.sequences[0].clips.first { $0.id == shots[1].id })
        #expect(cut.transition?.type == "shader" && cut.transition?.frames == 14 && cut.transition?.params?["strength"]?.double == 0.5)
        let tick = try #require(p.sequences[0].clips.first { $0.kind == .audio && $0.layer >= 2 })
        #expect(tick.gainDB == -16 && p.assets.first { $0.id == tick.assetID }?.path.hasPrefix(folder.path) == true)
    }
}

/// The library's previews (techniques.md › The library): every entry plays on the same made-up shots.
@Suite(.serialized) struct LibraryPreviewTests {
    @Test func everyKindOfEntryRendersAPreviewAndAPoster() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-previews-" + UUID().uuidString)
        defer { if ProcessInfo.processInfo.environment["DIRECTION_KEEP_PREVIEWS"] == nil { try? FileManager.default.removeItem(at: root) } }
        let pick = ["builtin-whip", "builtin-punchIn", "builtin-halation", "builtin-screenZoom", "builtin-dipToBlack"]
        var entries = LibraryCatalog.builtIns.filter { pick.contains($0.id) }
        entries.append(LibraryEntry(id: "pixel-grid", name: "Pixel grid", kind: "effect", summary: "", icon: "squareshape.split.3x3", use: "",
                                    technique: Technique(id: "pixel-grid", url: root, tokens: .object(["name": .string("Pixel grid"), "kind": .string("effect"), "effect": .object(["name": .string("pixelGrid"), "params": .object(["cells": .number(12)])])]))))
        for e in entries {
            let subject = try #require(LibraryPreviews.subject(for: e))
            let out = root.appendingPathComponent(e.id + ".mp4")
            try await LibraryPreviews.render(subject, to: out, cacheDirectory: root.appendingPathComponent("cache"))
            let length = try await AVURLAsset(url: out).load(.duration).seconds
            #expect(abs(length - 3) < 0.1, "\(e.name) is \(length) s")
            #expect(FileManager.default.fileExists(atPath: out.deletingPathExtension().appendingPathExtension("jpg").path), "\(e.name) has a poster")
        }
        // Every one of Direction's own has a preview to make.
        #expect(LibraryCatalog.builtIns.allSatisfy { LibraryPreviews.subject(for: $0) != nil })
    }
}

/// Makes every preview in the library into DIRECTION_CACHE_DIR, for snapshots; only when asked.
@Suite(.serialized) struct LibraryPreviewBatch {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIRECTION_RENDER_LIBRARY"] != nil)) func renderEveryPreview() async throws {
        for e in LibraryCatalog.entries(techniques: TechniqueLibrary.list(in: SharedSettings.techniquesFolder)) {
            guard let subject = LibraryPreviews.subject(for: e) else { continue }
            let url = ToolRuntime.previewURL(for: e)
            if !FileManager.default.fileExists(atPath: url.path) { try await LibraryPreviews.render(subject, to: url, cacheDirectory: DirectionPaths.caches) }
        }
    }
}

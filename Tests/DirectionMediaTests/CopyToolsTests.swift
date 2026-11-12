import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import DirectionCore
import DirectionTools

/// direction_copy: the editor's `cp`, from places Direction vouches for into its working folder only.
struct CopyToolsTests {
    private func film() throws -> (ToolRuntime, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("copy-\(UUID().uuidString).direction")
        return (try ToolRuntime(store: try ProjectStore.create(at: dir, name: "Copy film")), dir)
    }
    private func copy(_ runtime: ToolRuntime, _ a: [String: JSONValue]) async throws -> ToolResponse {
        try await runtime.invoke("direction_copy", arguments: .object(a))
    }
    private func refusal(_ runtime: ToolRuntime, _ a: [String: JSONValue]) async -> String? {
        do { _ = try await copy(runtime, a); return nil } catch { return (error as? DirectionError)?.code }
    }

    @Test func aFontByItsNameAndAStillInAnotherKind() async throws {
        let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
        let font = try await copy(runtime, ["font": .string("Helvetica"), "to": .string("Graphics/title/helvetica.ttc")])
        #expect(font.value["path"] == .string("Graphics/title/helvetica.ttc"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Editor/Graphics/title/helvetica.ttc").path))
        #expect(await refusal(runtime, ["font": .string("No Such Font Anywhere"), "to": .string("x.otf")]) == "font_not_found")
        // A frame a tool drew, as a jpg; again, it replaces the first.
        let png = runtime.cacheDirectory.appendingPathComponent("Frames/f.png")
        try FileManager.default.createDirectory(at: png.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let out = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(out, context.makeImage()!, nil); #expect(CGImageDestinationFinalize(out))
        for _ in 0..<2 { _ = try await copy(runtime, ["from": .string(png.path), "to": .string("stills/opening.jpg")]) }
        let jpg = dir.appendingPathComponent("Editor/stills/opening.jpg")
        #expect(CGImageSourceCreateWithURL(jpg as CFURL, nil).flatMap(CGImageSourceGetType) as String? == UTType.jpeg.identifier)
        #expect(try FileManager.default.contentsOfDirectory(atPath: jpg.deletingLastPathComponent().path) == ["opening.jpg"])
    }

    /// Only into the folder, never over an agent's settings or instructions; only from Direction's places.
    @Test func onlyIntoTheFolderAndOnlyFromDirectionsPlaces() async throws {
        let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
        for to in ["../project.sqlite", "/tmp/x.otf", ".claude/settings.json", "Graphics/.hidden/x", "CLAUDE.md", "AGENTS.md", "Graphics/../../x"] {
            #expect(await refusal(runtime, ["font": .string("Helvetica"), "to": .string(to)]) == "copy_not_here", "\(to)")
        }
        #expect(await refusal(runtime, ["from": .string("/etc/hosts"), "to": .string("hosts")]) == "copy_not_from_here")
        // Hidden files are refused even inside the film (an agent's settings live there).
        let hidden = dir.appendingPathComponent("Editor/.mcp.json")
        try FileManager.default.createDirectory(at: hidden.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: hidden)
        #expect(await refusal(runtime, ["from": .string(hidden.path), "to": .string("x.json")]) == "copy_not_from_here")
        // One file, never a folder.
        #expect(await refusal(runtime, ["from": .string(dir.appendingPathComponent("Editor").path), "to": .string("x")]) == "copy_not_a_file")
        #expect(await refusal(runtime, ["font": .string("Helvetica"), "to": .string("Graphics/title/")]) == "copy_not_here")
        #expect(await refusal(runtime, ["font": .string("Helvetica"), "from": .string("/etc/hosts"), "to": .string("x")]) == "invalid_arguments")
        // A file in the film comes in.
        let inFilm = dir.appendingPathComponent("Library/Images/logo.txt")
        try FileManager.default.createDirectory(at: inFilm.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("logo".utf8).write(to: inFilm)
        _ = try await copy(runtime, ["from": .string(inFilm.path), "to": .string("Graphics/end/logo.txt")])
        #expect(try String(contentsOf: dir.appendingPathComponent("Editor/Graphics/end/logo.txt"), encoding: .utf8) == "logo")
        // A graphic's folder named as where to copy isn't replaced by the file.
        #expect(await refusal(runtime, ["from": .string(inFilm.path), "to": .string("Graphics/end")]) == "copy_not_here")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Editor/Graphics/end/logo.txt").path))
    }

    /// The editor's own commands (Codex keeps them) or a shared film could point a link anywhere; Direction writes
    /// outside the editor's sandbox, so a copy never goes through one.
    @Test func aCopyNeverGoesThroughALink() async throws {
        let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default, editor = dir.appendingPathComponent("Editor")
        let outside = fm.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true); defer { try? fm.removeItem(at: outside) }
        try fm.createDirectory(at: editor.appendingPathComponent("Graphics"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: editor.appendingPathComponent("Graphics/la"), withDestinationURL: outside)
        #expect(await refusal(runtime, ["font": .string("Helvetica"), "to": .string("Graphics/la/evil.ttc")]) == "copy_not_here")
        #expect(await refusal(runtime, ["font": .string("Helvetica"), "to": .string("Graphics/la/deeper/evil.ttc")]) == "copy_not_here")
        // A link as the file itself.
        try fm.createSymbolicLink(at: editor.appendingPathComponent("Graphics/x.ttc"), withDestinationURL: outside.appendingPathComponent("x.ttc"))
        #expect(await refusal(runtime, ["font": .string("Helvetica"), "to": .string("Graphics/x.ttc")]) == "copy_not_here")
        #expect(try fm.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}

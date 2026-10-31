import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

/// The editor's side of styles (specs/styles.md): reading what the film follows, writing a style when asked,
/// and the style's layouts and moves carried out by name.
@Suite("The editor's styles", .serialized)
struct StyleToolTests {
    @Test func theEditorSavesAStyleAndReadsTheFilms() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-style-tools-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let styles = root.appendingPathComponent("Styles")
        SharedSettings.stylesFolderOverride = styles
        defer { SharedSettings.stylesFolderOverride = nil }
        let store = try ProjectStore.create(at: root.appendingPathComponent("Launch film.direction"), name: "Launch film")
        let runtime = try ToolRuntime(store: store)
        #expect(try await runtime.invoke("direction_brief").value["style"] == .null)
        // Without a style, the film follows the house style: empty until the director keeps a rule in it.
        let bare = try await runtime.invoke("direction_style").value
        #expect(bare["id"].string == "house" && bare["rules"].array?.isEmpty == true && bare["moves"]["punchIn"]["scales"].array?.count == 2)

        // Parts come from the editor's working folder.
        let editor = store.url.appendingPathComponent("Editor")
        try FileManager.default.createDirectory(at: editor.appendingPathComponent("Graphics/lower-third"), withIntermediateDirectories: true)
        try Data("<script>direction.graphic({})</script>".utf8).write(to: editor.appendingPathComponent("Graphics/lower-third/index.html"))
        let saved = try await runtime.invoke("direction_save_style", arguments: .object([
            "name": .string("Desk Talk"), "summary": .string("Quick explainers."),
            "tokens": .object(["captions": .object(["wordsAtATime": .number(3)])]), "rules": .array([.object(["area": .string("pace"), "text": .string("Three-second shots.")])]),
            "files": .array([.object(["from": .string("Graphics/lower-third"), "to": .string("graphics/lower-third")])]),
        ])).value
        #expect(saved["id"].string == "desk-talk" && saved["parts"]["graphics"].array?.first?["copyTo"].string == "Graphics/lower-third")
        do {
            _ = try await runtime.invoke("direction_save_style", arguments: .object(["id": .string("desk-talk"), "files": .array([.object(["from": .string("/etc/hosts"), "to": .string("sounds/hosts.wav")])])]))
            Issue.record("Only files in the film go into a style")
        } catch let e as DirectionError { #expect(e.code == "invalid_arguments") }
        #expect(try await runtime.invoke("direction_styles").value["styles"].array?.map { $0["name"].string } == ["Desk Talk"])

        // Once the brief names it, the film's copy is what the editor reads.
        var brief = Brief(); brief.logline = "Maya builds it."; brief.feeling = "Proud."; brief.style = "desk-talk"
        try store.saveBrief(brief, styles: styles)
        let named = try await runtime.invoke("direction_brief").value["style"]
        #expect(named["name"].string == "Desk Talk")
        let read = try await runtime.invoke("direction_style").value
        #expect(read["values"]["captions"]["wordsAtATime"].double == 3 && read["rules"].array?.map { $0["text"].string } == ["Three-second shots."])
        #expect(read["parts"]["graphics"].array?.first?["path"].string?.hasPrefix(store.url.appendingPathComponent("Style").path) == true)
        #expect(try await runtime.invoke("direction_graphic_examples").value["fromStyle"].array?.first?["name"].string == "lower-third")

        // Changing the film's own style copies it again; rules come and go by id.
        _ = try await runtime.invoke("direction_save_style", arguments: .object(["id": .string("desk-talk"), "summary": .string("Faster now."), "rules": .array([.object(["area": .string("avoid"), "text": .string("No dissolves.")])])]))
        let faster = try await runtime.invoke("direction_style").value
        #expect(faster["summary"].string == "Faster now." && faster["rules"].array?.count == 2)
        let first = try #require(faster["rules"].array?.first?["id"].string)
        _ = try await runtime.invoke("direction_save_style", arguments: .object(["id": .string("desk-talk"), "removeRules": .array([.string(first)])]))
        #expect(try await runtime.invoke("direction_style").value["rules"].array?.map { $0["text"].string } == ["No dissolves."])

        // The house style's rules come first, then the style's, each saying where it's from.
        _ = try await runtime.invoke("direction_save_style", arguments: .object(["id": .string("house"), "rules": .array([.object(["area": .string("graphics"), "text": .string("Text never covers my face.")])])]))
        let both = try await runtime.invoke("direction_style").value
        #expect(both["rules"].array?.map { $0["from"].string } == ["House style", "Desk Talk"] && both["follows"].string?.contains("Desk Talk wins") == true)
        #expect(try await runtime.invoke("direction_styles").value["house"]["rules"].double == 1)
    }

    @Test func theEditorUsesTheStylesLayoutsAndMovesByName() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let styles = f.directory.appendingPathComponent("Styles")
        SharedSettings.stylesFolderOverride = styles
        defer { SharedSettings.stylesFolderOverride = nil }
        try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
        _ = try StyleLibrary.save(id: nil, name: "Desk + Screen", summary: "", tokens: .object([
            "layouts": .array([.object(["name": .string("Talking"), "kind": .string("you")]), .object(["name": .string("Showing"), "kind": .string("screenAndYou"), "corner": .string("topRight"), "shape": .string("rounded"), "edge": .string("#FFD43B")])]),
            "moves": .object(["punchIn": .object(["scales": .array([.number(1), .number(1.2)])])]),
        ]), guide: nil, in: styles)
        // Its Chapter transition is its own Metal with a whoosh under it.
        let parts = f.directory.appendingPathComponent("parts")
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        try Data(Self.glint.utf8).write(to: parts.appendingPathComponent("glint.metal"))
        try MediaFixture.writeTone(to: parts.appendingPathComponent("whoosh.wav"), frequency: 660, seconds: 0.6)
        _ = try StyleLibrary.save(id: "desk-screen", name: nil, summary: nil, tokens: .object(["transitions": .array([
            .object(["name": .string("Chapter"), "type": .string("shader"), "file": .string("transitions/glint.metal"), "frames": .number(10), "sound": .string("sounds/whoosh.wav"), "soundDB": .number(-20)]),
            .object(["name": .string("New section"), "type": .string("slide"), "frames": .number(8), "params": .object(["x": .number(-1)])]),
        ])]), guide: nil, files: [(parts.appendingPathComponent("glint.metal"), "transitions/glint.metal"), (parts.appendingPathComponent("whoosh.wav"), "sounds/whoosh.wav")], in: styles)
        var brief = Brief(); brief.logline = "A demo."; brief.feeling = "Clear."; brief.style = "desk-screen"
        try f.store.saveBrief(brief, styles: styles)

        // A screen recording in sync with the take on V1, which stands in for the camera.
        let copy = f.directory.appendingPathComponent("Screen Recording 2026-10-31.mov")
        try FileManager.default.copyItem(at: f.source, to: copy)
        _ = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(copy.path)]))
        var p = try f.store.read()
        let story = try #require(p.assets.first { $0.path == f.source.path }), screen = try #require(p.assets.first { $0.path == copy.path })
        try f.store.saveSync([SyncGroup(id: "sync-1", soundAssetID: story.id, takes: [SyncedTake(assetID: story.id, offset: 0, match: 1), SyncedTake(assetID: screen.id, offset: 0, match: 1)], method: "sound", createdAt: 0)], checked: [story.id, screen.id])

        func edit(_ ops: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.read().editRevision)), "summary": .string("Style"), "operations": .array(ops)])).value
        }
        let length = p.sequences[0].duration.seconds
        let range: JSONValue = .object(["start": .number(0), "end": .number(length)])
        do { _ = try await edit([.object(["op": .string("layout"), "range": range, "layout": .string("Detail")])]); Issue.record("The style has no Detail") }
        catch let e as DirectionError { #expect(e.code == "bad_argument" && e.message.contains("Talking, Showing")) }
        _ = try await edit([.object(["op": .string("layout"), "range": range, "layout": .string("showing")])])
        p = try f.store.read()
        let bubble = try #require(p.sequences[0].clips.first { $0.layout?.role == .camera })
        #expect(bubble.layout?.layout.name == "Showing" && bubble.layout?.layout.corner == .topRight && bubble.effects?.first { $0.name == "card" }?.params["edgeColor"] == .string("#FFD43B"))

        // A move with the style's numbers: split the take into a jump cut, then punch in on it. Under Showing
        // the story doesn't show, so nothing is framed; under Talking the camera a layout puts full frame is.
        let v1 = try #require(p.sequences[0].clips.first { $0.layer == 0 && $0.kind == .video })
        _ = try await edit([.object(["op": .string("split"), "clipID": .string(v1.id), "at": .number(1)]), .object(["op": .string("punchIn"), "range": range])])
        #expect(try f.store.read().sequences[0].clips.allSatisfy { $0.layer > 0 || $0.effects?.contains { $0.name == "transform" } != true })
        _ = try await edit([.object(["op": .string("layout"), "range": range, "layout": .string("Talking")]), .object(["op": .string("punchIn"), "range": range])])
        let cameras = try f.store.read().sequences[0].clips.filter { $0.layout?.role == .camera }.sorted { $0.start < $1.start }
        #expect(cameras.map { $0.effects?.first { $0.name == "transform" }?.params["scale"]?.double }.prefix(2) == [1, 1.2])

        // The style's Chapter at the jump cut: its Metal from the film's copy of the style, its whoosh under the cut.
        let shots = try f.store.read().sequences[0].clips.filter { $0.layer == 0 && $0.kind == .video }.sorted { $0.start < $1.start }
        let point = "\(shots[0].id)|\(shots[1].id)"
        do { _ = try await edit([.object(["op": .string("transition"), "editPoint": .string(point), "name": .string("Finale")])]); Issue.record("The style has no Finale") }
        catch let e as DirectionError { #expect(e.message.contains("Chapter, New section")) }
        _ = try await edit([.object(["op": .string("transition"), "editPoint": .string(point), "name": .string("chapter")])])
        p = try f.store.read()
        let cut = try #require(p.sequences[0].clips.first { $0.id == shots[1].id })
        #expect(cut.transition?.type == "shader" && cut.transition?.file == "transitions/glint.metal" && cut.transition?.frames == 10)
        let whoosh = try #require(p.sequences[0].clips.first { $0.kind == .audio && $0.layer >= 2 })
        #expect(whoosh.gainDB == -20 && p.assets.first { $0.id == whoosh.assetID }?.path.hasPrefix(f.store.url.appendingPathComponent("Style").path) == true)
        #expect(abs(whoosh.start.seconds + whoosh.duration.seconds / 2 - cut.start.seconds) < 0.05)
    }

    static let glint = """
    // direction: param angle -90 90 25
    // direction: param strength 0 1 0.55
    [[ stitchable ]] float4 glint(coreimage::sampler from, coreimage::sampler to, float progress, float angle, float strength, coreimage::destination dest) {
        float2 uv = direction::uv(from, dest);
        float r = angle * 3.14159265 / 180.0;
        float2 d = float2(cos(r), sin(r));
        float along = dot(uv - 0.5, d) / (0.5 * (abs(d.x) + abs(d.y)));
        float band = exp(-pow((along - mix(-1.5, 1.5, progress)) / 0.22, 2.0));
        float4 c = mix(direction::at(from, uv), direction::at(to, uv), smoothstep(0.38, 0.62, progress));
        float glow = clamp(strength * band * sin(3.14159265 * progress), 0.0, 1.0);
        float3 warm = float3(1.0, 0.95, 0.84) * c.a;
        return float4(mix(c.rgb, warm, glow), c.a);
    }
    """
}

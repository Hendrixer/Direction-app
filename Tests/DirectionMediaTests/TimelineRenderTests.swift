import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreImage
import DirectionCore
@testable import DirectionMedia
import DirectionTools

/// What the editor's edit functions look and sound like (agent-timeline.md › What Direction renders),
/// on the media fixture: 3 s, red then blue at 1.5 s, a faint square moving across, 440 and 880 Hz tones.
@Suite(.serialized)
struct TimelineRenderTests {
    /// Runs edit functions through direction_edit, as the editor does.
    @discardableResult
    func edit(_ f: MediaFixture, _ ops: [String]) async throws -> JSONValue {
        let operations = try ops.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        return try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Test"), "operations": .array(operations)])).value
    }
    func expectToolError(_ code: String, _ f: MediaFixture, _ ops: [String], contains text: String? = nil) async {
        do { _ = try await edit(f, ops); Issue.record("Expected \(code)") }
        catch let e as DirectionError { #expect(e.code == code, "\(e.code): \(e.message)"); #expect(e.index == 0); if let text { #expect(e.message.contains(text), "\(e.message)") } }
        catch { Issue.record("Unexpected error: \(error)") }
    }
    func frame(_ f: MediaFixture, _ t: Double, in part: CGRect? = nil, look: (@Sendable (CIImage, String?, Int) -> CIImage)? = nil) async throws -> (Double, Double, Double) {
        let compiled = try await SequenceRenderer.compile(project: f.store.read(), sequenceID: nil, cacheDirectory: f.runtime.cacheDirectory, previewMaxDimension: nil, looks: nil, look: look)
        let url = f.directory.appendingPathComponent(UUID().uuidString + ".png")
        _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: t), to: url)
        return try meanColor(url, in: part)
    }

    @Test func aDissolveIsHalfOfEachAtItsMidpoint() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        _ = try await edit(f, [#"{"op":"removeRange","range":{"start":1,"end":2}}"#])
        let clips = try f.store.read().sequences[0].clips.sorted { $0.start < $1.start }
        let result = try await edit(f, [#"{"op":"transition","editPoint":"\#(clips[0].id)|\#(clips[1].id)","type":"dissolve","frames":12}"#])
        #expect(result["operations"].array?[0]["changes"].array?[0]["new"]["start"].double == 0.8)
        let red = try await frame(f, 0.7), mid = try await frame(f, 1.0), blue = try await frame(f, 1.3)
        #expect(red.0 > red.2 * 2 && blue.2 > blue.0 * 2)
        // At the cut, halfway through: each channel sits between the two pictures.
        #expect(mid.0 > blue.0 + 20 && mid.0 < red.0 - 20 && mid.2 > red.2 + 20 && mid.2 < blue.2 - 20)
    }

    @Test func aDissolveFadesTheOutgoingShotWhereTheIncomingHasNoPicture() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        _ = try await edit(f, [#"{"op":"removeRange","range":{"start":1,"end":2}}"#])
        let clips = try f.store.read().sequences[0].clips.sorted { $0.start < $1.start }
        // The blue shot coming in is pillarboxed: only its middle 40%, like a vertical clip in a wide cut.
        _ = try await edit(f, [#"{"op":"addEffect","target":"\#(clips[1].id)","effect":"transform","params":{"crop":{"l":0.3,"r":0.3,"t":0,"b":0}}}"#,
                               #"{"op":"transition","editPoint":"\#(clips[0].id)|\#(clips[1].id)","type":"dissolve","frames":12}"#])
        let bars = CGRect(x: 0, y: 0, width: 0.1, height: 1), middle = CGRect(x: 0.45, y: 0, width: 0.1, height: 1)
        func light(_ v: Double) -> Double { pow(v / 255, 2.2) }
        let red = try await frame(f, 0.7, in: bars), half = try await frame(f, 1.0, in: bars), after = try await frame(f, 1.3, in: bars)
        // In the bars the red shot is about half at the cut and gone after it, rather than full until it pops off.
        #expect(red.0 > 120 && abs(light(half.0) / light(red.0) - 0.5) < 0.1 && after.0 < 4 && after.2 < 4, "\(red) \(half) \(after)")
        // Where both shots have picture it's the crossfade it always was.
        let mid = try await frame(f, 1.0, in: middle), blue = try await frame(f, 1.3, in: middle)
        #expect(mid.0 > blue.0 + 20 && mid.0 < red.0 - 20 && mid.2 > red.2 + 20 && mid.2 < blue.2 - 20, "\(mid) \(blue)")
        // A dip still plays over each shot: black at the cut, all of it.
        _ = try await edit(f, [#"{"op":"transition","editPoint":"\#(clips[0].id)|\#(clips[1].id)","type":"dipToBlack","frames":12}"#])
        let dark = try await frame(f, 1.0), before = try await frame(f, 0.9, in: bars)
        #expect(dark.0 < 6 && dark.2 < 6 && before.0 > 40 && before.0 < red.0 - 20, "\(dark) \(before)")
    }

    @Test func anOpacityKeyFadesThePictureIn() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let full = try await frame(f, 0.5), fullLater = try await frame(f, 1.0)
        let id = try f.store.read().sequences[0].clips[0].id
        _ = try await edit(f, [#"{"op":"addEffect","target":"\#(id)","effect":"transform","params":{},"keys":{"opacity":[{"t":0,"v":0},{"t":1,"v":1}]}}"#])
        let start = try await frame(f, 0), half = try await frame(f, 0.5), end = try await frame(f, 1.0)
        #expect(start.0 < 3 && abs(end.0 - fullLater.0) < 3)
        #expect(half.0 > full.0 * 0.3 && half.0 < full.0 * 0.9)
    }

    @Test func blendModesMixAnOverlayIntoTheStory() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let asset = try f.store.read().assets[0].id
        let away = try await edit(f, [#"{"op":"cutaway","assetID":"\#(asset)","sourceRange":{"start":2,"end":3},"at":0}"#])
        let overlay = try #require(away["operations"].array?[0]["clipIDs"].array?[0].string)
        let normal = try await frame(f, 0.5)
        #expect(normal.2 > normal.0 * 2)
        _ = try await edit(f, [#"{"op":"addEffect","target":"\#(overlay)","effect":"blend","params":{"mode":"multiply"}}"#])
        let multiplied = try await frame(f, 0.5)
        #expect(multiplied.0 < 60 && multiplied.1 < 60 && multiplied.2 < normal.2 - 60)
        _ = try await edit(f, [#"{"op":"setEffect","effectID":"\#(overlay):blend","params":{"mode":"screen"}}"#])
        let screened = try await frame(f, 0.5)
        #expect(screened.0 > normal.0 + 60 && screened.2 >= normal.2 - 5)
    }

    @Test func anAlphaGraphicSitsAboveTheLook() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        // A ProRes 4444 render with alpha, as the graphics area makes them: half-transparent blue.
        let url = f.directory.appendingPathComponent("badge.mov")
        try await writeAlphaMovie(to: url)
        var asset = try await MediaInspector.inspect(url: url); asset.graphic = "Badge"
        _ = try f.store.addAsset(asset, append: false, expectedRevision: f.store.revision())
        _ = try await edit(f, [#"{"op":"placeGraphic","graphic":"Badge","at":0,"seconds":1}"#])
        let plain = try await frame(f, 0.5)
        #expect(plain.0 > 60 && plain.2 > 60 && plain.2 < 230)
        // A look that takes the color out shows what's under it and what's over it.
        let grey: @Sendable (CIImage, String?, Int) -> CIImage = { image, _, _ in image.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0]) }
        let over = try await frame(f, 0.5, look: grey)
        #expect(over.2 > over.0 + 25 && over.0 > 40)
        let id = try #require(f.store.read().sequences[0].clips.first { $0.layer > 0 }?.id)
        _ = try await edit(f, [#"{"op":"remove","clipID":"\#(id)"}"#, #"{"op":"placeGraphic","graphic":"Badge","at":0,"seconds":1,"aboveLook":false}"#])
        let under = try await frame(f, 0.5, look: grey)
        #expect(abs(under.0 - under.2) < 6)
    }

    @Test func aShaderTheEditorWroteRunsOnTheGPU() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let effects = f.store.url.appendingPathComponent("Editor/Effects")
        try FileManager.default.createDirectory(at: effects, withIntermediateDirectories: true)
        try """
        // direction: param amount 0 1 1
        // direction: param tint color #FFFFFF
        [[ stitchable ]] half4 effect(coreimage::sample_h s, float amount, float3 tint, coreimage::destination dest) {
            half4 inverted = half4((s.a - s.rgb) * half3(tint), s.a);
            return mix(s, inverted, half(amount));
        }
        """.write(to: effects.appendingPathComponent("invert.metal"), atomically: true, encoding: .utf8)
        let catalog = try await f.runtime.invoke("direction_edit_catalog").value
        #expect(catalog["customEffects"].array?.first?["file"].string == "Effects/invert.metal" && catalog["customEffects"].array?.first?["params"].array?.count == 2)
        let id = try f.store.read().sequences[0].clips[0].id
        let before = try await frame(f, 0.5)
        _ = try await edit(f, [#"{"op":"addEffect","target":"\#(id)","effect":"shader","params":{"file":"Effects/invert.metal","amount":1}}"#])
        let after = try await frame(f, 0.5)
        #expect(after.1 > before.1 + 100 && after.2 > before.2 + 100 && after.0 < before.0)
        // Compile errors name the editor's own lines; NaN and slowness are refused before anything changes.
        try "[[ stitchable ]] half4 effect(coreimage::sample_h s) {\n    return s * undefined;\n}\n".write(to: effects.appendingPathComponent("broken.metal"), atomically: true, encoding: .utf8)
        await expectToolError("shader_invalid", f, [#"{"op":"addEffect","target":"\#(id)","effect":"shader","params":{"file":"Effects/broken.metal"}}"#], contains: "line 2")
        try "[[ stitchable ]] half4 effect(coreimage::sample_h s) {\n    return s / half(0.0);\n}\n".write(to: effects.appendingPathComponent("nan.metal"), atomically: true, encoding: .utf8)
        await expectToolError("shader_invalid", f, [#"{"op":"addEffect","target":"\#(id)","effect":"shader","params":{"file":"Effects/nan.metal"}}"#], contains: "NaN")
        try "// direction: param seed 0 1 0.5\n[[ stitchable ]] half4 effect(coreimage::sample_h s, float seed, coreimage::destination dest) {\n    float v = seed + dest.coord().x * 0.001;\n    for (int i = 0; i < 40000; i++) { v = fract(sin(v * 12.9898 + float(i)) * 43758.5453); }\n    return half4(half3(v), 1.0);\n}\n".write(to: effects.appendingPathComponent("slow.metal"), atomically: true, encoding: .utf8)
        await expectToolError("shader_too_slow", f, [#"{"op":"addEffect","target":"\#(id)","effect":"shader","params":{"file":"Effects/slow.metal"}}"#])
        await expectToolError("bad_argument", f, [#"{"op":"addEffect","target":"\#(id)","effect":"shader","params":{"file":"../escape.metal"}}"#])
        #expect(try f.store.read().sequences[0].clips[0].effects?.count == 1)
    }

    @Test func directionMeasuresWhatTheEditFunctionsNeed() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let id = try f.store.read().sequences[0].clips[0].id
        // There's no face in the fixture, and follow says so.
        await expectToolError("bad_argument", f, [#"{"op":"reframe","clipID":"\#(id)","scale":1.5,"follow":"face"}"#], contains: "face")
        _ = try await edit(f, [#"{"op":"reframe","clipID":"\#(id)","scale":1.5,"follow":"subject","keepIn":"center"}"#])
        #expect(try (f.store.read().sequences[0].clips[0].effects?.first?.keys?["x"]?.count ?? 0) > 5)
        // Stabilize measures the clip once and keeps the corrections with the effect.
        _ = try await edit(f, [#"{"op":"addEffect","target":"\#(id)","effect":"stabilize","params":{"amount":0.5}}"#])
        #expect(try f.store.read().sequences[0].clips[0].effects?.contains { $0.name == "stabilize" && $0.keys?["dx"] != nil } == true)
        _ = try await frame(f, 1.0)
        // matchBalance makes the blue half read more like the red half.
        let split = try await edit(f, [#"{"op":"split","clipID":"\#(id)","at":1.5}"#])
        let blue = try #require(split["operations"].array?[0]["clipIDs"].array?[0].string)
        let before = try await frame(f, 2.2)
        _ = try await edit(f, [#"{"op":"matchBalance","clipID":"\#(blue)","toClipID":"\#(id)"}"#])
        let after = try await frame(f, 2.2)
        #expect(after.0 > before.0 + 10 && after.2 < before.2)
        // tightenPauses only takes quiet: the fixture's tone never stops, so the pause stays.
        let p = try f.store.read(), asset = p.assets[0]
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, provider: "test", words: [TranscriptWord(id: "w0", text: "One", range: .init(start: 0.1, end: 0.4)), TranscriptWord(id: "w1", text: "two", range: .init(start: 1.2, end: 1.4))]))
        let tightened = try await edit(f, [#"{"op":"tightenPauses","range":{"start":0,"end":1.5},"longerThan":0.4,"to":0.2}"#])
        #expect(tightened["delta"].double == 0 && tightened["operations"].array?[0]["summary"].string?.hasPrefix("Tightened 0") != true)
    }

    @Test func aLaterOperationMeasuresTheTakeAnEarlierOneSwappedIn() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let id = try f.store.read().sequences[0].clips[0].id
        let split = try await edit(f, [#"{"op":"split","clipID":"\#(id)","at":1.5}"#])
        let blue = try #require(split["operations"].array?[0]["clipIDs"].array?[0].string)
        // A red still of the cut to swap in for the blue half.
        let still = try await f.runtime.invoke("direction_frame", arguments: .object(["time": .number(0.5)])).imagePaths[0]
        let red = try #require(try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(still)])).value["asset"]["id"].string)
        let swap = #"{"op":"replaceTake","clipID":"\#(blue)","withAssetID":"\#(red)","alignOn":"head"}"#, match = #"{"op":"matchBalance","clipID":"\#(blue)","toClipID":"\#(id)"}"#
        let start = Double(try f.store.revision())
        func grade() throws -> ColorGrade { try #require(f.store.read().sequences[0].clips.first { $0.id == blue }).grade }
        func back() async throws { _ = try await f.runtime.invoke("direction_restore", arguments: .object(["revision": .number(start), "baseEditRevision": .number(Double(try f.store.revision()))])) }
        _ = try await edit(f, [match])
        let onBlue = try grade()
        // Swapped and matched in one batch, the match measures the still, as it does in a batch after the swap.
        try await back()
        _ = try await edit(f, [swap, match])
        let inBatch = try grade()
        try await back()
        _ = try await edit(f, [swap])
        _ = try await edit(f, [match])
        let after = try grade()
        #expect(inBatch == after && inBatch != onBlue, "\(inBatch) \(after) \(onBlue)")
    }

    @Test func aPauseIsFoundWhereTheRemovalBeforeItInTheBatchLeftIt() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        // Four seconds of tone, quiet from 1.5 to 2.5 s, with a word either side of the quiet.
        let wav = f.directory.appendingPathComponent("pause.wav")
        try MediaFixture.writeTone(to: wav, frequency: 440, seconds: 4, quiet: 1.5..<2.5)
        let store = try ProjectStore.create(at: f.directory.appendingPathComponent("Pause.direction"), name: "Pause")
        let runtime = try ToolRuntime(store: store)
        _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(wav.path), "append": .bool(true)]))
        let asset = try store.read().assets[0]
        try store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, provider: "test", words: [TranscriptWord(id: "w0", text: "One", range: .init(start: 0.2, end: 1.4)), TranscriptWord(id: "w1", text: "two", range: .init(start: 2.6, end: 3.8))]))
        let ops = try [#"{"op":"removeRange","range":{"start":0,"end":1}}"#, #"{"op":"tightenPauses","range":{"start":0,"end":3},"longerThan":0.5,"to":0.2}"#].map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        let result = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "summary": .string("Tighter"), "operations": .array(ops)])).value
        // After the removal the quiet is at 0.5–1.5 s, and all of it goes: the pause keeps 0.2 s.
        let tightened = try #require(result["operations"].array?[1]["changes"].array?.first)
        #expect(abs((result["newLength"].double ?? 0) - 2) < 0.05, "\(result["newLength"])")
        #expect(abs((tightened["old"]["start"].double ?? 0) - 1.5) < 0.05 && abs((tightened["old"]["end"].double ?? 0) - 2.5) < 0.05, "\(tightened)")
    }

    @Test func aRetriedBatchGetsBackWhatItDidOnceTheCutHasMovedOn() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let base = try f.store.revision()
        // punchIn takes the style's scales, which the batch didn't send; the retry matches all the same.
        let ops = try [#"{"op":"removeRange","range":{"start":0,"end":0.5}}"#, #"{"op":"punchIn","range":{"start":0,"end":2}}"#].map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        func send(_ key: String, _ operations: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(base)), "idempotencyKey": .string(key), "summary": .string("Tighter"), "operations": .array(operations)])).value
        }
        let first = try await send("tighter", ops)
        let again = try await send("tighter", ops)
        #expect(again == first && first["committed"].bool == true && first["editRevision"].int == base + 1)
        #expect(try f.store.revision() == base + 1)
        // The same key with another batch is refused, and a new batch on the old revision is stale.
        do { _ = try await send("tighter", Array(ops.prefix(1))); Issue.record("Expected idempotency_conflict") } catch let e as DirectionError { #expect(e.code == "idempotency_conflict") }
        do { _ = try await send("tighter-again", ops); Issue.record("Expected stale_revision") } catch let e as DirectionError { #expect(e.code == "stale_revision") }
    }

    @Test func aCutWithEffectsExportsAndMatchesItsFrames() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        _ = try await edit(f, [#"{"op":"removeRange","range":{"start":1,"end":2}}"#])
        let clips = try f.store.read().sequences[0].clips.sorted { $0.start < $1.start }
        let (a, b) = (clips[0].id, clips[1].id)
        let result = try await edit(f, [
            #"{"op":"transition","editPoint":"\#(a)|\#(b)","type":"dissolve","frames":12}"#,
            #"{"op":"addEffect","target":"\#(a)","effect":"blur","params":{"radius":6}}"#,
            #"{"op":"reframe","clipID":"\#(b)","scale":1.2,"x":0.05}"#,
            #"{"op":"addEffect","target":"\#(b)","effect":"filter.vignette","params":{"amount":0.4}}"#,
            #"{"op":"addEffect","target":"\#(b)","effect":"mask","params":{"shape":"ellipse","x":0.2,"y":0.2,"w":0.6,"h":0.6}}"#,
            #"{"op":"gain","target":"\#(a)","dB":-20}"#,
            #"{"op":"fade","clipID":"\#(b)","out":15}"#,
        ])
        #expect(result["committed"].bool == true && result["operations"].array?.count == 7)
        let timeline = try await f.runtime.invoke("direction_timeline", arguments: .object(["outlineOnly": .bool(true)])).value
        #expect(timeline["outline"].string?.contains("dissolve 12f in") == true && timeline["otio"] == .null)
        // direction_frame and the export show the same picture at the dissolve.
        let tool = try await f.runtime.invoke("direction_frame", arguments: .object(["time": .number(1.0)]))
        let fromTool = try meanColor(URL(fileURLWithPath: tool.imagePaths[0]))
        let path = f.directory.appendingPathComponent("effects.mp4")
        let job = try await f.runtime.invoke("direction_export", arguments: .object(["path": .string(path.path)]))
        let done = try await f.runtime.waitForJob(job.value.requiredString("id"))
        let length = try done.result?["duration"].decode(MediaTime.self).seconds ?? 0
        #expect(done.status == "completed" && abs(length - 2) < 0.08)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: path)); generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let exported = f.directory.appendingPathComponent("exported-frame.png")
        try MediaInspector.writePNG(try await generator.image(at: CMTime(seconds: 1.0, preferredTimescale: 600)).image, to: exported)
        let fromExport = try meanColor(exported)
        #expect(abs(fromTool.0 - fromExport.0) < 8 && abs(fromTool.1 - fromExport.1) < 8 && abs(fromTool.2 - fromExport.2) < 8)
        // The gain reaches the mix: the first clip's tone is 20 dB down.
        let wav = f.directory.appendingPathComponent("gain.wav")
        _ = try await SequenceRenderer.audioPreview(try await f.compile(), range: .init(start: 0.2, end: 0.7), to: wav)
        let level = try toneAmplitude(wav, frequency: 440)
        #expect(level < 0.04 && level > 0.005)
    }
}

/// A take whose sound runs on past its picture (AAC often does) plays and exports whole: the last frame
/// holds over the sound that's left, instead of the export stopping at the picture's end.
@Test func aTakeWhoseSoundOutlastsItsPictureExportsWhole() async throws {
    let f = try await MediaFixture.make(); defer { f.cleanup() }
    // The fixture's first second of picture over 1.2 s of its sound.
    let original = AVURLAsset(url: f.source), composition = AVMutableComposition()
    let take = try await original.loadTracks(withMediaType: .video)[0], sound = try await original.loadTracks(withMediaType: .audio)[0]
    try composition.addMutableTrack(withMediaType: .video, preferredTrackID: 1)!.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 48_000)), of: take, at: .zero)
    try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: 2)!.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 1.2, preferredTimescale: 48_000)), of: sound, at: .zero)
    let source = f.directory.appendingPathComponent("sound-runs-on.mov")
    try await AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!.export(to: source, as: .mov)
    let store = try ProjectStore.create(at: f.directory.appendingPathComponent("RunsOn.direction"), name: "Runs on")
    let runtime = try ToolRuntime(store: store)
    _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(source.path), "append": .bool(true)]))
    var format = EditOperation("format"); format.width = 320; format.height = 180
    _ = try store.apply(.init(baseEditRevision: store.revision(), operations: [format]))
    let clip = try store.read().sequences[0].clips.first { $0.kind == .video }
    #expect(abs((clip?.duration.seconds ?? 0) - 1.2) < 0.03)
    let path = f.directory.appendingPathComponent("runs-on.mp4")
    let job = try await runtime.invoke("direction_export", arguments: .object(["path": .string(path.path)]))
    let done = try await runtime.waitForJob(job.value.requiredString("id"))
    #expect(done.status == "completed")
    #expect(abs((try done.result?["duration"].decode(MediaTime.self).seconds ?? 0) - 1.2) < 0.06)
    // The held last frame: the fixture's red, not black.
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: path)); generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
    let still = f.directory.appendingPathComponent("held.png")
    try MediaInspector.writePNG(try await generator.image(at: CMTime(seconds: 1.12, preferredTimescale: 600)).image, to: still)
    let color = try meanColor(still)
    #expect(color.0 > 120 && color.2 < 90)
}

/// The editor reads the timeline; it changes the cut only through edit functions.
@Test func noToolTakesATimelineDocument() async throws {
    for d in ToolCatalog.definitions where !d.readOnly {
        for key in ["otio", "timeline", "document", "sequence", "tracks", "clips"] { #expect(d.inputSchema["properties"][key] == .null, "\(d.name) takes \(key)") }
    }
    #expect(ToolCatalog.definitions.contains { $0.name == "direction_timeline" && $0.readOnly } && ToolCatalog.definitions.contains { $0.name == "direction_edit_catalog" && $0.readOnly })
    let f = try await MediaFixture.make(); defer { f.cleanup() }
    let first = try f.store.revision()
    _ = try await f.runtime.invoke("direction_create_cut", arguments: .object(["name": .string("Assembly")]))
    _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(first)), "notes": .array([]), "operations": .array([.object(["op": .string("removeRange"), "range": .object(["start": .number(0), "end": .number(1)])])])]))
    let saved = try await f.runtime.invoke("direction_timeline", arguments: .object(["cut": .string("Assembly")])).value
    #expect(saved["editRevision"].int == first && saved["cut"].string == "Assembly" && saved["otio"]["OTIO_SCHEMA"].string == "Timeline.1")
    let working = try await f.runtime.invoke("direction_timeline").value
    #expect(working["cut"].string == "Cut 2 (working)" && working["editRevision"].int == first + 1)
    // Errors point at the operation that failed.
    do {
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(first + 1)), "operations": .array([.object(["op": .string("split"), "clipID": .string("nope"), "at": .number(1)]), .object(["op": .string("trim"), "colour": .string("red")])])]))
        Issue.record("Expected an error")
    } catch let e as DirectionError {
        let encoded = String(decoding: try JSONEncoder.direction.encode(e), as: UTF8.self)
        #expect(e.code == "bad_argument" && e.index == 1 && encoded.contains("\"index\":1"))
    }
}

/// One second of half-transparent blue at 320×180, ProRes 4444 with alpha.
func writeAlphaMovie(to url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
    writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    for i in 0..<30 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error! } }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "Cannot allocate an alpha frame.") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 320, height: 180))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.5)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30)) else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write an alpha frame.") }
    }
    input.markAsFinished(); await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot finish the alpha movie.") }
}

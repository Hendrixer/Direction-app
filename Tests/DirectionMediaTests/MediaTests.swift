import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
import DirectionMedia
import DirectionTools

@Suite(.serialized)
struct MediaIntegrationTests {
    @Test(arguments: ["h264", "hevc", "prores"])
    func advertisedExportPresetsProduceTheirExpectedCodec(preset: String) async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let output = f.directory.appendingPathComponent(preset + (preset == "prores" ? ".mov" : ".mp4"))
        _ = try await SequenceRenderer.export(f.compile(), to: output, preset: preset)
        let media = AVURLAsset(url: output), video = try await media.loadTracks(withMediaType: .video)[0]
        let description = try await video.load(.formatDescriptions)[0]
        let expected: FourCharCode = preset == "hevc" ? kCMVideoCodecType_HEVC : preset == "prores" ? kCMVideoCodecType_AppleProRes422 : kCMVideoCodecType_H264
        #expect(CMFormatDescriptionGetMediaSubType(description) == expected)
        #expect(abs(try await media.load(.duration).seconds - 3) < 0.04)
    }

    @Test func deliveringAtTheFootagesSizeRendersAtThatSize() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let s = try f.store.read().sequences[0]
        let output = f.directory.appendingPathComponent("double.mp4")
        let response = try await f.runtime.invoke("direction_export", arguments: .object(["path": .string(output.path), "width": .number(Double(s.width * 2)), "height": .number(Double(s.height * 2))]))
        _ = try await f.runtime.waitForJob(try #require(response.value["id"].string))
        let video = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)[0]
        #expect(try await video.load(.naturalSize) == CGSize(width: s.width * 2, height: s.height * 2))
        // Another shape is refused.
        do {
            _ = try await f.runtime.invoke("direction_export", arguments: .object(["path": .string(f.directory.appendingPathComponent("odd.mp4").path), "width": .number(Double(s.width * 2)), "height": .number(Double(s.height))]))
            Issue.record("Expected invalid_size")
        } catch let e as DirectionError { #expect(e.code == "invalid_size") }
    }

    @Test func sourceAudioOffsetsSurviveExtractionForSpeechAndDSP() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let composition = AVMutableComposition(), input = AVURLAsset(url: f.source)
        let sourceAudio = try await input.loadTracks(withMediaType: .audio)[0]
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: 1)!.insertTimeRange(.init(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 48_000)), of: sourceAudio, at: CMTime(seconds: 1, preferredTimescale: 48_000))
        let path = f.directory.appendingPathComponent("offset.mov")
        let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await session.export(to: path, as: .mov)
        let asset = try await MediaInspector.inspect(url: path)
        let decoded = try await AudioProcessor.extract(asset: asset, trackID: asset.audio[0].id, directory: f.runtime.cacheDirectory)
        let file = try AVAudioFile(forReading: decoded), buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 24_000)!
        try file.read(into: buffer)
        #expect((0..<Int(buffer.frameLength)).allSatisfy { abs(buffer.floatChannelData![0][$0]) < 0.001 })
        file.framePosition = 60_000; try file.read(into: buffer)
        #expect((0..<Int(buffer.frameLength)).contains { abs(buffer.floatChannelData![0][$0]) > 0.1 })
        #expect(abs(Double(file.length) / 48_000 - 2) < 0.03)
    }

    @Test func stillImagesTitlesAndEmptyGapsRenderWithoutSourceVideo() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let picture = try await f.runtime.invoke("direction_frame", arguments: .object(["time": .number(0.3)]))
        let still = try await MediaInspector.inspect(url: URL(fileURLWithPath: picture.imagePaths[0]))
        var project = Project(name: "Still and title")
        project.assets = [still]
        let image = Clip(assetID: still.id, name: "Still", start: .init(seconds: 1), sourceRange: .init(start: 0, end: 1))
        var title = Clip(assetID: nil, name: "Title", kind: .title, layer: 1, start: .init(seconds: 2), sourceRange: .init(start: 0, end: 1)); title.title = "DIRECTION"
        project.sequences = [.init(width: 320, height: 180, clips: [image, title])]
        let compiled = try await SequenceRenderer.compile(project: project, cacheDirectory: f.runtime.cacheDirectory)
        let black = f.directory.appendingPathComponent("gap.png"), red = f.directory.appendingPathComponent("still.png"), text = f.directory.appendingPathComponent("title.png")
        _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: 0.5), to: black)
        _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: 1.5), to: red)
        _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: 2.5), to: text)
        #expect(try meanColor(black).0 < 2)
        #expect(try meanColor(red).0 > 100)
        #expect(try meanColor(text).0 > 0)
        let output = f.directory.appendingPathComponent("still-title.mp4")
        _ = try await SequenceRenderer.export(compiled, to: output)
        let duration = try await AVURLAsset(url: output).load(.duration)
        #expect(abs(duration.seconds - 3) < 0.04)
    }

    @Test func videoLayersSpeedFramingAndColorAffectActualPixels() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        var p = try f.store.read()
        let original = p.sequences[0].clips[0]
        var slow = original; slow.speed = 0.5
        p.sequences[0].clips = [slow]
        let slowed = try await SequenceRenderer.compile(project: p, cacheDirectory: f.runtime.cacheDirectory)
        let before = f.directory.appendingPathComponent("slow-red.png")
        _ = try await SequenceRenderer.frame(slowed, at: .init(seconds: 2), to: before)
        #expect(try meanColor(before).0 > meanColor(before).2 * 2)
        #expect(slowed.sequence.duration.seconds == 6)
        var overlay = Clip(assetID: original.assetID, name: "Blue overlay", layer: 1, sourceRange: .init(start: 2, end: 3))
        overlay.framing.fit = false; overlay.grade.saturation = 0
        p.sequences[0].clips = [original, overlay]
        p.sequences[0].width = 180; p.sequences[0].height = 320
        let portrait = try await SequenceRenderer.compile(project: p, cacheDirectory: f.runtime.cacheDirectory)
        let after = f.directory.appendingPathComponent("portrait-grey.png")
        let result = try await SequenceRenderer.frame(portrait, at: .init(seconds: 0.5), to: after)
        let color = try meanColor(after)
        #expect(abs(color.0 - color.2) < 3 && color.0 > 10)
        #expect(result["width"].int == 180 && result["height"].int == 320)
    }

    @Test func bigEndianAIFFIsConvertedToNativePCMBeforeAnalysis() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let wave = f.directory.appendingPathComponent("little-endian.wav"), aiff = f.directory.appendingPathComponent("big-endian.aiff")
        try MediaFixture.writeTone(to: wave, frequency: 440, seconds: 1)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert"); process.arguments = ["-f", "AIFF", "-d", "BEI16@22050", wave.path, aiff.path]
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        let asset = try await MediaInspector.inspect(url: aiff)
        let decoded = try await AudioProcessor.extract(asset: asset, trackID: asset.audio[0].id, directory: f.runtime.cacheDirectory)
        #expect(try toneAmplitude(decoded, frequency: 440) > 0.15)
        let measure = try await AudioProcessor.measure(asset: asset, trackID: asset.audio[0].id, directory: f.runtime.cacheDirectory)
        let rms = try #require(measure["rmsDBFS"].double)
        #expect(rms.isFinite && rms > -20 && rms < -10)
    }

    @Test func importsAllSourceAudioTracksAndRendersWithMetal() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0]
        #expect(GPUCompositor.deviceName != nil)
        #expect(asset.audio.count == 2)
        #expect(asset.audio[0].id != asset.audio[1].id)
        let frame = try await f.runtime.invoke("direction_frame", arguments: .object(["time": .number(0.5)]))
        let color = try meanColor(URL(fileURLWithPath: frame.imagePaths[0]))
        #expect(color.0 > color.2 * 2)
        #expect(frame.value["editRevision"].int == p.editRevision)
    }

    @Test func realRippleCutChangesPictureAndExportDuration() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let before = try f.store.read()
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(before.editRevision)), "operations": .array([.object(["op": .string("removeRange"), "range": .object(["start": .number(1), "end": .number(2)])])])]))
        let sample = try await f.runtime.invoke("direction_frame", arguments: .object(["time": .number(1.2)]))
        let color = try meanColor(URL(fileURLWithPath: sample.imagePaths[0]))
        #expect(color.2 > color.0 * 2)
        let path = f.directory.appendingPathComponent("edited.mp4")
        let job = try await f.runtime.invoke("direction_export", arguments: .object(["path": .string(path.path)]))
        let finished = try await f.runtime.waitForJob(job.value.requiredString("id"))
        #expect(finished.status == "completed")
        let output = AVURLAsset(url: path), duration = try await output.load(.duration)
        #expect(abs(duration.seconds - 2) < 0.08)
        #expect(try await output.loadTracks(withMediaType: .video).count == 1)
        #expect(try await output.loadTracks(withMediaType: .audio).count >= 1)
    }

    @Test func mutingOneEmbeddedTrackRemovesOnlyItsTone() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0]
        #expect(asset.audio.count == 2)
        let before = try await f.compile(), beforePath = f.directory.appendingPathComponent("both.wav")
        _ = try await SequenceRenderer.audioPreview(before, range: .init(start: 0.2, end: 1.2), to: beforePath)
        #expect(try toneAmplitude(beforePath, frequency: 440) > 0.15)
        #expect(try toneAmplitude(beforePath, frequency: 880) > 0.15)
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "operations": .array([.object(["op": .string("audio"), "assetID": .string(asset.id), "audioTrackID": .number(Double(asset.audio[1].id)), "audio": .object(["muted": .bool(true)])])])]))
        let after = try await f.compile(), afterPath = f.directory.appendingPathComponent("first-only.wav")
        _ = try await SequenceRenderer.audioPreview(after, range: .init(start: 0.2, end: 1.2), to: afterPath)
        #expect(try toneAmplitude(afterPath, frequency: 440) > 0.15)
        #expect(try toneAmplitude(afterPath, frequency: 880) < 0.005)
        #expect(try f.store.read().assets[0].audio[0].settings.muted == false)
        let output = f.directory.appendingPathComponent("muted-export.mp4")
        _ = try await SequenceRenderer.export(after, to: output)
        let exported = try await MediaInspector.inspect(url: output)
        let decoded = try await AudioProcessor.extract(asset: exported, trackID: exported.audio[0].id, directory: f.runtime.cacheDirectory.appendingPathComponent("Audio"))
        #expect(try toneAmplitude(decoded, frequency: 440) > 0.15)
        #expect(try toneAmplitude(decoded, frequency: 880) < 0.01)
    }

    @Test func transcriptDeletionCutsActualVideoAndSound() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0]
        let words = [TranscriptWord(id: "first", text: "First", range: .init(start: 0, end: 1)), TranscriptWord(id: "middle", text: "middle", range: .init(start: 1, end: 2)), TranscriptWord(id: "last", text: "last", range: .init(start: 2, end: 3))]
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, provider: "test-timing", words: words))
        let projected = try await f.runtime.invoke("direction_transcript")
        let middle = try #require(projected.value["words"].array?[1]["id"].string)
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "operations": .array([.object(["op": .string("removeWords"), "wordIDs": .array([.string(middle)])])])]))
        let result = try await f.runtime.invoke("direction_transcript")
        #expect(result.value["words"].array?.map { $0["text"].string } == ["First", "last"])
        #expect(try f.store.read().sequences[0].duration == MediaTime(seconds: 2))
        let c = try await f.compile(), wav = f.directory.appendingPathComponent("cut-audio.wav")
        _ = try await SequenceRenderer.audioPreview(c, range: .init(start: 0, end: 2), to: wav)
        let audio = try AVAudioFile(forReading: wav)
        #expect(abs(Double(audio.length) / audio.processingFormat.sampleRate - 2) < 0.03)
    }

    @Test func feedbackContextIncludesOriginalFramesAudioAndRemappedSources() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let revision = try f.store.revision()
        let c = try await f.runtime.invoke("direction_add_comment", arguments: .object(["text": .string("Keep the red section"), "start": .number(0.5), "end": .number(1), "region": .object(["x": .number(0.1), "y": .number(0.2), "width": .number(0.4), "height": .number(0.3)])]))
        let id = try c.value.requiredString("id")
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(revision)), "operations": .array([.object(["op": .string("removeRange"), "range": .object(["start": .number(0), "end": .number(0.2)])])])]))
        let context = try await f.runtime.invoke("direction_feedback_context", arguments: .object(["commentID": .string(id)]))
        #expect(context.value["comment"]["editRevision"].int == revision)
        #expect(context.imagePaths.count >= 2)
        #expect(context.audioPaths.count == 1)
        #expect(context.value["sourceAssets"].array?[0]["audio"].array?.count == 2)
        #expect(context.value["anchors"].array?[0]["currentProjection"]["status"].string == "exact")
        let color = try meanColor(URL(fileURLWithPath: context.imagePaths[0])); #expect(color.0 > color.2 * 2)
    }

    @Test func nativeEQProcessesAudioAndExportRetainsPinnedRevision() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0]
        var effects = AudioEffects(); effects.highPassHz = 3_000
        let result = try await AudioProcessor.processed(asset: asset, trackID: asset.audio[0].id, effects: effects, directory: f.runtime.cacheDirectory.appendingPathComponent("Audio"))
        #expect(try toneAmplitude(result, frequency: 440) < 0.04)
        let export = try await f.runtime.invoke("direction_export", arguments: .object(["path": .string(f.directory.appendingPathComponent("pinned.mp4").path), "revision": .number(Double(p.editRevision))]))
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "operations": .array([.object(["op": .string("removeRange"), "range": .object(["start": .number(1), "end": .number(2)])])])]))
        let done = try await f.runtime.waitForJob(export.value.requiredString("id"))
        #expect(done.result?["editRevision"].int == p.editRevision)
        let time = try done.result?["duration"].decode(MediaTime.self)
        #expect(abs((time?.seconds ?? 0) - 3) < 0.08)
    }

    /// Effects on a clip's sound (a high-pass, the compressor, the limiter) play in the cut and measure: the
    /// processed sound stays open until it's in (Coded love's Cut 2 wouldn't play with the narration limited).
    @Test func aClipsSoundEffectsPlayInTheCutAndMeasure() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0]
        let clip = try #require(try p.sequence(nil).clips.first { $0.assetID == asset.id })
        let effects: JSONValue = .object(["highPassHz": .number(80), "compressor": .bool(true), "thresholdDB": .number(-24), "limiter": .bool(true)])
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "idempotencyKey": .string(UUID().uuidString), "operations": .array([
            .object(["op": .string("audio"), "assetID": .string(asset.id), "audioTrackID": .number(Double(asset.audio[0].id)), "clipID": .string(clip.id), "audio": .object(["effects": effects])])])]))
        // Only what was named changed: the rest of the clip's sound is the take's.
        let settings = try #require(try f.store.read().sequence(nil).clips.first { $0.id == clip.id }?.audioOverrides[String(asset.audio[0].id)])
        #expect(settings.effects.highPassHz == 80 && settings.effects.limiter && settings.gainDB == asset.audio[0].settings.gainDB && settings.effects.bassDB == asset.audio[0].settings.effects.bassDB)
        let compiled = try await f.compile()
        let loudness = try await SequenceRenderer.loudness(compiled)
        #expect(loudness["integratedLUFS"].double != nil, "\(loudness)")
        _ = try await SequenceRenderer.frame(compiled, at: MediaTime(seconds: 1), to: f.directory.appendingPathComponent("effects.png"), maxDimension: 320)
    }

    @Test func detectsChangedSourcesAndProtectsExistingExports() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let compiled = try await f.compile()
        do { _ = try await SequenceRenderer.export(compiled, to: f.source); Issue.record("Source export should be rejected") } catch let error as DirectionError { #expect(error.code == "destination_exists") }
        let handle = try FileHandle(forWritingTo: f.source); try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        do { _ = try await f.compile(); Issue.record("Changed source should be rejected") } catch let error as DirectionError { #expect(error.code == "source_changed") }
    }
}

import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import DirectionCore
@testable import DirectionMedia
@testable import DirectionTools

/// Where to cut (agent-timeline.md › Cut points): blinks, peaks of action and pauses, measured so the editor
/// chooses between them; split, trim and roll snap to one; direction_check finds jump cuts and cuts inside a word.
@Suite(.serialized)
struct CutPointsTests {
    // MARK: Finding them

    /// A blink is a short dip with the eyes open either side. Looking down, a head turning away and a head coming
    /// toward the camera aren't, though the eyes read as closing in all three.
    @Test func aBlinkIsAShortDipNotALookDownOrATurn() {
        var samples: [CutPoints.EyeSample] = []
        for i in 0..<(14 * 30) {
            let t = Double(i) / 30
            var open = 0.33 + 0.01 * sin(Double(i) * 1.7), yaw = 0.0, h = 0.3
            if (1.97...2.04).contains(t) { open = 0.08 }                        // a blink, three frames shut
            if (5.0...6.2).contains(t) { open = 0.15 }                          // looking down for over a second
            if (8.0...8.15).contains(t) { open = 0.1 }; if t > 8.05 && t < 11 { yaw = 0.45 } // the head turns as it dips
            if (11.0...11.1).contains(t) { open = 0.1 }; if t > 11.05 { h = 0.4 } // coming toward the camera
            samples.append(.init(t: t, open: open, x: 0.5, y: 0.5, h: h, yaw: yaw, pitch: 0.1))
        }
        let found = CutPoints.blinks(in: samples)
        #expect(found.count == 1, "\(found)")
        if let b = found.first { #expect(abs(b.t - 2.0) < 0.05 && b.start < b.t && b.end > b.t && b.end - b.t < 0.3 && b.depth > 0.6, "\(b)") }
        // No eyes to judge: no blinks, however the samples dip.
        #expect(CutPoints.blinks(in: samples.map { var s = $0; s.open = nil; return s }).isEmpty)
    }

    /// Peaks of action are where the picture changes fastest; a change of picture isn't action.
    @Test func actionIsTheFastestMovementNotAChangeOfPicture() {
        var energy: [(t: Double, e: Double)] = []
        for i in 1..<80 {
            let t = Double(i) / 10
            var e = 0.002
            if (1.0...1.4).contains(t) { e = 0.03 * sin((t - 1.0) / 0.4 * .pi) + 0.002 }
            if (3.0...3.4).contains(t) { e = 0.015 * sin((t - 3.0) / 0.4 * .pi) + 0.002 }
            if abs(t - 6.0) < 0.01 { e = 0.35 }
            energy.append((t, e))
        }
        let peaks = CutPoints.actions(in: energy)
        #expect(peaks.count == 2, "\(peaks)")
        #expect(abs((peaks.first?.t ?? 0) - 1.2) < 0.11 && abs((peaks.last?.t ?? 0) - 3.2) < 0.11, "\(peaks)")
        #expect((peaks.first?.strength ?? 0) > (peaks.last?.strength ?? 1))
    }

    @Test func pausesAreTheGapsBetweenWords() {
        let words = [("So", 0.1, 0.3), ("we", 0.35, 0.5), ("began.", 0.55, 0.9), ("Then", 1.6, 1.8), ("it", 1.85, 1.95), ("worked", 2.3, 2.6)].enumerated().map { i, w in
            TranscriptWord(id: "w\(i)", text: w.0, range: .init(start: w.1, end: w.2))
        }
        let pauses = CutPoints.pauses(words)
        #expect(pauses.count == 2 && abs(pauses[0].start - 0.9) < 1e-4 && abs(pauses[1].start - 1.95) < 1e-4 && pauses.map(\.afterSentence) == [true, false], "\(pauses)")
        // A stretch takes in the pauses that reach into it.
        #expect(CutPoints.pauses(words, from: 1.5).count == 2 && CutPoints.pauses(words, from: 1.7).count == 1)
        // Knowing the take's length: the quiet before the first word (too short here) and after the last.
        let whole = CutPoints.pauses(words, length: 4)
        #expect(whole.count == 3 && abs((whole.last?.start ?? 0) - 2.6) < 1e-4 && whole.last?.end == 4, "\(whole)")
        let alone = CutPoints.pauses([TranscriptWord(id: "a", text: "Hi.", range: .init(start: 1.0, end: 1.4))], length: 2)
        #expect(alone.count == 2 && alone[0].start == 0 && abs(alone[0].end - 1.0) < 1e-4 && abs(alone[1].start - 1.4) < 1e-4 && alone[1].end == 2, "\(alone)")
    }

    /// Two faces close together stay two: each frame's faces carry on their own tracks, one to one.
    @Test func twoFacesCloseTogetherStayTwo() {
        let a = CutPoints.EyeSample(t: 0, open: 0.3, x: 0.45, y: 0.5), b = CutPoints.EyeSample(t: 0, open: 0.3, x: 0.55, y: 0.5)
        #expect(CutPoints.match([a, b], to: []) == [nil, nil])
        let tracks = [[a], [b]]
        let next = [CutPoints.EyeSample(t: 0.1, open: 0.3, x: 0.56, y: 0.5), CutPoints.EyeSample(t: 0.1, open: 0.1, x: 0.44, y: 0.5)]
        #expect(CutPoints.match(next, to: tracks) == [1, 0])
        // A face of its own when there's no track left for it.
        #expect(CutPoints.match(next, to: [[a]]) == [nil, 0])
    }

    /// Two frames either side of a cut jump when they're framed alike but differ; a punch-in or another shot doesn't.
    @Test func aJumpIsFramedAlikeButDifferent() {
        let face = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.3)
        #expect(CutCheck.judge(distance: 0.15, before: face, after: face.offsetBy(dx: 0.03, dy: 0)) != nil)
        #expect(CutCheck.judge(distance: 0.03, before: face, after: face.offsetBy(dx: 0.002, dy: 0)) == nil, "the same picture: seamless")
        let closer = CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.42)
        #expect(CutCheck.judge(distance: 0.3, before: face, after: closer) == nil, "a punch-in")
        #expect(CutCheck.judge(distance: 0.2, before: nil, after: nil) != nil)
        #expect(CutCheck.judge(distance: 0.8, before: nil, after: nil) == nil, "another shot")
        #expect(CutCheck.judge(distance: 0.05, before: nil, after: nil) == nil)
        // Direction's own punch-in (1 to 1.15) is a change of framing either way, never a jump.
        let punched = CGRect(x: 0.385, y: 0.375, width: 0.23, height: 0.345)
        #expect(CutCheck.judge(distance: 0.25, before: face, after: punched) == nil && CutCheck.judge(distance: 0.25, before: punched, after: face) == nil)
        // A style that punches in less draws the line lower.
        let nudged = CGRect(x: 0.395, y: 0.39, width: 0.21, height: 0.315)
        #expect(CutCheck.judge(distance: 0.2, before: face, after: nudged) != nil && CutCheck.judge(distance: 0.2, before: face, after: nudged, punch: 1.06) == nil)
    }

    // MARK: In a film

    /// A take with two quick moves of a square over a still picture: at 1.2 s and 3.2 s it's moving fastest.
    static func movingTake(in directory: URL) async throws -> URL {
        let url = directory.appendingPathComponent("moves.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        func ease(_ p: Double) -> Double { let x = min(1, max(0, p)); return x * x * (3 - 2 * x) }
        for i in 0..<180 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "No frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let c = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
            for k in 0..<8 { c.setFillColor(CGColor(red: 0.2 + 0.07 * Double(k), green: 0.3, blue: 0.5 - 0.04 * Double(k), alpha: 1)); c.fill(CGRect(x: k * 40, y: 0, width: 40, height: 180)) }
            c.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1)); c.fill(CGRect(x: 30, y: 120, width: 60, height: 40)); c.fill(CGRect(x: 230, y: 20, width: 50, height: 30))
            let t = Double(i) / 30
            let x = 40 + 180 * (ease((t - 1.0) / 0.4) - ease((t - 3.0) / 0.4))
            c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: x, y: 70, width: 44, height: 44))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        input.markAsFinished(); await writer.finishWriting()
        return url
    }

    @Test func actionIsFoundInATakeAndAnEditSnapsToIt() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let take = try await Self.movingTake(in: f.directory)
        let asset = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(take.path)])).value["asset"]
        let id = try #require(asset["id"].string)
        let found = try await f.runtime.invoke("direction_cut_points", arguments: .object(["assetID": .string(id)])).value
        let actions = (found["points"].array ?? []).filter { $0["kind"].string == "action" }.compactMap { $0["t"].double }
        #expect(actions.count == 2 && abs(actions[0] - 1.2) < 0.1 && abs(actions[1] - 3.2) < 0.1, "\(found)")
        // No face, so no blinks, and it says why.
        #expect(!(found["points"].array ?? []).contains { $0["kind"].string == "blink" } && found["says"].string?.contains("No face there") == true, "\(found)")
        // Kept: asked again, it's read from the cache.
        let kept = try FileManager.default.contentsOfDirectory(at: f.runtime.cacheDirectory.appendingPathComponent("CutPoints"), includingPropertiesForKeys: nil)
        #expect(kept.count == 1)

        // A cut of the take on its own: split near the first move, snapped onto it.
        func edit(_ ops: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "operations": .array(ops)])).value
        }
        _ = try await edit([.object(["op": .string("remove"), "clipID": .string(try f.store.read().sequences[0].clips[0].id)]), .object(["op": .string("insert"), "assetID": .string(id), "at": .number(0), "sourceRange": .object(["start": .number(0), "end": .number(6)])])])
        let clip = try #require(try f.store.read().sequences[0].clips.first { $0.assetID == id })
        let near = try await f.runtime.invoke("direction_cut_points", arguments: .object(["clipID": .string(clip.id), "at": .number(1.05), "kinds": .array([.string("action")])])).value
        let peak = try #require(near["points"].array?.first?["t"].double, "\(near)")
        let split = try await edit([.object(["op": .string("split"), "clipID": .string(clip.id), "at": .number(peak - 5.0 / 30), "snap": .string("action")])])
        #expect(split["warnings"].array?.first?.string?.hasPrefix("Snapped the split to a peak of action") == true, "\(split)")
        let pieces = try f.store.read().sequences[0].clips.filter { $0.assetID == id }.sorted { $0.start < $1.start }
        // On the frame nearest the peak (a peak is stamped between two looks, so it can fall between frames).
        #expect(pieces.count == 2 && abs(pieces[0].end.seconds - peak) <= 0.5 / 30 + 1e-3, "\(pieces.map(\.end.seconds)) \(peak)")
        // Too far from one: the split is where it was asked, and the result says so.
        let far = try await edit([.object(["op": .string("split"), "clipID": .string(pieces[1].id), "at": .number(2.2), "snap": .string("action")])])
        #expect(far["warnings"].array?.first?.string?.hasPrefix("No peak of action within 8 frames") == true, "\(far)")
        #expect(try f.store.read().sequences[0].clips.contains { abs($0.start.seconds - 2.2) < 0.02 })

        // A jump cut: the take cut to itself after the square has moved. A split that plays on isn't one.
        let story = try f.store.read().sequences[0].clips.filter { $0.assetID == id }.sorted { $0.start < $1.start }
        let continuing = try await f.runtime.invoke("direction_check", arguments: .object(["checks": .array([.string("cuts")])])).value
        #expect(continuing["cuts"].array?.isEmpty == true && continuing["cutsOnTheStory"].int == story.count - 1 && continuing["cutsCompared"].int == 0 && continuing["loudness"] == .null, "\(continuing)")
        _ = try await edit([.object(["op": .string("removeRange"), "range": .object(["start": .number(0.8), "end": .number(1.8)])])])
        let jumped = try await f.runtime.invoke("direction_check", arguments: .object(["checks": .array([.string("cuts")])])).value
        let jump = try #require(jumped["cuts"].array?.first { $0["kind"].string == "jumpCut" }, "\(jumped)")
        #expect(abs((jump["at"].double ?? 0) - 0.8) < 0.05 && jump["says"].string?.contains("jumps") == true && jump["fix"].string?.contains("punchIn") == true, "\(jump)")
        #expect(jumped["cutsCompared"].int == 1, "\(jumped)")
        // With nothing asked, it's the sound and the framing, as finishing uses it: never the cuts.
        let plain = try await f.runtime.invoke("direction_check").value
        #expect(plain["cuts"] == .null && plain["framing"] != .null && plain["loudness"] != .null, "\(plain)")

        // A snap past what the edit can reach is left alone, not a failed batch: a 6-frame clip asked to lose 5
        // frames can't trim to the peak 8 or more frames back.
        _ = try await edit([.object(["op": .string("insert"), "assetID": .string(id), "at": .number(0), "sourceRange": .object(["start": .number(1.3), "end": .number(1.5)])])])
        let short = try #require(try f.store.read().sequences[0].clips.first { $0.assetID == id && abs($0.sourceRange.start.seconds - 1.3) < 0.01 })
        let trimmed = try await edit([.object(["op": .string("trim"), "clipID": .string(short.id), "edge": .string("tail"), "frames": .number(-5), "snap": .string("action")])])
        #expect(trimmed["warnings"].array?.first?.string?.hasPrefix("The nearest peak of action is further than") == true, "\(trimmed)")
        #expect(abs(try f.store.read().sequences[0].clips.first { $0.id == short.id }!.duration.seconds - 1.0 / 30) < 0.01)
        // A take asked for past its end is read to its end; one before its start is refused, not a crash.
        let past = try await f.runtime.invoke("direction_cut_points", arguments: .object(["assetID": .string(id), "sourceRange": .object(["start": .number(5), "end": .number(1e300)]), "kinds": .array([.string("action")])])).value
        #expect(past["says"].string?.contains("6.00 s of") == true, "\(past)")
        await #expect(throws: DirectionError.self) { _ = try await f.runtime.invoke("direction_cut_points", arguments: .object(["assetID": .string(id), "sourceRange": .object(["start": .number(-5), "end": .number(2)])])) }
    }

    /// Sound that stops inside a word is found, and a trim snapped to a pause puts it right.
    @Test func aCutInsideAWordIsFoundAndATrimSnapsToAPause() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0], clip = p.sequences[0].clips[0]
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, provider: "test-timing", words: [
            TranscriptWord(id: "a", text: "Hello", range: .init(start: 0.2, end: 0.6)), TranscriptWord(id: "b", text: "there", range: .init(start: 0.7, end: 1.2)),
            TranscriptWord(id: "c", text: "friend.", range: .init(start: 1.6, end: 2.2)),
        ]))
        func edit(_ ops: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "operations": .array(ops)])).value
        }
        let pauses = try await f.runtime.invoke("direction_cut_points", arguments: .object(["clipID": .string(clip.id), "at": .number(1.4), "kinds": .array([.string("pause")])])).value
        let pause = try #require(pauses["points"].array?.first, "\(pauses)")
        #expect(pause["from"].double == 1.2 && pause["to"].double == 1.6 && pauses["says"].string?.hasPrefix("2 pauses near 1.40 s") == true, "\(pauses)")
        // A pause reaching into a small stretch is found though its middle is outside it.
        let edge = try await f.runtime.invoke("direction_cut_points", arguments: .object(["clipID": .string(clip.id), "at": .number(1.25), "within": .number(0.1), "kinds": .array([.string("pause")])])).value
        #expect(edge["points"].array?.contains { $0["from"].double == 1.2 && $0["to"].double == 1.6 } == true, "\(edge)")
        // A split inside a word that plays straight on isn't a cut in it.
        _ = try await edit([.object(["op": .string("split"), "clipID": .string(clip.id), "at": .number(1.9)])])
        let split = try await f.runtime.invoke("direction_check", arguments: .object(["checks": .array([.string("cuts")])])).value
        #expect(split["cuts"].array?.isEmpty == true, "\(split)")
        // Without the second half, the tail is cut into "friend." (at 1.9 s).
        let halves = try f.store.read().sequences[0].clips.sorted { $0.start < $1.start }
        _ = try await edit([.object(["op": .string("remove"), "clipID": .string(halves[1].id), "ripple": .bool(true)])])
        let check = try await f.runtime.invoke("direction_check", arguments: .object(["checks": .array([.string("cuts")])])).value
        let word = try #require(check["cuts"].array?.first { $0["kind"].string == "midWord" }, "\(check)")
        #expect(word["says"].string?.contains("stops partway through \u{201C}friend\u{201D}") == true && word["fix"].string?.contains("snap") == true, "\(word)")
        // Asked for 10 frames shorter (1.57 s, just inside the pause's last 3 frames): snapped to 3 frames before the word.
        let trimmed = try await edit([.object(["op": .string("trim"), "clipID": .string(clip.id), "edge": .string("tail"), "frames": .number(-10), "snap": .string("pause")])])
        #expect(trimmed["warnings"].array?.first?.string?.contains("to a pause: trimmed 12 frames, not 10") == true, "\(trimmed)")
        #expect(abs(try f.store.read().sequences[0].clips[0].end.seconds - 1.5) < 0.02)
        let after = try await f.runtime.invoke("direction_check", arguments: .object(["checks": .array([.string("cuts")])])).value
        #expect(after["cuts"].array?.isEmpty == true, "\(after)")
        // Already clear of the words: it stays where it was asked.
        let stays = try await edit([.object(["op": .string("trim"), "clipID": .string(clip.id), "edge": .string("tail"), "frames": .number(-4), "snap": .string("pause")])])
        #expect(stays["warnings"].array?.first?.string == "The tail lands on a pause already.", "\(stays)")
        #expect(abs(try f.store.read().sequences[0].clips[0].end.seconds - (1.5 - 4.0 / 30)) < 0.02)
        // A trim given as a range doesn't snap, and says so.
        let ranged = try await edit([.object(["op": .string("trim"), "clipID": .string(clip.id), "range": .object(["start": .number(0), "end": .number(1.3)]), "snap": .string("pause")])])
        #expect(ranged["warnings"].array?.first?.string?.hasPrefix("snap goes with a trim by edge and frames") == true, "\(ranged)")
        // A narration (sound on its own) that ends inside a word.
        let voice = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(f.directory.appendingPathComponent("tone0.wav").path)])).value["asset"]
        let voiceID = try #require(voice["id"].string)
        try f.store.saveTranscript(.init(assetID: voiceID, audioTrackID: Int32(voice["audio"].array?.first?["id"].int ?? 0), provider: "test-timing", words: [
            TranscriptWord(id: "n", text: "narrated", range: .init(start: 1.8, end: 2.2)), TranscriptWord(id: "m", text: "line.", range: .init(start: 2.6, end: 3.0)),
        ]))
        _ = try await edit([.object(["op": .string("overwrite"), "assetID": .string(voiceID), "at": .number(0), "track": .string("A2"), "sourceRange": .object(["start": .number(0), "end": .number(2.1)])])])
        let narrated = try await f.runtime.invoke("direction_check", arguments: .object(["checks": .array([.string("cuts")])])).value
        #expect(narrated["cuts"].array?.contains { $0["kind"].string == "midWord" && ($0["says"].string ?? "").contains("\u{201C}narrated\u{201D}") } == true, "\(narrated)")
        // The narration has pauses (not blinks: it's sound only), and its tail snaps to one.
        let line = try #require(try f.store.read().sequences[0].clips.first { $0.assetID == voiceID })
        let spoken = try await f.runtime.invoke("direction_cut_points", arguments: .object(["clipID": .string(line.id), "kinds": .array([.string("blink"), .string("pause")])])).value
        #expect(spoken["says"].string?.contains("is sound only") == true && spoken["points"].array?.contains { $0["kind"].string == "pause" && $0["from"].double == 2.2 } == true, "\(spoken)")
        let carried = try await edit([.object(["op": .string("trim"), "clipID": .string(line.id), "edge": .string("tail"), "frames": .number(4), "snap": .string("pause")])])
        #expect(carried["warnings"].array?.first?.string?.contains("to a pause: extended 6 frames, not 4") == true, "\(carried)")
        #expect(abs(try f.store.read().sequences[0].clips.first { $0.id == line.id }!.end.seconds - 2.3) < 0.02)
        let clean = try await f.runtime.invoke("direction_check", arguments: .object(["checks": .array([.string("cuts")])])).value
        #expect(clean["cuts"].array?.contains { ($0["says"].string ?? "").contains("narrated") } == false, "\(clean)")
    }

    /// With an L-cut the sound ends after the picture: a pause is judged where the sound is cut.
    @Test func aPauseIsJudgedWhereTheSoundIsCut() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0], clip = p.sequences[0].clips[0]
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, provider: "test-timing", words: [
            TranscriptWord(id: "a", text: "Hello", range: .init(start: 0.2, end: 0.6)), TranscriptWord(id: "b", text: "there", range: .init(start: 0.7, end: 1.2)),
            TranscriptWord(id: "c", text: "friend.", range: .init(start: 1.6, end: 2.2)),
        ]))
        func edit(_ ops: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "operations": .array(ops)])).value
        }
        _ = try await edit([.object(["op": .string("split"), "clipID": .string(clip.id), "at": .number(1.4)])])
        let pieces = try f.store.read().sequences[0].clips.sorted { $0.start < $1.start }
        // The first piece's sound carries 12 frames (0.4 s) past its picture.
        _ = try await edit([.object(["op": .string("splitEdit"), "editPoint": .string("\(pieces[0].id)|\(pieces[1].id)"), "lead": .string("picture"), "frames": .number(12)])])
        // 3 frames shorter puts the picture at 1.3 s, in the pause, but the sound at 1.7 s, inside "friend.": it snaps
        // the sound back into the pause (1.5 s, 3 frames before the word), so the picture goes to 1.1 s.
        let snapped = try await edit([.object(["op": .string("trim"), "clipID": .string(pieces[0].id), "edge": .string("tail"), "frames": .number(-3), "snap": .string("pause")])])
        #expect(snapped["warnings"].array?.first?.string?.contains("to a pause: trimmed 9 frames, not 3") == true, "\(snapped)")
        let first = try #require(try f.store.read().sequences[0].clips.first { $0.id == pieces[0].id })
        #expect(abs(first.end.seconds - 1.1) < 0.02 && abs(first.soundRange.end.seconds - 1.5) < 0.02, "\(first.end.seconds) \(first.soundRange.end.seconds)")
    }

    @Test func snapIsOnlyForSplitTrimAndRoll() throws {
        #expect(throws: DirectionError.self) { try EditOperation(json: .object(["op": .string("insert"), "assetID": .string("a"), "snap": .string("blink")])) }
        #expect(throws: DirectionError.self) { try EditOperation(json: .object(["op": .string("split"), "clipID": .string("c"), "at": .number(1), "snap": .string("smile")])) }
        let op = try EditOperation(json: .object(["op": .string("roll"), "editPoint": .string("a|b"), "frames": .number(4), "snap": .string("blink")]))
        #expect(op.snap == "blink" && op.json["snap"].string == "blink")
    }
}

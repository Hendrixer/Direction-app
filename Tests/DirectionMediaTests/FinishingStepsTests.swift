import Testing
import Foundation
import DirectionCore
import DirectionMedia
@testable import DirectionTools

/// The finishing steps Direction does itself: captions from the cut's words and the credits roll, made as graphics,
/// checked, and placed in one edit, after picture lock too. In the graphics suite, one render at a time: graphics
/// draw on the main thread, and two at once can miss a frame's 2 s.
extension GraphicsTests {
    @Test func captionsAndCreditsAreMadeFromTheWordsAndTheCreditsAndPlaced() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read(), asset = p.assets[0]
        let words = [("So", 0.1, 0.3), ("we", 0.35, 0.5), ("started.", 0.55, 0.9), ("Then", 1.6, 1.8), ("it", 1.85, 1.95), ("worked.", 2.0, 2.5)].enumerated().map { i, w in
            TranscriptWord(id: "w\(i)", text: w.0, range: .init(start: w.1, end: w.2))
        }
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, provider: "test-timing", words: words))
        try f.store.saveCredits("Camera\nSam Ortiz")
        try f.store.lockPicture(cutID: nil, locked: true)
        func edit(_ ops: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "operations": .array(ops)])).value
        }
        let before = try f.store.read().sequences[0].duration.seconds
        _ = try await edit([.object(["op": .string("captions")]), .object(["op": .string("credits")])])
        let after = try f.store.read(), s = after.sequences[0]
        let graphic = { (c: Clip) in c.assetID.flatMap { id in after.assets.first { $0.id == id }?.graphic } }
        let captions = s.clips.filter { graphic($0) == "captions-1" }, credits = s.clips.filter { graphic($0)?.hasPrefix("credits-") == true }
        #expect(captions.count == 1 && abs((captions.first?.start.seconds ?? -1) - 0.1) < 0.05 && (captions.first?.layer ?? 0) > 0)
        // A caption ends at a sentence and at a pause; the page got the lines and when each starts.
        let page = try String(contentsOf: f.store.graphicsFolder.appendingPathComponent("captions-1/captions.js"), encoding: .utf8)
        #expect(page.contains("\"So we started.\"") && page.contains("\"Then it worked.\""), "\(page)")
        // The credits roll on black after the last shot, and the cut runs on for them.
        #expect(abs((credits.first?.start.seconds ?? -1) - before) < 0.05 && s.duration.seconds > before + 7)
        // The caption files say what the cut shows: the director's word where they changed one, at the line's time.
        _ = try f.store.setDirectorWords("captions-1", ["lines": "So we began.\nThen it worked."], render: nil)
        let laid = try await f.runtime.captionLines().lines
        #expect(laid.map(\.text) == ["So we began.", "Then it worked."], "\(laid)")
        #expect(abs((laid.first?.start ?? -1) - 0.1) < 0.02 && abs((laid.last?.start ?? -1) - 1.6) < 0.02 && (laid.last?.end ?? 99) <= before + 0.01, "\(laid)")
        let srt = f.directory.appendingPathComponent("Film \u{2013} Captions.srt")
        #expect(try await f.runtime.writeCaptionFiles(to: srt) == 2)
        let vtt = try String(contentsOf: srt.deletingPathExtension().appendingPathExtension("vtt"), encoding: .utf8)
        #expect(try String(contentsOf: srt, encoding: .utf8).hasPrefix("1\n00:00:00,100 --> ") && vtt.hasPrefix("WEBVTT\n\n00:00:00.100 --> ") && vtt.contains("So we began."), "\(vtt)")
        // Never over a file already there.
        await #expect(throws: (any Error).self) { _ = try await f.runtime.writeCaptionFiles(to: srt) }
        // Again: in place of the ones it laid, not on top, as a graphic of its own (the old one is the earlier
        // version's), and the director's line stays theirs.
        _ = try await edit([.object(["op": .string("captions")])])
        func placedCaptions() throws -> [String] {
            let p = try f.store.read()
            return p.sequences[0].clips.compactMap { c in c.assetID.flatMap { id in p.assets.first { $0.id == id }?.graphic } }.filter { $0.hasPrefix("captions-") }
        }
        let second = try placedCaptions()
        #expect(second == ["captions-2"], "\(second)")
        let again = try await f.runtime.captionLines().lines.map(\.text)
        #expect(again == ["So we began.", "Then it worked."], "\(again)")
        // Over a range: the lines around it stay as they were, a word at a time inside it.
        _ = try await edit([.object(["op": .string("captions"), "range": .object(["start": .number(1.5), "end": .number(2.6)]), "wordsAtATime": .number(1)])])
        let ranged = try await f.runtime.captionLines().lines.map(\.text)
        #expect(try placedCaptions() == ["captions-3"] && ranged == ["So we began.", "Then", "it", "worked."], "\(ranged)")
        // Checked only: nothing made, the film where it was.
        let revision = try f.store.revision()
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(revision)), "validateOnly": .bool(true), "operations": .array([.object(["op": .string("captions")]), .object(["op": .string("credits")])])]))
        #expect(try f.store.revision() == revision && !FileManager.default.fileExists(atPath: f.store.graphicsFolder.appendingPathComponent("captions-4").path))
        #expect(try placedCaptions() == ["captions-3"])
    }

    @Test func noWordsAndNoCreditsSayWhy() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        for (op, code) in [("captions", "no_words"), ("credits", "bad_argument")] {
            do { _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "operations": .array([.object(["op": .string(op)])])])); Issue.record("\(op) should be refused") }
            catch let e as DirectionError { #expect(e.code == code, "\(op): \(e.code) \(e.message)") }
        }
        // No words, no caption files: delivery leaves the row off and says why.
        #expect(try await f.runtime.captionLines().lines.isEmpty)
        do { _ = try await f.runtime.writeCaptionFiles(to: f.directory.appendingPathComponent("none.srt")); Issue.record("no words, no files") }
        catch let e as DirectionError { #expect(e.code == "no_words") }
    }

    @Test func twoAudioChangesInABatchBothHold() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let asset = try f.store.read().assets[0], track = Double(asset.audio[0].id)
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "operations": .array([
            .object(["op": .string("audio"), "assetID": .string(asset.id), "audioTrackID": .number(track), "audio": .object(["muted": .bool(true)])]),
            .object(["op": .string("audio"), "assetID": .string(asset.id), "audioTrackID": .number(track), "audio": .object(["effects": .object(["limiter": .bool(true)])])]),
        ])]))
        let settings = try f.store.read().assets[0].audio[0].settings
        #expect(settings.muted && settings.effects.limiter, "\(settings)")
        // A track number past what a track can be is refused, not a crash.
        do { _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "operations": .array([.object(["op": .string("audio"), "assetID": .string(asset.id), "audioTrackID": .number(4_294_967_296), "audio": .object(["muted": .bool(true)])])])])); Issue.record("should be refused") }
        catch let e as DirectionError { #expect(e.code == "bad_argument") }
    }

    @Test func captionFilesComeFromTheCutsWordsWhenNoneAreLaid() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let asset = try f.store.read().assets[0]
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, language: "fr-FR", provider: "test-timing", words: [
            TranscriptWord(id: "a", text: "Bonjour.", range: .init(start: 0.2, end: 0.7)), TranscriptWord(id: "b", text: "Merci.", range: .init(start: 1.5, end: 1.9)),
        ]))
        let read = try await f.runtime.captionLines()
        #expect(read.lines.map(\.text) == ["Bonjour.", "Merci."] && read.language == "fr-FR", "\(read)")
    }
}

/// The delivery check: the sound against the target, and words where a tall frame's apps cover them.
extension GraphicsTests {
    @Test func aTallCutsCaptionsClearTheAppsAndTheSoundIsJudged() async throws {
        // A throwaway settings suite: the target is −14, whatever this Mac's director chose.
        let real = SharedSettings.defaults, suite = "direction-check-" + UUID().uuidString
        SharedSettings.defaults = UserDefaults(suiteName: suite)!
        defer { SharedSettings.defaults.removePersistentDomain(forName: suite); SharedSettings.defaults = real }
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        func edit(_ ops: [JSONValue]) async throws -> JSONValue {
            try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "operations": .array(ops)])).value
        }
        _ = try await edit([.object(["op": .string("format"), "width": .number(540), "height": .number(960)])])
        let asset = try f.store.read().assets[0]
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio[0].id, provider: "test-timing", words: [
            TranscriptWord(id: "a", text: "Direction", range: .init(start: 0.2, end: 0.8)), TranscriptWord(id: "b", text: "edits.", range: .init(start: 0.85, end: 1.4)),
        ]))
        _ = try await edit([.object(["op": .string("captions")])])
        let check = try await f.runtime.invoke("direction_check").value
        #expect(check["framesLookedAt"].int ?? 0 > 0)
        #expect(check["framing"].array?.contains { $0["kind"].string == "wordsCovered" } == false, "\(check)")
        // Words at the very bottom are where the apps' buttons go.
        let low = f.store.graphicsFolder.appendingPathComponent("low")
        try FileManager.default.createDirectory(at: low, withIntermediateDirectories: true)
        try Data(#"<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;background:transparent}#w{position:absolute;bottom:2%;left:8%;font:700 56px 'Archivo',sans-serif;color:#fff;background:#000;padding:6px 12px}</style></head><body><div id="w" data-word="line"></div><script>direction.graphic({duration:3,words:{line:{label:'Line',text:'WATCH THIS',max:40}},render(t,words){w.textContent=words.line;}});</script></body></html>"#.utf8).write(to: low.appendingPathComponent("index.html"))
        _ = try await f.runtime.invoke("direction_graphic", arguments: .object(["name": .string("low"), "note": .string("unasked")]))
        _ = try await edit([.object(["op": .string("placeGraphic"), "graphic": .string("low"), "at": .number(0)])])
        let covered = try await f.runtime.invoke("direction_check").value
        #expect(covered["framing"].array?.contains { $0["kind"].string == "wordsCovered" && ($0["says"].string ?? "").contains("WATCH") } == true, "\(covered)")
        #expect(check["loudness"]["says"].string != nil && check["ready"].bool == check["loudness"]["ready"].bool)
        // Sound is done only once the mix is on target.
        try f.store.lockPicture(cutID: nil, locked: true)
        if check["ready"].bool == false {
            do { _ = try await f.runtime.invoke("direction_finishing", arguments: .object(["items": .array([.object(["id": .string("sound"), "state": .string("done")])])])); Issue.record("off target, sound shouldn't be done") }
            catch let e as DirectionError { #expect(e.code == "loudness_off_target") }
            _ = try await edit([.object(["op": .string("loudness")])])
        }
        _ = try await f.runtime.invoke("direction_finishing", arguments: .object(["items": .array([.object(["id": .string("sound"), "state": .string("done")])])]))
    }
}

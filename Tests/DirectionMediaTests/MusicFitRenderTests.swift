import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
@testable import DirectionMedia
@testable import DirectionTools

/// A song fitted to a length and played (agent-timeline.md › Music › fit), checked by ear's measures: at every join no
/// click (no step between samples bigger than the music's own), no jump in level, and the beat carries straight on.
@Suite(.serialized)
struct MusicFitRenderTests {
    static let rate = MusicListening.rate

    /// What a join sounds like in the rendered cut.
    struct Heard: CustomStringConvertible {
        var at: Double
        /// The biggest step between samples within 3 ms of the join, over the music's own biggest steps.
        var click: Double
        /// dB from the second and a half before the join to the second and a half after: about a bar each, so the downbeat's own hit doesn't count as a jump.
        var level: Double
        /// From the join to the nearest beat heard (the downbeat it joins on), and how far the beats either side of
        /// the join are from the usual gap.
        var beat: Double?, gap: Double?
        /// From the join to the nearest beat or halfway between two: a song heard in a short stretch can be followed
        /// half a beat over (at 80 or at 160).
        var eighth: Double?
        var description: String { String(format: "join %.3f: click %.2f, level %+.1f dB, beat %@ (%@ from a beat or half beat), gap %@", at, click, level, beat.map { String(format: "%+.1f ms", $0 * 1000) } ?? "-", eighth.map { String(format: "%+.1f ms", $0 * 1000) } ?? "-", gap.map { String(format: "%+.1f ms", $0 * 1000) } ?? "-") }
    }

    static func write(_ x: [Float], _ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(x.count))!
        buffer.frameLength = AVAudioFrameCount(x.count)
        for i in x.indices { buffer.floatChannelData![0][i] = x[i] }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }

    /// A film with the files brought in as one song's parts (or one sound), placed with fit; the cut, its music clips
    /// on the first part's track in order, and the edit's result.
    static func fitted(_ files: [(url: URL, part: String?)], song: String?, fit: Double, parts: [String]?, in dir: URL) async throws -> (store: ProjectStore, clips: [Clip], result: JSONValue) {
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Fit.direction"), name: "Fit")
        let runtime = try ToolRuntime(store: store)
        var ids: [(String, String?)] = []
        for f in files {
            let asset = try await runtime.invoke("direction_import", arguments: .object(["path": .string(f.url.path)])).value["asset"]
            ids.append((asset["id"].string ?? "", f.part))
        }
        if let song {
            let p = try store.read()
            _ = try store.update(expectedRevision: p.editRevision, key: UUID().uuidString, request: Data("{}".utf8), summary: "Song") { [ids] p in
                for (id, part) in ids { if let i = p.assets.firstIndex(where: { $0.id == id }) { p.assets[i].song = song; p.assets[i].part = part } }
            }
        }
        var op: [String: JSONValue] = ["op": .string("placeMusic"), "assetID": .string(ids[0].0), "at": .number(0), "fit": .number(fit)]
        if let parts { op["parts"] = .array(parts.map(JSONValue.string)) }
        let result = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Fit"), "operations": .array([.object(op)])])).value
        let p = try store.read(), first = p.sequences[0].clips.filter { $0.kind == .audio }.map(\.layer).min()
        return (store, p.sequences[0].clips.filter { $0.kind == .audio && $0.layer == first }.sorted { $0.start < $1.start }, result)
    }

    /// Every join of the music, played: the cut's sound around it, measured.
    static func joins(_ store: ProjectStore, _ clips: [Clip], in dir: URL) async throws -> [Heard] {
        let compiled = try await SequenceRenderer.compile(project: try store.read(), cacheDirectory: dir.appendingPathComponent("cache"))
        var out: [Heard] = []
        for a in clips.dropLast() {
            let join = a.soundRange.end.seconds, from = max(0, join - 9), to = min(compiled.sequence.duration.seconds, join + 9)
            let file = dir.appendingPathComponent("join-\(out.count).wav")
            _ = try await SequenceRenderer.audioPreview(compiled, range: MediaRange(start: from, end: to), to: file)
            let read = try AVAudioFile(forReading: file), sr = read.processingFormat.sampleRate
            let buffer = AVAudioPCMBuffer(pcmFormat: read.processingFormat, frameCapacity: AVAudioFrameCount(read.length))!
            try read.read(into: buffer)
            let x = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            let j = Int((join - from) * sr), near = Int(0.003 * sr), clear = Int(0.02 * sr)
            let steps = (1..<x.count).map { abs(x[$0] - x[$0 - 1]) }
            let atJoin = steps[max(0, j - near)..<min(steps.count, j + near)].max() ?? 0
            let elsewhere = steps.enumerated().filter { abs($0.offset - j) > clear }.map(\.element).sorted()
            let usual = elsewhere[Int(Double(elsewhere.count - 1) * 0.999)]
            func db(_ a: Int, _ b: Int) -> Double { let s = x[max(0, a)..<min(x.count, b)]; return 10 * log10(Double(s.reduce(0) { $0 + $1 * $1 }) / Double(max(1, s.count)) + 1e-12) }
            let level = db(j + Int(0.02 * sr), j + Int(1.5 * sr)) - db(j - Int(1.5 * sr), j - Int(0.02 * sr))
            var heard = Heard(at: join, click: Double(atJoin / max(usual, 1e-6)), level: level)
            if let g = try await SongBeats.offPool({ try SongBeats.hear(file) }).grid {
                let local = join - from + MusicFitting.early
                if let k = g.beats.indices.min(by: { abs(g.beats[$0] - local) < abs(g.beats[$1] - local) }) {
                    heard.beat = g.beats[k] - local
                    let gaps = zip(g.beats, g.beats.dropFirst()).map { $1 - $0 }.sorted(), usualGap = gaps[gaps.count / 2]
                    if k > 0, k + 1 < g.beats.count { heard.gap = max(abs(g.beats[k] - g.beats[k - 1] - usualGap), abs(g.beats[k + 1] - g.beats[k] - usualGap)) }
                    let half = usualGap / 2, off = g.beats[k] - local
                    heard.eighth = off - (off / half).rounded() * half
                }
            }
            out.append(heard)
        }
        return out
    }

    static func check(_ heard: [Heard], _ label: String) {
        #expect(!heard.isEmpty, "\(label): no joins")
        for h in heard {
            #expect(h.click < 1.5, "\(label): \(h)")
            #expect(abs(h.level) < 3, "\(label): \(h)")
            #expect(h.beat.map { abs($0) < 0.02 } == true && h.gap.map { $0 < 0.02 } == true, "\(label): \(h)")
        }
    }

    @Test func aSongFittedShorterAndLongerJoinsOnTheBeatWithoutAClick() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let band = SongBeatsTests.band(bpm: 112, sections: 5)
        let url = dir.appendingPathComponent("Song.wav")
        try Self.write(band.mix, url)
        let seconds = Double(band.mix.count) / Self.rate
        for (k, length) in [seconds * 0.8, seconds * 1.2].enumerated() {
            let sub = dir.appendingPathComponent("\(k)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            let (store, clips, result) = try await Self.fitted([(url, nil)], song: nil, fit: length, parts: nil, in: sub)
            let summary = result["operations"].array?.first?["summary"].string ?? ""
            #expect(summary.hasPrefix("Fitted Song.wav on A2") && summary.contains("joined bar"), "\(summary)")
            #expect(abs((clips.last?.end.seconds ?? 0) - (length * 30).rounded() / 30) < 1e-6, "\(length): ends at \(clips.last?.end.seconds ?? 0)")
            let heard = try await Self.joins(store, clips, in: sub)
            print("FIT \(String(format: "%.1f", length)) s: \(summary) | \(heard)")
            Self.check(heard, String(format: "%.1f s", length))
        }
    }

    @Test func aSongInPartsFitsEveryPartOnTheSameJoins() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fit-parts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let band = SongBeatsTests.band(bpm: 104, sections: 5)
        var files: [(url: URL, part: String?)] = []
        for (name, x) in [("Full mix", band.mix), ("Drums", band.drums), ("Bass", band.bass), ("Keys", band.keys)] {
            let url = dir.appendingPathComponent("Song (\(name)).wav"); try Self.write(x, url); files.append((url, name))
        }
        let seconds = Double(band.mix.count) / Self.rate
        let (store, clips, _) = try await Self.fitted(files, song: "Song", fit: seconds * 0.8, parts: ["Drums", "Bass"], in: dir)
        let p = try store.read(), all = p.sequences[0].clips.filter { $0.kind == .audio }
        func part(_ name: String) -> [Clip] { all.filter { c in p.assets.first { $0.id == c.assetID }?.part == name }.sorted { $0.start < $1.start } }
        let drums = part("Drums"), bass = part("Bass")
        #expect(drums.count >= 2 && drums.count == bass.count && zip(drums, bass).allSatisfy { $0.start == $1.start && $0.sourceRange == $1.sourceRange && $0.soundRange == $1.soundRange && $0.layer != $1.layer })
        let heard = try await Self.joins(store, clips, in: dir)
        print("FIT parts: \(heard)")
        Self.check(heard, "in parts")
    }

    /// Bars as times, against the music in the cut: a fitted piece's downbeat (just inside its J-cut) is found at the
    /// piece's head; at.clip picks one placing of a song placed twice; a whoosh on another track isn't music; and a made
    /// song is fitted by its made record's id.
    @Test func barsAreFoundWhereTheyPlay() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bars-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let band = SongBeatsTests.band(bpm: 112, sections: 5)
        let url = dir.appendingPathComponent("Song.wav"), whoosh = dir.appendingPathComponent("Whoosh.wav")
        try Self.write(band.mix, url)
        try Self.write((0..<Int(Self.rate)).map { Float(0.3 * sin(2 * Double.pi * 900 * Double($0) / Self.rate) * exp(-Double($0) / Self.rate * 4)) }, whoosh)
        let seconds = Double(band.mix.count) / Self.rate
        let (store, pieces, _) = try await Self.fitted([(url, nil)], song: nil, fit: seconds * 0.8, parts: nil, in: dir)
        let runtime = try ToolRuntime(store: store)
        let song = try #require(pieces.first?.assetID)
        // The same song again from 2 s after the fitted one ends, on A3, and a whoosh on A4.
        let end = pieces.last!.end.seconds
        let sfx = try await runtime.invoke("direction_import", arguments: .object(["path": .string(whoosh.path)])).value["asset"]["id"].string ?? ""
        func edit(_ ops: [JSONValue]) async throws {
            _ = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("More"), "operations": .array(ops)]))
        }
        try await edit([.object(["op": .string("placeMusic"), "assetID": .string(song), "at": .number(end + 2), "endOn": .number(end + 22), "track": .string("A3")]),
                        .object(["op": .string("overwrite"), "assetID": .string(sfx), "sourceRange": .object(["start": .number(0), "end": .number(1)]), "at": .number(3), "track": .string("A4")])])
        let p = try store.read(), s = p.sequences[0]
        let g = try #require(try await SongBeats.heard(p.assets.first { $0.id == song }!, in: p, cacheDirectory: runtime.cacheDirectory).grid)
        func at(_ music: JSONValue) async throws -> Double {
            var op = try EditOperation(json: .object(["op": .string("split"), "clipID": .string(pieces[0].id), "at": music]))
            try await runtime.resolveMusic(&op, p, s)
            return try #require(op.at).seconds
        }
        // Each piece after a join starts on the downbeat of its bar.
        for piece in pieces.dropFirst() {
            let bar = try #require(g.bar(at: piece.sourceRange.start.seconds + 0.05))
            let t = try await at(.object(["bar": .number(Double(bar))]))
            #expect(abs(t - piece.start.seconds) <= 1.0 / 30, "bar \(bar) at \(t), piece at \(piece.start.seconds)")
        }
        // The second placing, by its clip: the moment it plays there, not in the fitted one.
        let second = try #require(s.clips.first { $0.assetID == song && $0.layer == 2 })
        let lastBar = try #require(g.bar(at: second.sourceRange.start.seconds + 5))
        let there = try await at(.object(["bar": .number(Double(lastBar)), "clip": .string(second.id)]))
        #expect(there >= second.start.seconds - 1e-6 && there < second.end.seconds, "\(there) not in \(second.start.seconds)–\(second.end.seconds)")
        // Placed from a bar whose downbeat falls between frames: the song starts on the frame after it, and the bar is
        // still found at the clip's head.
        let bar = try #require((5..<g.barCount).first { b in let f = (g.barStart(b)! * 30).truncatingRemainder(dividingBy: 1); return f > 0.55 && f < 0.95 })
        try await edit([.object(["op": .string("placeMusic"), "assetID": .string(song), "at": .number(end + 40), "endOn": .number(end + 50), "from": .object(["bar": .number(Double(bar))]), "track": .string("A5")])])
        let q = try store.read(), fromBar = try #require(q.sequences[0].clips.first { $0.assetID == song && $0.layer == 4 })
        var op = try EditOperation(json: .object(["op": .string("split"), "clipID": .string(pieces[0].id), "at": .object(["bar": .number(Double(bar)), "clip": .string(fromBar.id)])]))
        try await runtime.resolveMusic(&op, q, q.sequences[0])
        #expect(abs((op.at?.seconds ?? -1) - fromBar.start.seconds) <= 1.0 / 30, "bar \(bar) at \(op.at?.seconds ?? -1), placed at \(fromBar.start.seconds) from \(fromBar.sourceRange.start.seconds) for \(g.barStart(bar)!)")
        // A made song is fitted by its made record's id.
        let made = try store.read()
        _ = try store.update(expectedRevision: made.editRevision, key: UUID().uuidString, request: Data("{}".utf8), summary: "Made") { p in
            if let i = p.assets.firstIndex(where: { $0.id == song }) { p.assets[i].madeID = "made-song" }
        }
        let result = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Made"),
            "operations": .array([.object(["op": .string("placeMusic"), "madeID": .string("made-song"), "at": .number(0), "fit": .number(seconds * 0.8), "track": .string("A6")])])])).value
        #expect(result["operations"].array?.first?["summary"].string?.hasPrefix("Fitted") == true, "\(result)")
    }

    /// A song in parts whose bass can't be read still gets its grid on the parts that can.
    @Test func aSongWithAPartThatCantBeReadSharesItsGridWithTheRest() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sounds"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let band = SongBeatsTests.band(bpm: 104, sections: 2)
        try Self.write(band.mix, dir.appendingPathComponent("Sounds/Song.wav"))
        try Self.write(band.drums, dir.appendingPathComponent("Sounds/Song (Drums).wav"))
        try Data("not a sound".utf8).write(to: dir.appendingPathComponent("Sounds/Song (Bass).wav"))
        let sounds = MediaLibrary(.sounds, folder: dir.appendingPathComponent("Sounds"))
        for (file, part, measured) in [("Song.wav", Stems.fullMix, true), ("Song (Drums).wav", "Drums", true), ("Song (Bass).wav", "Bass", false)] {
            try sounds.update(file) { i in
                i.song = "Song"; i.part = part
                if measured { var m = ShelfItem.Measured(); m.seconds = Double(band.mix.count) / Self.rate; m.version = ShelfItem.Measured.currentVersion; i.measured = m }
            }
        }
        let changed = await LibraryMeasuring.shareSongGrids(in: sounds, cacheDirectory: dir.appendingPathComponent("cache"))
        #expect(Set(changed.map(\.file)) == ["Song.wav", "Song (Drums).wav"])
        let items = sounds.items()
        #expect(items.filter { $0.file != "Song (Bass).wav" }.allSatisfy { $0.measured?.grid?.heardOn == "Drums" && abs(($0.measured?.tempo ?? 0) - 104) < 1 }, "\(items.map { ($0.file, $0.measured?.tempo ?? 0) })")
    }

    /// A sound that starts between the renderer's ticks (a seventh of a second), fading in, is scheduled without its
    /// ramp starting before its first volume, which AVFoundation refuses by stopping the app.
    @Test func aSoundStartingBetweenTicksFadesInWithoutStoppingTheRenderer() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ticks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Tone.wav")
        try Self.write((0..<Int(3 * Self.rate)).map { Float(0.2 * sin(2 * Double.pi * 330 * Double($0) / Self.rate)) }, url)
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Ticks.direction"), name: "Ticks")
        let runtime = try ToolRuntime(store: store)
        let id = try await runtime.invoke("direction_import", arguments: .object(["path": .string(url.path)])).value["asset"]["id"].string ?? ""
        let p = try store.read()
        _ = try store.update(expectedRevision: p.editRevision, key: UUID().uuidString, request: Data("{}".utf8), summary: "Tone") { p in
            for (k, at) in [MediaTime(value: 1, timescale: 7), MediaTime(value: 13, timescale: 11)].enumerated() {
                var c = Clip(assetID: id, name: "Tone", kind: .audio, layer: 1 + k, start: at, sourceRange: .init(start: 0, end: 2))
                c.fadeIn = 0.05; c.soundLead = 0.0123456; c.fadeOut = 0.0071
                p.sequences[0].clips.append(c)
            }
        }
        let compiled = try await SequenceRenderer.compile(project: try store.read(), cacheDirectory: dir.appendingPathComponent("cache"))
        #expect(compiled.sequence.clips.count == 2)
    }

    /// Fits each file in DIRECTION_FIT_PROBE (separated by |) shorter and longer and measures every join.
    @Test func probe() async throws {
        guard let list = ProcessInfo.processInfo.environment["DIRECTION_FIT_PROBE"] else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fit-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = list.split(separator: "|").map { URL(fileURLWithPath: String($0)) }
        let seconds = try await AVURLAsset(url: urls[0]).load(.duration).seconds
        let lengths = (ProcessInfo.processInfo.environment["DIRECTION_FIT_LENGTHS"] ?? "0.5,0.8,1.2").split(separator: ",").compactMap { Double($0) }.map { $0 > 3 ? $0 : seconds * $0 }
        let parts: [(url: URL, part: String?)] = urls.count > 1 ? zip(urls, ["Full mix", "Drums", "Bass", "Instruments"]).map { ($0, $1) } : [(urls[0], nil)]
        for (k, length) in lengths.enumerated() {
            let sub = dir.appendingPathComponent("\(k)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            let started = Date()
            let (store, clips, result) = try await Self.fitted(parts, song: urls.count > 1 ? "Song" : nil, fit: length, parts: urls.count > 1 ? ["Full mix", "Drums"] : nil, in: sub)
            let op = result["operations"].array?.first ?? .null
            print("PROBE fit \(String(format: "%.1f", length)) s in \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(op["summary"].string ?? "") warnings \(op["warnings"])")
            for h in try await Self.joins(store, clips, in: sub) { print("PROBE   \(h)") }
        }
    }
}

import Testing
import Foundation
@testable import DirectionCore

/// Fitting a song to a length by joining its bars (agent-timeline.md › Music › fit), on a song made here: 120 beats
/// a minute, 4 beats a bar from 0.5 s, an intro of 4 bars, a verse and a chorus of 16 each (a chord a bar, round in
/// fours), and an outro of 4, ringing 3.5 s after its last beat.
struct MusicFittingTests {
    static let bars = 40, barSeconds = 2.0, firstBeat = 0.5

    static func material() -> MusicMaterial {
        let beats = (0..<(bars * 4)).map { firstBeat + Double($0) * 0.5 }
        let grid = BeatGrid(beats: beats, bars: Array(stride(from: 0, to: beats.count, by: 4)), beatsPerBar: 4, changes: [5, 21, 37])
        func unit(_ k: Int, _ chord: Int?) -> [Float] {
            var v = [Float](repeating: 0, count: 25); v[k] = 1
            if let chord { v[5 + chord] = 0.35 }
            return v
        }
        var sounds: [[Float]] = [], levels: [Float] = []
        for b in 0..<bars {
            switch b {
            case 0..<4: sounds.append(unit(0, nil)); levels.append(-20)
            case 4..<20: sounds.append(unit(1, (b - 4) % 4)); levels.append(-14)
            case 20..<36: sounds.append(unit(2, 4 + (b - 20) % 4)); levels.append(-10)
            default: sounds.append(unit(3, nil)); levels.append(-16)
            }
        }
        return MusicMaterial(grid: grid, seconds: firstBeat + Double(bars) * barSeconds + 3.5, bars: sounds, levels: levels, lastHit: beats.last!)
    }

    /// Every piece but the first starts just before a downbeat, and every piece but the last ends just before one.
    static func onDownbeats(_ plan: MusicPlan, _ m: MusicMaterial) -> Bool {
        let starts = m.grid.barStarts
        func nearBar(_ t: Double) -> Bool { starts.contains { abs($0 - MusicFitting.early - t) < 1e-9 } }
        return plan.pieces.dropFirst().allSatisfy { nearBar($0.start) } && plan.pieces.dropLast().allSatisfy { nearBar($0.end) }
    }

    @Test func aSongIsFittedShorterAndLongerOnItsDownbeatsKeepingItsIntroAndEnding() throws {
        let m = Self.material(), starts = m.grid.barStarts
        // Lengths a whole number of phrases from the song's (83.5 s) give or take the ring and the moment before bar 1.
        for length in [66.8, 50.5, 115.0, 100.0] {
            let plan = try MusicFitting.plan(m, length: length, song: "Test")
            #expect(abs(plan.length - length) < 1e-9, "\(length): \(plan.length)")
            #expect(Self.onDownbeats(plan, m), "\(length): \(plan.pieces)")
            #expect((plan.pieces.first?.start ?? 1) <= Self.firstBeat, "\(length): starts at \(plan.pieces.first?.start ?? -1)")
            // Its own ending: the last piece runs to the end, less at most the ring.
            #expect((plan.pieces.last?.end ?? 0) >= m.lastHit + 1.5 - 1e-9, "\(length): ends at \(plan.pieces.last?.end ?? 0)")
            #expect(plan.pieces.count >= 2 && plan.pieces.count <= 3 && plan.warnings.isEmpty, "\(length): \(plan.pieces.count) pieces, \(plan.warnings)")
            // The joins are inside the verse and chorus, a whole number of phrases apart, between alike bars.
            for (a, b) in zip(plan.pieces, plan.pieces.dropFirst()) {
                let x = starts.firstIndex { abs($0 - MusicFitting.early - a.end) < 1e-9 }!, y = starts.firstIndex { abs($0 - MusicFitting.early - b.start) < 1e-9 }!
                #expect(x >= 4 && x <= 36 && y >= 4 && y <= 36 && (y - x) % 4 == 0, "\(length): joined bar \(x) to \(y)")
                #expect(m.bars[x - 1] == m.bars[y - 1] && m.bars[x] == m.bars[y], "\(length): bar \(x) into \(y) aren't alike")
            }
            #expect(plan.said.hasPrefix("bars 1\u{2013}") && plan.joins.allSatisfy { $0.contains("100% alike") }, "\(plan.said) \(plan.joins)")
        }
        // Lengths that can't be reached a whole number of phrases away still come out exact, on downbeats, and say
        // so, with lengths near them that join cleanly.
        for length in [m.seconds * 1.2, 31.25] {
            let plan = try MusicFitting.plan(m, length: length, song: "Test")
            #expect(abs(plan.length - length) < 1e-9 && Self.onDownbeats(plan, m), "\(length): \(plan)")
            #expect(!plan.warnings.isEmpty, "\(length): \(plan)")
        }
        let awkward = try MusicFitting.plan(m, length: 100.2, song: "Test")
        #expect(awkward.warnings.contains { $0.contains("fit to 100.0 s or 105.0 s, which join cleanly") }, "\(awkward.warnings)")
        #expect(try MusicFitting.plan(m, length: 100.0, song: "Test").warnings.isEmpty)
    }

    @Test func aShortFitStartsOnALaterBarAndATooLongOneIsRefused() throws {
        let m = Self.material()
        // Shorter than the intro and the ending together: the song starts on a later bar, or ends faded, and says so.
        let short = try MusicFitting.plan(m, length: 7.3, song: "Test")
        #expect(abs(short.length - 7.3) < 1e-9 && !short.warnings.isEmpty, "\(short)")
        #expect(throws: DirectionError.self) { try MusicFitting.plan(m, length: m.seconds * 3, song: "Test") }
    }

    /// A song in parts placed with fit: each part on its own track plays the same pieces, every piece's clip starts on
    /// a frame, and its sound meets the next exactly at the join, crossing over before the downbeat.
    @Test func placeMusicFitsEveryPartOnTheSameJoins() throws {
        var cut = TimelineCut.make()
        let m = Self.material()
        for part in ["Full mix", "Drums"] {
            var a = MediaAsset(id: "fit-" + part.lowercased().replacingOccurrences(of: " ", with: ""), name: "Fit \(part)", path: "/fit-\(part).wav", duration: .init(seconds: m.seconds), audio: [.init(id: 1, index: 0, label: "Audio 1", channels: 2, sampleRate: 48_000)])
            a.song = "Fit"; a.part = part
            cut.project.assets.append(a)
        }
        var place = try op(#"{"op":"placeMusic","assetID":"fit-fullmix","at":1,"fit":50,"parts":["Full mix","Drums"]}"#)
        place.resolved = ResolvedValues(); place.resolved?.music = m
        let (p, r) = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [place]), on: cut.project, context: cut.context)
        let summary = r.operations[0].summary
        #expect(summary.hasPrefix("Fitted Fit (Full mix, Drums) on A3, A4 to end on") && summary.contains("joined bar"), "\(summary)")
        let clips = p.sequences[0].clips.filter { $0.assetID?.hasPrefix("fit-") == true }
        let mix = clips.filter { $0.assetID == "fit-fullmix" }.sorted { $0.start < $1.start }, drums = clips.filter { $0.assetID == "fit-drums" }.sorted { $0.start < $1.start }
        #expect(mix.count >= 2 && mix.count == drums.count && zip(mix, drums).allSatisfy { $0.start == $1.start && $0.sourceRange == $1.sourceRange && $0.soundLead == $1.soundLead && $0.soundTail == $1.soundTail })
        #expect(mix.first?.start == MediaTime(seconds: 1) && mix.last?.end == MediaTime(seconds: 51))
        // Clips start on frames; sounds meet at the joins and cross over in the 10 ms before.
        for c in mix { #expect(abs((c.start.seconds * 30).rounded() - c.start.seconds * 30) < 1e-6) }
        for (a, b) in zip(mix, mix.dropFirst()) {
            #expect(a.end == b.start)
            let join = a.soundRange.end.seconds
            #expect(abs(b.soundRange.start.seconds + MusicFitting.crossfade - join) < 1e-6, "sound \(a.soundRange.end.seconds) meets \(b.soundRange.start.seconds)")
            #expect(a.fadeOut == MusicFitting.crossfade && b.fadeIn == MusicFitting.crossfade)
            // At the join, a has played to just before a downbeat and b plays on from just before another.
            let aSong = a.sourceRange.start.seconds + (join - a.start.seconds), bSong = b.sourceRange.start.seconds + (join - b.start.seconds)
            #expect(m.grid.barStarts.contains { abs($0 - MusicFitting.early - aSong) < 1e-4 } && m.grid.barStarts.contains { abs($0 - MusicFitting.early - bSong) < 1e-4 }, "\(aSong) \(bSong)")
        }
        // The outline says where it joined, not the cuts under a frame that make it.
        let outline = TimelineExport.document(.init(project: p, sequence: p.sequences[0], cutName: "Cut 1")).outline
        #expect(outline.contains("joined from") && !outline.contains("J 0f"), "\(outline)")
        // A part brought in or out keeps the joins.
        let heard = try op(#"{"op":"parts","clipID":"\#(mix[1].id)","heard":{"Drums":[]}}"#)
        let (q, _) = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [heard]), on: p, context: cut.context)
        let kept = q.sequences[0].clips.filter { $0.assetID == "fit-fullmix" }.sorted { $0.start < $1.start }
        #expect(kept.map(\.soundLead) == mix.map(\.soundLead) && kept.map(\.soundTail) == mix.map(\.soundTail))
    }

    /// A song that ends on a hit: its last bar is one beat, with 0.3 s after it. A join can't land in that bar and
    /// leave nothing of the ending to play: every piece plays at least a beat, at every length, and the music never
    /// runs past where it was asked to end.
    @Test func everyPiecePlaysAtLeastABeatOnASongEndingOnAHit() throws {
        // Bars that sound like one of a few, picked the same way every run, so some pairs far apart are alike and a join
        // into the last bar is as likely as any.
        var seed: UInt64 = 7
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        func song(bars: Int, bpm: Double) -> MusicMaterial {
            let beat = 60 / bpm, beats = (0..<((bars - 1) * 4 + 1)).map { 0.3 + Double($0) * beat }
            let grid = BeatGrid(beats: beats, bars: Array(stride(from: 0, to: beats.count, by: 4)), beatsPerBar: 4)
            let sounds = (0..<bars).map { _ -> [Float] in var v = [Float](repeating: 0, count: 25); v[next() % 3] = 1; return v }
            return MusicMaterial(grid: grid, seconds: beats.last! + 0.3, bars: sounds, levels: [Float](repeating: -12, count: bars), lastHit: beats.last!)
        }
        var cases: [(MusicMaterial, [Double])] = [(song(bars: 28, bpm: 120), [56.69]), (song(bars: 12, bpm: 120), [22.93]), (song(bars: 40, bpm: 80), [122.4, 146.9])]
        for _ in 0..<12 { cases.append((song(bars: 8 + next() % 32, bpm: 80 + Double(next() % 80)), [])) }
        for (m, asked) in cases {
            let beat = 60 / m.grid.tempo
            for length in asked + stride(from: 0.4, through: 1.9, by: 0.0237).map({ $0 * m.seconds }) {
                guard let plan = try? MusicFitting.plan(m, length: length, song: "Hit") else { continue }
                #expect(abs(plan.length - length) < 1e-9, "\(length): \(plan.length)")
                #expect(plan.pieces.allSatisfy { $0.end - $0.start >= beat - 1e-6 }, "\(m.seconds) s fitted to \(length): \(plan.pieces) \(plan.said)")
            }
        }
        // In the cut: the pieces end exactly at the asked end, with a clip after it on the same track.
        var cut = TimelineCut.make()
        let m = song(bars: 28, bpm: 120)
        cut.project.assets.append(MediaAsset(id: "hit", name: "Hit.wav", path: "/hit.wav", duration: .init(seconds: m.seconds), audio: [.init(id: 1, index: 0, label: "Audio 1", channels: 2, sampleRate: 48_000)]))
        cut.project.sequences[0].clips.append(Clip(id: "after", assetID: "music", name: "after", kind: .audio, layer: 4, start: .init(seconds: 57), sourceRange: .init(start: 0, end: 2)))
        var place = try op(#"{"op":"placeMusic","assetID":"hit","at":0.3,"fit":56.69,"track":"A5"}"#)
        place.resolved = ResolvedValues(); place.resolved?.music = m
        let (p, _) = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [place]), on: cut.project, context: cut.context)
        let pieces = p.sequences[0].clips.filter { $0.assetID == "hit" }.sorted { $0.start < $1.start }
        #expect(pieces.allSatisfy { $0.duration.seconds > 0.4 } && pieces.last?.end == MediaTime(seconds: 57), "\(pieces.map { ($0.start.seconds, $0.end.seconds) })")
    }

    /// The planner's last resort (starting on a later bar) looks at the best joins only, so a long song is planned in
    /// moments: 450 bars with nothing alike to join.
    @Test func aLongSongWithNothingAlikeIsPlannedQuickly() throws {
        let bars = 450, beats = (0..<(bars * 4)).map { 0.5 + Double($0) * 0.5 }
        let grid = BeatGrid(beats: beats, bars: Array(stride(from: 0, to: beats.count, by: 4)), beatsPerBar: 4)
        var random = SystemRandomNumberGenerator()
        let sounds = (0..<bars).map { _ in (0..<25).map { _ in Float.random(in: 0...1, using: &random) } }
        let m = MusicMaterial(grid: grid, seconds: beats.last! + 3, bars: sounds, levels: (0..<bars).map { _ in Float.random(in: -20 ... -8, using: &random) }, lastHit: beats.last!)
        let started = Date()
        _ = try? MusicFitting.plan(m, length: m.seconds * 0.63, song: "Long")
        #expect(Date().timeIntervalSince(started) < 20, "\(Date().timeIntervalSince(started)) s")
    }

    /// A cut made by hand in music (a split, then a slip) reads as it is; only a fitted song's pieces read as joined.
    @Test func onlyAFittedSongsPiecesReadAsJoined() throws {
        var cut = TimelineCut.make()
        _ = try cut.apply(#"{"op":"split","clipID":"m1","at":6}"#)
        let right = try #require(cut.project.sequences[0].clips.first { $0.assetID == "music" && $0.start == MediaTime(seconds: 6) })
        _ = try cut.apply(#"{"op":"slip","clipID":"\#(right.id)","frames":45}"#, #"{"op":"fade","clipID":"\#(right.id)","in":6}"#)
        let outline = TimelineExport.document(.init(project: cut.project, sequence: cut.project.sequences[0], cutName: "Cut 1")).outline
        #expect(!outline.contains("joined from") && outline.contains("fade 6f/0f"), "\(outline)")
    }

    /// Times and lengths past any cut are refused where they're read, not left to overflow.
    @Test func hugeTimesAndLengthsAreRefused() throws {
        for text in [#"{"op":"placeMusic","assetID":"music","at":0,"fit":1e300}"#, #"{"op":"placeMusic","assetID":"music","at":0,"fit":20000}"#, #"{"op":"split","clipID":"c1","at":1e300}"#,
                     #"{"op":"placeMusic","assetID":"music","at":0,"endOn":1e300}"#, #"{"op":"placeMusic","assetID":"music","at":0,"endOn":{"time":-1e12}}"#, #"{"op":"placeMusic","assetID":"music","at":0,"endOn":4,"from":1e300}"#,
                     #"{"op":"split","clipID":"c1","at":{"value":9000000000000,"timescale":1}}"#] {
            expectFailure("bad_argument", index: nil) { _ = try op(text) }
        }
    }

    @Test func fitIsRefusedWhereItCantBe() throws {
        var cut = TimelineCut.make()
        let m = Self.material()
        cut.project.assets.append(MediaAsset(id: "song", name: "Song.wav", path: "/song.wav", duration: .init(seconds: m.seconds), audio: [.init(id: 1, index: 0, label: "Audio 1", channels: 2, sampleRate: 48_000)]))
        func run(_ text: String, material: Bool = true) throws {
            var o = try op(text)
            if material { o.resolved = ResolvedValues(); o.resolved?.music = m }
            _ = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [o]), on: cut.project, context: cut.context)
        }
        // Without Direction's measuring, with from, or with a length and endOn both.
        expectFailure("bad_argument", index: 0) { try run(#"{"op":"placeMusic","assetID":"song","at":0,"fit":30}"#, material: false) }
        expectFailure("bad_argument", index: 0) { try run(#"{"op":"placeMusic","assetID":"song","at":0,"fit":30,"from":4}"#) }
        expectFailure("bad_argument", index: 0) { try run(#"{"op":"placeMusic","assetID":"song","at":0,"fit":30,"endOn":12}"#) }
        expectFailure("bad_argument", index: nil) { _ = try op(#"{"op":"placeMusic","assetID":"song","at":0,"fit":"long"}"#) }
        // A time in bars that never went through direction_edit.
        expectFailure("bad_argument", index: 0) { _ = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [try op(#"{"op":"split","clipID":"c1","at":{"bar":2}}"#)]), on: cut.project, context: cut.context) }
        // fit "cut": to the end of the picture.
        try run(#"{"op":"placeMusic","assetID":"song","at":0,"fit":"cut","track":"A5"}"#)
        // A bar time reads back as written.
        let bar = try op(#"{"op":"cutaway","assetID":"a","sourceRange":{"start":0,"end":1},"at":{"bar":3,"beat":2}}"#)
        #expect(bar.atMusic?["bar"].int == 3 && bar.at == nil && bar.json["at"]["beat"].int == 2)
        expectFailure("bad_argument", index: nil) { _ = try op(#"{"op":"split","clipID":"c1","at":{"bar":0}}"#) }
        expectFailure("bad_argument", index: nil) { _ = try op(#"{"op":"split","clipID":"c1","at":{"bar":2,"bars":3}}"#) }
    }
}

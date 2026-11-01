import Testing
import Foundation
import DirectionCore
@testable import DirectionMedia

/// Hearing the music in a video (styles.md › From a video › Music), checked on music made here: clicks at a
/// known beat, chords in a known key, and a change of key partway.
struct MusicListeningTests {
    static let rate = MusicListening.rate

    /// A note with its first few harmonics, as an instrument has.
    static func note(_ hz: Double, _ t: Double) -> Double { (1...4).reduce(0) { $0 + pow(0.6, Double($1 - 1)) * sin(2 * .pi * hz * Double($1) * t) } }
    static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// A short knock on every beat over a quiet hum.
    static func clicks(bpm: Double, seconds: Double) -> [Float] {
        let beat = 60 / bpm
        return (0..<Int(seconds * rate)).map { i in
            let t = Double(i) / rate, since = t.truncatingRemainder(dividingBy: beat)
            return Float(0.05 * sin(2 * .pi * 110 * t) + (since < 0.03 ? 0.8 * exp(-since * 120) * sin(2 * .pi * 900 * since) : 0))
        }
    }

    /// A chord held, its notes together over its bass.
    static func held(_ notes: [Int], bass: Int, seconds: Double) -> [Float] {
        (0..<Int(seconds * rate)).map { i in let t = Double(i) / rate; return Float(0.1 * notes.reduce(0) { $0 + note(hz($1), t) } + 0.2 * note(hz(bass), t)) }
    }

    /// A bass note held under an arpeggio of a chord, a note every quarter second.
    static func chord(_ notes: [Int], bass: Int, seconds: Double) -> [Float] {
        (0..<Int(seconds * rate)).map { i in
            let t = Double(i) / rate, n = notes[Int(t * 4) % notes.count]
            return Float(0.25 * note(hz(n), t) + 0.2 * note(hz(bass), t))
        }
    }

    @Test func aSteadyBeatIsHeardAtItsTempo() {
        for bpm in [120.0, 95, 72, 150] {
            let f = MusicListening.features(samples: Self.clicks(bpm: bpm, seconds: 20))
            let heard = MusicListening.tempo(f.onsets[...])
            #expect(heard.map { abs($0 - bpm) < 2 } == true, "\(bpm) heard as \(heard ?? 0)")
        }
        // Quietly, and with the frames under words left out.
        let quiet = MusicListening.features(samples: Self.clicks(bpm: 100, seconds: 20).map { $0 * 0.05 })
        let words = MusicListening.onsetMask([2...3.2, 7...8.5, 12...13], quiet)
        #expect(MusicListening.tempo(quiet.onsets[...], quiet: words).map { abs($0 - 100) < 2 } == true)
    }

    @Test func aHeldChordOrNoiseHasNoTempo() {
        let hum = (0..<Int(20 * Self.rate)).map { i in Float(0.3 * Self.note(110, Double(i) / Self.rate)) }
        #expect(MusicListening.tempo(MusicListening.features(samples: hum).onsets[...]) == nil)
        // A pad with vibrato and a slow swell repeats, but nothing in it knocks.
        let pad = (0..<Int(20 * Self.rate)).map { i -> Float in
            let t = Double(i) / Self.rate, v = 1 + 0.004 * sin(2 * .pi * 5 * t)
            return Float(0.15 * (Self.note(220 * v, t) + Self.note(261.6 * v, t) + Self.note(329.6 * v, t)) * (0.7 + 0.3 * sin(2 * .pi * 0.1 * t)))
        }
        #expect(MusicListening.tempo(MusicListening.features(samples: pad).onsets[...]) == nil)
        let noise = (0..<Int(20 * Self.rate)).map { _ in Float.random(in: -0.2...0.2) }
        #expect(MusicListening.tempo(MusicListening.features(samples: noise).onsets[...]) == nil)
        // Too short to tell.
        #expect(MusicListening.tempo(MusicListening.features(samples: Self.clicks(bpm: 120, seconds: 5)).onsets[...]) == nil)
    }

    @Test func chordsAreHeardInTheirKey() {
        let quiet = [Bool]()
        let aMinor = MusicListening.features(samples: Self.chord([57, 60, 64, 69], bass: 45, seconds: 12))
        #expect(MusicListening.key(MusicListening.notes(aMinor, from: 0, to: 12, quiet: quiet)) == "A minor")
        let cMajor = MusicListening.features(samples: Self.chord([60, 64, 67, 72], bass: 48, seconds: 12))
        #expect(MusicListening.key(MusicListening.notes(cMajor, from: 0, to: 12, quiet: quiet)) == "C major")
        let eFlat = MusicListening.features(samples: Self.chord([63, 67, 70, 75], bass: 51, seconds: 12))
        #expect(MusicListening.key(MusicListening.notes(eFlat, from: 0, to: 12, quiet: quiet)) == "E\u{266D} major")
    }

    @Test func aChangeOfKeyInsideTheMusicIsFound() {
        let f = MusicListening.features(samples: Self.chord([57, 60, 64, 69], bass: 45, seconds: 30) + Self.chord([63, 67, 70, 75], bass: 51, seconds: 30))
        let changes = MusicListening.changes(f, from: 0, to: 60, quiet: [])
        #expect(changes.count == 1 && abs((changes.first ?? 0) - 30) <= 2, "\(changes)")
        // The same chords all the way through don't change.
        let same = MusicListening.features(samples: Self.chord([57, 60, 64, 69], bass: 45, seconds: 60))
        #expect(MusicListening.changes(same, from: 0, to: 60, quiet: []).isEmpty)
    }

    @Test func hitsAndRisersOnCuts() {
        // Quiet, a knock at 5 s, then a swell from 8 to 10 s.
        let samples = (0..<Int(12 * Self.rate)).map { i -> Float in
            let t = Double(i) / Self.rate
            let knock = t >= 5 && t < 5.03 ? 0.9 * exp(-(t - 5) * 120) * sin(2 * .pi * 900 * (t - 5)) : 0
            let swell = t >= 8 && t < 10 ? 0.01 * pow(10, (t - 8) * 1.2) * sin(2 * .pi * 300 * t) : 0
            return Float(0.01 * sin(2 * .pi * 110 * t) + knock + swell)
        }
        let f = MusicListening.features(samples: samples)
        #expect(MusicListening.hit(f, at: 5) && !MusicListening.hit(f, at: 3))
        #expect(MusicListening.riser(f, into: 10) && !MusicListening.riser(f, into: 4))
    }
}

/// The whole read on a made-up mix: a held chord in A minor over a beat, then one in E♭ major with no gap, a voice over part of the
/// first, talk with no music, a short burst of music, and a whoosh on a cut.
@Test func aMixIsReadIntoCuesBreaksAndLevels() throws {
    typealias T = MusicListeningTests
    let rate = MusicListening.rate, length = 73.0
    let first = T.held([57, 60, 64, 69], bass: 45, seconds: 30), second = T.held([63, 67, 70, 75], bass: 51, seconds: 30)
    let beat = T.clicks(bpm: 100, seconds: 60)
    // Words of 0.3 s every 0.7 s from 10 to 20 s and from 60 to 70 s.
    let starts = stride(from: 10.0, to: 19.7, by: 0.7).map { $0 } + stride(from: 60.0, to: 69.7, by: 0.7).map { $0 }
    let words = starts.map { TranscriptWord(text: "word", range: MediaRange(start: $0, end: $0 + 0.3)) }
    let samples = (0..<Int(length * rate)).map { i -> Float in
        let t = Double(i) / rate
        let music: Float = i < first.count ? 0.25 * first[i] : i < first.count + second.count ? 0.25 * second[i - first.count] : (t >= 70 && t < 73 ? 0.05 * Float(sin(2 * .pi * 440 * t)) : 0)
        let click: Float = i < beat.count ? 0.3 * beat[i] : 0
        let speaking = starts.contains { t >= $0 && t < $0 + 0.3 }
        return music + click + (speaking ? Float(0.6 * sin(2 * .pi * 180 * t) + 0.3 * sin(2 * .pi * 360 * t)) : 0)
    }
    let f = MusicListening.features(samples: samples)
    let heard = (0..<Int(length)).map { s -> VideoStudying.Heard in
        let t = Double(s)
        var h = VideoStudying.Heard(music: t < 60 || (t >= 70 && t < 73) ? 0.8 : 0.05, speech: (t >= 10 && t < 20) || (t >= 60 && t < 70) ? 0.9 : 0)
        if t < 60 { h.instruments = ["piano": 0.7] }
        if s == 45 { h.others = ["whoosh": 0.6] }
        return h
    }
    var sound = VideoStudy.Sound()
    VideoStudying.score(&sound, heard: heard, features: f, words: words, cuts: [30, 45, 60], seconds: length)

    let cues = try #require(sound.cues)
    #expect(cues.count == 2, "\(cues)")
    guard cues.count == 2 else { return }
    #expect(cues[0].start == 0 && abs(cues[0].end - 30) <= 2 && cues[1].end == 60)
    #expect(cues[0].key == "A minor" && cues[1].key == "E\u{266D} major")
    #expect(cues.allSatisfy { $0.tempo.map { abs($0 - 100) < 2 } == true && $0.instruments == ["piano"] }, "\(cues.map(\.tempo))")
    #expect(abs(cues[0].underSpeech - 1.0 / 3) < 0.1 && cues[1].underSpeech == 0)
    #expect(cues[0].startsOnCut == nil && cues[1].startsOnCut == true && cues[1].endsOnCut == true)
    #expect(sound.stings == [70])
    #expect(sound.breaks == [VideoStudy.Stretch(start: 60, end: 73)])
    // The music sits well under the voice in the pauses, and no louder with nobody talking (there's no ducking here).
    let under = try #require(sound.musicUnderVoiceDB), alone = try #require(sound.musicAloneDB)
    #expect((-25 ... -6).contains(under) && abs(alone - under) <= 3, "\(under) \(alone)")
    #expect(sound.effects == [VideoStudy.Effect(at: 45, sound: "whoosh", onCut: true)])
    // The cut at 60 s has a word starting on it, so it's neither a hit nor a riser to hear.
    #expect(sound.cutsHeard == 2 && sound.cutsClearOfTalk == 2)
    // The two cues are in different keys, so the film as a whole fits neither well enough to name.
    #expect(sound.key == nil || sound.key == "A minor" || sound.key == "E\u{266D} major")
}

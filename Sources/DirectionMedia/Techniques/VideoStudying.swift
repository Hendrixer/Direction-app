import Foundation
@preconcurrency import AVFoundation
@preconcurrency import SoundAnalysis
import CoreGraphics
import Vision
import DirectionCore

/// Measuring a video someone else made, to learn a style from it (styles.md › From a video): how fast it cuts,
/// how it talks, how loud it is and whether music plays, how close it frames faces and how it looks, and the
/// words on its screen. All of it runs on this Mac. The editor takes these numbers as they are and judges the
/// rest from the contact sheets and the transcript written beside them.
public enum VideoStudying {
    /// The largest face's height as a share of the frame's: close from 0.33, medium from 0.15, wide below.
    static let close = 0.33, medium = 0.15
    /// Two shots show one face when its center moved under 0.12 of the frame; a cut between them punches in or
    /// out when the face's height changed by 8% or more.
    static let sameFace = 0.12, punch = 0.08
    /// Words on screen are captions when they're said within this many seconds.
    static let captionWindow = 1.5
    /// Frames are read for text at 1280 (a 720p video as it is) and for faces at 640.
    static let frameSize = 1280, faceSize = 640
    /// A second has music, or speech, when the classifier is this sure of it.
    static let musicHeard = 0.4, speechHeard = 0.5

    static let steps = ["Listening", "Reading the words on screen", "Finding the cuts", "Looking at the picture"]

    /// Measures `video` into `folder`: transcript.txt and the contact sheets (`TutorialStudy.prepare`), study.json
    /// and study.md. `credits` are the lines about its music on its page. Given `words`, they're used instead of listening. Progress is the step in words and how
    /// far through the whole study, 0–1. Sound that can't be measured is left out rather than failing the study.
    public static func study(video: URL, folder: URL, cacheDirectory: URL, title: String?, by: String?, link: String?, credits: [String]? = nil, words given: [TranscriptWord]? = nil,
                             progress: (@Sendable (String, Double) -> Void)? = nil) async throws -> VideoStudy {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asset = try await MediaInspector.inspect(url: video, thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails"))
        let seconds = asset.duration.seconds
        let say = Steps(report: progress, weights: [given == nil && !asset.audio.isEmpty ? 0.3 : 0.08, 0.25, 0.4, 0.17])

        say(0, 0)
        var heard = given
        if heard == nil, !asset.audio.isEmpty { heard = await TutorialStudy.listen(asset, cacheDirectory: cacheDirectory) }
        let words = (heard ?? []).sorted { $0.range.start < $1.range.start }
        say(0, 0.6)
        let listened = await Self.listen(asset, cacheDirectory: cacheDirectory)
        try Task.checkCancellation()

        // The screen is read before the cuts are found, so the captions' place can be covered while looking for them.
        say(1, 0)
        let looks = try await Self.looks(asset) { say(1, $0) }
        let captions = captionLines(looks, words: words)

        say(2, 0)
        let found = try await ShotDetector.detect(asset, covering: captionArea(captions)) { say(2, $0 * 0.85) }.ranges
        let ranges = try await pictureCuts(asset, found) { say(2, 0.85 + $0 * 0.15) }

        say(3, 0)
        let middles = try await Self.middles(asset, at: ranges.map { ($0.lowerBound + $0.upperBound) / 2 }) { say(3, $0 * 0.8) }
        _ = try await TutorialStudy.prepare(video: video, folder: folder, cacheDirectory: cacheDirectory, words: heard)

        let shots = zip(ranges, middles).map { r, m in VideoStudy.Shot(start: r.lowerBound, end: r.upperBound, framing: m.face.map { framing($0.h) }, text: m.text) }
        let sound = listened.flatMap { Self.sound($0, words: words, cuts: ranges.dropFirst().map(\.lowerBound), seconds: seconds) }
        let study = VideoStudy(title: title ?? video.deletingPathExtension().lastPathComponent, by: by, link: link, seconds: seconds, width: asset.video.first?.width, height: asset.video.first?.height,
                               pace: pace(ranges, seconds: seconds), words: Self.words(words, seconds: seconds), sound: sound, picture: picture(middles),
                               onScreen: asset.video.isEmpty ? nil : onScreen(looks, captions: captions), musicCredits: credits.flatMap { $0.isEmpty ? nil : $0 }, shots: shots)
        try JSONEncoder.direction.encode(study).write(to: folder.appendingPathComponent(VideoStudy.fileName), options: .atomic)
        try Data(study.markdown.utf8).write(to: folder.appendingPathComponent("study.md"), options: .atomic)
        say(3, 1)
        return study
    }

    /// The step in words and how far through the whole study, each step weighted by about how long it takes.
    struct Steps: Sendable {
        let report: (@Sendable (String, Double) -> Void)?
        let weights: [Double]
        func callAsFunction(_ step: Int, _ done: Double) {
            let total = weights.reduce(0, +), before = weights[..<step].reduce(0, +)
            report?(steps[step], min(1, (before + weights[step] * min(1, max(0, done))) / total))
        }
    }

    // MARK: Cuts

    /// The shots with the cuts where only words on screen changed left out. A caption changing over the same
    /// picture can move Vision's feature print past the detector's threshold, so each cut is looked at again a
    /// tenth of a second either side, with the text on both frames covered, and kept when the pictures still differ.
    static func pictureCuts(_ asset: MediaAsset, _ ranges: [ClosedRange<Double>], progress: @Sendable (Double) -> Void) async throws -> [ClosedRange<Double>] {
        guard let first = ranges.first, let last = ranges.last, ranges.count > 1 else { return ranges }
        let cuts = ranges.dropFirst().map(\.lowerBound)
        var kept: [Double] = []
        for start in stride(from: 0, to: cuts.count, by: 12) {
            try Task.checkCancellation()
            let chunk = Array(cuts[start..<min(cuts.count, start + 12)])
            let images = ((try? await SourceFrames.images(asset, at: chunk.flatMap { [$0 - 0.1, $0 + 0.1] }, maxDimension: frameSize)) ?? []).map(VisionImage.init)
            if images.count == chunk.count * 2 {
                let differ = try await each((0..<chunk.count).map { (images[2 * $0], images[2 * $0 + 1]) }) { pair in try await VisionWork.run { differs(pair.0.image, pair.1.image) } }
                kept += zip(chunk, differ).filter(\.1).map(\.0)
            } else { kept += chunk }
            progress(Double(start + chunk.count) / Double(cuts.count))
        }
        let edges = [first.lowerBound] + kept + [last.upperBound]
        return zip(edges, edges.dropFirst()).map { $0...$1 }
    }

    /// Whether two frames either side of a cut are different pictures once their words are covered. A fade to or
    /// from black always is.
    static func differs(_ a: CGImage, _ b: CGImage) -> Bool {
        if (SourceFrames.luminance(a) >= ShotDetector.black) != (SourceFrames.luminance(b) >= ShotDetector.black) { return true }
        let words = ((try? text(a)) ?? []) + ((try? text(b)) ?? [])
        guard !words.isEmpty else { return true }
        func covered(_ image: CGImage) -> CGImage? {
            let s = SourceFrames.scaled(image, maxDimension: ShotDetector.sampleSize), w = Double(s.width), h = Double(s.height)
            guard let c = CGContext(data: nil, width: s.width, height: s.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            c.draw(s, in: CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(CGColor(gray: 0.5, alpha: 1))
            // Vision's boxes and Core Graphics both count y up from the bottom; a little wider for the letters' edges.
            for r in words.map(\.rect) { let pad = r.height * h / 2; c.fill(CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h).insetBy(dx: -pad, dy: -pad)) }
            return c.makeImage()
        }
        guard let x = covered(a), let y = covered(b), let p = try? ShotDetector.featurePrint(x), let q = try? ShotDetector.featurePrint(y) else { return true }
        return ShotDetector.distance(p, q) > ShotDetector.threshold
    }

    // MARK: Pace and words

    public static func pace(_ shots: [ClosedRange<Double>], seconds: Double) -> VideoStudy.Pace {
        let lengths = shots.map { $0.upperBound - $0.lowerBound }, cuts = shots.dropFirst().map(\.lowerBound)
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return VideoStudy.Pace(shots: shots.count, cutsPerMinute: seconds > 0 ? Double(cuts.count) / seconds * 60 : 0, averageShot: lengths.isEmpty ? 0 : lengths.reduce(0, +) / Double(lengths.count),
                               medianShot: median(lengths) ?? 0, longestShot: lengths.max() ?? 0, firstCut: cuts.first,
                               cutsByMinute: (0..<minutes).map { m in cuts.filter { min(minutes - 1, Int($0 / 60)) == m }.count })
    }

    /// Words a minute of running time, and the gaps between one word's end and the next one's start.
    public static func words(_ words: [TranscriptWord], seconds: Double) -> VideoStudy.Words? {
        guard !words.isEmpty, seconds > 0 else { return nil }
        let w = words.sorted { $0.range.start < $1.range.start }
        let gaps = zip(w, w.dropFirst()).map { max(0, $1.range.start.seconds - $0.range.end.seconds) }, pauses = gaps.filter { $0 > 0.25 }
        return VideoStudy.Words(count: w.count, perMinute: Double(w.count) / seconds * 60, medianPause: median(gaps) ?? 0, longestPause: gaps.max() ?? 0,
                                pausesOverHalfSecond: pauses.isEmpty ? 0 : Double(pauses.filter { $0 > 0.5 }.count) / Double(pauses.count))
    }

    static func median(_ values: [Double]) -> Double? {
        let s = values.sorted()
        guard !s.isEmpty else { return nil }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    // MARK: Sound

    /// One second as the classifier heard it: how sure it is of music and of speech, and the instruments and
    /// other sounds it's fairly sure of, by the names a director uses.
    struct Heard: Sendable {
        var music: Double
        var speech: Double
        var instruments: [String: Double] = [:]
        var others: [String: Double] = [:]
    }

    /// What was heard, before the cuts are known: loudness, each second, and the music's features.
    struct Listened: Sendable {
        var meter: LoudnessMeter?
        var heard: [Heard]
        var features: MusicListening.Features?
    }

    /// The first audio track, from the same 48 kHz copy the transcript is made from.
    static func listen(_ asset: MediaAsset, cacheDirectory: URL) async -> Listened? {
        guard let track = asset.audio.first?.id, let file = try? await AudioProcessor.extract(asset: asset, trackID: track, directory: cacheDirectory) else { return nil }
        let meter = try? loudness(file)
        let heard = (try? await hear(file)) ?? []
        let features = try? await Task.detached(priority: .userInitiated) { try MusicListening.features(file) }.value
        return Listened(meter: meter, heard: heard, features: features)
    }

    /// Loudness and true peak, how much of it has music and music under speech, and what the music does: its
    /// cues, the stretches of talk it leaves alone, how far under the voice it sits, the other sounds heard, and
    /// the hits and risers on the cuts that have no word starting on them.
    static func sound(_ l: Listened, words: [TranscriptWord], cuts: [Double], seconds: Double) -> VideoStudy.Sound? {
        let heard = l.heard
        func share(_ test: (Heard) -> Bool) -> Double? { heard.isEmpty ? nil : Double(heard.filter(test).count) / Double(heard.count) }
        var sound = VideoStudy.Sound(loudness: l.meter?.integrated, truePeak: l.meter.flatMap { $0.peak > 0 ? $0.truePeakDBTP : nil },
                                     music: share { $0.music >= musicHeard }, musicUnderSpeech: share { $0.music >= musicHeard && $0.speech >= speechHeard })
        if !heard.isEmpty { score(&sound, heard: heard, features: l.features, words: words, cuts: cuts, seconds: seconds) }
        return sound == VideoStudy.Sound() ? nil : sound
    }

    // MARK: Music

    /// Music under two seconds apart is one stretch; a stretch under six seconds is a sting (a riser, a
    /// transition, a hit); talk of four seconds or more between cues is a break.
    static let musicGap = 2.0, cueLength = 6.0, breakLength = 4.0
    /// An instrument is in a cue when it's heard in a quarter of its seconds.
    static let inCue = 0.25

    static func score(_ sound: inout VideoStudy.Sound, heard: [Heard], features f: MusicListening.Features?, words: [TranscriptWord], cuts: [Double], seconds: Double) {
        let spoken = words.map { $0.range.start.seconds...max($0.range.start.seconds, $0.range.end.seconds) }
        let quiet = spoken.map { max(0, $0.lowerBound - 0.05)...($0.upperBound + 0.05) }
        let isMusic = heard.map { $0.music >= musicHeard }, isSpeech = heard.map { $0.speech >= speechHeard }

        // Stretches of music, in whole seconds.
        var runs: [(Double, Double)] = []
        for (i, on) in isMusic.enumerated() where on {
            if let last = runs.last, Double(i) - last.1 <= musicGap { runs[runs.count - 1].1 = Double(i + 1) } else { runs.append((Double(i), Double(i + 1))) }
        }
        let long = runs.filter { $0.1 - $0.0 >= cueLength }
        sound.stings = runs.filter { $0.1 - $0.0 < cueLength }.map(\.0)
        func onCut(_ t: Double, within: Double) -> Bool { cuts.contains { abs($0 - t) <= within } }
        func speechShare(_ a: Double, _ b: Double) -> Double {
            let r = max(0, Int(a))..<min(heard.count, Int(b))
            return r.isEmpty ? 0 : Double(r.filter { isSpeech[$0] }.count) / Double(r.count)
        }

        let noteQuiet = f.map { MusicListening.noteMask(quiet, $0) } ?? [], onsetQuiet = f.map { MusicListening.onsetMask(quiet, $0) } ?? []
        var cues: [VideoStudy.Cue] = []
        for (a, b) in long {
            let bounds = [a] + (f.map { MusicListening.changes($0, from: a, to: b, quiet: noteQuiet) } ?? []) + [b]
            for (s, e) in zip(bounds, bounds.dropFirst()) {
                let secondsIn = heard[max(0, Int(s))..<min(heard.count, Int(e))]
                var counts: [String: Int] = [:]
                for h in secondsIn { for name in h.instruments.keys { counts[name, default: 0] += 1 } }
                let instruments = counts.filter { Double($0.value) >= inCue * Double(secondsIn.count) }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(4).map(\.key)
                var tempo: Double?, key: String?
                if let f {
                    let oa = max(0, Int(s * MusicListening.onsetRate)), ob = min(f.onsets.count, Int(e * MusicListening.onsetRate))
                    if oa < ob { tempo = MusicListening.tempo(f.onsets[oa..<ob], quiet: Array(onsetQuiet[oa..<ob])) }
                    key = MusicListening.key(MusicListening.notes(f, from: s, to: e, quiet: noteQuiet))
                }
                cues.append(VideoStudy.Cue(start: s, end: e, instruments: instruments, tempo: tempo.map { ($0 * 2).rounded() / 2 }, key: key, underSpeech: speechShare(s, e),
                                           startsOnCut: s < 1 ? nil : onCut(s, within: 1), endsOnCut: e > seconds - 1 ? nil : onCut(e, within: 1)))
            }
        }
        sound.cues = cues

        // Talk the music leaves alone: before the first cue, between cues and after the last.
        if !cues.isEmpty {
            let edges = [0.0] + cues.flatMap { [$0.start, $0.end] } + [seconds]
            sound.breaks = stride(from: 0, to: edges.count - 1, by: 2).map { (edges[$0], edges[$0 + 1]) }
                .filter { $0.1 - $0.0 >= breakLength && speechShare($0.0, $0.1) >= 0.5 }.map { VideoStudy.Stretch(start: $0.0, end: $0.1) }
        }

        // The music against the voice: in the pauses between words, and with nobody talking.
        if let f, spoken.count >= 20, let voice = MusicListening.level(f, in: spoken) {
            let sorted = spoken.sorted { $0.lowerBound < $1.lowerBound }
            let pauses = zip(sorted, sorted.dropFirst()).compactMap { w, next -> ClosedRange<Double>? in
                let a = w.upperBound + 0.1, b = next.lowerBound - 0.1, mid = (a + b) / 2
                return b - a >= 0.15 && Int(mid) < isMusic.count && isMusic[Int(mid)] ? a...b : nil
            }
            let alone = isMusic.indices.filter { i in isMusic[i] && !spoken.contains { $0.overlaps(Double(i) - 0.25...Double(i) + 1.25) } }.map { Double($0)...Double($0 + 1) }
            sound.musicUnderVoiceDB = MusicListening.level(f, in: pauses).map { (($0 - voice) * 2).rounded() / 2 }
            sound.musicAloneDB = MusicListening.level(f, in: alone).map { (($0 - voice) * 2).rounded() / 2 }
        }

        // Other sounds, each where it starts: the same sound again within three seconds is the same one going on.
        var effects: [VideoStudy.Effect] = [], last: [String: Int] = [:]
        for (i, h) in heard.enumerated() {
            for name in h.others.keys.sorted() {
                defer { last[name] = i }
                guard last[name].map({ i - $0 > 3 }) ?? true else { continue }
                effects.append(VideoStudy.Effect(at: Double(i), sound: name, onCut: cuts.isEmpty ? nil : onCut(Double(i) + 0.5, within: 0.75)))
            }
        }
        sound.effects = effects

        // Hits and risers, on the cuts no word starts on (with no words, the cuts in seconds with no talk).
        if let f {
            let starts = words.map(\.range.start.seconds)
            let clear = cuts.filter { c in words.isEmpty ? !(Int(c) < isSpeech.count && isSpeech[Int(c)]) : !starts.contains { abs($0 - c) <= 0.15 } }
            sound.cutsHeard = clear.count
            sound.hitsOnCuts = clear.filter { MusicListening.hit(f, at: $0) }.count
            sound.risersIntoCuts = clear.filter { c in !spoken.contains { $0.overlaps((c - 2)...c) } && MusicListening.riser(f, into: c) }.count
        }
    }

    /// Apple's sound classifier's names for instruments and voices in music, as a director says them.
    static let instrumentNames: [String: String] = [
        "plucked_string_instrument": "plucked strings", "guitar": "guitar", "electric_guitar": "electric guitar", "bass_guitar": "bass guitar", "acoustic_guitar": "acoustic guitar",
        "steel_guitar_slide_guitar": "slide guitar", "guitar_strum": "strummed guitar", "banjo": "banjo", "sitar": "sitar", "mandolin": "mandolin", "ukulele": "ukulele",
        "keyboard_musical": "keys", "piano": "piano", "electric_piano": "electric piano", "organ": "organ", "electronic_organ": "electronic organ", "hammond_organ": "Hammond organ",
        "synthesizer": "synth", "harpsichord": "harpsichord", "percussion": "percussion", "drum_kit": "drum kit", "drum": "drums", "snare_drum": "snare", "bass_drum": "kick drum",
        "timpani": "timpani", "tabla": "tabla", "cymbal": "cymbal", "hi_hat": "hi-hat", "tambourine": "tambourine", "marimba_xylophone": "marimba", "glockenspiel": "glockenspiel",
        "vibraphone": "vibraphone", "mallet_percussion": "mallets", "steelpan": "steel pan", "orchestra": "orchestra", "brass_instrument": "brass", "french_horn": "French horn",
        "trumpet": "trumpet", "trombone": "trombone", "bowed_string_instrument": "bowed strings", "violin_fiddle": "violin", "cello": "cello", "double_bass": "double bass",
        "wind_instrument": "woodwinds", "flute": "flute", "saxophone": "saxophone", "clarinet": "clarinet", "oboe": "oboe", "bassoon": "bassoon", "harp": "harp",
        "harmonica": "harmonica", "accordion": "accordion", "theremin": "theremin", "singing_bowl": "singing bowl", "singing": "vocals", "choir_singing": "choir",
        "humming": "humming", "whistling": "whistling", "rapping": "rap vocals", "disc_scratching": "scratching",
    ]
    /// Its names for sounds an editor adds, or the footage has: effects, a clock, a camera.
    static let effectNames: [String: String] = [
        "whoosh_swoosh_swish": "whoosh", "boom": "boom", "thump_thud": "thud", "click": "click", "beep": "beep", "tick": "ticking clock", "tick_tock": "ticking clock", "clock": "clock",
        "bell": "bell", "chime": "chime", "wind_chime": "wind chime", "gong": "gong", "glass_clink": "clink", "glass_breaking": "glass breaking", "camera": "camera shutter",
        "typing": "typing", "typing_computer_keyboard": "typing", "typewriter": "typing", "slap_smack": "slap", "knock": "knock", "door_slam": "door slam",
        "coin_dropping": "coins", "crumpling_crinkling": "paper", "tearing": "tearing", "zipper": "zipper", "alarm_clock": "alarm", "ringtone": "ringtone",
        "telephone_bell_ringing": "phone ringing", "door_bell": "doorbell", "squeak": "squeak", "fireworks": "fireworks", "firecracker": "firecracker",
    ]
    /// How sure the classifier must be before an instrument, or another sound, counts in a second.
    static let instrumentHeard = 0.3, otherHeard = 0.35

    static func loudness(_ url: URL) throws -> LoudnessMeter {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
        let format = file.processingFormat, channels = Int(format.channelCount), step = AVAudioFrameCount(format.sampleRate)
        var meter = LoudnessMeter(sampleRate: format.sampleRate, channels: channels)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: step) else { return meter }
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: step)
            guard buffer.frameLength > 0, let data = buffer.audioBufferList.pointee.mBuffers.mData else { break }
            meter.add(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: Int(buffer.frameLength) * channels))
        }
        return meter
    }

    /// Each second's surest music and surest speech, by Apple's built-in sound classifier and `SoundIndexer`'s kinds.
    static func hear(_ url: URL) async throws -> [Heard] {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1, preferredTimescale: 48_000)
        request.overlapFactor = 0
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let observer = Hearing()
        try analyzer.add(request, withObserver: observer)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<[Heard], Error>) in
                observer.finish = { result in done.resume(with: result) }
                analyzer.analyze { _ in }
            }
        } onCancel: { analyzer.cancelAnalysis() }
    }

    private final class Hearing: NSObject, SNResultsObserving, @unchecked Sendable {
        var seconds: [Heard] = []
        var finish: ((Result<[Heard], Error>) -> Void)?
        private var finished = false
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            var h = Heard(music: 0, speech: 0)
            for c in r.classifications {
                switch SoundIndexer.kind(for: c.identifier) {
                case .music: h.music = max(h.music, c.confidence)
                case .speech: h.speech = max(h.speech, c.confidence)
                default: break
                }
                if c.confidence >= VideoStudying.instrumentHeard, let name = VideoStudying.instrumentNames[c.identifier] { h.instruments[name] = max(h.instruments[name] ?? 0, c.confidence) }
                if c.confidence >= VideoStudying.otherHeard, let name = VideoStudying.effectNames[c.identifier] { h.others[name] = max(h.others[name] ?? 0, c.confidence) }
            }
            seconds.append(h)
        }
        func request(_ request: SNRequest, didFailWithError error: Error) { done(.failure(error)) }
        func requestDidComplete(_ request: SNRequest) { done(.success(seconds)) }
        private func done(_ result: Result<[Heard], Error>) { guard !finished else { return }; finished = true; finish?(result) }
    }

    // MARK: Picture

    struct Face: Sendable { var x: Double; var y: Double; var h: Double }
    struct Tone: Sendable { var brightness: Double; var contrast: Double; var saturation: Double; var warmth: Double }
    /// What the middle frame of a shot shows: its largest face (middle y down, and height, as fractions of the
    /// frame), its tone, and its words.
    struct Middle: Sendable { var face: Face?; var tone: Tone?; var text: String? }

    static func framing(_ height: Double) -> String { height >= close ? "close" : height >= medium ? "medium" : "wide" }

    /// The middle frames, a dozen decoded at a time and four read at once. A batch that won't decode counts as
    /// frames with nothing in them.
    static func middles(_ asset: MediaAsset, at times: [Double], progress: @Sendable (Double) -> Void) async throws -> [Middle] {
        guard !asset.video.isEmpty, !asset.isImage else { return times.map { _ in Middle() } }
        var out: [Middle] = []
        for chunk in stride(from: 0, to: times.count, by: 12).map({ Array(times[$0..<min(times.count, $0 + 12)]) }) {
            try Task.checkCancellation()
            let images = ((try? await SourceFrames.images(asset, at: chunk, maxDimension: frameSize, tolerance: 0.1)) ?? []).map(VisionImage.init)
            let read = try await each(images) { frame in
                try await VisionWork.run {
                    let face = LayoutAnalysis.largestFace(in: SourceFrames.scaled(frame.image, maxDimension: faceSize)).map { Face(x: $0.x, y: $0.y, h: $0.h) }
                    let reads = (try? text(frame.image)) ?? []
                    return Middle(face: face, tone: tone(frame.image), text: brief(ScreenReader.ordered(reads, frameHeight: Double(frame.image.height))))
                }
            }
            out += read.count == chunk.count ? read : chunk.map { _ in Middle() }
            progress(Double(out.count) / Double(max(1, times.count)))
        }
        return out
    }

    /// Shares of the shots by the largest face's size, the cuts that punch in on one face, and the frames' tone.
    static func picture(_ middles: [Middle]) -> VideoStudy.Picture {
        let n = Double(max(1, middles.count)), faces = middles.map(\.face)
        func share(_ name: String?) -> Double { Double(faces.filter { $0.map { framing($0.h) } == name }.count) / n }
        var same = 0, punched = 0
        for (a, b) in zip(faces, faces.dropFirst()) {
            guard let a, let b, hypot(a.x - b.x, a.y - b.y) < sameFace else { continue }
            same += 1
            if abs(b.h - a.h) / a.h >= punch { punched += 1 }
        }
        let tones = middles.compactMap(\.tone), t = Double(max(1, tones.count))
        func mean(_ v: (Tone) -> Double) -> Double { tones.map(v).reduce(0, +) / t }
        return VideoStudy.Picture(close: share("close"), medium: share("medium"), wide: share("wide"), noFace: share(nil), punchIns: same == 0 ? 0 : Double(punched) / Double(same),
                                  brightness: mean(\.brightness), contrast: mean(\.contrast), saturation: mean(\.saturation), warmth: mean(\.warmth))
    }

    /// Mean luma (Rec. 709), its spread, mean HSV saturation and red minus blue, from a 64 × 36 copy.
    static func tone(_ image: CGImage) -> Tone {
        let w = 64, h = 36
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            c.interpolationQuality = .medium
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var sum = 0.0, squares = 0.0, saturation = 0.0, warmth = 0.0
        for i in 0..<(w * h) {
            let r = Double(px[i * 4]) / 255, g = Double(px[i * 4 + 1]) / 255, b = Double(px[i * 4 + 2]) / 255
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b, top = max(r, g, b)
            sum += y; squares += y * y; saturation += top > 0 ? (top - min(r, g, b)) / top : 0; warmth += r - b
        }
        let n = Double(w * h), mean = sum / n
        return Tone(brightness: mean, contrast: max(0, squares / n - mean * mean).squareRoot(), saturation: saturation / n, warmth: warmth / n)
    }

    // MARK: Words on screen

    /// One look at the screen: its lines and where each sits, in Vision's terms (origin bottom left).
    struct Look: Sendable { var time: Double; var lines: [ScreenReader.Read] }

    /// A look every second, in the middle of each, a dozen decoded at a time and four read at once.
    static func looks(_ asset: MediaAsset, progress: @Sendable (Double) -> Void) async throws -> [Look] {
        guard !asset.video.isEmpty, !asset.isImage else { return [] }
        let seconds = asset.duration.seconds
        let times = seconds >= 1 ? Array(stride(from: 0.5, to: seconds, by: 1)) : [seconds / 2]
        var out: [Look] = []
        for chunk in stride(from: 0, to: times.count, by: 12).map({ Array(times[$0..<min(times.count, $0 + 12)]) }) {
            try Task.checkCancellation()
            let images = ((try? await SourceFrames.images(asset, at: chunk, maxDimension: frameSize, tolerance: 0.25)) ?? []).map(VisionImage.init)
            let read = try await each(images) { frame in try await VisionWork.run { (try? text(frame.image)) ?? [] } }
            out += zip(chunk, read.count == chunk.count ? read : chunk.map { _ in [] }).map { Look(time: $0, lines: $1) }
            progress(Double(out.count) / Double(max(1, times.count)))
        }
        return out
    }

    /// A frame's lines, read quickly: captions and titles are large, and a look a second adds up.
    static func text(_ image: CGImage) throws -> [ScreenReader.Read] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { o in
            guard let c = o.topCandidates(1).first, c.confidence >= 0.5, let text = ScreenReader.clean(c.string) else { return nil }
            return ScreenReader.Read(text: text, rect: o.boundingBox)
        }
    }

    /// A shot's words in one short line: lines that read as words, not an app's small print read wrong
    /// ("AK3Jp.Swq", a timecode), which says nothing about the style and costs the editor its attention.
    static func brief(_ lines: [String]) -> String? {
        let text = lines.filter(readsAsWords).joined(separator: " \u{00B7} ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.count > 80 else { return text }
        let cut = text.prefix(79)
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// Most of its words are words: letters only (an apostrophe or end punctuation allowed), with a vowel,
    /// and cased as a word is (all lower, all upper, or capitalized).
    static func readsAsWords(_ line: String) -> Bool {
        let parts = line.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;\"\u{201C}\u{201D}()")) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }
        func word(_ w: String) -> Bool {
            let letters = w.filter { $0 != "'" && $0 != "\u{2019}" && $0 != "-" }
            guard letters.count >= 2, letters.allSatisfy(\.isLetter), letters.lowercased().contains(where: { "aeiouy".contains($0) }) else { return ["a", "A", "I"].contains(w) }
            let rest = letters.dropFirst()
            return letters == letters.lowercased() || letters == letters.uppercased() || (letters.first!.isUppercase && rest == rest.lowercased())
        }
        // And one of them is a real length: "ow Y" is a scrap, not a line.
        return Double(parts.filter(word).count) >= Double(parts.count) * 0.6 && parts.contains { $0.count >= 3 && word($0) }
    }

    /// Words compared without case or punctuation.
    static func tokens(_ text: String) -> [String] { text.split(whereSeparator: \.isWhitespace).map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty } }

    /// Pure: which lines of each look are captions. With words, a caption line is one at least half of whose words
    /// are said within 1.5 s, and a look has captions when those lines share two words with what's said, or are all
    /// said and one or two words long (a word at a time). Without words, captions are short text (six words at
    /// most) in the lower 60% that changes within three looks, next to more of the same.
    static func captionLines(_ looks: [Look], words: [TranscriptWord]) -> [[ScreenReader.Read]] {
        var captions: [[ScreenReader.Read]] = looks.map { _ in [] }
        if !words.isEmpty {
            let spoken = words.map { (start: $0.range.start.seconds, end: $0.range.end.seconds, tokens: tokens($0.text)) }
            for (i, look) in looks.enumerated() {
                let said = Set(spoken.filter { $0.end >= look.time - captionWindow && $0.start <= look.time + captionWindow }.flatMap(\.tokens))
                let lines = look.lines.filter { line in let k = tokens(line.text), m = k.filter(said.contains).count; return m >= 1 && m * 2 >= k.count }
                let shown = lines.flatMap { tokens($0.text) }, shared = Set(shown).intersection(said)
                if shared.count >= 2 || (!shown.isEmpty && shown.count <= 2 && shown.allSatisfy(said.contains)) { captions[i] = lines }
            }
        } else {
            let lower = looks.map { $0.lines.filter { $0.rect.midY <= 0.6 } }
            let keys = lower.map { lines -> String? in let k = lines.flatMap { tokens($0.text) }; return (1...6).contains(k.count) ? k.joined(separator: " ") : nil }
            var runs: [ClosedRange<Int>] = [], i = 0
            while i < keys.count {
                guard let key = keys[i] else { i += 1; continue }
                var j = i
                while j + 1 < keys.count, keys[j + 1] == key { j += 1 }
                runs.append(i...j); i = j + 1
            }
            for (n, run) in runs.enumerated() where run.count <= 3 {
                let before = n > 0 && runs[n - 1].upperBound == run.lowerBound - 1 && runs[n - 1].count <= 3
                let after = n + 1 < runs.count && runs[n + 1].lowerBound == run.upperBound + 1 && runs[n + 1].count <= 3
                if before || after { for k in run { captions[k] = lower[k] } }
            }
        }
        return captions
    }

    /// Where captions sit, to cover while finding cuts: the middle 80% of their lines' edges, half a line wider all
    /// round, when they keep to one place (under a third of the frame).
    static func captionArea(_ captions: [[ScreenReader.Read]]) -> CGRect? {
        let rects = captions.flatMap { $0.map(\.rect) }
        guard rects.count >= 2 else { return nil }
        func at(_ values: [CGFloat], _ q: Double) -> CGFloat { let s = values.sorted(); return s[Int((Double(s.count - 1) * q).rounded())] }
        let pad = CGFloat(median(rects.map { Double($0.height) }) ?? 0) / 2
        let x = at(rects.map(\.minX), 0.1) - pad, y = at(rects.map(\.minY), 0.1) - pad
        let area = CGRect(x: x, y: y, width: at(rects.map(\.maxX), 0.9) + pad - x, height: at(rects.map(\.maxY), 0.9) + pad - y).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return area.isNull || area.width * area.height > 1.0 / 3 ? nil : area
    }

    /// Pure: how often there are captions and other text, and how captions are set.
    static func onScreen(_ looks: [Look], captions: [[ScreenReader.Read]]) -> VideoStudy.OnScreenText {
        guard !looks.isEmpty, captions.count == looks.count else { return VideoStudy.OnScreenText(captions: 0, otherText: 0) }
        let n = Double(looks.count), shown = captions.filter { !$0.isEmpty }
        let other = zip(looks, captions).filter { look, caption in look.lines.contains { line in !caption.contains { $0.text == line.text && $0.rect == line.rect } } }.count
        guard !shown.isEmpty else { return VideoStudy.OnScreenText(captions: 0, otherText: Double(other) / n) }
        let lettered = shown.flatMap { $0.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map { $0.filter(\.isLetter) } } }.filter { $0.count >= 2 }
        // Vision's y runs up from the bottom; the study's runs down from the top.
        let heights = shown.map { lines in 1 - Double(lines.map(\.rect).reduce(lines[0].rect) { $0.union($1) }.midY) }
        return VideoStudy.OnScreenText(captions: Double(shown.count) / n, otherText: Double(other) / n,
                                       wordsPerCaption: Double(shown.map { $0.flatMap { tokens($0.text) }.count }.reduce(0, +)) / Double(shown.count),
                                       captionHeight: heights.reduce(0, +) / Double(shown.count),
                                       upperCase: lettered.isEmpty ? nil : Double(lettered.filter { $0 == $0.uppercased() }.count) / Double(lettered.count))
    }

    // MARK: Helpers

    /// Each item through `body`, four at once, in order.
    static func each<T: Sendable, R: Sendable>(_ items: [T], _ body: @escaping @Sendable (T) async throws -> R) async throws -> [R] {
        var out = [R?](repeating: nil, count: items.count)
        try await withThrowingTaskGroup(of: (Int, R).self) { group in
            var next = 0
            func add() { guard next < items.count else { return }; let i = next, item = items[i]; next += 1; group.addTask { (i, try await body(item)) } }
            for _ in 0..<4 { add() }
            while let (i, r) = try await group.next() { out[i] = r; add() }
        }
        return out.compactMap { $0 }
    }
}

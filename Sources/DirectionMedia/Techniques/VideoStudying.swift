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
    /// and study.md. Given `words`, they're used instead of listening. Progress is the step in words and how
    /// far through the whole study, 0–1. Sound that can't be measured is left out rather than failing the study.
    public static func study(video: URL, folder: URL, cacheDirectory: URL, title: String?, by: String?, link: String?, words given: [TranscriptWord]? = nil,
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
        let sound = await Self.sound(asset, cacheDirectory: cacheDirectory)
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
        let study = VideoStudy(title: title ?? video.deletingPathExtension().lastPathComponent, by: by, link: link, seconds: seconds, width: asset.video.first?.width, height: asset.video.first?.height,
                               pace: pace(ranges, seconds: seconds), words: Self.words(words, seconds: seconds), sound: sound, picture: picture(middles),
                               onScreen: asset.video.isEmpty ? nil : onScreen(looks, captions: captions), shots: shots)
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

    struct Heard: Sendable { var music: Double; var speech: Double }

    /// Loudness and true peak of the first audio track, and the share of its seconds with music and with music
    /// under speech. Read from the same 48 kHz copy the transcript is made from.
    static func sound(_ asset: MediaAsset, cacheDirectory: URL) async -> VideoStudy.Sound? {
        guard let track = asset.audio.first?.id, let file = try? await AudioProcessor.extract(asset: asset, trackID: track, directory: cacheDirectory) else { return nil }
        let meter = try? loudness(file)
        let heard = (try? await hear(file)) ?? []
        func share(_ test: (Heard) -> Bool) -> Double? { heard.isEmpty ? nil : Double(heard.filter(test).count) / Double(heard.count) }
        let sound = VideoStudy.Sound(loudness: meter?.integrated, truePeak: meter.flatMap { $0.peak > 0 ? $0.truePeakDBTP : nil },
                                     music: share { $0.music >= musicHeard }, musicUnderSpeech: share { $0.music >= musicHeard && $0.speech >= speechHeard })
        return sound == VideoStudy.Sound() ? nil : sound
    }

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

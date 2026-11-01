import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import DirectionCore
@testable import DirectionMedia

/// Learning a style from a video (styles.md › From a video): what Direction measures in someone else's video,
/// checked on a made-up one with known cuts, words, captions and sound.
@Suite(.serialized) struct VideoStudyingTests {
    /// Two words a second, drawn as the caption of that second; nothing said or shown in the seventh.
    static let said: [[String]] = [["make", "videos"], ["every", "single"], ["day", "with"], ["simple", "tools"], ["that", "help"], ["people", "learn"], [],
                                   ["faster", "than"], ["they", "ever"], ["thought", "possible"], ["right", "now"], ["today", "friends"]]
    /// Shots of flat color: 2.5, 4, 3 and 2.5 s, over and over.
    static let lengths = [2.5, 4, 3, 2.5]
    static let colors = [CGColor(red: 0.72, green: 0.18, blue: 0.12, alpha: 1), CGColor(red: 0.10, green: 0.24, blue: 0.78, alpha: 1), CGColor(red: 0.12, green: 0.55, blue: 0.25, alpha: 1), CGColor(red: 0.85, green: 0.65, blue: 0.20, alpha: 1)]

    /// Each second's two words: the first at 0.1–0.45, the second at 0.55–0.9, except in the fourth second, where
    /// the second word waits until 0.75 (a pause of 0.3 s).
    static func words(seconds: Int) -> [TranscriptWord] {
        (0..<seconds).flatMap { k -> [TranscriptWord] in
            let pair = said[k % said.count], t = Double(k)
            guard pair.count == 2 else { return [] }
            return [TranscriptWord(text: pair[0], range: MediaRange(start: t + 0.1, end: t + 0.45)), TranscriptWord(text: pair[1], range: MediaRange(start: t + (k == 3 ? 0.75 : 0.55), end: t + 0.9))]
        }
    }

    /// A 640 × 360 movie of `seconds`: the shots, each second's caption in capitals in the lower third, a title at
    /// the top of the first shot, and a 440 Hz tone. The video's asset is kept while its track is read.
    static func writeMovie(to url: URL, seconds: Int) async throws {
        let w = 640, h = 360, fps = 30
        let picture = url.deletingLastPathComponent().appendingPathComponent("picture-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: picture, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        func line(_ text: String, size: CGFloat) -> CTLine {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]))
        }
        let captions = (0..<said.count).map { said[$0].isEmpty ? nil : line(said[$0].joined(separator: " ").uppercased(), size: 30) }, title = line("CHAPTER ONE", size: 40)
        let starts = (0..<64).map { i in (0..<i).map { lengths[$0 % lengths.count] }.reduce(0, +) }
        for i in 0..<(seconds * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error! } }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "Cannot allocate a frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let c = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
            let t = Double(i) / Double(fps), shot = starts.lastIndex { $0 <= t + 1e-9 } ?? 0
            c.setFillColor(colors[shot % colors.count]); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // A large shape of its own in each shot: on a frame of flat color alone, a caption changing reads as a cut.
            c.setFillColor(CGColor(gray: 0, alpha: 0.35))
            switch shot % 4 {
            case 0: c.fillEllipse(in: CGRect(x: 60, y: 110, width: 220, height: 220))
            case 1: c.fill(CGRect(x: 360, y: 100, width: 240, height: 200))
            case 2: for k in 0..<4 { c.fill(CGRect(x: 0, y: 120 + k * 60, width: w, height: 28)) }
            default: c.move(to: CGPoint(x: 320, y: 340)); c.addLine(to: CGPoint(x: 520, y: 110)); c.addLine(to: CGPoint(x: 120, y: 110)); c.closePath(); c.fillPath()
            }
            // Core Graphics counts y up from the bottom: the caption's middle is 80% of the way down.
            if let caption = captions[Int(t) % said.count] {
                let width = CTLineGetTypographicBounds(caption, nil, nil, nil)
                c.textPosition = CGPoint(x: (Double(w) - width) / 2, y: 0.2 * Double(h) - 11); CTLineDraw(caption, c)
            }
            if shot == 0 { c.textPosition = CGPoint(x: 40, y: Double(h) - 70); CTLineDraw(title, c) }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: CMTimeScale(fps))) else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write a frame.") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot finish the movie.") }
        let tone = url.deletingLastPathComponent().appendingPathComponent("tone-\(UUID().uuidString).wav")
        try MediaFixture.writeTone(to: tone, frequency: 440, seconds: Double(seconds))
        let composition = AVMutableComposition(), video = AVURLAsset(url: picture), sound = AVURLAsset(url: tone)
        let length = CMTimeRange(start: .zero, duration: CMTime(seconds: Double(seconds), preferredTimescale: 600))
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: 1)!.insertTimeRange(length, of: try await video.loadTracks(withMediaType: .video)[0], at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: 2)!.insertTimeRange(length, of: try await sound.loadTracks(withMediaType: .audio)[0], at: .zero)
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await exporter.export(to: url, as: .mov)
        withExtendedLifetime((video, sound)) {}
    }

    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-study-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func aVideoIsMeasured() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appendingPathComponent("Someone\u{2019}s video.mov"), folder = root.appendingPathComponent("Study")
        try await Self.writeMovie(to: movie, seconds: 12)
        let steps = Steps()
        let study = try await VideoStudying.study(video: movie, folder: folder, cacheDirectory: root.appendingPathComponent("Cache"), title: nil, by: "Someone", link: "https://example.com/v",
                                                  words: Self.words(seconds: 12)) { step, done in steps.add(step, done) }

        #expect(study.title == "Someone\u{2019}s video" && study.by == "Someone" && study.width == 640 && study.height == 360 && abs(study.seconds - 12) < 0.05)
        // Four shots, cut where the color changes, to the frame.
        let p = study.pace
        #expect(p.shots == 4 && study.shots.count == 4)
        for (shot, length) in zip(study.shots, Self.lengths) { #expect(abs((shot.end - shot.start) - length) < 0.05) }
        #expect(abs(p.cutsPerMinute - 15) < 0.1 && abs((p.firstCut ?? 0) - 2.5) < 0.05 && p.cutsByMinute == [3])
        #expect(abs(p.averageShot - 3) < 0.05 && abs(p.medianShot - 2.75) < 0.05 && abs(p.longestShot - 4) < 0.05)

        // 22 words in 12 s; gaps of 0.1 and 0.2, one of 0.3 and one of 1.2 where nothing is said.
        let w = try #require(study.words)
        #expect(w.count == 22 && abs(w.perMinute - 110) < 0.01)
        #expect(abs(w.medianPause - 0.2) < 1e-6 && abs(w.longestPause - 1.2) < 1e-6 && abs(w.pausesOverHalfSecond - 0.5) < 1e-9)

        // The captions are found most of the time, two words at a time, in capitals, in the lower third; the title is other text.
        let t = try #require(study.onScreen)
        #expect(t.captions > 0.6 && t.captions <= 11.0 / 12 + 1e-9)
        #expect((1.5...2.5).contains(t.wordsPerCaption ?? 0) && (0.7...0.9).contains(t.captionHeight ?? 0) && (t.upperCase ?? 0) > 0.9)
        #expect(t.otherText > 0 && t.otherText < 0.5)
        #expect(study.shots[0].text?.contains("CHAPTER ONE") == true)

        // Flat color and no faces; the red and the gold outweigh the blue and the green, so it's a little warm.
        let pic = study.picture
        #expect(pic.noFace == 1 && pic.punchIns == 0)
        #expect(pic.brightness > 0.2 && pic.brightness < 0.8 && pic.saturation > 0.5 && pic.contrast < 0.2 && pic.warmth > 0)

        let sound = try #require(study.sound)
        #expect((sound.loudness ?? .nan).isFinite && (-22.0 ... -12.0).contains(sound.loudness ?? 0) && (sound.truePeak ?? .nan).isFinite)

        // Written beside the sheets and the transcript, and read back the same.
        #expect(VideoStudy.read(in: folder) == study)
        let markdown = try String(contentsOf: folder.appendingPathComponent("study.md"), encoding: .utf8)
        #expect(markdown == study.markdown && markdown.contains("## Pace"))
        let transcript = try String(contentsOf: folder.appendingPathComponent("transcript.txt"), encoding: .utf8)
        #expect(transcript.hasPrefix("[0:00.1] make videos every single"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("sheet-1.jpg").path))

        // Every step said in words, the whole only ever moving forward, to the end.
        let said = steps.all
        #expect(Set(said.map(\.0)) == Set(VideoStudying.steps) && zip(said, said.dropFirst()).allSatisfy { $0.1 <= $1.1 + 1e-9 } && said.last?.1 == 1)
    }

    @Test func withoutWordsCaptionsAreShortTextLowDownThatKeepsChanging() throws {
        func read(_ text: String, y: Double) -> ScreenReader.Read { ScreenReader.Read(text: text, rect: CGRect(x: 0.3, y: y, width: 0.4, height: 0.06)) }
        // Captions low down every second for five looks; a title at the top the whole time; a lower third held for six.
        var looks = (0..<5).map { VideoStudying.Look(time: Double($0) + 0.5, lines: [read("Caption \($0) here", y: 0.17), read("BIG TITLE AT THE TOP", y: 0.85)]) }
        looks += (5..<11).map { VideoStudying.Look(time: Double($0) + 0.5, lines: [read("Jane Smith Director", y: 0.17)]) }
        let captions = VideoStudying.captionLines(looks, words: [])
        let t = VideoStudying.onScreen(looks, captions: captions)
        #expect(abs(t.captions - 5.0 / 11) < 1e-9 && abs(t.otherText - 1) < 1e-9)
        #expect(t.wordsPerCaption == 3 && abs((t.captionHeight ?? 0) - 0.8) < 1e-9 && t.upperCase == 0)
        // Covered while finding cuts: where the captions sit, a little wider; nothing when they're all over the frame.
        let area = try #require(VideoStudying.captionArea(captions))
        #expect(abs(area.minX - 0.27) < 1e-6 && abs(area.maxX - 0.73) < 1e-6 && abs(area.minY - 0.14) < 1e-6 && abs(area.maxY - 0.26) < 1e-6)
        #expect(VideoStudying.captionArea([[read("One two", y: 0.05)], [ScreenReader.Read(text: "Three four", rect: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.5))]]) == nil)
    }

    @Test func aCutOnTheSameFaceThatChangesItsSizeIsAPunchIn() {
        func shot(_ x: Double, _ h: Double?) -> VideoStudying.Middle { VideoStudying.Middle(face: h.map { VideoStudying.Face(x: x, y: 0.4, h: $0) }, tone: nil, text: nil) }
        // Medium, then punched in close; held the same; then a wide on someone else across the frame; then a screen.
        let p = VideoStudying.picture([shot(0.5, 0.3), shot(0.52, 0.4), shot(0.52, 0.41), shot(0.1, 0.1), shot(0, nil)])
        #expect(abs(p.punchIns - 0.5) < 1e-9 && abs(p.close - 0.4) < 1e-9 && abs(p.medium - 0.2) < 1e-9 && abs(p.wide - 0.2) < 1e-9 && abs(p.noFace - 0.2) < 1e-9)
    }

    @Test func aShotKeepsOnlyTextThatReadsAsWords() {
        #expect(VideoStudying.brief(["23.20.07", "AK3Jp.Swq", "Here\u{2019}s the trick", "1WO \u{00B7} 1f*XO", "PIXEL GRID"]) == "Here\u{2019}s the trick \u{00B7} PIXEL GRID")
        #expect(VideoStudying.brief(["Or4nWcRot4tyEt", "ow Y"]) == nil)
    }

    /// A real video, studied without its words (nothing is transcribed): DIRECTION_STUDY_VIDEO=<path> prints study.md.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIRECTION_STUDY_VIDEO"] != nil)) func aRealVideo() async throws {
        let video = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DIRECTION_STUDY_VIDEO"]!)
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let started = Date()
        let study = try await VideoStudying.study(video: video, folder: root, cacheDirectory: root.appendingPathComponent("cache"), title: nil, by: nil, link: video.lastPathComponent, words: [])
        print("STUDY \(String(format: "%.1f", Date().timeIntervalSince(started))) s\n" + study.markdown.split(separator: "\n").prefix(28).joined(separator: "\n"))
        #expect(study.pace.shots > 0)
    }

    /// How long a minute of video takes to study: DIRECTION_STUDY_TIMING=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIRECTION_STUDY_TIMING"] != nil)) func aMinuteOfVideo() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appendingPathComponent("minute.mov")
        try await Self.writeMovie(to: movie, seconds: 60)
        let clock = ContinuousClock(), start = clock.now
        let study = try await VideoStudying.study(video: movie, folder: root.appendingPathComponent("Study"), cacheDirectory: root.appendingPathComponent("Cache"), title: nil, by: nil, link: nil, words: Self.words(seconds: 60)) { step, done in print("\(clock.now - start) \(step) \(String(format: "%.2f", done))") }
        print("A minute of video took \(clock.now - start): \(study.summary)")
        #expect(study.pace.shots == 20)
    }
}

/// What a study said as it went.
private final class Steps: @unchecked Sendable {
    private let lock = NSLock()
    private var said: [(String, Double)] = []
    func add(_ step: String, _ done: Double) { lock.withLock { said.append((step, done)) } }
    var all: [(String, Double)] { lock.withLock { said } }
}

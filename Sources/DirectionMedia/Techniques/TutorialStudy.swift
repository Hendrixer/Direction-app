import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import DirectionCore

/// Getting a tutorial video ready to learn a technique from (techniques.md › Learning one): fetched from a
/// link with yt-dlp once the director has said so, then read the way Direction reads footage: its words with
/// their times, and a frame every two seconds on contact sheets, so the editor can find the result and the
/// settings it's built from.
public enum TutorialStudy {
    /// yt-dlp, where uv, Homebrew or a person put it.
    public static func downloader() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/yt-dlp" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Downloads a link's video at 720p with its sound into `folder` as video.mp4, and what the page says about
    /// it (its title, maker, length and description) as info.json.
    public static func download(_ link: URL, to folder: URL) async throws -> URL {
        guard ["http", "https"].contains(link.scheme?.lowercased() ?? "") else { throw DirectionError("bad_link", "That isn't a link to a video.") }
        guard let tool = downloader() else { throw DirectionError("downloader_missing", "Direction fetches videos from links with yt-dlp. Install it with `uv tool install yt-dlp` in Terminal, or drop the video file in instead.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var arguments = ["-q", "--no-warnings", "--no-playlist", "-f", "bv*[height<=720][ext=mp4]+ba/b[height<=720]/bv*[height<=720]+ba", "--merge-output-format", "mp4",
                         "--write-info-json", "-o", folder.appendingPathComponent("video.%(ext)s").path]
        if let ffmpeg = WhisperTranscriber.ffmpeg() { arguments += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path] }
        let (status, output) = try await run(tool, arguments + [link.absoluteString])
        let video = folder.appendingPathComponent("video.mp4")
        guard status == 0, FileManager.default.fileExists(atPath: video.path) else { throw DirectionError("download_failed", "The video didn\u{2019}t download: \(output.split(separator: "\n").last.map(String.init) ?? "yt-dlp stopped").") }
        return video
    }

    /// Reads a video into `folder`: transcript.txt (its words, a line every few seconds with the time) and
    /// sheet-1.jpg, sheet-2.jpg… (a frame every two seconds, 24 to a sheet, each with its time). Returns the
    /// files' names.
    public static func prepare(video: URL, folder: URL, cacheDirectory: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [String] = []
        let asset = try await MediaInspector.inspect(url: video, thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails"))
        if let track = asset.audio.first?.id {
            let words: [TranscriptWord]
            if WhisperTranscriber.executable() != nil, let t = try? await WhisperTranscriber.transcribe(asset: asset, trackID: track, language: "en", model: SharedSettings.whisperModel, directory: cacheDirectory) { words = t.words }
            else { words = (try? await LocalTranscriber.transcribe(asset: asset, trackID: track, language: "en-US", directory: cacheDirectory))?.words ?? [] }
            try lines(words).write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
            written.append("transcript.txt")
        }
        let times = Array(stride(from: 0.0, to: max(0.1, asset.duration.seconds - 0.1), by: 2))
        let frames = try await grab(video, at: times, width: 320)
        for (n, start) in stride(from: 0, to: frames.count, by: 24).enumerated() {
            let name = "sheet-\(n + 1).jpg"
            try sheet(Array(frames[start..<min(frames.count, start + 24)]), to: folder.appendingPathComponent(name))
            written.append(name)
        }
        return written
    }

    /// Full frames of the video at given times, as JPEGs in `folder`.
    public static func frames(_ video: URL, at times: [Double], to folder: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var out: [URL] = []
        for (t, image) in try await grab(video, at: times, width: 1280) {
            let url = folder.appendingPathComponent(String(format: "frame-%07.2f.jpg", t))
            try jpeg(image, to: url); out.append(url)
        }
        return out
    }

    /// Words as lines of about ten, each with the time it starts: "[1:04] then go up to the feather".
    static func lines(_ words: [TranscriptWord]) -> String {
        var out: [String] = [], line: [String] = [], start = 0.0
        for w in words {
            if line.isEmpty { start = w.range.start.seconds }
            line.append(w.text.trimmingCharacters(in: .whitespaces))
            if line.count >= 10 || w.text.hasSuffix(".") || w.text.hasSuffix("?") { out.append("[\(clock(start))] " + line.joined(separator: " ")); line = [] }
        }
        if !line.isEmpty { out.append("[\(clock(start))] " + line.joined(separator: " ")) }
        return out.joined(separator: "\n") + "\n"
    }
    static func clock(_ t: Double) -> String { String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }

    static func grab(_ video: URL, at times: [Double], width: Int) async throws -> [(t: Double, image: CGImage)] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: width, height: width)
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance; generator.requestedTimeToleranceAfter = tolerance
        var out: [(t: Double, image: CGImage)] = []
        for t in times { if let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image { out.append((t, image)) } }
        return out
    }

    /// Frames six across, each with its time in the corner.
    static func sheet(_ frames: [(t: Double, image: CGImage)], to url: URL) throws {
        guard let first = frames.first else { return }
        let w = first.image.width, h = first.image.height, cols = 6, rows = (frames.count + cols - 1) / cols
        guard let c = CGContext(data: nil, width: w * cols, height: h * rows, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w * cols, height: h * rows))
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 13, nil)
        for (i, f) in frames.enumerated() {
            let x = (i % cols) * w, y = (rows - 1 - i / cols) * h
            c.draw(f.image, in: CGRect(x: x, y: y, width: w, height: h))
            c.setFillColor(CGColor(gray: 0, alpha: 0.7)); c.fill(CGRect(x: x, y: y + h - 18, width: 52, height: 18))
            let text = CTLineCreateWithAttributedString(NSAttributedString(string: clock(f.t), attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)]))
            c.textPosition = CGPoint(x: x + 4, y: y + h - 14); CTLineDraw(text, c)
        }
        if let image = c.makeImage() { try jpeg(image, to: url) }
    }

    static func jpeg(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw DirectionError("write_failed", "Can't write \(url.lastPathComponent).") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DirectionError("write_failed", "Can't write \(url.lastPathComponent).") }
    }

    static func run(_ tool: URL, _ arguments: [String]) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { done in
            let p = Process(), pipe = Pipe()
            p.executableURL = tool; p.arguments = arguments; p.standardOutput = pipe; p.standardError = pipe
            p.terminationHandler = { proc in
                let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                done.resume(returning: (proc.terminationStatus, text))
            }
            do { try p.run() } catch { done.resume(throwing: error) }
        }
    }
}

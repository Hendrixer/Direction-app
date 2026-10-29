import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Turning what OpenRouter sends into files Direction can probe like footage.
public enum MadeMedia {
    /// The container from the first bytes: OpenRouter's audio formats vary by version.
    public static func audioExtension(_ data: Data, contentType: String = "") -> String {
        let b = [UInt8](data.prefix(12))
        func at(_ i: Int, _ s: String) -> Bool { b.count >= i + s.count && Array(b[i..<i + s.count]) == Array(s.utf8) }
        if at(0, "RIFF") && at(8, "WAVE") { return "wav" }
        if at(0, "ID3") || (b.count > 1 && b[0] == 0xFF && b[1] & 0xE0 == 0xE0) { return "mp3" }
        if at(0, "fLaC") { return "flac" }
        if at(0, "OggS") { return "ogg" }
        if at(4, "ftyp") { return "m4a" }
        if contentType.contains("mpeg") { return "mp3" }
        return "pcm"
    }

    /// Raw 16-bit PCM (OpenAI-style `pcm16`, speech `pcm`) as a WAV file. 24 kHz mono unless told.
    public static func wav(pcm16 pcm: Data, sampleRate: Int = 24_000, channels: Int = 1) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(UInt16(channels)); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * channels * 2)); u16(UInt16(channels * 2)); u16(16)
        d.append(Data("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }

    /// Streamed audio is one file, or (from some versions) one WAV per chunk run together. Either way: one playable file.
    public static func assemble(_ data: Data, contentType: String = "") -> (data: Data, ext: String) {
        let ext = audioExtension(data, contentType: contentType)
        if ext == "pcm" { return (wav(pcm16: data), "wav") }
        guard ext == "wav" else { return (data, ext) }
        let parts = wavParts(data)
        guard parts.count > 1, let first = parts.first else { return (data, "wav") }
        var pcm = Data(); for p in parts { pcm.append(p.pcm) }
        return (wav(pcm16: pcm, sampleRate: first.rate, channels: first.channels), "wav")
    }

    /// Each RIFF/WAVE run's 16-bit PCM payload. A data size of 0 or 0xFFFFFFFF (streamed) runs to the next header.
    static func wavParts(_ data: Data) -> [(pcm: Data, rate: Int, channels: Int)] {
        let b = [UInt8](data)
        func u32(_ i: Int) -> Int { i + 4 <= b.count ? Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 : 0 }
        func u16(_ i: Int) -> Int { i + 2 <= b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
        var starts: [Int] = []
        var i = 0
        while i + 12 <= b.count {
            if b[i] == 0x52, b[i + 1] == 0x49, b[i + 2] == 0x46, b[i + 3] == 0x46, b[i + 8] == 0x57, b[i + 9] == 0x41, b[i + 10] == 0x56, b[i + 11] == 0x45 { starts.append(i); i += 12 } else { i += 1 }
        }
        var parts: [(Data, Int, Int)] = []
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : b.count
            var p = start + 12, rate = 24_000, channels = 1, bits = 16
            while p + 8 <= end {
                let id = String(bytes: b[p..<p + 4], encoding: .ascii) ?? "", size = u32(p + 4)
                if id == "fmt " { channels = u16(p + 10); rate = u32(p + 12); bits = u16(p + 22) }
                if id == "data" {
                    let len = size == 0 || size == 0xFFFF_FFFF || p + 8 + size > end ? end - p - 8 : size
                    if bits == 16 { parts.append((Data(b[p + 8..<p + 8 + len]), rate, channels)) }
                    break
                }
                p += 8 + size + (size & 1)
            }
        }
        return parts
    }

    /// Joins clips with an equal-power crossfade, cuts to `length`, fades the end if it was cut, and writes a WAV.
    /// Longer beds are made 30 s at a time and joined here.
    public static func join(_ files: [URL], crossfade: Double, length: Double?, fadeOut: Double = 0.5, to output: URL) throws {
        guard let firstURL = files.first else { throw DirectionError("no_audio", "Nothing to join.") }
        let first = try AVAudioFile(forReading: firstURL)
        let format = first.processingFormat, rate = format.sampleRate, channels = Int(format.channelCount)
        var samples = [[Float]](repeating: [], count: channels)
        for (n, url) in files.enumerated() {
            let clip = try read(url, as: format)
            let overlap = n == 0 ? 0 : min(Int(crossfade * rate), samples[0].count, clip[0].count)
            for c in 0..<channels {
                let start = samples[c].count - overlap
                for i in 0..<overlap {
                    let t = Float(i) / Float(max(1, overlap))
                    samples[c][start + i] = samples[c][start + i] * cos(t * .pi / 2) + clip[c][i] * sin(t * .pi / 2)
                }
                samples[c].append(contentsOf: clip[c][overlap...])
            }
        }
        if let length, length > 0, Int(length * rate) < samples[0].count {
            let keep = Int(length * rate), fade = min(keep, Int(fadeOut * rate))
            for c in 0..<channels {
                samples[c].removeSubrange(keep...)
                for i in 0..<fade { samples[c][keep - fade + i] *= 1 - Float(i) / Float(max(1, fade)) }
            }
        }
        try write(samples, rate: rate, to: output)
    }

    static func read(_ url: URL, as format: AVAudioFormat) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw DirectionError("bad_audio", "Couldn\u{2019}t read a clip.") }
        try file.read(into: buffer)
        var out = buffer
        if file.processingFormat != format {
            guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
                  let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / file.processingFormat.sampleRate) + 1024) else { throw DirectionError("bad_audio", "Couldn\u{2019}t match the clips\u{2019} formats.") }
            var fed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            if let error { throw error }
            out = converted
        }
        guard let data = out.floatChannelData else { throw DirectionError("bad_audio", "Couldn\u{2019}t read a clip.") }
        return (0..<Int(format.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: Int(out.frameLength))) }
    }

    static func write(_ samples: [[Float]], rate: Double, to url: URL) throws {
        let channels = samples.count, frames = samples.first?.count ?? 0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels)), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, frames))) else { throw DirectionError("bad_audio", "Couldn\u{2019}t write the clip.") }
        buffer.frameLength = AVAudioFrameCount(frames)
        for c in 0..<channels { samples[c].withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress!, count: frames) } }
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    public static func duration(_ url: URL) async -> Double? {
        guard let d = try? await AVURLAsset(url: url).load(.duration), d.isNumeric else { return nil }
        return d.seconds
    }

    /// A take's frame as JPEG, for "a shot from one you have" (`first_frame`) and references. Stills are read as they are.
    public static func frame(of path: String, at seconds: Double, isImage: Bool, maxDimension: Int = 1280) async throws -> Data {
        let url = URL(fileURLWithPath: path)
        let image: CGImage
        if isImage {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxDimension, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw DirectionError("frame_failed", "Couldn\u{2019}t read that still.") }
            image = thumb
        } else {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
            image = try await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)).image
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw DirectionError("frame_failed", "Couldn\u{2019}t encode the frame.") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DirectionError("frame_failed", "Couldn\u{2019}t encode the frame.") }
        return data as Data
    }

    public static func dataURL(_ data: Data, mime: String) -> String { "data:\(mime);base64," + data.base64EncodedString() }

    /// "music-sparse-felt-piano-1a2b.wav": readable in Finder, unique in the folder.
    public static func fileName(_ kind: MadeKind, asked: String, ext: String) -> String {
        let words = asked.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.prefix(4).joined(separator: "-")
        return "\(kind.rawValue)-\(words.isEmpty ? "made" : words)-\(UUID().uuidString.prefix(4).lowercased()).\(ext)"
    }
}

import Foundation
@preconcurrency import AVFoundation
import ImageIO
import Vision
import DirectionCore

/// What Direction hears and sees in a sound or image on the library's shelves (library.md), so the Library can
/// say what each is and the editor can choose one from words: a sound's length, its level over time and what it
/// sounds like (music's tempo, key, loudness, instruments and voice); an image's size, whether any of it is
/// see-through, and the words in it.
public enum LibraryMeasuring {
    /// Measures an item on its shelf and keeps what it found. A sound measured for the first time takes its kind
    /// from what was heard (music, or a sound effect); after that, its kind is the director's.
    @discardableResult
    public static func measure(_ item: ShelfItem, in library: MediaLibrary, cacheDirectory: URL) async throws -> ShelfItem {
        let url = library.url(item)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var measured: ShelfItem.Measured, kind = item.kind
        if item.kind == .image { measured = try await image(url) } else {
            let heard = try await sound(url, cacheDirectory: cacheDirectory)
            measured = heard.measured
            if item.measured == nil { kind = heard.kind }
        }
        return try library.update(item.file) { i in
            i.measured = measured; i.kind = kind
            i.fileSize = Int64(values.fileSize ?? 0); i.modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        }
    }

    /// A sound file that's music, not someone talking: no picture, music in most of it and speech in little.
    /// A recording longer than a quarter of an hour is taken as talk without listening.
    public static func isMusic(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks), tracks.contains(where: { $0.mediaType == .audio }), !tracks.contains(where: { $0.mediaType == .video }),
              let length = try? await asset.load(.duration).seconds, length >= shortest, length <= 15 * 60,
              let heard = try? await VideoStudying.hear(url), !heard.isEmpty else { return false }
        let n = Double(heard.count)
        let music = Double(heard.filter { $0.music >= VideoStudying.musicHeard }.count) / n, speech = Double(heard.filter { $0.speech >= VideoStudying.speechHeard }.count) / n
        return music >= 0.6 && speech < 0.25
    }

    /// Music is what the sound classifier hears as music in at least half its seconds, four seconds or longer.
    static let musicShare = 0.5, shortest = 4.0
    /// An instrument is named when it's heard in a quarter of the seconds; a voice, in a sixth.
    static let instrumentShare = 0.25, vocalShare = 0.16
    static let voices: Set<String> = ["vocals", "choir", "rap vocals", "humming"]
    /// The waveform the Library draws has at most this many bars.
    static let bars = 96

    static func sound(_ url: URL, cacheDirectory: URL) async throws -> (measured: ShelfItem.Measured, kind: ShelfItem.Kind) {
        let asset = try await MediaInspector.inspect(url: url)
        var m = ShelfItem.Measured()
        let seconds = asset.duration.seconds
        m.seconds = seconds
        guard let l = await VideoStudying.listen(asset, cacheDirectory: cacheDirectory) else { return (m, seconds < 20 ? .effect : .music) }
        m.loudness = l.meter?.integrated.map { ($0 * 10).rounded() / 10 }
        let heard = l.heard, count = Double(max(1, heard.count))
        let music = Double(heard.filter { $0.music >= VideoStudying.musicHeard }.count) / count
        var instruments: [String: Int] = [:], others: [String: Int] = [:]
        for h in heard {
            for name in h.instruments.keys { instruments[name, default: 0] += 1 }
            for name in h.others.keys { others[name, default: 0] += 1 }
        }
        let kind: ShelfItem.Kind = music >= musicShare && seconds >= shortest ? .music : .effect
        if kind == .music {
            m.instruments = instruments.filter { !voices.contains($0.key) && Double($0.value) >= instrumentShare * count }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(4).map(\.key)
            m.vocals = instruments.contains { voices.contains($0.key) && Double($0.value) >= vocalShare * count }
            if let f = l.features {
                m.tempo = MusicListening.tempo(f.onsets[...]).map { ($0 * 2).rounded() / 2 }
                if seconds >= VideoStudying.keyLength { m.key = MusicListening.key(MusicListening.notes(f, from: 0, to: seconds, quiet: MusicListening.noteMask([], f))) }
            }
        } else {
            m.sounds = others.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(3).map(\.key)
        }
        if let levels = l.features?.levels, !levels.isEmpty { m.levels = waveform(levels) }
        return (m, kind)
    }

    /// Levels in dB, a bar each for up to `bars` stretches of the sound: the loudest moment in each, 60 dB down to 0.
    static func waveform(_ levels: [Float]) -> [Float] {
        let n = min(bars, levels.count)
        return (0..<n).map { i in
            let slice = levels[(i * levels.count / n)..<max(i * levels.count / n + 1, (i + 1) * levels.count / n)]
            return ((max(0, min(1, ((slice.max() ?? -60) + 60) / 60))) * 100).rounded() / 100
        }
    }

    static func image(_ url: URL) async throws -> ShelfItem.Measured {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DirectionError("image_unreadable", "\(url.lastPathComponent) can\u{2019}t be read as an image.")
        }
        let picture = VisionImage(image: cg)
        var m = ShelfItem.Measured()
        m.width = cg.width; m.height = cg.height
        let clear = seeThrough(cg)
        m.transparent = clear
        // A logo is often dark on nothing: read the words over white and over black, and keep what says more.
        m.words = try await VisionWork.run {
            guard clear else { return words(picture.image) }
            return [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)].compactMap { flattened(picture.image, on: $0).flatMap(words) }.max { $0.count < $1.count }
        }
        return m
    }

    static func flattened(_ image: CGImage, on color: CGColor) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let all = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(color); context.fill(all); context.draw(image, in: all)
        return context.makeImage()
    }

    /// True when some of the picture is see-through: read small, any pixel less than nearly opaque.
    static func seeThrough(_ image: CGImage) -> Bool {
        switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return false; default: break }
        let side = 64
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }

    /// The words in a picture, as Vision reads them, largest first: a logo's name, a title.
    static func words(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).filter { ($0.topCandidates(1).first?.confidence ?? 0) >= 0.5 }
            .sorted { $0.boundingBox.height > $1.boundingBox.height }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = lines.prefix(3).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(80))
    }
}

import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import DirectionCore
import DirectionMedia
import DirectionTools

struct MediaFixture: Sendable {
    let directory: URL
    let source: URL
    let store: ProjectStore
    let runtime: ToolRuntime

    static func make() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direction-media-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("picture.mov")
        let writer = try AVAssetWriter(outputURL: video, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<90 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error! } }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "Cannot allocate fixture frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
            context.setFillColor(i < 45 ? CGColor(red: 0.72, green: 0.18, blue: 0.12, alpha: 1) : CGColor(red: 0.10, green: 0.24, blue: 0.78, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            context.setFillColor(CGColor(gray: 1, alpha: 0.2)); context.fill(CGRect(x: 20 + i, y: 30, width: 40, height: 40))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30)) else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write fixture video.") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot finish fixture video.") }
        let composition = AVMutableComposition(), sourceVideo = AVURLAsset(url: video)
        let videoTrack = try await sourceVideo.loadTracks(withMediaType: .video)[0]
        let length = CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 48_000))
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: 1)!.insertTimeRange(length, of: videoTrack, at: .zero)
        for (i, frequency) in [440.0, 880.0].enumerated() {
            let path = directory.appendingPathComponent("tone\(i).wav")
            try writeTone(to: path, frequency: frequency, seconds: 3)
            let source = AVURLAsset(url: path), tracks = try await source.loadTracks(withMediaType: .audio)
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(i + 2))!.insertTimeRange(length, of: tracks[0], at: .zero)
        }
        let source = directory.appendingPathComponent("two-track.mov")
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await exporter.export(to: source, as: .mov)
        let store = try ProjectStore.create(at: directory.appendingPathComponent("Test.direction"), name: "Integration fixture")
        let runtime = try ToolRuntime(store: store)
        _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(source.path), "append": .bool(true)]))
        var format = EditOperation("format"); format.width = 320; format.height = 180
        _ = try store.apply(.init(baseEditRevision: store.revision(), operations: [format]))
        if let artifacts = ProcessInfo.processInfo.environment["DIRECTION_TEST_ARTIFACTS"] {
            let directory = URL(fileURLWithPath: artifacts)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("two-track-source.mov")
            // Suites make fixtures in parallel; whichever copies first wins.
            if !FileManager.default.fileExists(atPath: target.path) { do { try FileManager.default.copyItem(at: source, to: target) } catch { if !FileManager.default.fileExists(atPath: target.path) { throw error } } }
        }
        return .init(directory: directory, source: source, store: store, runtime: runtime)
    }

    func compile(revision: Int? = nil) async throws -> CompiledSequence { try await SequenceRenderer.compile(project: store.read(revision: revision), cacheDirectory: runtime.cacheDirectory) }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    static func writeTone(to url: URL, frequency: Double, seconds: Double) throws {
        let count = Int(seconds * 48_000), bytes = count * 2
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + bytes)); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(48_000); u32(96_000); u16(2); u16(16); text("data"); u32(UInt32(bytes))
        for i in 0..<count { let value = Int16(sin(Double(i) * 2 * .pi * frequency / 48_000) * 7_000); u16(UInt16(bitPattern: value)) }
        try data.write(to: url)
    }
}

func meanColor(_ url: URL) throws -> (Double, Double, Double) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DirectionError("test_frame", "Cannot read test image.") }
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (Double(bytes[0]), Double(bytes[1]), Double(bytes[2]))
}

func toneAmplitude(_ url: URL, frequency: Double) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    let samples = buffer.floatChannelData![0], rate = file.processingFormat.sampleRate
    var a = 0.0, b = 0.0
    for i in 0..<Int(buffer.frameLength) { a += Double(samples[i]) * sin(Double(i) * 2 * .pi * frequency / rate); b += Double(samples[i]) * cos(Double(i) * 2 * .pi * frequency / rate) }
    return 2 * sqrt(a*a + b*b) / Double(buffer.frameLength)
}

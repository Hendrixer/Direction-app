import Foundation
@preconcurrency import AVFoundation
import CoreVideo
import DirectionCore

/// Writes a graphic's frames as ProRes 4444 with alpha (graphics.md › frames are cached as a ProRes 4444
/// file). Frames arrive as premultiplied BGRA, tagged Rec. 709 like the rest of the cut, so the
/// compositor lays them over footage with `source-over`.
@MainActor
final class GraphicMovieWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let url: URL, width: Int, height: Int, frameRate: FrameRate
    private(set) var frames = 0

    init(url: URL, width: Int, height: Int, frameRate: FrameRate) throws {
        self.url = url; self.width = width; self.height = height; self.frameRate = frameRate
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = false
        writer.metadata = []
        writer.movieTimeScale = CMTimeScale(frameRate.numerator)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = CMTimeScale(frameRate.numerator)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw DirectionError("graphic_write_failed", "This Mac can't write ProRes 4444.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? DirectionError("graphic_write_failed", "Couldn't start writing the graphic.") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: GraphicImage) async throws {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error ?? DirectionError("graphic_write_failed", "Couldn't write the graphic.") }
            try await Task.sleep(for: .milliseconds(2))
        }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("graphic_write_failed", "Couldn't allocate a frame for the graphic.") }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let stride = CVPixelBufferGetBytesPerRow(buffer), row = width * 4
            image.bytes.withUnsafeBytes { source in
                for y in 0..<height { memcpy(base.advanced(by: y * stride), source.baseAddress!.advanced(by: y * row), row) }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        let time = CMTime(value: Int64(frames) * Int64(frameRate.denominator), timescale: frameRate.numerator)
        guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? DirectionError("graphic_write_failed", "Couldn't write frame \(frames + 1) of the graphic.") }
        frames += 1
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("graphic_write_failed", "Couldn't finish the graphic.") }
        try MovieTimestamps.zero(url)
    }

    func cancel() { writer.cancelWriting(); try? FileManager.default.removeItem(at: url) }
}

/// QuickTime stamps a movie with the time it was written. Zeroing those stamps makes two renders of
/// the same graphic and words byte-identical (graphics.md › Acceptance).
enum MovieTimestamps {
    static func zero(_ url: URL) throws {
        var data = try Data(contentsOf: url)
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            func be32(_ i: Int) -> UInt64 { (0..<4).reduce(0) { ($0 << 8) | UInt64(bytes[i + $1]) } }
            func be64(_ i: Int) -> UInt64 { (0..<8).reduce(0) { ($0 << 8) | UInt64(bytes[i + $1]) } }
            func walk(_ start: Int, _ end: Int) {
                var i = start
                while i + 8 <= end {
                    var size = Int(be32(i)), header = 8
                    if size == 1, i + 16 <= end { size = Int(be64(i + 8)); header = 16 } else if size == 0 { size = end - i }
                    guard size >= header, i + size <= end else { return }
                    let type = String(decoding: bytes[(i + 4)..<(i + 8)], as: UTF8.self)
                    switch type {
                    case "moov", "trak", "mdia": walk(i + header, i + size)
                    case "mvhd", "tkhd", "mdhd":
                        // version(1) flags(3), then creation and modification times: 32-bit in version 0, 64-bit in 1.
                        let body = i + header, count = bytes[body] == 1 ? 16 : 8
                        if body + 4 + count <= i + size { for k in 0..<count { bytes[body + 4 + k] = 0 } }
                    default: break
                    }
                    i += size
                }
            }
            walk(0, bytes.count)
        }
        try data.write(to: url)
    }
}

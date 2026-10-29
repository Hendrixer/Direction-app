import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import DirectionCore

/// Real frames of a take, straight from its file: keyframes, contact-sheet cells and
/// `direction_frame` with an assetID. Never through the cut.
public enum SourceFrames {
    /// Frames at the given source times, in order. A time past the end reads the last frame.
    /// `tolerance` lets the decoder use a nearby frame when exactness doesn't matter (sampling).
    public static func images(_ asset: MediaAsset, at times: [Double], maxDimension: Int, tolerance: Double = 0) async throws -> [CGImage] {
        guard !times.isEmpty else { return [] }
        let access = try MediaAccess(assets: [asset]); defer { withExtendedLifetime(access) {} }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: try MediaInspector.checkedURL(asset)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let t = CMTime(seconds: max(0, tolerance), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = t; generator.requestedTimeToleranceAfter = t
        let last = max(0, asset.duration.seconds - 1 / max(1, asset.video.first?.frameRate ?? 24))
        let requested = times.map { CMTime(seconds: min(max(0, $0), last), preferredTimescale: 600) }
        var found: [Int64: CGImage] = [:]
        // The batch API decodes forward once instead of seeking for every frame.
        for await result in generator.images(for: Array(Set(requested.map(\.value))).sorted().map { CMTime(value: $0, timescale: 600) }) {
            try Task.checkCancellation()
            switch result {
            case .success(requestedTime: let time, image: let image, actualTime: _): found[time.convertScale(600, method: .roundHalfAwayFromZero).value] = image
            case .failure(requestedTime: let time, error: let error):
                // One unreadable frame shouldn't stop the take: try it alone, exactly.
                guard let (image, _) = try? await generator.image(at: time) else { throw DirectionError("frame_unreadable", "Couldn't read a frame of \(asset.name): \(error.localizedDescription)") }
                found[time.convertScale(600, method: .roundHalfAwayFromZero).value] = image
            }
        }
        return try requested.map { t in
            guard let image = found[t.value] else { throw DirectionError("frame_unreadable", "Couldn't read a frame of \(asset.name) at \(String(format: "%.2f", t.seconds)) s.") }
            return image
        }
    }

    public static func image(_ asset: MediaAsset, at time: Double, maxDimension: Int) async throws -> CGImage {
        guard let image = try await images(asset, at: [time], maxDimension: maxDimension).first else { throw DirectionError("frame_unreadable", "Couldn't read a frame of \(asset.name).") }
        return image
    }

    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.82) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw DirectionError("image_write_failed", "Cannot write \(url.lastPathComponent).") }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw DirectionError("image_write_failed", "Cannot finish \(url.lastPathComponent).") }
    }

    /// Scales so the longer side is at most `maxDimension` (never up).
    public static func scaled(_ image: CGImage, maxDimension: Int) -> CGImage {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let w = max(1, Int((Double(image.width) * scale).rounded())), h = max(1, Int((Double(image.height) * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Mean luminance 0…1, from a 32 × 18 thumbnail.
    public static func luminance(_ image: CGImage) -> Double {
        let w = 32, h = 18
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0.5 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(w * h * 255)
    }

    /// A take's frame for `direction_frame` with an assetID: PNG at the source time.
    public static func frame(_ asset: MediaAsset, at seconds: Double, to output: URL, maxDimension: Int) async throws -> JSONValue {
        guard !asset.video.isEmpty else { throw DirectionError("no_picture", "\(asset.name) has no picture.") }
        guard seconds.isFinite, seconds >= 0, seconds <= asset.duration.seconds else { throw DirectionError("invalid_time", "time must be inside the take, 0–\(String(format: "%.2f", asset.duration.seconds)) s.") }
        let image = try await self.image(asset, at: seconds, maxDimension: maxDimension)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MediaInspector.writePNG(image, to: output)
        let fps = asset.video.first?.frameRate ?? 24
        return .object(["assetID": .string(asset.id), "take": .string(asset.name), "time": .number(seconds), "timecode": .string(SourceTimecode.format(seconds, fps: fps)), "width": .number(Double(image.width)), "height": .number(Double(image.height)), "path": .string(output.path), "source": .bool(true)])
    }
}

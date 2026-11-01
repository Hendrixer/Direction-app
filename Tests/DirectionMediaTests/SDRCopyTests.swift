import Testing
import Foundation
@preconcurrency import AVFoundation
import VideoToolbox
import ImageIO
import UniformTypeIdentifiers
import DirectionCore
import DirectionMedia
import DirectionTools

/// HDR footage comes in as an SDR copy (architecture.md › Color), checked on a small clip made here the way an
/// iPhone tags its video: 10-bit HEVC, HLG, BT.2020.
struct SDRCopyTests {
    /// One second at 30 fps: a darker gray left half and a brighter gray right half.
    static func hlgClip(in folder: URL, name: String = "Take 1.MOV") async throws -> URL {
        let url = folder.appendingPathComponent(name), width = 640, height = 360
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error! } }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "Cannot allocate an HLG frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            // 10-bit video range in the top bits of 16: luma 64–940, chroma neutral at 512.
            let y = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!, yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for row in 0..<height {
                let line = (y + row * yStride).bindMemory(to: UInt16.self, capacity: width)
                for x in 0..<width { line[x] = UInt16(x < width / 2 ? 300 : 600) << 6 }
            }
            let c = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!, cStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            for row in 0..<(height / 2) {
                let line = (c + row * cStride).bindMemory(to: UInt16.self, capacity: width)
                for x in 0..<width { line[x] = UInt16(512) << 6 }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30)) else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write an HLG frame.") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot finish the HLG clip.") }
        return url
    }

    static func transfer(_ url: URL) async throws -> String? {
        let description = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first?.load(.formatDescriptions).first)
        return CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
    }

    /// A frame half a second in, as a PNG.
    static func frame(_ url: URL, to out: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url)); generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(value: 15, timescale: 30)).image
        let destination = try #require(CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
    }

    @Test func anHLGClipIsCopiedAsSDRAndTheOriginalStays() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-sdr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let original = try await Self.hlgClip(in: folder)
        let before = try FileManager.default.attributesOfItem(atPath: original.path)
        #expect(await SDRCopy.isHDR(original))
        await #expect(throws: DirectionError.self) { _ = try await MediaInspector.inspect(url: original) }

        let footage = folder.appendingPathComponent("Footage")
        let copy = try await SDRCopy.make(original, in: footage)
        #expect(copy.lastPathComponent == "Take 1.mov" && copy.deletingLastPathComponent().standardizedFileURL == footage.standardizedFileURL)
        #expect(try await Self.transfer(copy) == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(await !SDRCopy.isHDR(copy))
        let asset = try await MediaInspector.inspect(url: copy)
        #expect(abs(asset.duration.seconds - 1) < 0.05 && asset.video.first?.width == 640 && asset.video.first?.height == 360)
        // A second take with the same name gets its own.
        #expect(try await SDRCopy.make(original, in: footage).lastPathComponent == "Take 1 2.mov")
        #expect(try FileManager.default.contentsOfDirectory(atPath: footage.path).filter { $0.hasPrefix(".") }.isEmpty)
        // The original is as it was.
        let after = try FileManager.default.attributesOfItem(atPath: original.path)
        #expect(after[.size] as? NSNumber == before[.size] as? NSNumber && after[.modificationDate] as? Date == before[.modificationDate] as? Date)

        // Grays stay gray and keep their order, inside SDR's range.
        let still = folder.appendingPathComponent("frame.png")
        try await Self.frame(copy, to: still)
        let dark = try meanColor(still, in: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.6)), light = try meanColor(still, in: CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.6))
        for c in [dark, light] { #expect(max(c.0, c.1, c.2) - min(c.0, c.1, c.2) < 12, "\(c)") }
        #expect(dark.1 > 10 && light.1 > dark.1 + 30 && light.1 < 250, "\(dark) \(light)")
    }

    @Test func importingHDRBringsInTheSDRCopyOnce() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let original = try await Self.hlgClip(in: f.directory)
        let imported = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(original.path)]))
        let path = try #require(imported.value["asset"]["path"].string)
        #expect(URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path == MediaAsset.copies(in: f.store.url).standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(imported.value["asset"]["sdrCopyOf"].string == original.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(try f.store.read().assets.first { $0.path == path }?.isFootage(film: f.store.url) == true)
        // The same clip again is already in, and no second copy is made.
        await #expect(throws: DirectionError.self) { _ = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(original.path)])) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: MediaAsset.copies(in: f.store.url).path).filter { $0.hasSuffix(".mov") } == ["Take 1.mov"])
    }
}

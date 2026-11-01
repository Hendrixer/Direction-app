import Foundation
@preconcurrency import AVFoundation
import DirectionCore

private final class ConversionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

/// HDR video (an iPhone's HLG, PQ) comes into a film as an SDR Rec.709 copy Direction makes in the film's
/// Footage folder, tone-mapped by AVFoundation; the original stays as it is (architecture.md › Color).
public enum SDRCopy {
    /// True when the file's picture is HDR.
    public static func isHDR(_ url: URL) async -> Bool {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let description = try? await track.load(.formatDescriptions).first,
              let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String else { return false }
        return transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String || transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
    }

    /// Writes the SDR copy into `folder` under the original's name as a .mov, or "Name 2.mov" when that's
    /// taken, at the original's size and rate with its sound. It's written to a hidden file first, so a copy
    /// cut short never looks finished.
    public static func make(_ url: URL, in folder: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        var configuration = try await AVVideoComposition.Configuration(for: asset)
        configuration.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2; configuration.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2; configuration.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else { throw DirectionError("sdr_copy_failed", "Direction couldn\u{2019}t make an SDR copy of \(url.lastPathComponent).") }
        session.videoComposition = AVVideoComposition(configuration: configuration)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent(".\(UUID().uuidString).converting.mov")
        let box = ConversionBox(session)
        do {
            try await withTaskCancellationHandler { @Sendable in try await box.session.export(to: temp, as: .mov) } onCancel: { box.session.cancelExport() }
            try Task.checkCancellation()
            return try place(temp, as: url, in: folder)
        } catch {
            session.cancelExport(); try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// A finished copy Direction made (this, SeekableCopy) takes the original's name as a .mov, or "Name 2.mov" when that's taken.
    static func place(_ temp: URL, as original: URL, in folder: URL) throws -> URL {
        let base = original.deletingPathExtension().lastPathComponent
        var n = 1, target = folder.appendingPathComponent(base + ".mov")
        while FileManager.default.fileExists(atPath: target.path) { n += 1; target = folder.appendingPathComponent("\(base) \(n).mov") }
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }
}

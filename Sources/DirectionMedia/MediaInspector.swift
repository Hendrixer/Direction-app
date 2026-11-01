import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import DirectionCore

public enum MediaInspector {
    public static func inspect(url: URL, thumbnailDirectory: URL? = nil) async throws -> MediaAsset {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        guard info.isRegularFile == true else { throw DirectionError("invalid_media", "Choose a regular video, audio, or image file.") }
        var result: MediaAsset
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            result = MediaAsset(name: url.lastPathComponent, path: url.path, duration: .init(seconds: 5), video: [.init(id: 0, width: image.width, height: image.height, frameRate: 0)], fileSize: Int64(info.fileSize ?? 0), modifiedAt: info.contentModificationDate?.timeIntervalSince1970 ?? 0)
            result.isImage = true
        } else {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.isNumeric, duration.seconds > 0 else { throw DirectionError("invalid_media", "The file has no finite playable duration.") }
            let tracks = try await asset.load(.tracks)
            var video: [VideoStream] = [], audio: [AudioStream] = []
            for t in tracks {
                if t.mediaType == .video {
                    let size = try await t.load(.naturalSize), transform = try await t.load(.preferredTransform), rate = try await t.load(.nominalFrameRate)
                    let bounds = CGRect(origin: .zero, size: size).applying(transform)
                    let descriptions = try await t.load(.formatDescriptions)
                    let ext: NSDictionary? = descriptions.first.flatMap { CMFormatDescriptionGetExtensions($0) }.map { $0 as NSDictionary }
                    let transfer = ext?[kCMFormatDescriptionExtension_TransferFunction] as? String
                    let pq = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
                    let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
                    if transfer == pq || transfer == hlg {
                        throw DirectionError("hdr_not_supported", "\(url.lastPathComponent) is HDR. Direction works in SDR: bring it into a film as footage and Direction makes an SDR copy.")
                    }
                    video.append(.init(id: t.trackID, width: Int(abs(bounds.width)), height: Int(abs(bounds.height)), frameRate: Double(rate), colorPrimaries: ext?[kCMFormatDescriptionExtension_ColorPrimaries] as? String, transferFunction: transfer))
                } else if t.mediaType == .audio {
                    let descriptions = try await t.load(.formatDescriptions)
                    let format = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
                    let language = try await t.load(.extendedLanguageTag)
                    audio.append(.init(id: t.trackID, index: audio.count, label: "Audio \(audio.count + 1)", channels: Int(format?.mChannelsPerFrame ?? 1), sampleRate: format?.mSampleRate ?? 48_000, language: language))
                }
            }
            guard !video.isEmpty || !audio.isEmpty else { throw DirectionError("unsupported_media", "No supported video or audio streams were found.") }
            result = MediaAsset(name: url.lastPathComponent, path: url.path, duration: .init(duration), video: video, audio: audio, fileSize: Int64(info.fileSize ?? 0), modifiedAt: info.contentModificationDate?.timeIntervalSince1970 ?? 0)
        }
        result.bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        if let directory = thumbnailDirectory, !result.video.isEmpty {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(result.id + ".png")
            if result.isImage {
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 480] as CFDictionary) { try writePNG(image, to: destination); result.thumbnailPath = destination.path }
            } else {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = .init(width: 480, height: 270)
                if let frame = try? await generator.image(at: .zero) { try writePNG(frame.image, to: destination); result.thumbnailPath = destination.path }
            }
        }
        return result
    }

    public static func checkedURL(_ asset: MediaAsset) throws -> URL {
        var url = URL(fileURLWithPath: asset.path)
        if let bookmark = asset.bookmark { var stale = false; if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), !stale { url = resolved } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard asset.fileSize == Int64(values.fileSize ?? -1), abs(asset.modifiedAt - (values.contentModificationDate?.timeIntervalSince1970 ?? 0)) < 0.01 else { throw DirectionError("source_changed", "\(asset.name) has changed since import. Relink or import the changed file explicitly.") }
        return url
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw DirectionError("image_write_failed", "Cannot write frame image.") }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw DirectionError("image_write_failed", "Cannot finish frame image.") }
    }
}

public final class MediaAccess: @unchecked Sendable {
    private let urls: [URL]
    public init(assets: [MediaAsset]) throws {
        var values: [URL] = []
        do { for asset in assets { let url = try MediaInspector.checkedURL(asset); if url.startAccessingSecurityScopedResource() { values.append(url) } } }
        catch { for url in values { url.stopAccessingSecurityScopedResource() }; throw error }
        urls = values
    }
    deinit { for url in urls { url.stopAccessingSecurityScopedResource() } }
}

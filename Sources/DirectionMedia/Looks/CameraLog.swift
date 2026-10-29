import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import DirectionCore

/// Finds log footage (looks.md › Where color happens, 1) from what the file says about itself:
/// the video track's format description first (Apple Log has its own extension), then the color
/// metadata cameras write, then a Sony sidecar (`C0001M01.XML`). Direction ships no camera LUTs;
/// the matching file is `Looks/Camera/<log name>.cube`, which the director adds.
public enum CameraLog {
    /// The log curve's name, one of `SharedSettings.logNames`, or nil for normal video.
    public static func detect(url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let description = try? await track.load(.formatDescriptions).first,
           let ext = CMFormatDescriptionGetExtensions(description) as NSDictionary? {
            if let log = ext[kCMFormatDescriptionExtension_LogTransferFunction] as? String, log == kCMFormatDescriptionLogTransferFunction_AppleLog as String { return "Apple Log" }
            for key in [kCMFormatDescriptionExtension_LogTransferFunction, kCMFormatDescriptionExtension_TransferFunction, kCMFormatDescriptionExtension_GammaLevel] {
                if let value = ext[key] as? String, let found = match(value) { return found }
            }
            let items = ((try? await asset.load(.metadata)) ?? []) + ((try? await track.load(.metadata)) ?? [])
            for item in items {
                // Only color fields: a title like "my vlog" must not read as V-Log.
                let key = ((item.identifier?.rawValue ?? "") + " " + ((item.key as? String) ?? "")).lowercased()
                guard ["gamma", "transfer", "color", "curve", "log", "look"].contains(where: key.contains),
                      let value = try? await item.load(.stringValue), let found = match(value) else { continue }
                return found
            }
        }
        let sidecar = URL(fileURLWithPath: url.deletingPathExtension().path + "M01.XML")
        if let xml = try? String(contentsOf: sidecar, encoding: .utf8), let range = xml.range(of: "CaptureGammaEquation") {
            return match(String(xml[range.upperBound...].prefix(80)))
        }
        return nil
    }

    /// The log name in a metadata value: "s-log3-cine", "LogC3", "V-Log", "AppleLog".
    public static func match(_ text: String) -> String? {
        let t = text.lowercased().filter { $0.isLetter || $0.isNumber }
        if t.contains("applelog") { return "Apple Log" }
        if t.contains("slog3") { return "S-Log3" }
        if t.contains("logc") { return "LogC" }
        if t.contains("vlog") { return "V-Log" }
        return nil
    }

    /// Detects every take the store hasn't checked yet and remembers the answer ("" for normal video).
    public static func detectMissing(in store: ProjectStore) async {
        guard let project = try? store.read(), let known = try? store.cameraLUTs().detected else { return }
        var found: [String: String] = [:]
        for asset in project.assets where !asset.isImage && !asset.video.isEmpty && known[asset.id] == nil {
            guard FileManager.default.fileExists(atPath: asset.path) else { continue }
            found[asset.id] = await detect(url: URL(fileURLWithPath: asset.path)) ?? ""
        }
        try? store.recordLogDetection(found)
    }
}

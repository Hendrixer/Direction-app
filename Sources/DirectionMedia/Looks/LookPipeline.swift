import Foundation
import CoreImage
import Synchronization
import DirectionCore

/// Applies the director's look to a composited frame (specs/looks.md › Where color happens).
/// The compositor calls this after every layer below the look, before layers marked above it.
public enum LookPipeline {
    /// - storyAssetID: the take on the story track (V1) at this frame, to find its scene's look.
    /// - frameIndex: frames from the cut's start; grain and gate weave are seeded by it.
    public static func apply(_ image: CIImage, context: LookContext?, storyAssetID: String?, frameIndex: Int) -> CIImage {
        guard let context, let look = context.look.look(forScene: storyAssetID.flatMap { context.sceneForAsset[$0] }) else { return image }
        return apply(look, to: image, frameIndex: frameIndex)
    }

    /// One look on its own: the LUT at its strength, then the filters in their fixed order.
    public static func apply(_ look: LookSettings, to image: CIImage, frameIndex: Int) -> CIImage {
        guard !look.isNone else { return image }
        let finite = !image.extent.isInfinite
        let frame = finite ? image.extent : CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var out = image
        if let lut = look.lut { out = self.lut(out, path: lut, strength: look.strength) }
        for f in look.active { out = LookFilters.apply(f.filter, out, amount: f.amount, option: f.option, frameIndex: frameIndex, in: frame) }
        return finite ? out.cropped(to: frame) : out
    }

    /// One filter on its own (looks.md › Filters), for the editor's per-clip `filter.<kind>` effects.
    public static func filter(_ image: CIImage, kind: String, amount: Double, option: String?, frameIndex: Int) -> CIImage {
        let name = kind.hasPrefix("filter.") ? String(kind.dropFirst(7)) : kind
        guard let f = LookFilter(rawValue: name), amount > 0 || !f.hasAmount else { return image }
        let finite = !image.extent.isInfinite
        let frame = finite ? image.extent : CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let out = LookFilters.apply(f, image, amount: min(1, max(0, amount)), option: option ?? f.options.first, frameIndex: frameIndex, in: frame)
        return finite ? out.cropped(to: frame) : out
    }

    /// The camera LUT for one take's picture (log to normal video), before balance and effects.
    /// The compositor calls it on each layer's source frame.
    public static func camera(_ image: CIImage, context: LookContext?, assetID: String?) -> CIImage {
        guard let path = assetID.flatMap({ context?.cameraLUTs[$0] }) else { return image }
        return lut(image, path: path, strength: 1)
    }

    /// A .cube file at a strength, mixed with the original. Files that don't validate are never applied.
    public static func lut(_ image: CIImage, path: String, strength: Double) -> CIImage {
        guard strength > 0, case .success(let cube) = LUTCache.prepared(path) else { return image }
        let graded = image.applyingFilter("CIColorCubeWithColorSpace", parameters: ["inputCubeDimension": cube.dimension, "inputCubeData": cube.data, "inputColorSpace": LookFilters.rec709])
        guard strength < 1 else { return graded }
        return image.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": graded, "inputTime": strength])
    }

    /// Why a LUT can't be used, or nil when it can.
    public static func problem(_ path: String) -> String? {
        if case .failure(let e) = LUTCache.prepared(path) { return e.message }
        return nil
    }
}

/// Parsed LUTs as Core Image cube data, cached per file and read again when the file changes.
public enum LUTCache {
    public struct Prepared: Sendable { public let dimension: Int; public let data: Data }
    private struct Entry { var stamp: String; var result: Result<Prepared, DirectionError> }
    private static let entries = Mutex<[String: Entry]>([:])

    public static func prepared(_ path: String) -> Result<Prepared, DirectionError> {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let stamp = "\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1):\((attributes?[.size] as? NSNumber)?.intValue ?? -1)"
        if let hit = entries.withLock({ $0[path] }), hit.stamp == stamp { return hit.result }
        let result: Result<Prepared, DirectionError>
        do { let d = try CubeLUT.load(URL(fileURLWithPath: path)).cubeData(); result = .success(.init(dimension: d.dimension, data: d.data)) }
        catch let e as DirectionError { result = .failure(e) }
        catch { result = .failure(DirectionError("lut_invalid", "Can't read this LUT: \(error.localizedDescription)")) }
        entries.withLock { $0[path] = Entry(stamp: stamp, result: result) }
        return result
    }
}

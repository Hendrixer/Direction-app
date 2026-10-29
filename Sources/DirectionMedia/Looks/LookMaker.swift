import Foundation
import CoreImage
import ImageIO
import simd
import DirectionCore

/// Color statistics of a picture in CIELAB: what per-channel color transfer matches.
public struct ColorStats: Sendable, Hashable, Codable {
    public var mean: SIMD3<Double>
    public var deviation: SIMD3<Double>
    public init(mean: SIMD3<Double>, deviation: SIMD3<Double>) { self.mean = mean; self.deviation = deviation }
}

/// How the editor makes a look from a reference still: per-channel color transfer (Reinhard et al.)
/// in CIELAB. The film's frames and the still each give a mean and spread per channel; the LUT moves
/// the film's onto the still's. Lightness spread is held to 0.6–1.6× so a dark still doesn't crush.
public enum LookMaker {
    public static let context = CIContext(options: [.cacheIntermediates: false])

    public static func transfer(from source: ColorStats, to reference: ColorStats, size: Int = 33, title: String? = nil) -> CubeLUT {
        var ratio = reference.deviation / simd_max(source.deviation, SIMD3(repeating: 1e-3))
        ratio.x = min(1.6, max(0.6, ratio.x)); ratio.y = min(2.5, max(0.4, ratio.y)); ratio.z = min(2.5, max(0.4, ratio.z))
        return CubeLUT.make(size: size, title: title) { rgb in
            let lab = Self.lab(SIMD3<Double>(rgb))
            let moved = (lab - source.mean) * ratio + reference.mean
            return SIMD3<Float>(Self.rgb(moved))
        }
    }

    /// Statistics over one or more pictures, read as Rec. 709 values at about 160 px wide.
    public static func stats(_ images: [CIImage]) -> ColorStats? {
        var labs: [SIMD3<Double>] = []
        for image in images {
            guard !image.extent.isInfinite, image.extent.width > 0 else { continue }
            let s = min(1, 160 / image.extent.width)
            let small = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            let rect = small.extent.integral, w = Int(rect.width), h = Int(rect.height)
            guard w > 0, h > 0 else { continue }
            var pixels = [Float](repeating: 0, count: w * h * 4)
            context.render(small, toBitmap: &pixels, rowBytes: w * 16, bounds: rect, format: .RGBAf, colorSpace: LookFilters.rec709)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                labs.append(lab(SIMD3(Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))))
            }
        }
        guard !labs.isEmpty else { return nil }
        let mean = labs.reduce(.zero, +) / Double(labs.count)
        let variance = labs.reduce(SIMD3<Double>.zero) { $0 + ($1 - mean) * ($1 - mean) } / Double(labs.count)
        return ColorStats(mean: mean, deviation: simd_max(variance.squareRoot(), SIMD3(repeating: 1e-3)))
    }

    /// Where to take stills that show a look across the film: one story-track frame per scene, spread
    /// over the cut when there are more scenes than stills. Each is the middle of the scene's first shot.
    public struct StillPick: Sendable, Hashable { public var time: Double; public var assetID: String?; public var sceneID: String? }
    public static func picks(_ sequence: DirectionCore.Sequence, sceneForAsset: [String: String], count: Int) -> [StillPick] {
        let clips = sequence.clips.filter { $0.kind == .video && $0.layer == 0 }.sorted { $0.start < $1.start }
        var firsts: [StillPick] = [], seen = Set<String>()
        for c in clips {
            let key = c.assetID.flatMap { sceneForAsset[$0] } ?? c.id
            guard seen.insert(key).inserted else { continue }
            let mid = c.start.seconds + c.duration.seconds / 2
            firsts.append(StillPick(time: min(mid, max(0, sequence.duration.seconds - 0.05)), assetID: c.assetID, sceneID: c.assetID.flatMap { sceneForAsset[$0] }))
        }
        guard firsts.count > count, count > 1 else { return Array(firsts.prefix(max(0, count))) }
        return (0..<count).map { firsts[Int((Double($0) * Double(firsts.count - 1) / Double(count - 1)).rounded())] }
    }

    public static func image(at url: URL) -> CIImage? { CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) }

    /// Writes a still as PNG in the color space it came in with.
    public static func writePNG(_ image: CIImage, to url: URL, colorSpace: CGColorSpace? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let space = colorSpace ?? image.colorSpace ?? LookFilters.rec709
        try context.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: space.model == .rgb ? space : LookFilters.rec709)
    }

    // MARK: Rec. 709 (gamma 2.4) ↔ CIELAB, D65

    private static let toXYZ = simd_double3x3(rows: [SIMD3(0.4124, 0.3576, 0.1805), SIMD3(0.2126, 0.7152, 0.0722), SIMD3(0.0193, 0.1192, 0.9505)])
    private static let fromXYZ = simd_double3x3(rows: [SIMD3(3.2406, -1.5372, -0.4986), SIMD3(-0.9689, 1.8758, 0.0415), SIMD3(0.0557, -0.2040, 1.0570)])
    private static let white = SIMD3<Double>(0.95047, 1.0, 1.08883)

    static func lab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let lin: SIMD3<Double> = simd_clamp(rgb, SIMD3<Double>.zero, SIMD3<Double>.one).map { pow($0, 2.4) }
        let xyz: SIMD3<Double> = (toXYZ * lin) / white
        let f: SIMD3<Double> = xyz.map { $0 > 0.008856 ? cbrt($0) : 7.787 * $0 + 16.0 / 116.0 }
        return SIMD3<Double>(116 * f.y - 16, 500 * (f.x - f.y), 200 * (f.y - f.z))
    }

    static func rgb(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let fy: Double = (lab.x + 16) / 116
        let f = SIMD3<Double>(fy + lab.y / 500, fy, fy - lab.z / 200)
        let xyz: SIMD3<Double> = f.map { $0 > 0.206893 ? $0 * $0 * $0 : ($0 - 16.0 / 116.0) / 7.787 } * white
        let lin: SIMD3<Double> = simd_clamp(fromXYZ * xyz, SIMD3<Double>.zero, SIMD3<Double>.one)
        return lin.map { pow($0, 1 / 2.4) }
    }
}

private extension SIMD3 where Scalar == Double {
    func map(_ f: (Double) -> Double) -> SIMD3<Double> { SIMD3(f(x), f(y), f(z)) }
}

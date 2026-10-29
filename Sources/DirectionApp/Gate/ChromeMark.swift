import SwiftUI
import AppKit
import CoreImage

/// The chrome D, with its rainbow reflection travelling around the letter as if the light moved.
/// The rainbow lives at the lower left of the stem. Each pass carries it up the stem, across the top,
/// around the bowl and back along the bottom to where it started: slowly at first, then quicker,
/// then easing into a stall at home, where it rests before the next pass. Reduce Motion shows the still mark.
struct ChromeMark: View {
    var size: CGFloat = 168
    /// Pins the moment, in seconds, for snapshots. Nil follows the clock.
    var at: Double? = nil

    static let pass = 5.2, rest = 2.6
    /// Slow out of the rest, quick through the middle, a long eased stall on the way home.
    static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.72, y: 0), endControlPoint: UnitPoint(x: 0.14, y: 1))

    /// 0…1 around the letter; holds at 0 (home) through the rest.
    static func progress(_ time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: pass + rest)
        return t >= pass ? 0 : curve.value(at: t / pass)
    }

    var body: some View {
        if let mark = BrandAssets.mark {
            Group {
                if let layers = ChromeLight.layers, !(at == nil && SettingsKey.reducesMotion) {
                    if let at { lit(layers, mark, Self.progress(at)) }
                    else { TimelineView(.animation) { lit(layers, mark, Self.progress($0.date.timeIntervalSinceReferenceDate)) } }
                } else {
                    Image(nsImage: mark).resizable().interpolation(.high).scaledToFit()
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    private func lit(_ layers: ChromeLight.Layers, _ mark: NSImage, _ p: Double) -> some View {
        let k = size / ChromeLight.side, spot = ChromePath.point(at: p)
        // The art already holds the rainbow's light at home; away from home the reflection brings it along.
        let away = min(1, hypot(spot.x - ChromeLight.home.x, spot.y - ChromeLight.home.y) / 160)
        return ZStack {
            // The mark with its rainbow taken out, so the chrome is grey where the rainbow used to sit.
            Image(nsImage: layers.base).resizable().interpolation(.high)
            // The rainbow alone. Color blending gives the chrome under it the rainbow's hue and
            // saturation while keeping the chrome's own light and shade, so it reads as a reflection.
            Image(nsImage: layers.rainbow).resizable().interpolation(.high)
                .frame(width: ChromeLight.patch * k, height: ChromeLight.patch * k)
                .position(x: spot.x * k, y: spot.y * k)
                .blendMode(.color)
            Image(nsImage: layers.glow).resizable().interpolation(.high)
                .frame(width: ChromeLight.patch * k, height: ChromeLight.patch * k)
                .position(x: spot.x * k, y: spot.y * k)
                .blendMode(.screen).opacity(0.7 * away * away * (3 - 2 * away))
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .mask(Image(nsImage: mark).resizable().interpolation(.high))
    }
}

/// The two images the light is made of, cut once from the mark.
@MainActor private enum ChromeLight {
    struct Layers { let base: NSImage; let rainbow: NSImage; let glow: NSImage }
    /// The art's coordinates: a 1024 square, top-left origin.
    static let side: CGFloat = 1024
    /// Where the rainbow sits in the art, and how much of it travels.
    static let home = CGPoint(x: 180, y: 700), inner: CGFloat = 70, outer: CGFloat = 135, patch: CGFloat = 300

    static let layers: Layers? = {
        guard let mark = BrandAssets.mark, let cg = mark.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let image = CIImage(cgImage: cg), extent = image.extent, s = extent.width / side
        let center = CGPoint(x: home.x * s, y: extent.height - home.y * s)
        // Grey by the same luminance weights color blending uses, so the rainbow at home restores the art.
        let weights = CIVector(x: 0.3, y: 0.59, z: 0.11, w: 0)
        let grey = image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": weights, "inputGVector": weights, "inputBVector": weights, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        guard let spot = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(cgPoint: center), "inputRadius0": inner * s, "inputRadius1": outer * s,
            "inputColor0": CIColor.white, "inputColor1": CIColor.black,
        ])?.outputImage?.cropped(to: extent) else { return nil }
        let base = grey.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: spot])
        let rainbow = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), kCIInputMaskImageKey: spot])
        // Only the colored pixels, weighted by how saturated they are: the light the reflection carries.
        let saturation = image.applyingFilter("CIMaximumComponent")
            .applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: image.applyingFilter("CIMinimumComponent")])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 2.2, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 2.2, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 2.2, w: 0)])
            .applyingFilter("CIColorClamp")
        let glow = rainbow.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), kCIInputMaskImageKey: saturation])
        let half = patch * s / 2
        let patchRect = CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
        guard let baseCG = context.createCGImage(base, from: extent, format: .RGBA8, colorSpace: sRGB),
              let rainbowCG = context.createCGImage(rainbow, from: patchRect, format: .RGBA8, colorSpace: sRGB),
              let glowCG = context.createCGImage(glow, from: patchRect, format: .RGBA8, colorSpace: sRGB) else { return nil }
        let patchSize = NSSize(width: patch, height: patch)
        return Layers(base: NSImage(cgImage: baseCG, size: mark.size), rainbow: NSImage(cgImage: rainbowCG, size: patchSize), glow: NSImage(cgImage: glowCG, size: patchSize))
    }()
}

/// The loop the rainbow follows over the letter's face, in the art's coordinates, from home and back.
private enum ChromePath {
    static let stops: [CGPoint] = [
        CGPoint(x: 180, y: 700), CGPoint(x: 188, y: 470), CGPoint(x: 205, y: 230), CGPoint(x: 330, y: 140), CGPoint(x: 560, y: 150),
        CGPoint(x: 740, y: 245), CGPoint(x: 850, y: 390), CGPoint(x: 885, y: 565), CGPoint(x: 820, y: 760), CGPoint(x: 640, y: 870),
        CGPoint(x: 400, y: 890), CGPoint(x: 215, y: 860),
    ]

    /// Catmull-Rom through the stops, sampled densely and indexed by distance so speed is even
    /// along the curve; the timing curve alone decides how fast the rainbow moves.
    private static let samples: [(CGPoint, CGFloat)] = {
        var points: [CGPoint] = []
        let n = stops.count
        for i in 0..<n {
            let p0 = stops[(i - 1 + n) % n], p1 = stops[i], p2 = stops[(i + 1) % n], p3 = stops[(i + 2) % n]
            for step in 0..<40 {
                let t = CGFloat(step) / 40, t2 = t * t, t3 = t2 * t
                func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
                }
                points.append(CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        points.append(stops[0])
        var out: [(CGPoint, CGFloat)] = [(points[0], 0)], total: CGFloat = 0
        for i in 1..<points.count { total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y); out.append((points[i], total)) }
        return out.map { ($0.0, $0.1 / total) }
    }()

    static func point(at p: Double) -> CGPoint {
        let d = CGFloat(min(max(p, 0), 1))
        guard let i = samples.firstIndex(where: { $0.1 >= d }), i > 0 else { return samples[0].0 }
        let (a, da) = samples[i - 1], (b, db) = samples[i], f = db > da ? (d - da) / (db - da) : 0
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }
}

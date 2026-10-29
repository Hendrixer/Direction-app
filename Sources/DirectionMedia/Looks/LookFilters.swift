import Foundation
import CoreImage
import DirectionCore

/// The eleven filters of looks.md, from Core Image built-ins. Sizes are given at 1080p and scale with
/// the frame, so a 960-wide preview looks like the export. Tonal filters work on Rec. 709 values (the
/// look's working space); light-like ones (glows, softening) blend there too, which is how they read
/// on a monitor. Grain and Gate weave depend only on the frame index, so every render matches.
enum LookFilters {
    static let rec709 = CGColorSpace(name: CGColorSpace.itur_709)!

    static func apply(_ filter: LookFilter, _ image: CIImage, amount a: Double, option: String?, frameIndex: Int, in frame: CGRect) -> CIImage {
        let k = frame.height / 1080
        switch filter {
        case .blackAndWhite:
            // Red-weighted, like panchromatic stock behind a light yellow filter: skin stays bright.
            let w = (0.50, 0.40, 0.10), keep = 1 - a
            return working(matrix(signal(image),
                                  r: CIVector(x: keep + a * w.0, y: a * w.1, z: a * w.2, w: 0),
                                  g: CIVector(x: a * w.0, y: keep + a * w.1, z: a * w.2, w: 0),
                                  b: CIVector(x: a * w.0, y: a * w.1, z: keep + a * w.2, w: 0)))
        case .splitTone:
            // A color added to the shadows and another to the highlights, each weighted by a luminance
            // curve that's zero at black and white. Warm·Teal: warm highlights, teal shadows; Cool·Amber flips it.
            let warm = option != "coolAmber"
            let s: (Double, Double, Double) = warm ? (-0.07, 0.015, 0.06) : (0.07, 0.03, -0.06)
            let h: (Double, Double, Double) = warm ? (0.07, 0.02, -0.06) : (-0.05, 0.0, 0.07)
            let x = signal(image), y = luma(x)
            func tint(_ base: CIImage, _ c: (Double, Double, Double), _ weight: @escaping (Double) -> Double) -> CIImage {
                let tinted = matrix(base, r: CIVector(x: 1, y: 0, z: 0, w: 0), g: CIVector(x: 0, y: 1, z: 0, w: 0), b: CIVector(x: 0, y: 0, z: 1, w: 0), bias: CIVector(x: a * c.0, y: a * c.1, z: a * c.2, w: 0))
                return tinted.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base, kCIInputMaskImageKey: curve(y, weight)])
            }
            // Shadows peak at 0.2 and fade out by 0.6; highlights start at 0.4 and peak at 0.8.
            let shadows = tint(x, s) { l in l < 0.2 ? l / 0.2 : max(0, 1 - (l - 0.2) / 0.4) }
            return working(tint(shadows, h) { l in l > 0.8 ? (1 - l) / 0.2 : max(0, (l - 0.4) / 0.4) })
        case .fade:
            let lift = 0.16 * a
            return working(matrix(signal(image), r: CIVector(x: 1 - lift, y: 0, z: 0, w: 0), g: CIVector(x: 0, y: 1 - lift, z: 0, w: 0), b: CIVector(x: 0, y: 0, z: 1 - lift, w: 0), bias: CIVector(x: lift, y: lift, z: lift, w: 0)))
        case .halation:
            // Light that went through the emulsion and back off the base: red-orange, around highlights.
            return glow(image, threshold: 0.6, color: (1, 0.36, 0.12), sigma: 30 * k, strength: 1.3 * a, frame: frame)
        case .bloom:
            return glow(image, threshold: 0.55, color: (1, 1, 1), sigma: 32 * k, strength: 0.7 * a, frame: frame)
        case .soften:
            // A mist filter: highlights spread into what's around them; shadows are left alone.
            let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 18 * k).cropped(to: frame)
            let spread = blurred.applyingFilter("CILightenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            return image.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": spread, "inputTime": 0.65 * a])
        case .chromaticAberration:
            // Red grows and blue shrinks about the center, up to 4 px apart at the left and right edges.
            let shift = 4 * a * frame.width / 1920, half = frame.width / 2
            let src = image.clampedToExtent()
            func scaled(_ s: CGFloat) -> CIImage {
                src.transformed(by: CGAffineTransform(translationX: frame.midX, y: frame.midY).scaledBy(x: s, y: s).translatedBy(x: -frame.midX, y: -frame.midY))
            }
            // Each channel on white, then multiplied: (r,1,1)·(1,g,1)·(1,1,b), all opaque.
            let one = CIVector(x: 0, y: 0, z: 0, w: 0)
            let r = matrix(scaled(1 + shift / half), r: CIVector(x: 1, y: 0, z: 0, w: 0), g: one, b: one, bias: CIVector(x: 0, y: 1, z: 1, w: 0))
            let g = matrix(src, r: one, g: CIVector(x: 0, y: 1, z: 0, w: 0), b: one, bias: CIVector(x: 1, y: 0, z: 1, w: 0))
            let b = matrix(scaled(1 - shift / half), r: one, g: one, b: CIVector(x: 0, y: 0, z: 1, w: 0), bias: CIVector(x: 1, y: 1, z: 0, w: 0))
            return r.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: g])
                .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: b]).cropped(to: frame)
        case .vignette:
            return image.applyingFilter("CIVignetteEffect", parameters: [kCIInputCenterKey: CIVector(x: frame.midX, y: frame.midY), kCIInputRadiusKey: hypot(frame.width, frame.height) * 0.36, kCIInputIntensityKey: 0.9 * a, "inputFalloff": 0.6])
        case .grain:
            return grain(image, amount: a, size: option ?? "fine", frameIndex: frameIndex, frame: frame)
        case .gateWeave:
            // The drift of film in a projector gate: two slow sines a frame apart, never more than 0.6 px.
            let f = Double(frameIndex), px = 0.6 * a * k
            let dx = px * (0.6 * sin(f * 0.37) + 0.4 * sin(f * 0.113 + 1.3)), dy = px * (0.6 * sin(f * 0.29 + 0.7) + 0.4 * sin(f * 0.071 + 2.1))
            return image.clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: frame)
        case .letterbox:
            let ratio = Double(option ?? "2.39") ?? 2.39, picture = frame.width / ratio
            guard picture < frame.height else { return image }
            let bar = (frame.height - picture) / 2, black = CIImage(color: .black)
            return black.cropped(to: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bar))
                .composited(over: black.cropped(to: CGRect(x: frame.minX, y: frame.maxY - bar, width: frame.width, height: bar)))
                .composited(over: image)
        }
    }

    /// Grain: monochrome noise picks, pixel by pixel, between a lighter and a darker version of the picture.
    /// Both come from tone curves that move the midtones most and leave black and white alone, so the
    /// grain is luminance-weighted like film and the picture's average stays put. The noise is Core Image's
    /// fixed-seed generator moved by a whole-pixel offset from the frame index: new grain every frame,
    /// and the same grain every time that frame renders.
    private static func grain(_ image: CIImage, amount a: Double, size: String, frameIndex: Int, frame: CGRect) -> CIImage {
        let scale = (size == "coarse" ? 2.6 : size == "medium" ? 1.7 : 1.0) * frame.height / 1080
        let seed = UInt64(bitPattern: Int64(frameIndex)) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let ox = CGFloat((seed >> 33) % 4096), oy = CGFloat((seed >> 17) % 4096)
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        // The generator's alpha is random too; reading the noise from it avoids unpremultiplying the color.
        let one = CIVector(x: 0, y: 0, z: 0, w: 1)
        let noise = matrix(random.transformed(by: CGAffineTransform(translationX: -ox, y: -oy)), r: one, g: one, b: one, a: CIVector(x: 0, y: 0, z: 0, w: 0), bias: CIVector(x: 0, y: 0, z: 0, w: 1))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)).transformed(by: CGAffineTransform(translationX: frame.minX, y: frame.minY)).cropped(to: frame)
        let x = signal(image), d = 0.16 * a
        let lighter = curve(x) { $0 + d * 4 * $0 * (1 - $0) }, darker = curve(x) { $0 - d * 4 * $0 * (1 - $0) }
        return working(lighter.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: darker, kCIInputMaskImageKey: noise]))
    }

    /// Highlights above a threshold, tinted, blurred and screened back over the picture.
    private static func glow(_ image: CIImage, threshold t: Double, color: (Double, Double, Double), sigma: Double, strength: Double, frame: CGRect) -> CIImage {
        let x = signal(image), gain = 1 / (1 - t)
        let w = (0.2126 * gain, 0.7152 * gain, 0.0722 * gain)
        func row(_ c: Double) -> CIVector { CIVector(x: w.0 * c * strength, y: w.1 * c * strength, z: w.2 * c * strength, w: 0) }
        let bias = CIVector(x: -t * gain * color.0 * strength, y: -t * gain * color.1 * strength, z: -t * gain * color.2 * strength, w: 0)
        let highlights = matrix(x, r: row(color.0), g: row(color.1), b: row(color.2), bias: bias).applyingFilter("CIColorClamp")
        let spread = highlights.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: frame)
        return working(spread.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: x]))
    }

    // MARK: Helpers

    static func signal(_ image: CIImage) -> CIImage { image.matchedFromWorkingSpace(to: rec709) ?? image }
    static func working(_ image: CIImage) -> CIImage { image.matchedToWorkingSpace(from: rec709) ?? image }
    static func matrix(_ image: CIImage, r: CIVector, g: CIVector, b: CIVector, a: CIVector = CIVector(x: 0, y: 0, z: 0, w: 1), bias: CIVector = CIVector(x: 0, y: 0, z: 0, w: 0)) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": r, "inputGVector": g, "inputBVector": b, "inputAVector": a, "inputBiasVector": bias])
    }
    /// Rec. 709 luma in every channel, opaque.
    static func luma(_ image: CIImage) -> CIImage {
        let w = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        return matrix(image, r: w, g: w, b: w)
    }
    /// The same curve on every channel, on the numbers as they are. CIToneCurve would color-manage
    /// them first; CIColorCurves in the working space doesn't.
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    static func curve(_ image: CIImage, _ f: (Double) -> Double) -> CIImage {
        let table = (0..<65).flatMap { i -> [Float] in let v = Float(f(Double(i) / 64)); return [v, v, v] }
        return image.applyingFilter("CIColorCurves", parameters: ["inputCurvesData": table.withUnsafeBufferPointer { Data(buffer: $0) }, "inputCurvesDomain": CIVector(x: 0, y: 1), "inputColorSpace": workingSpace])
    }
}

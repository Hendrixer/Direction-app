import Foundation
import CoreImage
import Synchronization
import DirectionCore

/// One clip's picture at one frame (agent-timeline.md › What Direction renders): stabilize, camera LUT and
/// balance, crop and placement (or a pin into four corners), then its other effects in order (limited by
/// any mask), opacity and the dissolves and dips at its cuts. Preview, direction_frame and export all come
/// through here; transitions drawn from both shots happen where the track is composited.
enum ClipRendering {
    static func render(_ l: RenderLayer, source: CIImage, t: Double, frameIndex: Int, bounds: CGRect, scale: CGFloat) -> CIImage {
        let c = l.clip
        let s = c.hold != nil ? c.sourceRange.start.seconds : c.sourceRange.start.seconds + (t - c.start.seconds) * c.speed
        // Keys play on over a held frame (a freeze that pushes in), while the picture stays the one frame.
        let k = c.hold != nil ? c.sourceRange.start.seconds + (t - c.start.seconds) * c.speed : s
        var image = source.transformed(by: l.transform)
        let e0 = image.extent
        guard e0.width > 0, e0.height > 0, e0.width.isFinite, e0.height.isFinite else { return .empty() }
        image = image.transformed(by: .init(translationX: -e0.minX, y: -e0.minY))
        let w = e0.width, h = e0.height, frame = CGRect(x: 0, y: 0, width: w, height: h)
        let effects = c.effects ?? []
        if let st = effects.first(where: { $0.name == "stabilize" }) {
            // Corrections are fractions of the frame (y down); a little zoom hides the moving edges.
            let amount = st.number("amount", at: nil, default: 0.5)
            let dx = amount * st.number("dx", at: s, default: 0) * w, dy = amount * st.number("dy", at: s, default: 0) * h
            let rot = -amount * st.number("rotation", at: s, default: 0) * .pi / 180
            let reach = ((st.keys?["dx"] ?? []) + (st.keys?["dy"] ?? [])).map { abs($0.v) }.max() ?? 0
            let zoom = min(1.25, 1 + 2 * amount * reach)
            let move = CGAffineTransform(translationX: -w / 2, y: -h / 2).concatenating(.init(rotationAngle: rot)).concatenating(.init(scaleX: zoom, y: zoom)).concatenating(.init(translationX: w / 2 + dx, y: h / 2 - dy))
            image = image.clampedToExtent().transformed(by: move).cropped(to: frame)
        }
        if let lut = l.lut { image = lut.apply(image) }
        let g = l.grade
        if g.exposure != 0 { image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": g.exposure]) }
        if g.temperature != 0 || g.tint != 0 { image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + g.temperature, y: g.tint)]) }
        if g.contrast != 1 || g.saturation != 1 { image = image.applyingFilter("CIColorControls", parameters: ["inputContrast": g.contrast, "inputSaturation": g.saturation]) }

        // Crop keeps the picture where it was; placement fits it to the frame, then the transform moves it.
        let tr = effects.first { $0.name == "transform" }
        let cl = tr?.number("crop.l", at: k, default: 0) ?? 0, cr = tr?.number("crop.r", at: k, default: 0) ?? 0
        let ct = tr?.number("crop.t", at: k, default: 0) ?? 0, cb = tr?.number("crop.b", at: k, default: 0) ?? 0
        if cl + cr + ct + cb > 0 { image = image.cropped(to: CGRect(x: cl * w, y: cb * h, width: max(1, w * (1 - cl - cr)), height: max(1, h * (1 - ct - cb)))) }
        let f = l.framing
        if let pin = effects.first(where: { $0.name == "pin" }) {
            // Pinned: the whole picture goes into four corners of the frame, in perspective.
            let e = image.extent
            image = image.transformed(by: .init(translationX: -e.minX, y: -e.minY))
            func corner(_ name: String, _ x: Double, _ y: Double) -> CIVector {
                CIVector(x: bounds.minX + pin.number(name + ".x", at: k, default: x) * bounds.width, y: bounds.maxY - pin.number(name + ".y", at: k, default: y) * bounds.height)
            }
            image = image.applyingFilter("CIPerspectiveTransform", parameters: ["inputTopLeft": corner("tl", 0, 0), "inputTopRight": corner("tr", 1, 0), "inputBottomRight": corner("br", 1, 1), "inputBottomLeft": corner("bl", 0, 1)])
        } else {
            let ts = tr?.number("scale", at: k, default: 1) ?? 1, tx = tr?.number("x", at: k, default: 0) ?? 0, ty = tr?.number("y", at: k, default: 0) ?? 0
            let rotation = tr?.number("rotation", at: k, default: 0) ?? 0
            let ratio = (f.fit ? min(bounds.width / w, bounds.height / h) : max(bounds.width / w, bounds.height / h)) * f.scale * ts
            image = image.transformed(by: .init(scaleX: ratio, y: ratio))
            let ox = (bounds.width - w * ratio) / 2 + (f.offsetX + tx) * bounds.width, oy = (bounds.height - h * ratio) / 2 - (f.offsetY + ty) * bounds.height
            image = image.transformed(by: .init(translationX: bounds.minX + ox, y: bounds.minY + oy))
            if rotation != 0 {
                let cx = bounds.minX + ox + w * ratio / 2, cy = bounds.minY + oy + h * ratio / 2
                image = image.transformed(by: CGAffineTransform(translationX: -cx, y: -cy).concatenating(.init(rotationAngle: -rotation * .pi / 180)).concatenating(.init(translationX: cx, y: cy)))
            }
        }
        image = apply(effects, to: image.cropped(to: bounds), at: k, frameIndex: frameIndex, bounds: bounds, scale: scale)

        var alpha = f.opacity * (tr?.number("opacity", at: k, default: 1) ?? 1)
        var dip: (amount: Double, white: Bool)?
        if let tin = c.transition {
            let cut = c.start.seconds
            if tin.type == "dissolve" { let span = tin.before + tin.after; if span > 0 && t < cut + tin.after { alpha *= min(1, max(0, (t - (cut - tin.before)) / span)) } }
            else if tin.isDip && tin.after > 0 && t >= cut - 1e-9 && t < cut + tin.after { dip = (1 - (t - cut) / tin.after, tin.type == "dipToWhite") }
        }
        if let tout = l.outgoing, tout.isDip, tout.before > 0 {
            let cut = c.end.seconds
            if t >= cut - tout.before && t < cut { dip = ((t - (cut - tout.before)) / tout.before, tout.type == "dipToWhite") }
        }
        if alpha < 1 { image = opacity(image, max(0, alpha)) }
        if let dip, dip.amount > 0 {
            let v = dip.white ? 1.0 : 0.0
            image = CIImage(color: CIColor(red: v, green: v, blue: v, alpha: min(1, dip.amount))).cropped(to: bounds).applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: image])
        }
        return image.cropped(to: bounds)
    }

    /// How far through a transition drawn from both shots a frame is, 0–1, or nil outside it.
    static func progress(_ tr: ClipTransition, cut: Double, t: Double) -> Double? {
        guard tr.source != nil, !tr.isDip else { return nil }
        let span = tr.before + tr.after, start = cut - tr.before
        guard span > 0, t >= start - 1e-9, t < cut + tr.after - 1e-9 else { return nil }
        return min(1, max(0, (t - start) / span))
    }

    static func opacity(_ image: CIImage, _ a: Double) -> CIImage { image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)]) }

    /// Blur, sharpen, per-clip filters and shaders, in order, limited to the union of any masks.
    /// `t` is source seconds for a clip's keys, cut seconds for a track's.
    static func apply(_ effects: [ClipEffect], to image: CIImage, at t: Double?, frameIndex: Int, bounds: CGRect, scale: CGFloat) -> CIImage {
        guard effects.contains(where: { !["transform", "stabilize", "mask"].contains($0.name) }) else { return image }
        let plain = image
        var out = image
        for e in effects {
            switch e.name {
            case "blur":
                let r = e.number("radius", at: t, default: 0) * scale
                if r > 0.01 { out = out.clampedToExtent().applyingGaussianBlur(sigma: r).cropped(to: image.extent) }
            case "sharpen":
                let a = e.number("amount", at: nil, default: 0)
                if a > 0 { out = out.applyingFilter("CIUnsharpMask", parameters: ["inputRadius": 2.5 * scale, "inputIntensity": a * 1.5]).cropped(to: image.extent) }
            case "shader": out = ShaderEffect.apply(out.cropped(to: bounds), effect: e, at: t)
            case let name where name.hasPrefix("filter."):
                out = LookPipeline.filter(out, kind: String(name.dropFirst(7)), amount: e.number("amount", at: t, default: 0.5), option: e.params["option"]?.string, frameIndex: frameIndex)
            default: break
            }
        }
        let masks = effects.filter { $0.name == "mask" }.map { mask($0, at: t, bounds: bounds) }
        guard let first = masks.first else { return out.cropped(to: bounds) }
        let m = masks.dropFirst().reduce(first) { $1.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]) }
        return out.cropped(to: bounds).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: plain, "inputMaskImage": m]).cropped(to: bounds)
    }

    /// A white shape on black over the frame. x y w h are fractions of the frame from its top left.
    static func mask(_ e: ClipEffect, at t: Double?, bounds: CGRect) -> CIImage {
        let x = e.number("x", at: t, default: 0.25), y = e.number("y", at: t, default: 0.25), w = e.number("w", at: t, default: 0.5), h = e.number("h", at: t, default: 0.5)
        let rect = CGRect(x: bounds.minX + x * bounds.width, y: bounds.maxY - (y + h) * bounds.height, width: max(1, w * bounds.width), height: max(1, h * bounds.height))
        let black = CIImage(color: .black).cropped(to: bounds)
        var shape: CIImage
        if e.params["shape"]?.string == "ellipse" {
            let disc = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 99.5, "inputRadius1": 100, "inputColor0": CIColor.white, "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)])!.outputImage!.cropped(to: CGRect(x: -100, y: -100, width: 200, height: 200))
            shape = disc.transformed(by: CGAffineTransform(scaleX: rect.width / 200, y: rect.height / 200).concatenating(.init(translationX: rect.midX, y: rect.midY)))
        } else { shape = CIImage(color: .white).cropped(to: rect) }
        var m = shape.composited(over: black)
        let feather = e.number("feather", at: t, default: 0.05) * min(bounds.width, bounds.height) / 2
        if feather > 0.5 { m = m.clampedToExtent().applyingGaussianBlur(sigma: feather).cropped(to: bounds) }
        if e.params["invert"]?.bool == true { m = m.applyingFilter("CIColorInvert") }
        return m
    }

    static func blend(_ top: CIImage, over bottom: CIImage, mode: String) -> CIImage {
        guard let name = ["screen": "CIScreenBlendMode", "multiply": "CIMultiplyBlendMode", "overlay": "CIOverlayBlendMode", "add": "CIAdditionCompositing"][mode] else { return top.composited(over: bottom) }
        return top.applyingFilter(name, parameters: [kCIInputBackgroundImageKey: bottom])
    }
}

/// A camera LUT from a .cube file (looks.md › LUT files), applied in Rec. 709 with CIColorCubeWithColorSpace.
/// 1D files become a 33-point cube. Files that don't read are skipped.
struct CameraLUTFile: @unchecked Sendable {
    let dimension: Int
    let data: Data
    static let cache = Mutex<[String: CameraLUTFile]>([:])
    static let space = CGColorSpace(name: CGColorSpace.itur_709)!

    static func load(_ path: String) -> CameraLUTFile? {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(path)|\(modified)"
        if let hit = cache.withLock({ $0[key] }) { return hit }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), let lut = parse(text) else { return nil }
        cache.withLock { $0[key] = lut }
        return lut
    }

    static func parse(_ text: String) -> CameraLUTFile? {
        var size3 = 0, size1 = 0, values: [Float] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ")
            if parts[0] == "LUT_3D_SIZE", parts.count > 1 { size3 = Int(parts[1]) ?? 0; continue }
            if parts[0] == "LUT_1D_SIZE", parts.count > 1 { size1 = Int(parts[1]) ?? 0; continue }
            if let first = parts.first, Float(first) == nil { continue }
            guard parts.count >= 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else { return nil }
            values += [r, g, b].map { min(1, max(0, $0)) }
        }
        var cube: [Float] = []
        let n: Int
        if size3 > 0 {
            guard (2...65).contains(size3), values.count == size3 * size3 * size3 * 3 else { return nil }
            n = size3
            for i in 0..<(n * n * n) { cube += [values[i * 3], values[i * 3 + 1], values[i * 3 + 2], 1] }
        } else if size1 > 1 {
            guard values.count == size1 * 3 else { return nil }
            n = 33
            func curve(_ channel: Int, _ x: Float) -> Float { let p = x * Float(size1 - 1), i = min(size1 - 2, Int(p)), f = p - Float(i); return values[i * 3 + channel] * (1 - f) + values[(i + 1) * 3 + channel] * f }
            for b in 0..<n { for g in 0..<n { for r in 0..<n { cube += [curve(0, Float(r) / 32), curve(1, Float(g) / 32), curve(2, Float(b) / 32), 1] } } }
        } else { return nil }
        return CameraLUTFile(dimension: n, data: cube.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    func apply(_ image: CIImage) -> CIImage { image.applyingFilter("CIColorCubeWithColorSpace", parameters: ["inputCubeDimension": dimension, "inputCubeData": data, "inputColorSpace": Self.space]) }
}

/// A clip's volume over time (agent-timeline.md › What Direction renders): stream gain, clip gain and
/// keys, track gain and keys, ducking, then fades, as ramps AVFoundation can play.
enum AudioEnvelope {
    struct Point { var t: Double; var gain: Float }

    static func points(clip: Clip, streamDB: Double, streamFadeIn: Double, streamFadeOut: Double, track: TrackSettings?, from a: Double, to b: Double) -> [Point] {
        guard b > a else { return [] }
        let fadeIn = min(max(clip.fadeIn ?? 0, streamFadeIn), (b - a) / 2), fadeOut = min(max(clip.fadeOut ?? 0, streamFadeOut), (b - a) / 2)
        func source(_ t: Double) -> Double { clip.sourceRange.start.seconds + (t - clip.start.seconds) * clip.speed }
        func cut(_ s: Double) -> Double { clip.start.seconds + (s - clip.sourceRange.start.seconds) / clip.speed }
        func dB(_ t: Double) -> Double {
            streamDB + (clip.gainDB ?? 0) + (clip.gainKeys.flatMap { Keyframe.value($0, at: source(t)) } ?? 0) + (clip.duckKeys.flatMap { Keyframe.value($0, at: source(t)) } ?? 0)
                + (track?.gainDB ?? 0) + (track?.gainKeys.flatMap { Keyframe.value($0, at: t) } ?? 0)
        }
        func amplitude(_ t: Double) -> Float {
            var g = pow(10, dB(t) / 20)
            if fadeIn > 0 && t < a + fadeIn { g *= max(0, (t - a) / fadeIn) }
            if fadeOut > 0 && t > b - fadeOut { g *= max(0, (b - t) / fadeOut) }
            return Float(max(0, g))
        }
        var times = Set([a, b, a + fadeIn, b - fadeOut])
        for k in (clip.gainKeys ?? []) + (clip.duckKeys ?? []) { times.insert(cut(k.t)) }
        for k in track?.gainKeys ?? [] { times.insert(k.t) }
        let marks = times.filter { $0 >= a - 1e-9 && $0 <= b + 1e-9 }.sorted()
        // Keys change in dB but ramps are linear in amplitude, so big changes get more points.
        var out: [Double] = []
        for (x, y) in zip(marks, marks.dropFirst()) where y - x > 1e-6 {
            out.append(x)
            let n = min(40, Int(abs(dB(y) - dB(x))))
            if n > 1 { for k in 1..<n { out.append(x + (y - x) * Double(k) / Double(n)) } }
        }
        out.append(marks.last ?? b)
        return out.map { Point(t: $0, gain: amplitude($0)) }
    }
}

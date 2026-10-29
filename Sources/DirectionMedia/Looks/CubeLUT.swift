import Foundation
import simd
import DirectionCore

/// A `.cube` LUT (Adobe Cube 1.0, as Resolve, Premiere and Final Cut write it), validated the way
/// looks.md asks: 1D or 3D, size 17–65, a sane domain, and every value inside 0–1.
public struct CubeLUT: Sendable, Hashable {
    public enum Kind: String, Sendable { case oneD = "1D", threeD = "3D" }
    public var title: String?
    public var kind: Kind
    public var size: Int
    public var domainMin: SIMD3<Float>
    public var domainMax: SIMD3<Float>
    /// RGB triples in file order: red changes fastest, then green, then blue.
    public var values: [SIMD3<Float>]

    public static let sizes = 17...65
    /// Float noise a little past 0 or 1 is common in exported LUTs; it's clamped, not refused.
    static let tolerance: Float = 1e-4

    public init(title: String? = nil, kind: Kind = .threeD, size: Int, domainMin: SIMD3<Float> = .zero, domainMax: SIMD3<Float> = .one, values: [SIMD3<Float>]) {
        self.title = title; self.kind = kind; self.size = size; self.domainMin = domainMin; self.domainMax = domainMax; self.values = values
    }

    static func invalid(_ reason: String) -> DirectionError { DirectionError("lut_invalid", "Can't read this LUT: \(reason)") }

    public static func load(_ url: URL) throws -> CubeLUT {
        guard let data = FileManager.default.contents(atPath: url.path) else { throw DirectionError("lut_not_found", "There's no LUT at \(url.path).") }
        guard data.count <= 64 << 20 else { throw invalid("the file is larger than 64 MB.") }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw invalid("it isn't text.") }
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> CubeLUT {
        var title: String?, kind: Kind?, size = 0
        var lo = SIMD3<Float>(repeating: 0), hi = SIMD3<Float>(repeating: 1)
        var values: [SIMD3<Float>] = []
        func triple(_ parts: [Substring], line: Int) throws -> SIMD3<Float> {
            guard parts.count == 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]), r.isFinite, g.isFinite, b.isFinite else { throw invalid("line \(line) isn't three numbers.") }
            return SIMD3(r, g, b)
        }
        for (i, raw) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let line = i + 1
            let content = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard !content.isEmpty else { continue }
            let parts = content.split(whereSeparator: \.isWhitespace)
            let keyword = String(parts[0])
            if let first = keyword.unicodeScalars.first, CharacterSet.letters.contains(first) {
                guard values.isEmpty else { throw invalid("line \(line): \(keyword) comes after the table.") }
                let rest = Array(parts.dropFirst())
                switch keyword {
                case "TITLE": title = content.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                case "LUT_1D_SIZE", "LUT_3D_SIZE":
                    guard kind == nil else { throw invalid("it declares both a 1D and a 3D size.") }
                    guard rest.count == 1, let n = Int(rest[0]) else { throw invalid("line \(line): \(keyword) needs one whole number.") }
                    kind = keyword == "LUT_1D_SIZE" ? .oneD : .threeD; size = n
                case "DOMAIN_MIN": lo = try triple(rest, line: line)
                case "DOMAIN_MAX": hi = try triple(rest, line: line)
                // Resolve's older form: one range for all three channels.
                case "LUT_1D_INPUT_RANGE", "LUT_3D_INPUT_RANGE":
                    guard rest.count == 2, let a = Float(rest[0]), let b = Float(rest[1]), a.isFinite, b.isFinite else { throw invalid("line \(line): \(keyword) needs two numbers.") }
                    lo = SIMD3(repeating: a); hi = SIMD3(repeating: b)
                // Other keywords (LUT_IN_VIDEO_RANGE…) don't change how the table maps color.
                default: continue
                }
                continue
            }
            let v = try triple(parts, line: line)
            guard v.min() >= -tolerance, v.max() <= 1 + tolerance else { throw invalid("line \(line) has a value outside 0–1.") }
            values.append(simd_clamp(v, .zero, .one))
        }
        guard let kind else { throw invalid("it has no LUT_3D_SIZE or LUT_1D_SIZE.") }
        guard sizes.contains(size) else { throw invalid("size \(size) is outside 17–65.") }
        let expected = kind == .threeD ? size * size * size : size
        guard values.count == expected else { throw invalid("a \(size)-point \(kind.rawValue) LUT has \(expected) values; this one has \(values.count).") }
        guard all(lo .< hi) else { throw invalid("DOMAIN_MIN must be below DOMAIN_MAX.") }
        return CubeLUT(title: title, kind: kind, size: size, domainMin: lo, domainMax: hi, values: values)
    }

    /// A LUT that changes nothing.
    public static func identity(size: Int = 33, kind: Kind = .threeD) -> CubeLUT {
        make(size: size, kind: kind) { $0 }
    }
    /// Builds a LUT by evaluating `transform` at every lattice point (0–1 in, clamped 0–1 out).
    public static func make(size: Int = 33, kind: Kind = .threeD, title: String? = nil, _ transform: (SIMD3<Float>) -> SIMD3<Float>) -> CubeLUT {
        let step = 1 / Float(size - 1)
        var values: [SIMD3<Float>] = []
        if kind == .oneD {
            values = (0..<size).map { i in simd_clamp(transform(SIMD3(repeating: Float(i) * step)), .zero, .one) }
        } else {
            values.reserveCapacity(size * size * size)
            for b in 0..<size { for g in 0..<size { for r in 0..<size {
                values.append(simd_clamp(transform(SIMD3(Float(r), Float(g), Float(b)) * step), .zero, .one))
            } } }
        }
        return CubeLUT(title: title, kind: kind, size: size, values: values)
    }

    /// The color this LUT gives an input color, with the domain and trilinear (or per-channel linear) interpolation.
    public func sample(_ color: SIMD3<Float>) -> SIMD3<Float> {
        let unit = simd_clamp((color - domainMin) / (domainMax - domainMin), .zero, .one) * Float(size - 1)
        if kind == .oneD {
            let i0 = SIMD3<Int>(Int(unit.x), Int(unit.y), Int(unit.z)), f = unit - SIMD3(Float(i0.x), Float(i0.y), Float(i0.z))
            var out = SIMD3<Float>()
            for c in 0..<3 { let a = values[i0[c]][c], b = values[min(size - 1, i0[c] + 1)][c]; out[c] = a + (b - a) * f[c] }
            return out
        }
        let i0 = SIMD3<Int>(Int(unit.x), Int(unit.y), Int(unit.z)), i1 = simd_min(i0 &+ 1, SIMD3(repeating: size - 1))
        let f = unit - SIMD3(Float(i0.x), Float(i0.y), Float(i0.z))
        func v(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> { values[r + size * (g + size * b)] }
        let c00 = simd_mix(v(i0.x, i0.y, i0.z), v(i1.x, i0.y, i0.z), SIMD3(repeating: f.x)), c10 = simd_mix(v(i0.x, i1.y, i0.z), v(i1.x, i1.y, i0.z), SIMD3(repeating: f.x))
        let c01 = simd_mix(v(i0.x, i0.y, i1.z), v(i1.x, i0.y, i1.z), SIMD3(repeating: f.x)), c11 = simd_mix(v(i0.x, i1.y, i1.z), v(i1.x, i1.y, i1.z), SIMD3(repeating: f.x))
        return simd_mix(simd_mix(c00, c10, SIMD3(repeating: f.y)), simd_mix(c01, c11, SIMD3(repeating: f.y)), SIMD3(repeating: f.z))
    }

    /// RGBA float32 data for `CIColorCubeWithColorSpace`. A 1D LUT, or a 3D one with a domain other than
    /// 0–1, is resampled into a plain 3D cube of its own size, so one filter covers every case.
    public func cubeData() -> (dimension: Int, data: Data) {
        let plain = kind == .threeD && domainMin == .zero && domainMax == .one
        var floats = [Float](); floats.reserveCapacity(size * size * size * 4)
        let step = 1 / Float(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let v = plain ? values[r + size * (g + size * b)] : sample(SIMD3(Float(r), Float(g), Float(b)) * step)
            floats += [v.x, v.y, v.z, 1]
        } } }
        return (size, floats.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    /// The file's text, for looks the editor makes.
    public var text: String {
        var out = ""
        if let title { out += "TITLE \"\(title.replacingOccurrences(of: "\"", with: "'"))\"\n" }
        out += "\(kind == .threeD ? "LUT_3D_SIZE" : "LUT_1D_SIZE") \(size)\n"
        if domainMin != .zero || domainMax != .one {
            out += "DOMAIN_MIN \(domainMin.x) \(domainMin.y) \(domainMin.z)\nDOMAIN_MAX \(domainMax.x) \(domainMax.y) \(domainMax.z)\n"
        }
        for v in values { out += String(format: "%.6f %.6f %.6f\n", v.x, v.y, v.z) }
        return out
    }
}

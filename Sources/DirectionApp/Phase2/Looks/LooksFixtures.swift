import SwiftUI
import CoreImage
import simd
import DirectionCore
import DirectionMedia

/// Frame 63 from real views and the real look pipeline. The looks are LUTs made here from the
/// frame's CSS (sepia, saturate, contrast… then the tint layer), written to a temporary folder.
@MainActor
enum LooksFixtures {
    static var frames: [String: () -> SnapshotScene] {
        ["63-look": { .film(lookSheet()) }]
    }

    /// Screening paused on Cut 4 at 01:20:00 (scene 3, The ridge), the sheet open on the editor's
    /// "Window light": Halation 30%, Vignette 20%, Grain 40% Fine. The film has no look yet.
    static func lookSheet() -> FilmModel {
        let m = SampleFilm.make(room: .screening)
        SampleFilm.withCut4(m)
        m.notes = []
        m.position = SampleFilm.tc(1, 20, 0)
        m.playing = false
        m.screeningStartedAt = Date()
        let l = m.looks
        l.groups = groups
        l.look = FilmLook()
        let stills = m.stripScenes.prefix(5).map { s in LooksModel.Still(id: s.id, label: s.label, frame: frame(s.art, width: 276, frameIndex: Int(s.start * 24))) }
        l.setFrames(current: frame(.dusk, width: 1440, frameIndex: Int(m.position * 24)), stills: Array(stills))
        l.applyTo = nil
        l.select(groups[0].looks[0])
        m.sheet = .look
        l.renderTiles(sync: true); l.renderDraft(sync: true)
        return m
    }

    // MARK: Looks

    static var groups: [LookGroup] {
        let editor = [
            look("Window light", by: "editor", [.sepia(0.3), .saturate(1.15), .contrast(0.9), .brightness(1.06)], screen: (amber, 0.1), filters: windowFilters),
            look("Window light, warmer", by: "editor", [.sepia(0.5), .saturate(1.45), .hueRotate(-4), .contrast(0.9), .brightness(1.08)], screen: (amber, 0.14), filters: windowFilters),
        ]
        let folder = [
            look("Print film", by: "folder", [.contrast(1.25), .saturate(0.9), .brightness(0.9)]),
            look("Soft stock", by: "folder", [.sepia(0.12), .contrast(0.72), .saturate(0.85), .brightness(1.16)], screen: (amber, 0.08)),
            look("Bleach bypass", by: "folder", [.saturate(0.28), .contrast(1.45), .brightness(0.94)]),
            look("Teal & amber", by: "folder", [.saturate(1.25), .contrast(1.08)], split: true),
            look("Muted", by: "folder", [.saturate(0.38), .contrast(0.92), .brightness(0.86)]),
        ]
        return [LookGroup(name: LooksLibrary.editorGroup, looks: editor), LookGroup(name: LooksLibrary.folderGroup, looks: folder)]
    }
    static let windowFilters: (filters: [String: Double], options: [String: String]) = (["halation": 0.3, "vignette": 0.2, "grain": 0.4], ["grain": "fine"])

    enum Op { case sepia(Double), saturate(Double), hueRotate(Double), contrast(Double), brightness(Double) }
    static let amber = rgb(0.80, 0.15, 55), teal = rgb(0.75, 0.14, 200)
    static func rgb(_ l: Double, _ c: Double, _ h: Double) -> SIMD3<Double> { let v = GateColorSpace.sRGB(lightness: l, chroma: c, hue: h); return SIMD3(v.red, v.green, v.blue) }

    private static func look(_ name: String, by: String, _ ops: [Op], screen: (SIMD3<Double>, Double)? = nil, split: Bool = false, filters: (filters: [String: Double], options: [String: String]) = ([:], [:])) -> LookEntry {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-look-fixtures")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name + ".cube")
        if !FileManager.default.fileExists(atPath: url.path) {
            let cube = CubeLUT.make(size: 25, title: name) { v in SIMD3<Float>(css(SIMD3<Double>(v), ops, screen: screen, split: split)) }
            try? cube.text.write(to: url, atomically: true, encoding: .utf8)
        }
        let settings = LookSettings(name: name, lut: url.path, filters: filters.filters, options: filters.options, by: by)
        return LookEntry(name: name, path: url.path, group: by == "editor" ? LooksLibrary.editorGroup : LooksLibrary.folderGroup, settings: settings)
    }

    /// CSS filter functions on sRGB values, then the tint layer (screen, or `color` by luminance for Teal & amber).
    private static func css(_ input: SIMD3<Double>, _ ops: [Op], screen: (SIMD3<Double>, Double)?, split: Bool) -> SIMD3<Double> {
        var v = input
        for op in ops {
            switch op {
            case .sepia(let s):
                let k = 1 - s
                v = SIMD3(simd_dot(v, SIMD3(0.393 + 0.607 * k, 0.769 - 0.769 * k, 0.189 - 0.189 * k)), simd_dot(v, SIMD3(0.349 - 0.349 * k, 0.686 + 0.314 * k, 0.168 - 0.168 * k)), simd_dot(v, SIMD3(0.272 - 0.272 * k, 0.534 - 0.534 * k, 0.131 + 0.869 * k)))
            case .saturate(let s):
                v = SIMD3(simd_dot(v, SIMD3(0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s)), simd_dot(v, SIMD3(0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s)), simd_dot(v, SIMD3(0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s)))
            case .hueRotate(let deg):
                let a = deg * .pi / 180, c = cos(a), s = sin(a)
                v = SIMD3(simd_dot(v, SIMD3(0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928)), simd_dot(v, SIMD3(0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283)), simd_dot(v, SIMD3(0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072)))
            case .contrast(let c): v = (v - 0.5) * c + 0.5
            case .brightness(let b): v *= b
            }
            v = simd_clamp(v, .zero, .one)
        }
        if let (color, alpha) = screen { v = v + (SIMD3(repeating: 1) - (SIMD3(repeating: 1) - v) * (SIMD3(repeating: 1) - color) - v) * alpha }
        if split {
            let lum = simd_dot(v, SIMD3(0.3, 0.59, 0.11))
            let t = min(1, max(0, (lum - 0.3) / 0.3)), color = teal + (amber - teal) * t, alpha = 0.65 + (0.42 - 0.65) * t
            var c = color + SIMD3(repeating: lum - simd_dot(color, SIMD3(0.3, 0.59, 0.11)))
            let l = simd_dot(c, SIMD3(0.3, 0.59, 0.11)), lo = c.min(), hi = c.max()
            if lo < 0 { c = SIMD3(repeating: l) + (c - l) * l / (l - lo) }
            if hi > 1 { c = SIMD3(repeating: l) + (c - l) * (1 - l) / (hi - l) }
            v = v + (c - v) * alpha
        }
        return simd_clamp(v, .zero, .one)
    }

    // MARK: Frames

    /// A footage stand-in drawn at the size the sheet shows it, as a picture the pipeline can take.
    static func frame(_ art: FootageArt, width: CGFloat, frameIndex: Int) -> LooksModel.Frame {
        let renderer = ImageRenderer(content: FootageArtView(art: art).frame(width: width, height: width * 9 / 16))
        renderer.scale = 1
        let image = renderer.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: width, height: width * 9 / 16))
        return LooksModel.Frame(image: image, frameIndex: frameIndex)
    }
}

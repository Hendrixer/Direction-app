import Foundation
import SwiftUI

/// Gate tokens. Mirrors design/spec/tokens.json and design/spec/gate.css; CSS px are points.
enum Gate {
    enum Steel {
        static let ramp: [Color] = [
            Color(oklch: 0, 0, 0),
            Color(oklch: 0.13, 0.003, 265),
            Color(oklch: 0.165, 0.004, 265),
            Color(oklch: 0.20, 0.005, 265),
            Color(oklch: 0.245, 0.006, 265),
            Color(oklch: 0.295, 0.007, 265),
            Color(oklch: 0.43, 0.008, 265),
            Color(oklch: 0.58, 0.008, 265),
            Color(oklch: 0.76, 0.006, 265),
            Color(oklch: 0.96, 0.003, 265),
        ]
    }

    enum Surface {
        /// Behind picture.
        static let canvas = Steel.ramp[0]
        /// Inputs, wells.
        static let sunken = Steel.ramp[1]
        /// Window background, sheets, sidebars.
        static let ground = Steel.ramp[2]
        /// Cards, selected rows, popovers.
        static let panel = Steel.ramp[3]
        /// Buttons, chips, selected segment.
        static let raised = Steel.ramp[4]
        static let hover = Steel.ramp[5]
        static let scrim = Color.black.opacity(0.55)
    }

    enum Text {
        static let primary = Steel.ramp[9]
        static let secondary = Steel.ramp[8]
        static let tertiary = Steel.ramp[7]
        static let disabled = Steel.ramp[6]
    }

    enum Line {
        static let subtle = Color.white.opacity(0.08)
        static let strong = Color.white.opacity(0.15)
    }

    enum Voice {
        /// The director's acts only: marks, note numbers, circles, ranges, regions.
        static let director = Color(oklch: 0.82, 0.13, 72)
        static let directorInk = Color(oklch: 0.26, 0.06, 60)
        static let directorWash = Color(oklch: 0.82, 0.13, 72, opacity: 0.15)
        /// Editor text and solid diamonds.
        static let agent = Color(oklch: 0.78, 0.11, 250)
        static let agentWash = Color(oklch: 0.78, 0.11, 250, opacity: 0.13)
        static let prismStops = [
            Color(oklch: 0.82, 0.12, 200),
            Color(oklch: 0.70, 0.16, 268),
            Color(oklch: 0.72, 0.20, 330),
            Color(oklch: 0.84, 0.13, 62),
        ]
        /// Editor hairlines (≤ 2 pt), diamonds, shimmer and sweep. Never a fill behind text.
        static let prism = LinearGradient(
            stops: zip(prismStops, [0.0, 0.34, 0.66, 1.0]).map { .init(color: $0, location: $1) },
            startPoint: .init(x: 0, y: 0.412), endPoint: .init(x: 1, y: 0.588)
        )
        /// Kept for older call sites.
        static var agentGradient: LinearGradient { prism }
        static var agentStroke: [Color] { prismStops }
    }

    enum State {
        static let locked = Steel.ramp[9]
        static let approve = Color(oklch: 0.79, 0.13, 155)
        static let approveWash = Color(oklch: 0.79, 0.13, 155, opacity: 0.13)
        static let alert = Color(oklch: 0.70, 0.17, 25)
        static let alertWash = Color(oklch: 0.70, 0.17, 25, opacity: 0.13)
    }

    enum Space {
        static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
        static let s5: CGFloat = 20, s6: CGFloat = 24, s7: CGFloat = 28, s8: CGFloat = 32
        static let s9: CGFloat = 36, s10: CGFloat = 40, s11: CGFloat = 44, s12: CGFloat = 48
        static let s13: CGFloat = 52, s14: CGFloat = 56
    }

    enum Radius {
        static let window: CGFloat = 16, panel: CGFloat = 12, card: CGFloat = 10
        static let control: CGFloat = 8, chip: CGFloat = 6, frame: CGFloat = 2
    }

    enum Size {
        static let titlebar: CGFloat = 52
        static let sidebar: CGFloat = 240
        static let notesSheet: CGFloat = 380
        static let control: CGFloat = 28, controlLarge: CGFloat = 36, controlSmall: CGFloat = 22
        static let chip: CGFloat = 20, pill: CGFloat = 28
        static let windowMin = CGSize(width: 1180, height: 740)
        static let windowDesign = CGSize(width: 1440, height: 900)
        /// Settings: a sidebar of sections and a 744 content column, one size for every section.
        static let settingsWidth: CGFloat = 940
        static let settingsSidebar: CGFloat = 196
        static let settingsHeight: CGFloat = 760
        static let trafficLightsX: CGFloat = 20
    }

    enum Motion {
        static let snapDuration = 0.12, settleDuration = 0.22, glideDuration = 0.36, sweepDuration = 0.90
        static let snap = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: snapDuration)
        static let settle = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: settleDuration)
        static let glide = Animation.timingCurve(0.6, 0, 0.2, 1, duration: glideDuration)
        static let sweep = Animation.timingCurve(0.6, 0, 0.2, 1, duration: sweepDuration)
        static let shimmerPeriod = 2.4
        static let reduced = Animation.linear(duration: settleDuration)
    }

    @MainActor
    enum Font {
        static func brand(size: CGFloat, width: Double = 125, weight: Double = 800) -> SwiftUI.Font {
            SwiftUI.Font(BrandAssets.archivo(size: size, width: width, weight: weight))
        }
        /// Empty-state and welcome titles.
        static var brandXL: SwiftUI.Font { brand(size: 34, width: 125, weight: 800) }
        /// Sheet and room titles.
        static var brandL: SwiftUI.Font { brand(size: 24, width: 120, weight: 800) }
        /// Panel headings: "Notes on Cut 3".
        static var brandM: SwiftUI.Font { brand(size: 17, width: 112, weight: 700) }
        /// Option labels, cut names in lists.
        static var brandS: SwiftUI.Font { brand(size: 14, width: 112, weight: 700) }
        static var room: SwiftUI.Font { brandM }
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyMedium = SwiftUI.Font.system(size: 13, weight: .medium)
        static let control = SwiftUI.Font.system(size: 12.5, weight: .medium)
        static let small = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11)
        static let label = SwiftUI.Font.system(size: 10.5, weight: .medium, design: .monospaced)
        static let timecode = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced).monospacedDigit()
        static let timecodeSmall = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit()
        static let noteNumber = SwiftUI.Font.system(size: 14, weight: .semibold, design: .monospaced).monospacedDigit()
        static let mono = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit()
    }

    enum Material {
        static let glass = Color(oklch: 0.20, 0.005, 265, opacity: 0.55)
        static let glassBorder = Color.white.opacity(0.14)
        static let glassTopLip = Color.white.opacity(0.12)
    }

    enum Component {
        enum Button {
            static let steelTop = Color(oklch: 0.98, 0.002, 265)
            static let steelBottom = Color(oklch: 0.80, 0.006, 265)
            static let steelInk = Color(oklch: 0.17, 0.006, 265)
            static let steelHoverTop = Color.white
            static let steelHoverBottom = Color(oklch: 0.86, 0.006, 265)
            static let disabledOpacity = 0.4
        }
        enum Strip {
            static let height: CGFloat = 44, scene: CGFloat = 24, gap: CGFloat = 2
            static let tallHeight: CGFloat = 64, tallScene: CGFloat = 40
        }
    }

    static let grain = (window: 0.035, steel: 0.18)
}

struct GateSRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double
}

/// OKLCH → OKLab → linear sRGB → encoded sRGB. Values outside sRGB are channel-clipped.
enum GateColorSpace {
    static func sRGB(lightness: Double, chroma: Double, hue: Double, opacity: Double = 1) -> GateSRGB {
        let lightness = bounded(lightness)
        let chroma = bounded(chroma)
        let angle = (hue.isFinite ? hue.truncatingRemainder(dividingBy: 360) : 0) * .pi / 180
        let a = chroma * cos(angle), b = chroma * sin(angle)
        let l = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s = lightness - 0.0894841775 * a - 1.2914855480 * b
        let ll = l * l * l, mm = m * m * m, ss = s * s * s
        return .init(
            red: encoded(4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss),
            green: encoded(-1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss),
            blue: encoded(-0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss),
            opacity: bounded(opacity)
        )
    }

    private static func bounded(_ value: Double) -> Double { value.isNaN ? 0 : min(1, max(0, value)) }

    private static func encoded(_ value: Double) -> Double {
        let value = bounded(value)
        return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

extension Color {
    init(oklch lightness: Double, _ chroma: Double, _ hue: Double, opacity: Double = 1) {
        let value = GateColorSpace.sRGB(lightness: lightness, chroma: chroma, hue: hue, opacity: opacity)
        self.init(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.opacity)
    }
}

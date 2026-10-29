import Foundation
import SwiftUI

/// Gate 2.0. The explicit CSS primitives are authoritative where the sample Swift differs.
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
        static let canvas = Steel.ramp[0]
        static let sunken = Steel.ramp[1]
        static let ground = Steel.ramp[2]
        static let panel = Steel.ramp[3]
        static let raised = Steel.ramp[4]
        static let hover = Steel.ramp[5]
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
        static let director = Color(oklch: 0.82, 0.13, 72)
        static let directorInk = Color(oklch: 0.26, 0.06, 60)
        static let directorWash = director.opacity(0.15)
        static let agent = Color(oklch: 0.78, 0.11, 250)
        static let agentWash = agent.opacity(0.13)
        /// For suggestion diamonds and strokes no thicker than 2 points; never a text fill.
        static let agentStroke = [
            Color(oklch: 0.82, 0.12, 200),
            Color(oklch: 0.70, 0.16, 268),
            Color(oklch: 0.72, 0.20, 330),
            Color(oklch: 0.84, 0.13, 62),
        ]
        static let agentGradient = LinearGradient(
            stops: zip(agentStroke, [0.0, 0.34, 0.66, 1.0]).map { .init(color: $0, location: $1) },
            startPoint: .init(x: 0, y: 0.412), endPoint: .init(x: 1, y: 0.588)
        )
    }

    enum State {
        static let locked = Steel.ramp[9]
        static let approve = Color(oklch: 0.79, 0.13, 155)
        static let alert = Color(oklch: 0.70, 0.17, 25)
    }

    /// Order reflects the director's priorities, not the order notes were entered.
    enum NoteKind: Int, CaseIterable, Sendable {
        case feeling, story, pace, picture, sound
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

    enum Motion {
        static let snapDuration = 0.12, settleDuration = 0.22, glideDuration = 0.36, sweepDuration = 0.90
        static let snap = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: snapDuration)
        static let settle = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: settleDuration)
        static let glide = Animation.timingCurve(0.6, 0, 0.2, 1, duration: glideDuration)
        static let sweep = Animation.timingCurve(0.6, 0, 0.2, 1, duration: sweepDuration)
        static let shimmerPeriod = 2.4
        static let reduced = Animation.linear(duration: snapDuration)
    }

    @MainActor
    enum Font {
        static var room: SwiftUI.Font { brand(size: 22) }
        static func brand(size: CGFloat, width: Double = 125, weight: Double = 800) -> SwiftUI.Font {
            SwiftUI.Font(BrandAssets.archivo(size: size, width: width, weight: weight))
        }
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let control = SwiftUI.Font.system(size: 12.5, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11.5)
        static let timecode = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced).monospacedDigit()
        static let noteNumber = SwiftUI.Font.system(size: 15, weight: .semibold, design: .monospaced).monospacedDigit()
        static let brandTrackingRatio: CGFloat = -0.025
        static let minimumBrandSize: CGFloat = 14
        static let titleLineHeight: CGFloat = 22, bodyLineHeight: CGFloat = 18
        static let controlLineHeight: CGFloat = 16, captionLineHeight: CGFloat = 14, timecodeLineHeight: CGFloat = 16
    }

    enum Material {
        static let glass = Color(oklch: 0.20, 0.005, 265, opacity: 0.55)
        static let glassBorder = Color.white.opacity(0.14)
        static let glassTopLip = Color.white.opacity(0.12)
        static let glassBlur: CGFloat = 18
        static let glassSaturation = 1.4
    }

    enum Component {
        enum Button {
            static let steelTop = Color(oklch: 0.98, 0.002, 265)
            static let steelBottom = Color(oklch: 0.80, 0.006, 265)
            static let steelInk = Color(oklch: 0.17, 0.006, 265)
            static let steelHoverTop = Color.white
            static let steelHoverBottom = Color(oklch: 0.86, 0.006, 265)
            static let steelPressedTop = steelBottom
            static let steelPressedBottom = Color(oklch: 0.96, 0.002, 265)
            static let steelGradient = LinearGradient(stops: [
                .init(color: steelTop, location: 0), .init(color: steelBottom, location: 0.92),
            ], startPoint: .top, endPoint: .bottom)
            static let height: CGFloat = 30, largeHeight: CGFloat = 36
            static let disabledOpacity = 0.4
        }
        enum Note {
            static let numberColor = Voice.director
            static let rowPadding = Space.s3
        }
        enum SceneStrip {
            static let height: CGFloat = 44, sceneHeight: CGFloat = 24, gap: CGFloat = 2
            static let changedEdge = Voice.agentGradient
            static let directorMark = Voice.director
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
/// This preserves the guide's explicit OKLCH values without treating lightness as RGB gray.
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

    private static func bounded(_ value: Double) -> Double {
        value.isNaN ? 0 : min(1, max(0, value))
    }

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

import SwiftUI
import DirectionCore

/// A drawn board (specs/script.md › Boards): line drawings on near-black, one weight of grey, a single lit
/// edge where the light falls. Free, instant, and plainly not footage. Drawn on a 160 × 90 page.
struct BoardView: View {
    var kind: BoardKind
    var move: ShotMove? = nil
    /// "Close · still" in the corner, shown when the board is big enough to read it.
    var label: String? = nil

    var body: some View {
        GeometryReader { g in
            Canvas { c, size in
                c.scaleBy(x: size.width / 160, y: size.height / 90)
                Self.draw(kind, move: move, in: &c)
            }
            .overlay(alignment: .topTrailing) {
                if kind == .made { GemMark(size: max(5, g.size.width * 0.035)).padding(g.size.width * 0.06) }
            }
            .overlay(alignment: .bottomLeading) {
                if let label, g.size.width >= 160 {
                    Text(label.uppercased()).font(.system(size: g.size.width * 0.036, weight: .medium, design: .monospaced)).tracking(0.6)
                        .foregroundStyle(Gate.Text.secondary).padding(.leading, g.size.width * 0.035).padding(.bottom, g.size.height * 0.06)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Gate.Surface.sunken)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(Self.description(kind))
        .clearOfGrain()
    }

    static func description(_ kind: BoardKind) -> String {
        switch kind {
        case .title: "Board: a title over black"
        case .screen: "Board: a screen recording"
        case .wide: "Board: wide, from behind, lit by a screen"
        case .medium: "Board: medium"
        case .close: "Board: close, in profile, lit by a screen"
        case .detail: "Board: hands at a keyboard"
        case .onCamera: "Board: on camera with a microphone"
        case .action: "Board: a hand at a monitor"
        case .made: "Board: made by the editor"
        case .empty: "Board: nothing yet"
        }
    }

    // The board style's four tones, all from Gate's steel ramp.
    private static let line = GraphicsContext.Shading.color(Gate.Text.tertiary)     // steel-7
    private static let dim = GraphicsContext.Shading.color(Gate.Text.disabled)      // steel-6
    private static let lit = GraphicsContext.Shading.color(Gate.Text.primary)       // steel-9: where the light falls
    private static let pale = GraphicsContext.Shading.color(Gate.Text.secondary)    // steel-8
    private static let black = GraphicsContext.Shading.color(Gate.Surface.canvas)
    private static let stroke = StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)

    private static func path(_ build: (inout Path) -> Void) -> Path { var p = Path(); build(&p); return p }
    private static func lines(_ segments: [(CGPoint, CGPoint)]) -> Path { path { p in for (a, b) in segments { p.move(to: a); p.addLine(to: b) } } }
    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 0) -> Path { Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r) }

    private static func fillStroke(_ c: inout GraphicsContext, _ p: Path, fill: GraphicsContext.Shading, stroke s: GraphicsContext.Shading = line) {
        c.fill(p, with: fill); c.stroke(p, with: s, style: stroke)
    }

    static func draw(_ kind: BoardKind, move: ShotMove?, in c: inout GraphicsContext) {
        let panel = GraphicsContext.Shading.color(Gate.Surface.panel), raised = GraphicsContext.Shading.color(Gate.Surface.raised), screen = GraphicsContext.Shading.color(Gate.Surface.hover)
        switch kind {
        case .title:
            c.fill(rect(0, 0, 160, 90), with: black)
            c.fill(rect(34, 38, 78, 5, 2.5), with: pale)
            c.fill(rect(34, 47, 52, 5, 2.5), with: pale)
            c.fill(rect(89, 46, 2, 7), with: lit)
        case .screen:
            fillStroke(&c, rect(18, 12, 124, 66, 3), fill: panel)
            c.stroke(lines([(pt(18, 20), pt(142, 20)), (pt(42, 20), pt(42, 78)), (pt(50, 30), pt(90, 30)), (pt(50, 37), pt(96, 37)), (pt(50, 44), pt(80, 44)), (pt(50, 51), pt(92, 51))]), with: line, style: stroke)
            fillStroke(&c, rect(104, 24, 32, 48, 2), fill: raised, stroke: pale)
            c.stroke(rect(108, 30, 20, 5, 2.5), with: line, style: stroke)
            c.fill(rect(112, 39, 20, 5, 2.5), with: dim)
            c.stroke(rect(107, 63, 26, 5, 2.5), with: line, style: stroke)
        case .wide:
            c.fill(Path(ellipseIn: CGRect(x: 39, y: 10, width: 92, height: 56)), with: .color(Gate.Surface.raised.opacity(0.35)))
            c.stroke(lines([(pt(6, 64), pt(154, 64)), (pt(20, 64), pt(20, 86)), (pt(140, 64), pt(140, 86)), (pt(85, 54), pt(85, 64)), (pt(77, 64), pt(93, 64))]), with: line, style: stroke)
            fillStroke(&c, rect(58, 22, 54, 32, 2), fill: screen, stroke: pale)
            fillStroke(&c, Path(ellipseIn: CGRect(x: 76, y: 50, width: 16, height: 16)), fill: black, stroke: dim)
            fillStroke(&c, path { p in p.move(to: pt(60, 90)); p.addCurve(to: pt(84, 68), control1: pt(62, 76), control2: pt(71, 68)); p.addCurve(to: pt(108, 90), control1: pt(97, 68), control2: pt(106, 76)) }, fill: black, stroke: dim)
            c.stroke(path { p in p.addArc(center: pt(84, 58), radius: 8, startAngle: .degrees(-62), endAngle: .degrees(-8), clockwise: false) }, with: pale, style: stroke)
        case .close:
            c.fill(rect(146, 0, 14, 90), with: screen)
            let face = path { p in
                p.move(to: pt(62, 90)); p.addCurve(to: pt(56, 64), control1: pt(62, 78), control2: pt(58, 72))
                p.addCurve(to: pt(72, 24), control1: pt(50, 50), control2: pt(54, 30))
                p.addCurve(to: pt(106, 40), control1: pt(88, 19), control2: pt(102, 26))
                p.addLine(to: pt(111, 50)); p.addCurve(to: pt(108, 53), control1: pt(112, 52), control2: pt(111, 53))
                p.addLine(to: pt(108, 58)); p.addCurve(to: pt(104, 62), control1: pt(108, 61), control2: pt(106, 62))
                p.addCurve(to: pt(96, 70), control1: pt(105, 66), control2: pt(102, 70))
                p.addLine(to: pt(92, 71)); p.addCurve(to: pt(92, 90), control1: pt(90, 76), control2: pt(90, 82))
            }
            fillStroke(&c, face, fill: black, stroke: dim)
            c.stroke(path { p in
                p.move(to: pt(106, 40)); p.addLine(to: pt(111, 50)); p.move(to: pt(108, 53)); p.addLine(to: pt(108, 58))
                p.move(to: pt(104, 62)); p.addCurve(to: pt(96, 70), control1: pt(105, 66), control2: pt(102, 70))
            }, with: lit, style: stroke)
            c.stroke(path { p in p.move(to: pt(74, 44)); p.addCurve(to: pt(74, 54), control1: pt(71, 46), control2: pt(71, 52)); p.move(to: pt(98, 41)); p.addLine(to: pt(102, 41)) }, with: dim, style: stroke)
        case .detail:
            fillStroke(&c, path { p in p.move(to: pt(18, 72)); p.addLine(to: pt(142, 72)); p.addLine(to: pt(130, 40)); p.addLine(to: pt(30, 40)); p.closeSubpath() }, fill: panel)
            c.stroke(lines([(pt(28, 48), pt(132, 48)), (pt(25, 56), pt(135, 56)), (pt(22, 64), pt(138, 64))]), with: line, style: stroke)
            fillStroke(&c, path { p in p.move(to: pt(44, 88)); p.addCurve(to: pt(60, 58), control1: pt(42, 72), control2: pt(48, 60)); p.addCurve(to: pt(76, 68), control1: pt(70, 57), control2: pt(76, 62)); p.addLine(to: pt(78, 88)) }, fill: black, stroke: dim)
            fillStroke(&c, path { p in p.move(to: pt(116, 88)); p.addCurve(to: pt(100, 58), control1: pt(118, 72), control2: pt(112, 60)); p.addCurve(to: pt(84, 68), control1: pt(90, 57), control2: pt(84, 62)); p.addLine(to: pt(82, 88)) }, fill: black, stroke: dim)
            // The screen's light along the tops of the fingers.
            c.stroke(path { p in
                p.move(to: pt(52, 61)); p.addCurve(to: pt(70, 59), control1: pt(57, 57), control2: pt(65, 56))
                p.move(to: pt(90, 59)); p.addCurve(to: pt(108, 61), control1: pt(95, 56), control2: pt(103, 57))
            }, with: lit, style: stroke)
        case .medium, .onCamera:
            c.stroke(lines([(pt(10, 30), pt(50, 30)), (pt(112, 26), pt(150, 26))]), with: line, style: stroke)
            fillStroke(&c, Path(ellipseIn: CGRect(x: 68, y: 24, width: 24, height: 24)), fill: black, stroke: dim)
            fillStroke(&c, path { p in p.move(to: pt(46, 90)); p.addCurve(to: pt(80, 58), control1: pt(48, 70), control2: pt(61, 58)); p.addCurve(to: pt(114, 90), control1: pt(99, 58), control2: pt(112, 70)) }, fill: black, stroke: dim)
            // The key light from the right: one lit edge down the face and shoulder.
            c.stroke(path { p in
                p.addArc(center: pt(80, 36), radius: 12, startAngle: .degrees(-70), endAngle: .degrees(50), clockwise: false)
                p.move(to: pt(88, 59)); p.addCurve(to: pt(112, 84), control1: pt(101, 61), control2: pt(110, 71))
            }, with: lit, style: stroke)
            if kind == .onCamera {
                c.stroke(lines([(pt(0, 80), pt(160, 80)), (pt(120, 80), pt(120, 64))]), with: line, style: stroke)
                fillStroke(&c, rect(116, 52, 8, 13, 4), fill: panel)
            }
        case .action:
            fillStroke(&c, rect(20, 10, 120, 66, 3), fill: screen)
            c.stroke(lines([(pt(80, 76), pt(80, 84)), (pt(68, 84), pt(92, 84))]), with: line, style: stroke)
            var note = c
            note.translateBy(x: 110, y: 31); note.rotate(by: .degrees(4)); note.translateBy(x: -110, y: -31)
            note.fill(rect(96, 18, 28, 26, 1), with: pale)
            note.stroke(path { p in p.move(to: pt(101, 27)); p.addCurve(to: pt(113, 26), control1: pt(105, 25), control2: pt(109, 28)); p.move(to: pt(101, 33)); p.addCurve(to: pt(115, 33), control1: pt(106, 32), control2: pt(110, 34)) }, with: panel, style: stroke)
            c.stroke(path { p in p.move(to: pt(134, 90)); p.addCurve(to: pt(125, 48), control1: pt(132, 72), control2: pt(130, 58)) }, with: pale, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        case .made:
            c.fill(rect(0, 0, 160, 90), with: black)
            fillStroke(&c, rect(34, 16, 92, 58, 6), fill: panel)
            c.stroke(lines([(pt(34, 26), pt(126, 26))]), with: line, style: stroke)
            fillStroke(&c, rect(42, 56, 76, 11, 5.5), fill: .color(Gate.Surface.sunken))
            c.stroke(lines([(pt(47, 59), pt(47, 64))]), with: lit, style: stroke)
        case .empty:
            c.stroke(rect(10, 8, 140, 74, 3), with: dim, style: StrokeStyle(lineWidth: 1.1, dash: [3, 3]))
            c.draw(Text("?").font(.system(size: 22, weight: .semibold)).foregroundStyle(Gate.Text.tertiary), at: pt(80, 46))
        }
        // A push ends where the corner marks are.
        if move == .push || move == .pull {
            c.stroke(path { p in
                for (x, y, dx, dy) in [(34.0, 16.0, -8.0, 6.0), (126.0, 16.0, 8.0, 6.0), (34.0, 74.0, -8.0, -6.0), (126.0, 74.0, 8.0, -6.0)] {
                    p.move(to: pt(x, y)); p.addLine(to: pt(x + dx, y)); p.addLine(to: pt(x + dx, y + dy))
                }
            }, with: lit, style: stroke)
        }
    }
}

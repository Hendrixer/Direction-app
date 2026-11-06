import SwiftUI
import DirectionCore

// Layouts (layouts.md) belong to the editor: a style names them and the editor lays out a screen recording and a
// camera with them. The director changes one with a note. This is how a style shows its layouts.

/// A layout drawn small, from the same geometry the renderer uses: the frame, the screen, the camera.
struct LayoutGlyph: View {
    var layout: FrameLayout?
    var size: CGSize
    var lit = false
    var body: some View {
        // The glyph is the frame's own shape: tall cuts stack side by side.
        let frame = LayoutGeometry.Size(size.width, size.height)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2.5).fill(Gate.Surface.sunken)
            if let l = layout {
                if l.kind != .you { shape(LayoutGeometry.screenRect(l, frame: frame, screen: .init(16, 9)), radius: l.kind == .sideBySide || l.screen == .framed ? 1.5 : 0, Gate.Steel.ramp[6]) }
                if l.kind != .screen {
                    let r = LayoutGeometry.cameraRect(l, frame: frame)
                    shape(r, radius: l.kind == .screenAndYou ? min(r.w * size.width, r.h * size.height) * l.shape.radius : l.kind == .sideBySide ? 1.5 : 0, lit ? Gate.Text.primary : Gate.Text.secondary)
                }
            } else {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: size.height * 0.6, weight: .medium)).foregroundStyle(Gate.Text.tertiary).frame(width: size.width, height: size.height)
            }
            RoundedRectangle(cornerRadius: 2.5).strokeBorder(lit ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 2.5))
    }
    private func shape(_ r: LayoutGeometry.Rect, radius: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
            .frame(width: r.w * size.width, height: r.h * size.height)
            .offset(x: r.x * size.width, y: r.y * size.height)
    }
}

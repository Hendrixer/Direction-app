import SwiftUI

/// The chrome D with light moving over it: the rainbow at its edges travels around the chrome and a
/// soft highlight crosses it. Each pass starts slowly, gathers speed, eases into a stall, then rests.
/// Reduce Motion shows the still mark.
struct ChromeMark: View {
    var size: CGFloat = 168
    /// Pins the moment, in seconds, for snapshots. Nil follows the clock.
    var at: Double? = nil

    static let pass = 4.6, rest = 2.4
    /// Slow out of the rest, fast through the middle, a long eased stall at the end.
    static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.72, y: 0), endControlPoint: UnitPoint(x: 0.14, y: 1))
    private static let spectrum: [Color] = [
        Color(red: 1.0, green: 0.36, blue: 0.36), Color(red: 1.0, green: 0.72, blue: 0.3), Color(red: 0.98, green: 0.95, blue: 0.4),
        Color(red: 0.4, green: 0.95, blue: 0.6), Color(red: 0.3, green: 0.75, blue: 1.0), Color(red: 0.62, green: 0.45, blue: 1.0),
        Color(red: 1.0, green: 0.4, blue: 0.85),
    ]

    /// 0…1 through a pass; holds at 1 through the rest.
    static func progress(_ time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: pass + rest)
        return t >= pass ? 1 : curve.value(at: t / pass)
    }

    var body: some View {
        if let mark = BrandAssets.mark {
            let image = Image(nsImage: mark).resizable().interpolation(.high).scaledToFit()
            Group {
                if let at { lit(image, Self.progress(at)) }
                else if SettingsKey.reducesMotion { image }
                else { TimelineView(.animation) { lit(image, Self.progress($0.date.timeIntervalSinceReferenceDate)) } }
            }
            .frame(width: size, height: size)
        }
    }

    private func lit(_ image: some View, _ p: Double) -> some View {
        image
            // Hue blending takes only the gradient's hue: grey chrome stays grey, and the colored fringes
            // shift along the spectrum. It repeats twice around, so half a turn per pass loops cleanly.
            .overlay {
                AngularGradient(colors: Self.spectrum + Self.spectrum + [Self.spectrum[0]], center: .center, angle: .degrees(p * 180 - 40))
                    .blendMode(.hue).opacity(0.8)
            }
            // The light: a soft band that crosses on the diagonal, top left to bottom right. Drawn in an
            // overlay so its oversized frame never changes the mark's layout.
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.43), .init(color: .white.opacity(0.85), location: 0.5), .init(color: .clear, location: 0.57)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: size * 3, height: size * 3)
                    .offset(x: (p * 2 - 1) * size * 1.1, y: (p * 2 - 1) * size * 1.1)
                    .blendMode(.overlay)
            }
            .compositingGroup()
            .mask(image)
            .accessibilityHidden(true)
    }
}

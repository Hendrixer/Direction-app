import SwiftUI

/// How the Script and Breakdown pages use a wide window (specs/script.md › The page): the page grows with the
/// window up to `cap`, and a page past 1240 pt reads one step bigger (two past 1440): its words, its boards
/// and the room between rows, so a line stays a length you can read and the page doesn't turn into a band of
/// small type down the middle. The room's bars, lists and panels keep their sizes.
struct PrepMeasure: Equatable {
    /// The widest a page gets.
    static let cap: CGFloat = 1560
    /// The page's sides, inside the scroll area.
    static let margin: CGFloat = 32
    /// 0 to 2.
    let step: CGFloat

    /// `available`: the scroll area's width. Not measured yet reads as the narrowest page.
    init(available: CGFloat) {
        let page = min(Self.cap, max(0, available - 2 * Self.margin))
        step = page >= 1440 ? 2 : page >= 1240 ? 1 : 0
    }

    /// A reading size (13 pt picture words, 12.5 pt beat lines) on this page.
    func text(_ base: CGFloat) -> CGFloat { base + step }
    /// Captions under the words step once, so they stay quieter than what they're under.
    func caption(_ base: CGFloat) -> CGFloat { base + min(step, 1) }
    /// A script row's board: 80 pt wide, then 104, then 128.
    var board: CGFloat { 80 + 24 * step }
    /// A breakdown shot's picture, 16:9: 96 pt wide, then 112, then 128.
    var shot: CGFloat { 96 + 16 * step }
    /// The space above and below a row's words.
    var rowPadding: CGFloat { 13 + 3 * step }
}

extension View {
    /// Reads the width the page has, for `PrepMeasure`.
    func measuringWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.wrappedValue = $0 }
    }
}

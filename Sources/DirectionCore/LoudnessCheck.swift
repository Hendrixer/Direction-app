import Foundation

/// Whether a mix is ready to deliver for loudness (finish.md › Sound): its integrated loudness within a loudness
/// unit of the target from Settings › Cutting, and no true peak over the ceiling. Measured by SequenceRenderer;
/// said here so the editor's tools, the loudness step and the Deliver sheet say it the same way.
public enum LoudnessCheck {
    public enum Verdict: Equatable, Sendable {
        case onTarget
        /// No sound to measure.
        case silent
        /// Off, and the loudness step fixes it.
        case off(String)
        /// Under the target with its peaks already at the ceiling: louder only with a limiter on its loudest sound.
        case heldByPeaks(String)

        public var isReady: Bool { switch self { case .onTarget, .silent, .heldByPeaks: true; case .off: false } }
        public var words: String? { switch self { case .onTarget, .silent: nil; case .off(let w), .heldByPeaks(let w): w } }
    }

    public static func verdict(integrated: Double?, truePeak: Double, target: Double = SharedSettings.loudnessTarget, ceiling: Double = SharedSettings.truePeakCeiling) -> Verdict {
        guard let integrated else { return .silent }
        let tolerance = SharedSettings.loudnessTolerance
        if truePeak > ceiling + 0.1 { return .off("Its loudest peak is \(peakText(truePeak)), over the \(peakText(ceiling)) ceiling.") }
        let off = integrated - target
        if abs(off) <= tolerance { return .onTarget }
        if off > 0 { return .off("The mix is \(lufsText(integrated)), \(number(off)) LU over the \(lufsText(target)) target.") }
        if truePeak >= ceiling - 0.2 { return .heldByPeaks("The mix is \(lufsText(integrated)), \(number(-off)) LU under the \(lufsText(target)) target, and its peaks already reach \(peakText(ceiling)): it gets louder only with a limiter on its loudest sound.") }
        return .off("The mix is \(lufsText(integrated)), \(number(-off)) LU under the \(lufsText(target)) target.")
    }

    /// "−14 LUFS", "−14.2 LUFS".
    public static func lufsText(_ x: Double) -> String { signed(x, plus: false) + " LUFS" }
    /// "+3.2 dB".
    public static func dBText(_ x: Double) -> String { signed(x, plus: true) + " dB" }
    /// "−1 dBTP".
    public static func peakText(_ x: Double) -> String { signed(x, plus: false) + " dBTP" }
    /// The finish job's words for the target.
    public static func target(_ lufs: Double) -> String { lufsText(lufs) }

    static func number(_ x: Double) -> String { let r = (x * 10).rounded() / 10; return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r) }
    static func signed(_ x: Double, plus: Bool) -> String {
        let n = number(abs(x)), zero = n == "0"
        return zero ? "0" : (x < 0 ? "\u{2212}" : (plus ? "+" : "")) + n
    }
}

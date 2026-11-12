import Foundation

/// Speed and quality: one setting per film, moved on a slider while the editor isn't running
/// (specs/editor.md › Speed and quality). From it Direction picks the editor's version and effort for each
/// job and the version for each made request (docs/speed-and-quality.md), so nobody chooses versions or
/// effort by hand.
public enum FilmQuality: String, CaseIterable, Codable, Sendable {
    /// Quickest: every job on a lighter version, cutting and notes included (Sonnet rather than Opus), made shots as
    /// Faster's. Added 2026-11-11: Faster kept the strongest version for cutting, so it wasn't quick enough.
    case fastest
    /// Quicker: the editor thinks less, the list-like jobs run on lighter versions, made shots come back sooner.
    case faster
    /// Care where judgement is (cutting, notes, a style), speed elsewhere.
    case balanced
    /// The most careful editor and the best-rated versions, whatever they take.
    case best

    public var label: String {
        switch self { case .fastest: "Fastest"; case .faster: "Faster"; case .balanced: "Balanced"; case .best: "Best" }
    }

    /// The line under the slider.
    public var detail: String {
        switch self {
        case .fastest: "The editor works on a quicker version for everything, and made shots come back sooner. Good for a rough first pass."
        case .faster: "The editor thinks less while it cuts, and made shots come back sooner. Good for a quick cut."
        case .balanced: "The editor takes its time cutting and answering notes, and moves quickly through the rest."
        case .best: "The editor takes its time on everything, and made shots use the best versions. Slower, and spends more."
        }
    }
}

extension DirectingState {
    /// The film's setting; films from before it existed are Balanced.
    public var speedAndQuality: FilmQuality { quality ?? .balanced }
}

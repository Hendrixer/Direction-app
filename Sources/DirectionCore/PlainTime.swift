import Foundation

/// "0:12", "12:04", "1:02:03": a time the way a video player says it, in whole seconds, hours only past an hour. The
/// one way Direction writes a time for people and for the editor (the app's Timecode adds frames where they mean
/// something).
public enum PlainTime {
    public static func text(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds < 360_000 else { return "\u{2013}:\u{2013}\u{2013}" }
        let t = Int(max(0, seconds)), h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

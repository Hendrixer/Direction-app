import Foundation

/// Shot numbers are the slates (specs/breakdown.md › Slates): "2C, take one" said at the head of a take, or a
/// file named for its shot ("2C T1.mov", "5a_take3.mp4"). Only numbers the breakdown has count.
public enum Slate {
    public struct Mark: Equatable, Sendable {
        public var code: String
        public var take: Int?
        public init(code: String, take: Int?) { self.code = code; self.take = take }
    }

    /// Seconds at the head of a take where a slate is said.
    public static let headSeconds = 10.0

    /// "2C, take 1", "two C take one", "scene 2 charlie take 3", "2C T1".
    public static func spoken(_ words: [String]) -> Mark? {
        var tokens: [String] = []
        for w in words.prefix(16) {
            let t = w.lowercased().filter { $0.isLetter || $0.isNumber }
            guard !t.isEmpty else { continue }
            // "2c" → "2", "c"; "t1" → "take", "1".
            if let m = t.wholeMatch(of: /(\d{1,3})([a-z])/) { tokens += [String(m.1), String(m.2)]; continue }
            if let m = t.wholeMatch(of: /t(\d{1,3})/) { tokens += ["take", String(m.1)]; continue }
            tokens.append(numbers[t].map(String.init) ?? letters[t].map(String.init) ?? t)
        }
        // Two-word numbers: "twenty one".
        var joined: [String] = []
        for t in tokens {
            if let last = joined.last, let tens = Int(last), tens >= 20, tens % 10 == 0, let unit = Int(t), unit < 10 { joined[joined.count - 1] = String(tens + unit) } else { joined.append(t) }
        }
        for i in joined.indices {
            guard let n = Int(joined[i]), n > 0, i + 1 < joined.count, joined[i + 1].count == 1, joined[i + 1].first!.isLetter else { continue }
            let code = "\(n)\(joined[i + 1].uppercased())"
            if i + 3 < joined.count, joined[i + 2] == "take", let take = Int(joined[i + 3]) { return Mark(code: code, take: take) }
            if i + 2 < joined.count, joined[i + 2] == "take" { return Mark(code: code, take: nil) }
        }
        return nil
    }

    /// "2C T1.mov", "2c_take3.mp4", "5A.mov".
    public static func fileName(_ name: String) -> Mark? {
        let base = (name as NSString).deletingPathExtension
        guard let m = base.prefixMatch(of: /(?i)(\d{1,3})[ _-]?([a-z])(?![a-z0-9])(?:[ _-]*(?:take|tk|t)[ _-]*(\d{1,3}))?/) else { return nil }
        return Mark(code: "\(m.1)\(String(m.2).uppercased())", take: m.3.flatMap { Int($0) })
    }

    private static let numbers: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                                                 "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
                                                 "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50]
    private static let letters: [String: Character] = ["alpha": "a", "alfa": "a", "bravo": "b", "charlie": "c", "delta": "d", "echo": "e", "foxtrot": "f", "golf": "g", "hotel": "h",
                                                       "india": "i", "juliet": "j", "kilo": "k", "lima": "l", "mike": "m", "november": "n", "oscar": "o", "papa": "p", "quebec": "q",
                                                       "romeo": "r", "sierra": "s", "tango": "t", "uniform": "u", "victor": "v", "whiskey": "w", "xray": "x", "yankee": "y", "zulu": "z",
                                                       "bee": "b", "see": "c", "sea": "c", "dee": "d", "gee": "g", "jay": "j", "kay": "k", "pee": "p", "tee": "t", "vee": "v"]
}

import Foundation
import NaturalLanguage

/// Search footage (specs/footage-index.md › What the editor gets): Apple's sentence embeddings for
/// meaning, FTS5 for exact words, blended 0.6 meaning and 0.4 words, best shot per take first.
/// Everything runs on this Mac; the query never leaves it.
public enum FootageSearch {
    public enum Why: String, Codable, Sendable {
        case picture, words, both, screen
        /// How Dailies says it.
        public var label: String { self == .screen ? "on screen" : rawValue }
    }

    public struct Hit: Codable, Sendable, Hashable {
        public var shotID: String
        public var assetID: String
        public var score: Double
        public var why: Why
        /// The description, the quoted line of dialogue when it matched on words, or the lines on
        /// screen that matched.
        public var text: String
        /// Query words found in `text` (stemmed matches included), for highlighting.
        public var matched: [String]
        /// The shot's range, or for text on screen, when that text is on screen.
        public var start: Double
        public var end: Double
        public var keyframes: [String]
        public init(shotID: String, assetID: String, score: Double, why: Why, text: String, matched: [String], start: Double, end: Double, keyframes: [String]) {
            self.shotID = shotID; self.assetID = assetID; self.score = score; self.why = why; self.text = text; self.matched = matched; self.start = start; self.end = end; self.keyframes = keyframes
        }
    }

    public struct Options: Sendable {
        public var sceneID: String?
        public var circledOnly = false
        /// Transcripts alone ("Search words only").
        public var wordsOnly = false
        public var limit = 12
        public init(sceneID: String? = nil, circledOnly: Bool = false, wordsOnly: Bool = false, limit: Int = 12) { self.sceneID = sceneID; self.circledOnly = circledOnly; self.wordsOnly = wordsOnly; self.limit = limit }
    }

    /// Below this a shot doesn't count as a match at all.
    public static let floor = 0.26

    // MARK: Embeddings

    nonisolated(unsafe) private static var embedding: NLEmbedding?
    private static let lock = NSLock()

    /// A sentence vector, or nil when the embedding isn't available on this Mac.
    public static func vector(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if embedding == nil { embedding = NLEmbedding.sentenceEmbedding(for: .english) }
        return embedding?.vector(for: trimmed).map { $0.map(Float.init) }
    }

    /// Cosine similarity mapped onto 0…1. Apple's sentence vectors put unrelated sentences at
    /// cosine 0.1–0.3 and close ones at 0.4–0.55, so 0.30 reads as nothing and 0.52 as a strong
    /// match (calibrated on the sample film's descriptions).
    public static func meaning(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return 0 }
        let cosine = Double(dot / (na.squareRoot() * nb.squareRoot()))
        return max(0, min(1, (cosine - 0.30) / 0.22))
    }

    // MARK: Words

    private static let stopwords: Set<String> = ["a", "an", "the", "of", "at", "in", "on", "and", "or", "with", "to", "is", "are", "for", "by", "from", "it", "her", "his", "their", "this", "that", "shot", "shots", "take", "takes"]

    /// Query words worth matching.
    public static func tokens(_ query: String) -> [String] {
        var seen = Set<String>()
        return query.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty && !stopwords.contains($0) && seen.insert($0).inserted }
    }

    /// A rough stem for highlighting (FTS5's porter stemmer does the real matching).
    public static func stem(_ word: String) -> String {
        var w = word.lowercased().filter { $0.isLetter || $0.isNumber }
        for suffix in ["ing", "ed", "es", "s"] where w.count > suffix.count + 2 && w.hasSuffix(suffix) { w.removeLast(suffix.count); break }
        if w.count > 3, let last = w.last, w.dropLast().last == last, !"aeiou".contains(last) { w.removeLast() }
        return w
    }

    /// The words in `text` that match a query token.
    public static func matchedWords(in text: String, tokens: [String]) -> [String] {
        let stems = Set(tokens.map(stem))
        var seen = Set<String>()
        return text.split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init).filter { stems.contains(stem($0)) && seen.insert($0.lowercased()).inserted }
    }

    // MARK: Ranking

    /// Ranks shots for a query. `takes` filters by scene and circle; pass nil to search every take.
    public static func search(_ query: String, store: ProjectStore, dailies: Dailies? = nil, options: Options = .init()) throws -> [Hit] {
        let tokens = tokens(query)
        let q = vector(query)
        let shots = Dictionary(uniqueKeysWithValues: try store.shots().map { ($0.id, $0) })
        let allowed: (String) -> Bool = { assetID in
            guard let dailies else { return true }
            let t = dailies.take(assetID)
            if let s = options.sceneID, t.sceneID != s { return false }
            return !options.circledOnly || t.circled
        }

        struct Side { var meaning = 0.0; var exact = 0.0; var text = ""; var hits = Set<String>(); var start = 0.0 }
        var picture: [String: Side] = [:], words: [String: Side] = [:], screen: [String: Side] = [:]

        // Meaning: the query's sentence vector against each description and line.
        if let q {
            for row in try cachedVectors(store) where shots[row.shotID] != nil && allowed(row.assetID) {
                if options.wordsOnly && row.kind != .words { continue }
                guard let v = row.vector else { continue }
                let m = meaning(q, v)
                switch row.kind {
                case .picture: if m > picture[row.shotID, default: Side()].meaning { picture[row.shotID, default: Side()].meaning = m; picture[row.shotID]!.text = row.text }
                case .words: if m > words[row.shotID, default: Side()].meaning { words[row.shotID, default: Side()].meaning = m; words[row.shotID]!.text = row.text }
                case .screen: if m > screen[row.shotID, default: Side()].meaning { screen[row.shotID, default: Side()].meaning = m; screen[row.shotID]!.text = row.text; screen[row.shotID]!.start = row.start }
                }
            }
        }
        // Exact words: the share of query words each side contains.
        if !tokens.isEmpty {
            var lineHits: [String: [String: Set<String>]] = [:]
            var screenHits: [String: [Double: (text: String, tokens: Set<String>)]] = [:]
            for token in tokens {
                for (row, _) in try store.searchWord(token) where shots[row.shotID] != nil && allowed(row.assetID) {
                    switch row.kind {
                    case .picture:
                        guard !options.wordsOnly else { continue }
                        picture[row.shotID, default: Side()].hits.insert(token)
                        if picture[row.shotID]!.text.isEmpty { picture[row.shotID]!.text = row.text }
                    case .words:
                        lineHits[row.shotID, default: [:]][row.text, default: []].insert(token)
                    case .screen:
                        guard !options.wordsOnly else { continue }
                        screenHits[row.shotID, default: [:]][row.start, default: (row.text, [])].tokens.insert(token)
                    }
                }
            }
            // A shot's text on screen is its best stretch, the earliest of equals, so the hit
            // says when that text is on screen.
            for (shotID, stretches) in screenHits {
                guard let best = stretches.max(by: { ($0.value.tokens.count, -$0.key) < ($1.value.tokens.count, -$1.key) }) else { continue }
                var side = screen[shotID, default: Side()]
                side.hits = best.value.tokens; side.text = best.value.text; side.start = best.key
                screen[shotID] = side
            }
            // A shot's words side is its best single line, so a quote reads as one line.
            for (shotID, lines) in lineHits {
                guard let best = lines.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }) else { continue }
                var side = words[shotID, default: Side()]
                if side.hits.count < best.value.count || side.text.isEmpty { side.hits = best.value; side.text = best.key }
                words[shotID] = side
            }
            for k in picture.keys { picture[k]!.exact = Double(picture[k]!.hits.count) / Double(tokens.count) }
            for k in words.keys { words[k]!.exact = Double(words[k]!.hits.count) / Double(tokens.count) }
            for k in screen.keys { screen[k]!.exact = Double(screen[k]!.hits.count) / Double(tokens.count) }
        }

        var hits: [Hit] = [], stretches: [String: ScreenText]?
        for id in Set(picture.keys).union(words.keys).union(screen.keys) {
            guard let shot = shots[id] else { continue }
            let p = picture[id] ?? Side(), w = words[id] ?? Side(), o = screen[id] ?? Side()
            let pScore = 0.6 * p.meaning + 0.4 * p.exact, wScore = 0.6 * w.meaning + 0.4 * w.exact, oScore = 0.6 * o.meaning + 0.4 * o.exact
            let score = 0.6 * max(p.meaning, w.meaning, o.meaning) + 0.4 * max(p.exact, w.exact, o.exact)
            guard score >= floor else { continue }
            var start = shot.start, end = shot.end
            let why: Why, text: String
            // Text on screen is read, not judged, so its exact words count for more than its meaning:
            // it wins when it holds more of the query than the description or the lines do.
            if oScore > max(pScore, wScore) || (o.exact >= 0.5 && o.exact > max(p.exact, w.exact)) {
                why = .screen; text = screenLines(o.text, tokens: tokens)
                // When that text is on screen, not the whole shot.
                if stretches == nil { stretches = Dictionary(try store.screenText().map { ("\($0.assetID)|\($0.start)", $0) }, uniquingKeysWith: { a, _ in a }) }
                if let s = stretches?["\(shot.assetID)|\(o.start)"] { start = s.start; end = s.end }
            } else {
                why = (!p.hits.isEmpty && !w.hits.isEmpty && min(pScore, wScore) >= 0.85 * max(pScore, wScore)) ? .both : (pScore >= wScore ? .picture : .words)
                text = why == .words ? "\u{201C}\(w.text)\u{201D}" : (shot.look?.description ?? (p.text.isEmpty ? w.text : p.text))
            }
            hits.append(Hit(shotID: id, assetID: shot.assetID, score: (score * 1000).rounded() / 1000, why: why, text: text, matched: matchedWords(in: text, tokens: tokens), start: start, end: end, keyframes: shot.keyframes))
        }
        return bestPerTakeFirst(hits, limit: options.limit)
    }

    /// The lines of a stretch on screen that hold query words (three at most), else its longest two.
    static func screenLines(_ text: String, tokens: [String]) -> String {
        let lines = text.split(separator: "\n").map(String.init)
        let matching = lines.filter { !matchedWords(in: $0, tokens: tokens).isEmpty }
        if !matching.isEmpty { return matching.prefix(3).joined(separator: " \u{00B7} ") }
        let longest = Set(lines.sorted { $0.count > $1.count }.prefix(2))
        return lines.filter(longest.contains).joined(separator: " \u{00B7} ")
    }

    /// Each take's best shot, by score, then every other shot by score.
    public static func bestPerTakeFirst(_ hits: [Hit], limit: Int) -> [Hit] {
        let sorted = hits.sorted { ($0.score, $1.shotID) > ($1.score, $0.shotID) }
        var seen = Set<String>(), first: [Hit] = [], rest: [Hit] = []
        for h in sorted { if seen.insert(h.assetID).inserted { first.append(h) } else { rest.append(h) } }
        return Array((first + rest).prefix(max(1, limit)))
    }

    /// "More like this shot": nearest Vision feature prints, best shot per take first.
    public static func similar(to shotID: String, store: ProjectStore, dailies: Dailies? = nil, options: Options = .init()) throws -> [Hit] {
        let prints = try store.featurePrints()
        guard let target = prints[shotID] else { throw DirectionError("no_feature_print", "That shot hasn't been looked at yet.") }
        let shots = Dictionary(uniqueKeysWithValues: try store.shots().map { ($0.id, $0) })
        var hits: [Hit] = []
        for (id, p) in prints where id != shotID {
            guard let shot = shots[id], p.count == target.count else { continue }
            if let dailies {
                let t = dailies.take(shot.assetID)
                if let s = options.sceneID, t.sceneID != s { continue }
                if options.circledOnly && !t.circled { continue }
            }
            var d: Float = 0
            for i in p.indices { let x = p[i] - target[i]; d += x * x }
            // Feature-print distance runs about 0 (same frame) to 1.4 (unrelated).
            let score = max(0, 1 - Double(d.squareRoot()) / 1.4)
            hits.append(Hit(shotID: id, assetID: shot.assetID, score: (score * 1000).rounded() / 1000, why: .picture, text: shot.look?.description ?? "", matched: [], start: shot.start, end: shot.end, keyframes: shot.keyframes))
        }
        return bestPerTakeFirst(hits, limit: options.limit)
    }

    // MARK: Cache

    nonisolated(unsafe) private static var cache: [String: (generation: Int64, rows: [IndexSearchRow])] = [:]
    private static let cacheLock = NSLock()

    /// Vectors stay in memory between searches until a take's rows change, so typing stays fast.
    private static func cachedVectors(_ store: ProjectStore) throws -> [IndexSearchRow] {
        let generation = try store.searchGeneration(), key = store.url.path
        cacheLock.lock(); let hit = cache[key]; cacheLock.unlock()
        if let hit, hit.generation == generation { return hit.rows }
        let rows = try store.searchVectors()
        cacheLock.lock(); cache[key] = (generation, rows); cacheLock.unlock()
        return rows
    }
}

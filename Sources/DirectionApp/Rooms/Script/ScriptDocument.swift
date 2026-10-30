import Foundation
import DirectionCore

// The cut's dialogue as a lined script, built from the takes' transcripts.
//
// Transcripts are timed words. A few in-band conventions, the ones screenplays and
// transcripts already use, give the page its shape:
//   MAYA:  or  MAYA (O.S.):   an all-caps label ending in a colon starts a speech.
//   [She looks to the window.] a bracketed phrase on its own is an action line;
//                              right after a word (no pause) it's an aside on that line.
//   [INT. MAYA'S OFFICE, DAY]  a bracketed INT./EXT. phrase is the scene's slugline.
// Lines break at sentence ends, at a pause after a comma, and at long pauses.
//
// Line numbers belong to the whole shoot, not to one cut: every take's lines are merged
// per scene (circled takes first), so a number means the same line in every cut and
// lines that were never used keep theirs. Coverage is the set of takes whose own
// line merged into the same entry: the lined script's vertical bars.

struct ScriptLine: Identifiable, Hashable {
    enum Kind: Hashable { case dialogue, action }
    /// Stable for one document: the clip and the source line it plays.
    var id: String
    var number: Int
    var kind: Kind
    /// Shown on the first line of a speech.
    var speaker: String?
    var text: String
    /// Seconds in the cut.
    var start: Double
    var end: Double
    var assetID: String
    var clipID: String
    var sceneID: String?
    var sceneNumber: Int
    /// Every reading of this line, the one in the cut included.
    var readings: [ScriptReading]
    var key: String { ScriptText.key(text) }
    var duration: Double { max(0, end - start) }
    var label: String { "Line \(number)" }
    func reading(_ assetID: String) -> ScriptReading? { readings.first { $0.assetID == assetID } }
}

/// One take's version of a line.
struct ScriptReading: Identifiable, Hashable {
    var id: String { "\(assetID):\(lineIndex)" }
    var assetID: String
    var lineIndex: Int
    /// The take's own words.
    var text: String
    /// Seconds in the take.
    var start: Double
    var end: Double
    /// Same words as the line in the cut.
    var exact: Bool
    /// Heard, but the speaker isn't in shot.
    var offCamera: Bool
    /// An aside that follows the line in this take: "Breaks off, laughs".
    var aside: String?
    var duration: Double { max(0, end - start) }
}

enum ScriptCoverage: Hashable { case none, onCamera, offCamera, inCut }

/// A coverage column: one take of the scene.
struct ScriptColumn: Hashable, Identifiable {
    var id: String { assetID }
    var assetID: String
    var setup: String
    var take: String
}

struct ScriptScene: Identifiable, Hashable {
    var id: String
    var number: Int
    var title: String
    var slugline: String?
    var locked: Bool
    var lines: [ScriptLine]
    var columns: [ScriptColumn]
    /// Every line plays from sound with no picture of its own.
    var voiceOverOnly: Bool
    func coverage(_ line: ScriptLine, _ column: ScriptColumn) -> ScriptCoverage {
        guard let reading = line.reading(column.assetID) else { return .none }
        if column.assetID == line.assetID { return .inCut }
        return reading.offCamera ? .offCamera : .onCamera
    }
}

struct ScriptDocument {
    var scenes: [ScriptScene] = []
    var lines: [ScriptLine] = []
    /// Spoken time in the cut.
    var dialogueSeconds: Double = 0
    /// Takes in the cut that have no transcript yet.
    var untranscribed: [String] = []
    var takeLabels: [String: String] = [:]

    var isEmpty: Bool { lines.isEmpty }
    func line(_ id: String?) -> ScriptLine? { id.flatMap { id in lines.first { $0.id == id } } }
    func line(number: Int) -> ScriptLine? { lines.first { $0.number == number } }
    func index(of id: String?) -> Int? { id.flatMap { id in lines.firstIndex { $0.id == id } } }
    func scene(of line: ScriptLine) -> ScriptScene? { scenes.first { $0.lines.contains { $0.id == line.id } } }
    /// The line at a time in the cut: the one playing, else the last one that started.
    func line(at time: Double) -> ScriptLine? {
        if let playing = lines.first(where: { time >= $0.start - 0.05 && time < $0.end + 0.25 }) { return playing }
        return lines.last { $0.start <= time }
    }
    func takeLabel(_ assetID: String) -> String { takeLabels[assetID] ?? assetID }
    /// Lines whose words, read together, are exactly `text`: a held passage, or a struck line.
    func run(matching text: String) -> [ScriptLine] {
        let target = ScriptText.normalized(text)
        guard !target.isEmpty else { return [] }
        for i in lines.indices {
            var words: [String] = []
            for j in i..<lines.count {
                words += ScriptText.normalized(lines[j].text)
                if words == target { return Array(lines[i...j]) }
                if words.count >= target.count || words != Array(target.prefix(words.count)) { break }
            }
        }
        return []
    }
}

// MARK: Text

enum ScriptText {
    /// Lowercased words without punctuation; curly apostrophes folded.
    static func normalized(_ text: String) -> [String] {
        let trim = CharacterSet.punctuationCharacters.union(.symbols).subtracting(CharacterSet(charactersIn: "'"))
        return text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .split { $0.isWhitespace || $0 == "\u{2014}" || $0 == "\u{2013}" }
            .map { $0.trimmingCharacters(in: trim) }
            .filter { !$0.isEmpty }
    }
    static func key(_ text: String) -> String { normalized(text).joined(separator: " ") }

    /// 1 for the same words or one inside the other; otherwise the share of words in common, in order.
    static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        if short.count >= 3, contains(long, short) { return 1 }
        if short.count <= 2 { return 0 }
        var row = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var diagonal = 0
            for j in 1...b.count {
                let above = row[j]
                row[j] = x == b[j - 1] ? diagonal + 1 : max(row[j], row[j - 1])
                diagonal = above
            }
        }
        return 2 * Double(row[b.count]) / Double(a.count + b.count)
    }
    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle { return true }
        return false
    }
    /// "no one" for "nobody" is the same line; "I set out to make a film" and "I didn't set out to build a tool" aren't.
    static let sameLine = 0.75

    /// A line quoted in a note. A line that starts on a conjunction is mid-thought, so
    /// "And that's when…" reads as “and that’s when…”.
    static func quoted(_ text: String) -> String {
        let lowered: Set = ["and", "but", "or", "so", "then", "nor", "yet"]
        var t = text
        if let first = normalized(text).first, lowered.contains(first), let c = t.first { t.replaceSubrange(t.startIndex...t.startIndex, with: String(c).lowercased()) }
        return "\u{201C}\(t)\u{201D}"
    }

    static func spelled(_ n: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(n) ? words[n] : String(n)
    }
}

// MARK: Building

extension ScriptDocument {
    /// A line as one take says it, before it's placed in any cut.
    struct SourceLine {
        enum Kind { case dialogue, action, slug }
        var index: Int
        var kind: Kind
        var speaker: String?
        var wordIDs: [String]
        var text: String
        var norm: [String]
        var start: Double
        var end: Double
        var aside: String?
    }

    /// Splits one take's words into lines. See the conventions at the top of this file.
    static func sourceLines(_ unsorted: [TranscriptWord]) -> [SourceLine] {
        let words = unsorted.sorted { $0.range.start < $1.range.start }
        var out: [SourceLine] = []
        var speaker: String?
        var current: [TranscriptWord] = []
        func flush() {
            guard !current.isEmpty else { return }
            let text = current.map(\.text).joined(separator: " ")
            out.append(.init(index: out.count, kind: .dialogue, speaker: speaker, wordIDs: current.map(\.id), text: text, norm: ScriptText.normalized(text), start: current[0].range.start.seconds, end: current.last!.range.end.seconds))
            current = []
        }
        var i = 0
        while i < words.count {
            let word = words[i]
            if word.text.hasPrefix("[") {
                var j = i
                while j < words.count - 1 && !words[j].text.hasSuffix("]") { j += 1 }
                let parts = Array(words[i...j])
                let text = parts.map(\.text).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                let start = parts[0].range.start.seconds, end = parts.last!.range.end.seconds
                let previousEnd = current.last?.range.end.seconds ?? (out.last?.kind == .dialogue ? out.last?.end : nil)
                let upper = text.uppercased()
                if upper.hasPrefix("INT.") || upper.hasPrefix("EXT.") || upper.hasPrefix("INT/EXT") || upper.hasPrefix("I/E") {
                    flush()
                    out.append(.init(index: out.count, kind: .slug, wordIDs: parts.map(\.id), text: text, norm: [], start: start, end: end))
                } else if let previousEnd, start - previousEnd < 0.3 || text.first?.isLowercase == true {
                    flush()
                    if out.last?.kind == .dialogue { out[out.count - 1].aside = text.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                } else {
                    flush()
                    out.append(.init(index: out.count, kind: .action, wordIDs: parts.map(\.id), text: text, norm: ScriptText.normalized(text), start: start, end: end))
                }
                i = j + 1; continue
            }
            if let (label, last) = speakerLabel(words, at: i) { flush(); speaker = label; i = last + 1; continue }
            if let previous = current.last {
                let gap = word.range.start.seconds - previous.range.end.seconds
                if gap >= 1.0 || (gap >= 0.35 && previous.text.hasSuffix(",")) { flush() }
            }
            current.append(word)
            if endsSentence(word.text) { flush() }
            i += 1
        }
        flush()
        return out
    }

    private static func speakerLabel(_ words: [TranscriptWord], at i: Int) -> (String, Int)? {
        func labelToken(_ s: String) -> Bool {
            let letters = s.filter(\.isLetter)
            return !letters.isEmpty && letters == letters.uppercased() && s.allSatisfy { $0.isLetter || $0.isNumber || "().'\u{2019}-:".contains($0) }
        }
        var j = i
        while j < min(words.count, i + 4), labelToken(words[j].text) {
            if words[j].text.hasSuffix(":") {
                let label = words[i...j].map(\.text).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                return label.filter(\.isLetter).count >= 2 ? (label, j) : nil
            }
            j += 1
        }
        return nil
    }

    private static func endsSentence(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201D}\u{2019})"))
        return t.hasSuffix(".") || t.hasSuffix("?") || t.hasSuffix("!") || t.hasSuffix("\u{2026}") || t.hasSuffix("\u{2014}") || t.hasSuffix("--")
    }

    /// A shoot-wide line: one number, and every take's version of it.
    private struct Entry {
        var kind: SourceLine.Kind
        var norm: [String]
        var members: [(assetID: String, line: Int)]
    }

    static func build(project: Project?, sequence: DirectionCore.Sequence?, transcripts: [SourceTranscript], dailies: Dailies, cutScenes: [StripScene]) -> ScriptDocument {
        var doc = ScriptDocument()
        guard let project, let sequence else { return doc }
        let assets = Dictionary(project.assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func audioOnly(_ id: String) -> Bool { assets[id].map { $0.video.isEmpty && !$0.isImage } ?? false }
        for id in assets.keys {
            let t = dailies.take(id)
            doc.takeLabels[id] = [t.setupCode, t.code].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? assets[id]?.name ?? id
        }

        // Each asset's chosen transcript, split into lines.
        let selected = Dictionary(grouping: transcripts, by: \.assetID).compactMapValues { $0.max { ($0.selectedAt ?? 0) < ($1.selectedAt ?? 0) } }
        let source = selected.mapValues { sourceLines($0.words) }
        var lineOfWord: [String: [String: Int]] = [:]
        for (asset, lines) in source { for line in lines { for w in line.wordIDs { lineOfWord[asset, default: [:]][w] = line.index } } }

        // Shoot-wide numbering, scene by scene: setup by setup, the circled take first in each.
        func order(_ a: String, _ b: String) -> Bool {
            let ta = dailies.take(a), tb = dailies.take(b)
            if audioOnly(a) != audioOnly(b) { return !audioOnly(a) }
            let sa = ta.setupCode ?? "", sb = tb.setupCode ?? ""
            if sa != sb { return sa.localizedStandardCompare(sb) == .orderedAscending }
            if ta.circled != tb.circled { return ta.circled }
            return doc.takeLabel(a).localizedStandardCompare(doc.takeLabel(b)) == .orderedAscending
        }
        let sceneOrder = dailies.scenes.sorted { $0.number < $1.number }.map(\.id)
        var groups: [[String]] = sceneOrder.map { id in source.keys.filter { dailies.take($0).sceneID == id }.sorted(by: order) }
        groups.append(source.keys.filter { id in dailies.take(id).sceneID.map { !sceneOrder.contains($0) } ?? true }.sorted(by: order))
        var entries: [Entry] = []
        var slugByScene: [String: String] = [:]
        for (g, group) in groups.enumerated() {
            var local: [Entry] = []
            for asset in group {
                // Lines before this take's first match wait, so they land just before it
                // (or after everything, if the take shares no line with the others).
                var cursor: Int?
                var lead: [Entry] = []
                for line in source[asset] ?? [] {
                    if line.kind == .slug {
                        if g < sceneOrder.count, slugByScene[sceneOrder[g]] == nil { slugByScene[sceneOrder[g]] = line.text.uppercased() }
                        continue
                    }
                    // The closest line; among equals, the first one after this take's last match.
                    func rank(_ k: Int, _ s: Double) -> (Double, Int) { (s, cursor.map { k > $0 ? 1 : 0 } ?? 1) }
                    var best: (Int, Double)?
                    for (k, e) in local.enumerated() where e.kind == line.kind {
                        let s = ScriptText.similarity(e.norm, line.norm)
                        guard s >= ScriptText.sameLine else { continue }
                        if best.map({ rank(k, s) > rank($0.0, $0.1) }) ?? true { best = (k, s) }
                    }
                    let entry = Entry(kind: line.kind, norm: line.norm, members: [(asset, line.index)])
                    if var (k, _) = best {
                        if !lead.isEmpty { local.insert(contentsOf: lead, at: k); k += lead.count; lead = [] }
                        local[k].members.append((asset, line.index)); cursor = k
                    } else if let c = cursor {
                        local.insert(entry, at: c + 1); cursor = c + 1
                    } else {
                        lead.append(entry)
                    }
                }
                local += lead
            }
            entries += local
        }
        var entryOf: [String: Int] = [:]
        for (k, e) in entries.enumerated() { for m in e.members { entryOf["\(m.assetID):\(m.line)"] = k } }

        // The cut's words, then runs of words from one source line in one clip.
        var words = TranscriptEditing.words(in: sequence, transcripts: transcripts)
        var voice = sequence
        voice.clips = sequence.clips.filter { $0.kind == .audio && $0.assetID.map(audioOnly) == true }
        if !voice.clips.isEmpty { words += TranscriptEditing.words(in: voice, transcripts: transcripts) }
        words.sort { $0.range.start < $1.range.start }
        struct Run { var asset: String; var clip: String; var line: Int; var words: [TimelineWord] }
        var runs: [Run] = []
        for w in words {
            guard let index = lineOfWord[w.assetID]?[w.sourceWordID], let line = source[w.assetID]?[index], line.kind != .slug else { continue }
            if let last = runs.last, last.asset == w.assetID, last.clip == w.clipID, last.line == index { runs[runs.count - 1].words.append(w) }
            else { runs.append(Run(asset: w.assetID, clip: w.clipID, line: index, words: [w])) }
        }

        let sceneByID = Dictionary(dailies.scenes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var lines: [ScriptLine] = []
        for run in runs {
            guard let src = source[run.asset]?[run.line] else { continue }
            let start = run.words[0].range.start.seconds, end = run.words.last!.range.end.seconds
            var text = run.words.map(\.text).joined(separator: " ")
            if src.kind == .action { text = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")) }
            let entry = entryOf["\(run.asset):\(run.line)"]
            let number = entry.map { $0 + 1 } ?? (entries.count + lines.count + 1)
            let picture = cutScenes.first { start >= $0.start && start < $0.end }
            let scene = picture.flatMap { sceneByID[$0.id] } ?? dailies.scene(for: run.asset)
            let norm = ScriptText.normalized(text)
            var readings: [ScriptReading] = []
            // A take in sync with this one recorded the same performance from another angle: not
            // another reading of the line (footage-index.md › Sync).
            let angles = Set(dailies.syncGroup(for: run.asset)?.takes.map(\.assetID) ?? []).subtracting([run.asset])
            for m in entry.map({ entries[$0].members }) ?? [(run.asset, run.line)] where !angles.contains(m.assetID) {
                guard let l = source[m.assetID]?[m.line] else { continue }
                let off = l.speaker.map { $0.contains("O.S") || $0.contains("OFF") } ?? false
                readings.append(.init(assetID: m.assetID, lineIndex: m.line, text: l.text.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")), start: l.start, end: l.end, exact: l.norm == norm || l.norm == src.norm, offCamera: off, aside: l.aside))
            }
            var speaker = src.kind == .dialogue ? src.speaker : nil
            if let s = speaker, audioOnly(run.asset), !s.contains("(") { speaker = s + " (V.O.)" }
            lines.append(ScriptLine(id: "\(run.clip):\(run.line)", number: number, kind: src.kind == .action ? .action : .dialogue, speaker: speaker, text: text,
                                    start: start, end: end, assetID: run.asset, clipID: run.clip, sceneID: scene?.id, sceneNumber: scene?.number ?? picture?.number ?? 0, readings: readings))
        }

        // Scenes in cut order; a speaker is named on the first line of each speech.
        var scenes: [ScriptScene] = []
        for line in lines {
            let id = line.sceneID ?? "scene-\(line.sceneNumber)"
            if scenes.last?.id != id {
                let s = line.sceneID.flatMap { sceneByID[$0] }
                scenes.append(ScriptScene(id: id, number: line.sceneNumber, title: s?.title ?? "", slugline: line.sceneID.flatMap { slugByScene[$0] }, locked: s?.locked ?? false, lines: [], columns: [], voiceOverOnly: false))
            }
            var l = line
            if l.kind == .dialogue, let s = l.speaker, shownSpeaker(scenes[scenes.count - 1].lines) == s { l.speaker = nil }
            scenes[scenes.count - 1].lines.append(l)
        }
        for i in scenes.indices {
            let sceneLines = scenes[i].lines
            scenes[i].voiceOverOnly = sceneLines.allSatisfy { audioOnly($0.assetID) }
            let inCut = Set(sceneLines.map(\.assetID))
            let covering = Set(sceneLines.flatMap { $0.readings.map(\.assetID) })
            let candidates = covering.filter { id in !audioOnly(id) && (inCut.contains(id) || dailies.take(id).sceneID == scenes[i].id) }
            scenes[i].columns = candidates.sorted { doc.takeLabel($0).localizedStandardCompare(doc.takeLabel($1)) == .orderedAscending }.prefix(7).map { id in
                let t = dailies.take(id)
                return ScriptColumn(assetID: id, setup: t.setupCode ?? "", take: (t.code ?? "").replacingOccurrences(of: "T", with: ""))
            }
        }
        doc.scenes = scenes
        doc.lines = scenes.flatMap(\.lines)
        doc.dialogueSeconds = doc.lines.filter { $0.kind == .dialogue }.reduce(0) { $0 + $1.duration }
        let videoInCut = Set(sequence.clips.filter { $0.kind == .video }.compactMap(\.assetID))
        doc.untranscribed = videoInCut.filter { selected[$0] == nil && !(assets[$0]?.audio.isEmpty ?? true) }.sorted()
        return doc
    }

    /// The speaker last named in a run of dialogue.
    private static func shownSpeaker(_ lines: [ScriptLine]) -> String? {
        for line in lines.reversed() { if line.kind != .dialogue { return nil }; if let s = line.speaker { return s } }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

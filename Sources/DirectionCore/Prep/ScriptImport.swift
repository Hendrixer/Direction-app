import Foundation

/// Reads a script into rows of the A/V script (specs/script.md › Bringing in a script). The words go in the
/// sound column as written; picture ideas the writer left ("[me at the desk]") become each row's hint.
///
/// - Markdown or plain text: headings are sections, paragraphs are voice-over a beat or two at a time,
///   "NAME: words" is someone on camera, a line on its own like "[ON CAMERA]" or "[VO]" switches what follows.
/// - A two-column table (Picture | Sound, Video | Audio) keeps both columns.
/// - Fountain: scene headings are sections, dialogue is on camera (V.O. is voice-over), action is picture.
public enum ScriptImport {
    public struct Result: Sendable {
        public var sections: [AVSection]; public var rows: [AVRow]; public var words: Int
        /// A story's writer's notes: everything around the beats they numbered.
        public var notes: String? = nil
    }

    public static func read(_ text: String, fileName: String) -> Result {
        let lines = clean(text)
        let rows: (sections: [AVSection], rows: [AVRow])
        if let table = table(lines) { rows = table }
        else if [".fountain", ".fdx"].contains(where: fileName.lowercased().hasSuffix) || lines.contains(where: isSceneHeading) { rows = fountain(lines) }
        else { rows = prose(lines) }
        return Result(sections: rows.sections, rows: rows.rows, words: rows.rows.reduce(0) { $0 + AVScript.wordCount($1.sound.text) })
    }

    /// A story in beats (specs/script.md › From a story): headings are sections, each sentence or two of a
    /// paragraph a beat with that part of the story on it; the sound is left for the editor, since nobody's
    /// words are written. A "[…]" picture idea is the beat's hint, as in a script.
    ///
    /// A treatment numbers its beats ("**1 · Assembly · 0:00–0:05.**", "Beat 3:"): then each numbered paragraph
    /// is one beat as the writer wrote it, timed from its times, and the rest (the idea, the rules, questions
    /// for the director) is the writer's notes, kept as written for the editor rather than laid out.
    public static func story(_ text: String, fileName: String) -> Result {
        let lines = clean(text)
        let numbered = lines.contains(where: isNumberedBeat)
        var sections: [AVSection] = [], rows: [AVRow] = [], section: String?, paragraph: [String] = [], pendingHint: String?, words = 0
        var notes: [String] = [], heading: String?, pendingSection: String?
        let headings = lines.filter { $0.hasPrefix("#") }.count
        var sawContent = false
        func note(_ lines: [String]) {
            if let h = heading { notes.append(h); heading = nil }
            notes.append(lines.joined(separator: "\n"))
        }
        func add(_ told: String, hint: String?, seconds: Double) {
            if let title = pendingSection { let s = AVSection(title: title); sections.append(s); section = s.id; pendingSection = nil }
            words += AVScript.wordCount(told)
            rows.append(AVRow(section: section, sound: AVSound(), seconds: seconds, hint: [pendingHint, hint].compactMap { $0 }.joined(separator: " ").nilIfEmpty, story: told))
            pendingHint = nil
        }
        func flush() {
            guard !paragraph.isEmpty else { return }
            defer { paragraph = [] }
            if numbered {
                guard let first = paragraph.first, isNumberedBeat(first) else { note(paragraph); return }
                let (told, hint) = takeHints(paragraph.map(plain).joined(separator: " "))
                guard !told.isEmpty else { return }
                let n = Double(AVScript.wordCount(told))
                add(told, hint: hint, seconds: writersTime(first) ?? max(2, min(20, (n / 2.5 * 2).rounded() / 2)))
                return
            }
            for beat in storyBeats(paragraph.joined(separator: " ")) {
                let (told, hint) = takeHints(beat)
                guard !told.isEmpty else { if let hint { pendingHint = [pendingHint, hint].compactMap { $0 }.joined(separator: " ") }; continue }
                let n = Double(AVScript.wordCount(told))
                add(told, hint: hint, seconds: max(2, min(8, (n / 2.5 * 2).rounded() / 2)))
            }
        }
        for raw in lines {
            if raw.isEmpty { flush(); continue }
            if raw.hasPrefix("#") {
                flush()
                let title = plain(raw.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                if !sawContent, raw.hasPrefix("# "), headings > 1, sections.isEmpty { sawContent = true; continue }
                sawContent = true
                heading = raw
                // With numbered beats, a section is kept only once a beat comes in it.
                if !title.isEmpty { if numbered { pendingSection = title } else { let s = AVSection(title: title); sections.append(s); section = s.id } }
                continue
            }
            if raw.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { flush(); continue }
            sawContent = true
            if let hint = pictureLine(plain(raw)) { flush(); pendingHint = [pendingHint, hint].compactMap { $0 }.joined(separator: " "); continue }
            paragraph.append(numbered ? raw : plain(raw))
        }
        flush()
        if let h = pendingHint, !rows.isEmpty { rows[rows.count - 1].hint = [rows[rows.count - 1].hint, h].compactMap { $0 }.joined(separator: " ") }
        let kept = notes.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(sections: sections, rows: rows, words: words, notes: kept.isEmpty ? nil : kept)
    }

    /// A paragraph the writer numbered as a beat: "**1 · Assembly · 0:00–0:05.**", "Beat 3: …", "Scene 2 —".
    static func isNumberedBeat(_ raw: String) -> Bool {
        raw.range(of: #"^(\*\*|__)?\s*((beat|scene)\s+)?\d{1,3}\s*(·|—|–|:|\.|\))"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// How long the writer gave a beat, from the times in its lead: "0:05–0:13" is 8 seconds.
    static func writersTime(_ raw: String) -> Double? {
        let lead = String(raw.prefix(80))
        guard let r = lead.range(of: #"(\d{1,2}):(\d{2})(?:\.\d+)?\s*[–—-]\s*(\d{1,2}):(\d{2})"#, options: .regularExpression) else { return nil }
        let parts = lead[r].split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
        guard parts.count >= 4 else { return nil }
        let seconds = (parts[parts.count - 2] * 60 + parts[parts.count - 1]) - (parts[0] * 60 + parts[1])
        return seconds > 0 ? min(600, max(0.5, seconds)) : nil
    }

    /// A paragraph of story in beats: a sentence each, a short one ("She erases it.") kept with the one
    /// before, never more than about 24 words.
    static func storyBeats(_ text: String) -> [String] {
        var out: [String] = [], current: [String] = []
        func count(_ s: [String]) -> Int { s.reduce(0) { $0 + AVScript.wordCount($1) } }
        for s in sentences(text) {
            if !current.isEmpty, AVScript.wordCount(s) >= 5 || count(current) + AVScript.wordCount(s) > 24 { out.append(current.joined(separator: " ")); current = [] }
            current.append(s)
        }
        if !current.isEmpty { out.append(current.joined(separator: " ")) }
        return out
    }

    // MARK: Cleaning

    /// Lines without front matter, comments or Fountain's boneyard.
    static func clean(_ text: String) -> [String] {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if s.hasPrefix("---\n"), let end = s.range(of: "\n---\n", range: s.index(s.startIndex, offsetBy: 4)..<s.endIndex) { s = String(s[end.upperBound...]) }
        for (open, close) in [("<!--", "-->"), ("/*", "*/"), ("[[", "]]")] {
            while let a = s.range(of: open), let b = s.range(of: close, range: a.upperBound..<s.endIndex) { s.removeSubrange(a.lowerBound..<b.upperBound) }
        }
        return s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Markdown emphasis, quotes and list markers off; the words stay.
    static func plain(_ line: String) -> String {
        var s = line
        for prefix in ["> ", "- ", "* ", "+ "] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if let r = s.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) { s.removeSubrange(r) }
        s = s.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w])[*_]([^*_]+)[*_](?![\w])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Prose (Markdown, plain text)

    static func prose(_ lines: [String]) -> ([AVSection], [AVRow]) {
        var sections: [AVSection] = [], rows: [AVRow] = []
        var section: String?, kind = HeardKind.voice, pendingHint: String?, paragraph: [String] = []
        let headings = lines.filter { $0.hasPrefix("#") }.count
        var sawContent = false

        func addRow(_ sound: AVSound, hint: String?) {
            var row = AVRow(section: section, sound: sound)
            row.hint = [pendingHint, hint].compactMap { $0 }.joined(separator: " ").nilIfEmpty
            pendingHint = nil
            rows.append(row)
        }
        // A picture idea in the words belongs to the beat it's in.
        func flush() {
            guard !paragraph.isEmpty else { return }
            var body = paragraph.joined(separator: " "), heard = kind, speaker: String?
            paragraph = []
            if let (name, said) = speakerLine(body) {
                let voice = ["VO", "V.O.", "NARRATOR", "NARRATION", "VOICE", "VOICEOVER", "VOICE-OVER"].contains(name.uppercased())
                body = said; heard = voice ? .voice : .onCamera; speaker = voice ? nil : name
            }
            for beat in beats(body) {
                let (words, hints) = takeHints(beat)
                guard !words.isEmpty else { if let h = hints { pendingHint = [pendingHint, h].compactMap { $0 }.joined(separator: " ") }; continue }
                addRow(AVSound(kind: heard, speaker: speaker, text: words), hint: hints)
            }
        }

        for raw in lines {
            if raw.isEmpty { flush(); continue }
            if raw.hasPrefix("#") {
                flush()
                let title = plain(raw.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                // The film's own title at the top, when the script has sections under it.
                if !sawContent, raw.hasPrefix("# "), headings > 1, sections.isEmpty { sawContent = true; continue }
                sawContent = true
                if !title.isEmpty { let s = AVSection(title: title); sections.append(s); section = s.id }
                continue
            }
            if raw.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { flush(); continue }
            sawContent = true
            let line = plain(raw)
            if let mode = modeSwitch(line) { flush(); kind = mode; continue }
            if let hint = pictureLine(line) { flush(); pendingHint = [pendingHint, hint].compactMap { $0 }.joined(separator: " "); continue }
            // A "NAME:" line starts its own beat even without a blank line before it.
            if speakerLine(line) != nil { flush() }
            paragraph.append(line)
        }
        flush()
        if let h = pendingHint, !rows.isEmpty { rows[rows.count - 1].hint = [rows[rows.count - 1].hint, h].compactMap { $0 }.joined(separator: " ") }
        return (sections, rows)
    }

    /// "[ON CAMERA]", "On camera", "VO" on a line of their own.
    static func modeSwitch(_ line: String) -> HeardKind? {
        let s = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]():*_ ")).uppercased()
        if ["ON CAMERA", "ON-CAMERA", "TO CAMERA", "SYNC", "TALKING HEAD"].contains(s) { return .onCamera }
        if ["VO", "V.O.", "V/O", "VOICE-OVER", "VOICEOVER", "VOICE OVER", "NARRATION"].contains(s) { return .voice }
        return nil
    }

    /// A line that's only a picture: "[me at the desk]", "(B-roll: hands)", "PICTURE: …".
    static func pictureLine(_ line: String) -> String? {
        if (line.hasPrefix("[") && line.hasSuffix("]")) || (line.hasPrefix("(") && line.hasSuffix(")")) {
            return stripLabel(String(line.dropFirst().dropLast())).nilIfEmpty
        }
        for label in ["PICTURE:", "VISUAL:", "VISUALS:", "VIDEO:", "B-ROLL:", "BROLL:", "SHOT:", "SHOW:", "ON SCREEN:"] where line.uppercased().hasPrefix(label) {
            return String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
        return nil
    }

    private static func stripLabel(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        for label in ["picture:", "visual:", "visuals:", "video:", "b-roll:", "broll:", "shot:", "show:"] where t.lowercased().hasPrefix(label) { t = String(t.dropFirst(label.count)).trimmingCharacters(in: .whitespaces) }
        return t
    }

    /// The words with "[…]" picture ideas taken out, and those ideas.
    static func takeHints(_ text: String) -> (String, String?) {
        var words = text, hints: [String] = []
        while let r = words.range(of: #"\[[^\]]+\]"#, options: .regularExpression) {
            hints.append(stripLabel(String(words[r].dropFirst().dropLast())))
            words.replaceSubrange(r, with: " ")
        }
        words = words.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return (words, hints.filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty)
    }

    /// "SCOTT: So here's what I think." A name of up to three words, then a colon.
    static func speakerLine(_ line: String) -> (String, String)? {
        guard let r = line.range(of: #"^([A-Z][A-Za-z.'’-]*(?: [A-Z][A-Za-z.'’-]*){0,2}|V\.O\.)\s*(?:\([^)]*\))?:\s+"#, options: .regularExpression) else { return nil }
        let name = String(line[r]).split(separator: ":")[0].replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let said = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        // "Note: …" and the like are words, not a speaker.
        guard !said.isEmpty, !["Note", "Notes", "Update", "Edit", "Todo", "TODO", "Idea", "Example", "Source", "Link"].contains(name) else { return nil }
        return (name, said)
    }

    /// A paragraph in beats: a sentence or two, about 18 words at most, never split mid-sentence.
    static func beats(_ text: String) -> [String] {
        let sentences = sentences(text)
        var out: [String] = [], current: [String] = []
        func count(_ s: [String]) -> Int { s.reduce(0) { $0 + AVScript.wordCount($1) } }
        for s in sentences {
            if !current.isEmpty, count(current) + AVScript.wordCount(s) > 18 { out.append(current.joined(separator: " ")); current = [] }
            current.append(s)
            if count(current) >= 12 { out.append(current.joined(separator: " ")); current = [] }
        }
        if !current.isEmpty { out.append(current.joined(separator: " ")) }
        return out
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = [], start = text.startIndex
        let ends = try! NSRegularExpression(pattern: #"[.!?…]+["”’)\]]*\s+(?=["“‘(\[]?[A-Z0-9])"#)
        let ns = text as NSString
        for m in ends.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: text) else { continue }
            let piece = text[start..<r.upperBound].trimmingCharacters(in: .whitespaces)
            // "Dr. Smith", "e.g. this": a one-word "sentence" stays with what follows.
            if AVScript.wordCount(piece) < 2 { continue }
            out.append(piece); start = r.upperBound
        }
        let rest = text[start...].trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    // MARK: A two-column table

    static func table(_ lines: [String]) -> ([AVSection], [AVRow])? {
        func cells(_ line: String) -> [String] { line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { plain($0.trimmingCharacters(in: .whitespaces)) } }
        guard let headerIndex = lines.firstIndex(where: { l in
            guard l.hasPrefix("|") else { return false }
            let h = cells(l).map { $0.lowercased() }
            return h.contains { ["picture", "video", "visual", "visuals", "image"].contains($0) } && h.contains { ["sound", "audio", "voice", "narration", "words"].contains($0) }
        }) else { return nil }
        let header = cells(lines[headerIndex]).map { $0.lowercased() }
        guard let p = header.firstIndex(where: { ["picture", "video", "visual", "visuals", "image"].contains($0) }),
              let s = header.firstIndex(where: { ["sound", "audio", "voice", "narration", "words"].contains($0) }) else { return nil }
        var sections: [AVSection] = [], rows: [AVRow] = [], section: String?
        for line in lines[(headerIndex + 1)...] {
            if line.hasPrefix("#") { let s = AVSection(title: plain(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))); sections.append(s); section = s.id; continue }
            guard line.hasPrefix("|"), line.range(of: #"^\|[\s:|-]+\|?$"#, options: .regularExpression) == nil else { continue }
            let c = cells(line)
            let picture = p < c.count ? c[p] : "", said = s < c.count ? c[s] : ""
            guard !picture.isEmpty || !said.isEmpty else { continue }
            var sound = AVSound(kind: said.isEmpty ? .silence : .voice, text: said)
            if let (speaker, words) = speakerLine(said) {
                let voice = ["VO", "V.O.", "NARRATOR", "NARRATION"].contains(speaker.uppercased())
                sound = AVSound(kind: voice ? .voice : .onCamera, speaker: voice ? nil : speaker, text: words)
            }
            var row = AVRow(section: section, sound: sound)
            if !picture.isEmpty { row.picture.text = picture; row.picture.yours = true }
            rows.append(row)
        }
        return (sections, rows)
    }

    // MARK: Fountain

    static func isSceneHeading(_ line: String) -> Bool {
        line.range(of: #"^(INT|EXT|EST|INT\./EXT|INT/EXT|I/E)[. ]"#, options: [.regularExpression, .caseInsensitive]) != nil || (line.hasPrefix(".") && !line.hasPrefix(".."))
    }

    static func fountain(_ lines: [String]) -> ([AVSection], [AVRow]) {
        var sections: [AVSection] = [], rows: [AVRow] = [], section: String?
        var i = 0
        // A title page ("Title: …") runs to the first blank line.
        if lines.first?.range(of: #"^[A-Za-z ]+:"#, options: .regularExpression) != nil { while i < lines.count, !lines[i].isEmpty { i += 1 } }
        func block(from j: Int) -> (lines: [String], next: Int) {
            var k = j, out: [String] = []
            while k < lines.count, !lines[k].isEmpty { out.append(lines[k]); k += 1 }
            return (out, k)
        }
        while i < lines.count {
            let line = lines[i]
            if line.isEmpty { i += 1; continue }
            if isSceneHeading(line) {
                let title = line.hasPrefix(".") ? String(line.dropFirst()) : line
                let s = AVSection(title: title.replacingOccurrences(of: #"\s*#[^#]*#\s*$"#, with: "", options: .regularExpression))
                sections.append(s); section = s.id; i += 1; continue
            }
            let (b, next) = block(from: i)
            defer { i = next }
            // Transitions and page breaks.
            if b.count == 1, line.hasSuffix("TO:") || line.hasPrefix(">") && !line.hasSuffix("<") || line == "===" { continue }
            // Centered text is a title on the picture.
            if b.count == 1, line.hasPrefix(">"), line.hasSuffix("<") {
                var row = AVRow(section: section, sound: AVSound(kind: .silence))
                row.picture = AVPicture(text: "Title: \(line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces))", board: .title); row.picture.yours = true
                rows.append(row); continue
            }
            if b.count >= 2, isCharacterCue(b[0]) {
                let cue = b[0].hasPrefix("@") ? String(b[0].dropFirst()) : b[0]
                let voice = cue.range(of: #"\((V\.?O\.?|VO)\)"#, options: [.regularExpression, .caseInsensitive]) != nil
                let name = cue.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression).replacingOccurrences(of: "^", with: "").trimmingCharacters(in: .whitespaces)
                let said = b.dropFirst().filter { !($0.hasPrefix("(") && $0.hasSuffix(")")) }.map(plain).joined(separator: " ")
                for beat in beats(said) { rows.append(AVRow(section: section, sound: AVSound(kind: voice ? .voice : .onCamera, speaker: name.capitalized, text: beat))) }
                continue
            }
            // Action: what we see, in the writer's words.
            let action = b.map { $0.hasPrefix("!") ? String($0.dropFirst()) : $0 }.map(plain).joined(separator: " ")
            var row = AVRow(section: section, sound: AVSound(kind: .silence))
            row.picture.text = action; row.picture.yours = true
            rows.append(row)
        }
        return (sections, rows)
    }

    static func isCharacterCue(_ line: String) -> Bool {
        if line.hasPrefix("@") { return true }
        let name = line.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression).replacingOccurrences(of: "^", with: "").trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && name == name.uppercased() && name.rangeOfCharacter(from: .letters) != nil && !name.hasSuffix(":") && !isSceneHeading(name)
    }
}

extension String {
    var nilIfEmpty: String? { let t = trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
}

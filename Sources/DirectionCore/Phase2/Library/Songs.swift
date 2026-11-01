import Foundation

// Songs in parts (library.md › Songs in parts): a music library's stems of one song (drums, bass, instruments,
// melody) and its full mix, kept as one song. Direction puts them together from their names and lengths once
// they've been listened to; the director can join a sound to a song, rename the song or take it apart.

/// A song the library keeps in parts.
public struct Song: Hashable, Sendable, Identifiable {
    public var name: String
    /// Its parts: the full mix first, then drums, bass, instruments, melody, vocals, then any other.
    public var parts: [ShelfItem]
    public init(name: String, parts: [ShelfItem]) { self.name = name; self.parts = parts }
    public var id: String { name }

    /// The part that stands for the song: its full mix, or its first stem.
    public var lead: ShelfItem { parts[0] }
    public var hasFullMix: Bool { parts.contains { $0.part == Stems.fullMix } }
    /// The name a part goes by in a note: "Neon Drive Drums".
    public static func name(_ song: String, part: String) -> String { "\(song) \(part)" }

    /// A part by what it is ("drums"), its name in a note ("Neon Drive Drums"), or its own name or file.
    public func part(_ named: String) -> ShelfItem? {
        let n = named.trimmingCharacters(in: .whitespaces).lowercased()
        return parts.first { p in [p.part ?? "", Self.name(name, part: p.part ?? ""), p.name, p.file].contains { $0.lowercased() == n } }
    }

    /// "full mix and 4 stems: Drums, Bass, Instruments, Melody".
    public var partsText: String {
        let stems = parts.compactMap(\.part).filter { $0 != Stems.fullMix }
        let count = stems.count == 1 ? "1 stem" : "\(stems.count) stems"
        return (hasFullMix ? "full mix and \(count)" : count) + (stems.isEmpty ? "" : ": " + stems.joined(separator: ", "))
    }
    /// What Direction measured of the lead, with what the song's in after its length, tempo and key.
    public var summary: String {
        var words = lead.summary.components(separatedBy: " \u{00B7} ")
        words.insert(partsText, at: min(words.count, lead.measured?.key == nil ? 3 : 4))
        return words.joined(separator: " \u{00B7} ")
    }
    /// What the director wrote about the song, kept on each of its parts.
    public var note: String? { parts.lazy.compactMap(\.note).first { !$0.isEmpty } }
    public var source: String? { parts.lazy.compactMap(\.source).first { !$0.isEmpty } }
}

/// Reading a sound's name as a song and a part, and finding the parts of one song among the sounds.
public enum Stems {
    public static let fullMix = "Full mix"
    /// Words in a file's name that say which part it is.
    static let words: [String: String] = [
        "full": fullMix, "main": fullMix, "mix": fullMix, "mixdown": fullMix, "master": fullMix,
        "drums": "Drums", "drum": "Drums", "percussion": "Drums", "perc": "Drums",
        "bass": "Bass", "instruments": "Instruments", "instrument": "Instruments", "inst": "Instruments",
        "melody": "Melody", "melodies": "Melody", "lead": "Melody", "vocals": "Vocals", "vocal": "Vocals", "vox": "Vocals",
        "keys": "Keys", "piano": "Piano", "guitar": "Guitar", "guitars": "Guitar", "synth": "Synth", "synths": "Synth", "strings": "Strings", "pads": "Pads", "fx": "FX",
    ]
    static let noise: Set<String> = ["stem", "stems"]
    /// The order a song's parts are listed in.
    static let order = [fullMix, "Drums", "Bass", "Instruments", "Melody", "Vocals"]
    /// How far apart two parts of one song can be in length: a full mix and its stems are the same length, give or take an encoder's padding.
    static let lengthTolerance = 0.25
    /// A sound heard as an effect this long or longer can still be a stem.
    static let stemLength = 30.0

    /// A file's name as a song and the part it is: "ES_Neon Drive (Drums) - Artist" is the Drums of
    /// "ES Neon Drive - Artist". A name with no part in it is the song itself, and maybe its full mix.
    public static func read(_ name: String) -> (song: String, part: String?) {
        // Words, where each is in the name, and whether it's in brackets.
        var tokens: [(word: String, range: Range<String.Index>, bracketed: Bool)] = []
        var i = name.startIndex, depth = 0
        while i < name.endIndex {
            let c = name[i]
            if "([{".contains(c) { depth += 1 } else if ")]}".contains(c) { depth = max(0, depth - 1) }
            guard c.isLetter || c.isNumber else { i = name.index(after: i); continue }
            let start = i
            while i < name.endIndex, name[i].isLetter || name[i].isNumber || name[i] == "'" { i = name.index(after: i) }
            tokens.append((name[start..<i].lowercased(), start..<i, depth > 0))
        }
        func part(at k: Int) -> (part: String, range: Range<String.Index>)? {
            if tokens[k].word == "mix", k > 0, tokens[k - 1].word == "full" { return (fullMix, tokens[k - 1].range.lowerBound..<tokens[k].range.upperBound) }
            return words[tokens[k].word].map { ($0, tokens[k].range) }
        }
        // The part: the last word in brackets that names one, or else the last after the first word, so a song
        // called "Bass Drop" is a song.
        var found: (part: String, range: Range<String.Index>)?
        for k in tokens.indices.reversed() where tokens[k].bracketed { if let f = part(at: k) { found = f; break } }
        if found == nil { for k in tokens.indices.reversed() where k > 0 || tokens.count == 1 { if let f = part(at: k) { found = f; break } } }
        var cut = found.map { [$0.range] } ?? []
        cut += tokens.filter { noise.contains($0.word) }.map(\.range)
        let part = found?.part
        var song = name
        for r in cut.sorted(by: { $0.lowerBound > $1.lowerBound }) { song.replaceSubrange(r, with: "") }
        return (clean(song), part)
    }

    /// A name without the brackets and separators a part leaves behind.
    static func clean(_ s: String) -> String {
        var s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: #"\(\s*\)|\[\s*\]|\{\s*\}"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*([-–—·,])(\s*[-–—·,])+\s*"#, with: " $1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " -\u{2013}\u{2014}\u{00B7},."))
    }
    static func key(_ s: String) -> String { clean(s).lowercased() }

    /// A music library's code at the start of its file names, and the library: Epidemic Sound's "ES_".
    static let libraries = ["ES": "Epidemic Sound"]

    /// What a music library's file name says of the song: its title, short ("Try Again") and with its version
    /// ("Try Again (Instrumental Version)"), the artist after " - ", and the library its code names.
    /// "ES_Try Again (Instrumental Version) STEMS BASS - mr." is Try Again by mr., from Epidemic Sound.
    public static func title(_ name: String) -> (short: String, long: String, artist: String?, library: String?) {
        var raw = name, library: String?
        if let code = raw.range(of: #"^[A-Z]{2,3}_"#, options: .regularExpression), let l = libraries[String(raw[code].dropLast())] { library = l; raw.removeSubrange(code) }
        let base = read(raw).song
        var long = base, artist: String?
        if let dash = base.range(of: " - ", options: .backwards), let rawDash = raw.range(of: " - ", options: .backwards) {
            long = String(base[..<dash.lowerBound])
            // The artist as written, unless a part is named after it.
            let written = raw[rawDash.upperBound...].trimmingCharacters(in: .whitespaces)
            artist = read(written).part == nil ? written : String(base[dash.upperBound...])
        }
        let short = long.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]\s*$"#, with: "", options: .regularExpression)
        return (short.isEmpty ? long : short, long, artist?.isEmpty == true ? nil : artist, library)
    }

    /// A song put together from the sounds: its name, which part each is, and where it's from when its name says.
    public struct Found: Hashable, Sendable { public var song: String; public var part: String; public var source: String? }

    /// Which of these sounds are parts of one song: music that's been listened to, on its own, the same length
    /// as the others and named the same once its part is taken out, with at least one stem among them. A sound
    /// joins a song already kept the same way. By file. A new song takes its title from the names, the version
    /// too where two would share a title.
    public static func found(_ items: [ShelfItem]) -> [String: Found] {
        var out: [String: Found] = [:]
        func length(_ i: ShelfItem) -> Double? { i.measured?.seconds }
        // A stem heard on its own (drums alone) can sound like an effect, but no effect is as long as a song.
        let open = items.filter { $0.song == nil && length($0) != nil && ($0.kind == .music || ($0.kind == .effect && length($0)! >= stemLength)) }
        var placed = Set<String>()
        // Into a song already kept: named as its parts are, the same length, a part it hasn't got.
        let kept = MediaLibrary.songs(items)
        for song in kept {
            guard let seconds = length(song.lead) else { continue }
            let named = Set(song.parts.map { key(read($0.name).song) } + [key(song.name)])
            var taken = Set(song.parts.compactMap { $0.part?.lowercased() })
            for i in open where !placed.contains(i.file) {
                let r = read(i.name), part: String
                if named.contains(key(r.song)) { part = r.part ?? fullMix } else if named.contains(key(i.name)) { part = fullMix } else { continue }
                guard abs(length(i)! - seconds) <= lengthTolerance, taken.insert(part.lowercased()).inserted else { continue }
                out[i.file] = Found(song: song.name, part: part, source: nil); placed.insert(i.file)
            }
        }
        // New songs: stems named alike, then a full mix that's named as the song is.
        var groups: [String: [(item: ShelfItem, song: String, part: String)]] = [:]
        for i in open where !placed.contains(i.file) {
            let r = read(i.name)
            if let p = r.part, p != fullMix, key(r.song).count >= 2 { groups[key(r.song), default: []].append((i, r.song, p)) }
        }
        for i in open where !placed.contains(i.file) && !(groups.values.contains { $0.contains { $0.item.file == i.file } }) {
            let r = read(i.name)
            if r.part == nil || r.part == fullMix, groups[key(r.song)] != nil { groups[key(r.song)]!.append((i, r.song, fullMix)) }
        }
        // A song named with a part word in it ("Bass Drop") is read as that part of something else; its stems
        // name it whole.
        for (k, g) in groups where g.count == 1 && g[0].part != fullMix && groups[key(g[0].item.name)] != nil {
            groups[key(g[0].item.name)]!.append((g[0].item, g[0].item.name, fullMix)); groups[k] = nil
        }
        var songs: [(title: (short: String, long: String, artist: String?, library: String?), members: [(item: ShelfItem, song: String, part: String)])] = []
        for k in groups.keys.sorted() {
            let g = groups[k]!
            let lengths = g.map { length($0.item)! }.sorted(), middle = lengths[lengths.count / 2]
            var parts = Set<String>(), members: [(item: ShelfItem, song: String, part: String)] = []
            for m in g.sorted(by: { $0.item.name < $1.item.name }) where abs(length(m.item)! - middle) <= lengthTolerance && parts.insert(m.part.lowercased()).inserted { members.append(m) }
            guard members.count >= 2, members.contains(where: { $0.part != fullMix }) else { continue }
            songs.append((title(members.first { $0.part != fullMix }!.item.name), members))
        }
        // The short title where it's the only one; the version where two share it; then the artist.
        var used = Set(kept.map { $0.name.lowercased() })
        for (t, members) in songs {
            let shared = songs.filter { $0.title.short.lowercased() == t.short.lowercased() }.count > 1
            let choices = (shared ? [] : [t.short]) + [t.long] + (t.artist.map { ["\(t.long) - \($0)"] } ?? []) + [members[0].song]
            let name = choices.first { !used.contains($0.lowercased()) } ?? "\(t.long) \(used.count + 1)"
            used.insert(name.lowercased())
            let source = t.library.map { l in t.artist.map { "\(l), by \($0)" } ?? l }
            for m in members { out[m.item.file] = Found(song: name, part: m.part, source: source) }
        }
        return out
    }

    /// Where a part comes in the song's list.
    static func rank(_ part: String?) -> Int { order.firstIndex(of: part ?? "") ?? order.count }
}

extension MediaLibrary {
    /// The songs kept in parts, by name.
    public static func songs(_ items: [ShelfItem]) -> [Song] {
        Dictionary(grouping: items.filter(\.isPart)) { $0.song! }.map { name, parts in
            Song(name: name, parts: parts.sorted { (Stems.rank($0.part), $0.part ?? "") < (Stems.rank($1.part), $1.part ?? "") })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func songs() -> [Song] { Self.songs(items()) }

    /// A song by its name, or the song and the part that a name or a file names ("Neon Drive Drums").
    public static func findSong(_ name: String) -> (song: Song, part: ShelfItem?)? { sounds.findSong(name) }
    public func findSong(_ name: String) -> (song: Song, part: ShelfItem?)? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        let all = songs()
        if let s = all.first(where: { $0.name.lowercased() == n }) { return (s, nil) }
        for s in all { if let p = s.part(name) { return (s, p) } }
        return nil
    }

    /// Puts together the parts of songs found among the sounds (`Stems.found`), after they've been listened to.
    @discardableResult
    public func groupStems() throws -> [ShelfItem] {
        guard shelf == .sounds else { return [] }
        let found = Stems.found(items())
        guard !found.isEmpty else { return [] }
        var changed: [ShelfItem] = []
        for (file, a) in found { changed.append(try update(file) { $0.song = a.song; $0.part = a.part; $0.kind = .music; if ($0.source ?? "").isEmpty { $0.source = a.source } }) }
        return changed
    }

    /// Makes a sound one part of a song ("Neon Drive", "Drums"), or with no song keeps it on its own, so it isn't
    /// put with others again.
    @discardableResult
    public func setSong(_ file: String, song: String?, part: String?) throws -> ShelfItem {
        let name = song?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", what = part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.isEmpty || !what.isEmpty else { throw DirectionError("bad_name", "Say which part of \(name) it is: Drums, Bass, Full mix\u{2026}") }
        if !name.isEmpty, let had = songs().first(where: { $0.name.lowercased() == name.lowercased() }), let other = had.part(what), other.file != file {
            throw DirectionError("name_taken", "\(had.name) already has \(other.part ?? what): \(other.name).")
        }
        let canonical = songs().first { $0.name.lowercased() == name.lowercased() }?.name ?? name
        return try update(file) { $0.song = canonical; $0.part = name.isEmpty ? nil : what }
    }

    /// Gives a song a new name, on every part.
    public func renameSong(_ song: Song, to name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw DirectionError("bad_name", "Give the song a name.") }
        guard clean != song.name else { return }
        guard !songs().contains(where: { $0.name.lowercased() == clean.lowercased() && $0.name != song.name }) else { throw DirectionError("name_taken", "Another song is already called \(clean).") }
        for p in items() where p.song == song.name { try update(p.file) { $0.song = clean } }
    }

    /// Takes a song apart: each of its parts a sound on its own, and kept that way.
    public func partSong(_ song: Song) throws {
        for p in items() where p.song == song.name { try update(p.file) { $0.song = ""; $0.part = nil } }
    }
}

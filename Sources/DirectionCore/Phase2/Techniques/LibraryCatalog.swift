import Foundation

// The library (techniques.md › The library): every transition, move and effect the director can name, each
// with a simple icon of its own, a sentence, and how the editor makes it. Direction's own come first; the
// director's techniques (learned from tutorials) join them, then their sounds and images (library.md).
// "@Name" in a note or the brief names one.

public struct LibraryEntry: Hashable, Sendable, Identifiable {
    /// "builtin-whip", or a technique's id.
    public var id: String
    public var name: String
    /// transition, move or effect; music, sound or image for the director's sounds and images.
    public var kind: String
    public var summary: String
    /// An SF Symbol, monochrome (icons.md), different for every transition, move, effect and technique; a sound
    /// or image shows its kind's.
    public var icon: String
    /// How the editor makes it, in its own words: "transition type whip", "technique Grid flash".
    public var use: String
    /// A technique from the Techniques folder, rather than one of Direction's own.
    public var technique: Technique?
    /// A sound or an image from the director's library; for a song kept in parts, the part that stands for it.
    public var item: ShelfItem?
    /// A song kept in parts (library.md › Songs in parts): every part, the full mix first.
    public var parts: [ShelfItem]?
    /// One part of a song: the song's name. Named on its own in a note ("@Neon Drive Drums"); the Library shows it in its song.
    public var partOf: String?
    public init(id: String, name: String, kind: String, summary: String, icon: String, use: String, technique: Technique? = nil, item: ShelfItem? = nil, parts: [ShelfItem]? = nil, partOf: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.summary = summary; self.icon = icon; self.use = use; self.technique = technique; self.item = item; self.parts = parts; self.partOf = partOf
    }
    public var isBuiltIn: Bool { technique == nil && item == nil }
}

public enum LibraryCatalog {
    /// Direction's own transitions, moves and film looks, in the order the library shows them.
    public static let builtIns: [LibraryEntry] = [
        t("dissolve", "Dissolve", "One shot fades through into the next.", "circle.lefthalf.filled"),
        t("dipToBlack", "Dip to black", "The picture fades to black, then up on the next shot.", "moon.fill"),
        t("dipToWhite", "Dip to white", "A flash to white between two shots.", "sun.max.fill"),
        t("push", "Push", "The new shot pushes the old one out of frame.", "arrow.right.to.line"),
        t("slide", "Slide", "The new shot slides in over the old one.", "rectangle.righthalf.inset.filled"),
        t("whip", "Whip", "A fast pan smeared along its way, onto the next shot.", "wind"),
        t("zoom", "Zoom", "The old shot rushes to the middle and the new one settles out of it.", "plus.magnifyingglass"),
        t("wipe", "Wipe", "An edge crosses the frame onto the new shot.", "rectangle.lefthalf.filled"),
        t("iris", "Iris", "A circle opens onto the new shot.", "circle.circle"),
        m("punchIn", "Punch in", "The framing changes on every jump cut, so no cut looks like a twitch.", "arrow.up.left.and.arrow.down.right", "the punchIn edit over the stretch"),
        m("emphasisPunch", "Emphasis punch", "Cuts in close on one line and back out after it.", "exclamationmark.square", "the emphasisPunch edit on the line"),
        m("slowPush", "Slow push", "The framing creeps in across a long take.", "arrow.up.forward.square", "the slowPush edit over the stretch"),
        m("screenZoom", "Screen zoom", "Zooms to where the action is on a screen recording, and eases out.", "cursorarrow.rays", "autoZoom over the stretch, or zoomTo a point or words on screen"),
        f("blackAndWhite", "Black and white", "Takes the color out.", "circle.righthalf.filled"),
        f("splitTone", "Split tone", "Warm highlights and cool shadows, or the other way.", "paintpalette"),
        f("fade", "Faded", "Lifted blacks and softer contrast, like an old print.", "cloud.fog"),
        f("halation", "Halation", "A red glow bleeds around bright edges, like film.", "light.max"),
        f("bloom", "Bloom", "Highlights glow and spread.", "sparkle"),
        f("soften", "Soften", "Takes the edge off detail, gently.", "drop"),
        f("chromaticAberration", "Color fringe", "Red and blue edges split apart toward the corners.", "aqi.medium"),
        f("vignette", "Vignette", "The corners darken toward the middle.", "smallcircle.filled.circle"),
        f("grain", "Film grain", "Fine moving grain over the picture.", "circle.dotted"),
        f("gateWeave", "Gate weave", "The picture drifts a little, like film in a projector.", "wave.3.right"),
        f("letterbox", "Letterbox", "Black bars for a wider frame.", "rectangle.split.1x2"),
    ]

    private static func t(_ type: String, _ name: String, _ summary: String, _ icon: String) -> LibraryEntry {
        LibraryEntry(id: "builtin-" + type, name: name, kind: "transition", summary: summary, icon: icon, use: "the transition edit with type \(type)")
    }
    private static func m(_ id: String, _ name: String, _ summary: String, _ icon: String, _ use: String) -> LibraryEntry {
        LibraryEntry(id: "builtin-" + id, name: name, kind: "move", summary: summary, icon: icon, use: use)
    }
    private static func f(_ kind: String, _ name: String, _ summary: String, _ icon: String) -> LibraryEntry {
        LibraryEntry(id: "builtin-" + kind, name: name, kind: "effect", summary: summary, icon: icon, use: "addEffect filter.\(kind) on the clip (it's apart from the director's look)")
    }

    /// Icons a technique can take when it names none, or names one already used.
    static let spareIcons = ["square.grid.3x3.fill", "squareshape.split.3x3", "rectangle.split.3x3", "sparkles.rectangle.stack", "film.stack", "rectangle.on.rectangle.angled",
                             "square.stack.3d.forward.dottedline", "circle.hexagongrid", "triangle.lefthalf.filled", "seal", "rhombus", "hexagon", "octagon", "staroflife",
                             "burst", "bolt", "flame", "drop.triangle", "scribble.variable", "lasso", "circle.grid.cross", "square.on.circle", "diamond", "capsule.portrait"]

    /// Everything the director can name, from the folders: Direction's own, their techniques, sounds and images.
    public static func all() -> [LibraryEntry] {
        entries(techniques: TechniqueLibrary.list(in: SharedSettings.techniquesFolder), items: MediaLibrary.shelves.flatMap { $0.items() })
    }

    /// Everything the director can name: Direction's own, then their techniques, each with an icon no other has,
    /// then their sounds and images.
    public static func entries(techniques: [Technique], items: [ShelfItem] = []) -> [LibraryEntry] {
        var used = Set(builtIns.map(\.icon)), out = builtIns
        let builtInNames = Set(builtIns.map { $0.name.lowercased() })
        for t in techniques where !builtInNames.contains(t.name.lowercased()) {
            var icon = t.tokens["icon"].string ?? ""
            if icon.isEmpty || used.contains(icon) { icon = spareIcons.first { !used.contains($0) } ?? "square.dashed" }
            used.insert(icon)
            out.append(LibraryEntry(id: t.id, name: t.name, kind: t.kind == "recipe" ? "move" : t.kind, summary: t.summary, icon: icon,
                                    use: t.kind == "recipe" ? "follow the steps of the technique \(t.name) (direction_technique)" : "the technique edit with name \"\(t.name)\"\(t.kind == "transition" ? " and an editPoint" : " and a clipID")", technique: t))
        }
        let taken = Set(out.map { $0.name.lowercased() })
        for song in MediaLibrary.songs(items) where !taken.contains(song.name.lowercased()) {
            out.append(entry(song))
            out += song.parts.map { entry($0, of: song) }
        }
        for i in items where !i.isPart && !taken.contains(i.name.lowercased()) { out.append(entry(i)) }
        return out
    }

    /// A song kept in parts: brought in whole, then placed with the parts to play.
    public static func entry(_ song: Song) -> LibraryEntry {
        LibraryEntry(id: "song:" + song.name, name: song.name, kind: "music", summary: song.summary, icon: "music.note",
                     use: "direction_import with library \"\(song.name)\" (the film gets its own copy of every part), then placeMusic with its assetID and the parts to play, and parts for where each is heard", item: song.lead, parts: song.parts)
    }
    /// One part of a song, by the name a note gives it.
    public static func entry(_ part: ShelfItem, of song: Song) -> LibraryEntry {
        let what = part.part ?? ""
        return LibraryEntry(id: "sound:" + part.file, name: Song.name(song.name, part: what), kind: "music", summary: part.summary, icon: "music.note",
                            use: "direction_import with library \"\(song.name)\", then placeMusic with parts [\"\(what)\"], or parts to bring it in or out where the song plays", item: part, partOf: song.name)
    }

    /// A sound or image as the library lists it, and how the editor brings it into a film and uses it.
    public static func entry(_ i: ShelfItem) -> LibraryEntry {
        let bring = "direction_import with library \"\(i.name)\" (the film gets its own copy), then"
        return switch i.kind {
        case .music: LibraryEntry(id: "sound:" + i.file, name: i.name, kind: "music", summary: i.summary, icon: "music.note", use: "\(bring) placeMusic with its assetID", item: i)
        case .effect: LibraryEntry(id: "sound:" + i.file, name: i.name, kind: "sound", summary: i.summary, icon: "waveform", use: "\(bring) overwrite it onto A3 where it lands", item: i)
        case .image: LibraryEntry(id: "image:" + i.file, name: i.name, kind: "image", summary: i.summary, icon: "photo", use: "\(bring) cutaway with its assetID, and reframe it to its size and place", item: i)
        }
    }

    /// The entries named with "@Name" in some words, longest name first so "@Grid flash big" finds Grid flash.
    public static func mentions(in text: String, entries: [LibraryEntry]) -> [LibraryEntry] { mentioned(in: text, entries, name: \.name) }

    /// The things named with "@" and their name in some words, each once, longest name first, and only whole
    /// names: "@Scene 2" isn't found in "@Scene 20".
    public static func mentioned<T: Hashable>(in text: String, _ items: [T], name: (T) -> String) -> [T] {
        var found: [T] = []
        for m in mentions(in: text, items, name: name) where !found.contains(m.item) { found.append(m.item) }
        return found
    }

    /// Every "@Name" in some words, where it is: "@" through the end of the name, in the order written. Whole
    /// names only, the longest first, so the words show each as what it names.
    public static func mentions<T>(in text: String, _ items: [T], name: (T) -> String) -> [(item: T, range: Range<String.Index>)] {
        guard text.contains("@") else { return [] }
        var found: [(item: T, range: Range<String.Index>)] = []
        for e in items.sorted(by: { name($0).count > name($1).count }) {
            var from = text.startIndex
            while let r = text.range(of: "@" + name(e), options: .caseInsensitive, range: from..<text.endIndex) {
                from = r.upperBound
                // A whole name: nothing word-like right after it, and not inside a longer one already found.
                let next = r.upperBound < text.endIndex ? text[r.upperBound] : " "
                let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : " "
                guard !(next.isLetter || next.isNumber), !(before.isLetter || before.isNumber), !found.contains(where: { $0.range.overlaps(r) }) else { continue }
                found.append((e, r))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// What the editor reads under a note that names some: "@Grid flash is the technique Grid flash: …".
    public static func explain(_ found: [LibraryEntry]) -> String {
        found.map { e in
            if let parts = e.parts {
                let song = Song(name: e.name, parts: parts)
                let words = [song.note, song.source.map { "From \($0)." }].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return "@\(e.name) is a song in the director's library, in parts (\(song.partsText)): \(song.lead.summary).\(words.isEmpty ? "" : " " + words.joined(separator: " ")) Use \(e.use)."
            }
            if let i = e.item, let song = e.partOf {
                let words = [i.note, i.source.map { "From \($0)." }].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return "@\(e.name) is the \(i.part ?? "part") of \(song), a song in the director's library: \(i.summary).\(words.isEmpty ? "" : " " + words.joined(separator: " ")) Use \(e.use)."
            }
            if let i = e.item {
                let words = [i.note, i.source.map { "From \($0)." }].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return "@\(e.name) is \(i.kind == .image ? "an image" : i.kind == .music ? "music" : "a sound effect") in the director's library: \(i.summary).\(words.isEmpty ? "" : " " + words.joined(separator: " ")) Use \(e.use)."
            }
            return "@\(e.name) is \(e.isBuiltIn ? "Direction's own \(e.kind)" : "the \(e.kind) technique \(e.name)"): \(e.summary) Use \(e.use)."
        }.joined(separator: " ")
    }
}

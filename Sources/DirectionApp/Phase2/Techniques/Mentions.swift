import SwiftUI
import AppKit
import DirectionCore

// "@Name" in what the director writes names a transition, a move, an effect, a sound, an image, or a scene,
// setup or take (techniques.md › The library, notes.md › Naming footage). Wherever it shows, the "@" becomes
// an icon of the kind of thing it names, and the name is in the director's color.
enum Mentions {
    /// The icon of each kind: what it is, not which one.
    static func icon(_ kind: String) -> String {
        switch kind {
        case "transition": "rectangle.2.swap"
        case "move": "camera.viewfinder"
        case "effect": "camera.filters"
        case "music": "music.note"
        case "sound": "waveform"
        case "image": "photo"
        case "scene": "film"
        case "setup": "video"
        default: "play.rectangle"
        }
    }
    static func label(_ kind: String) -> String {
        switch kind {
        case "music": "music"; case "sound": "sound effect"
        default: kind
        }
    }

    /// The library and the film's footage named in some words, where each is.
    @MainActor static func found(in text: String, footage: [FootageName]) -> [(entry: LibraryEntry, range: Range<String.Index>)] {
        guard text.contains("@") else { return [] }
        let library = LibraryModel.shared
        if library.entries.isEmpty { library.load() }
        return LibraryCatalog.mentions(in: text, library.entries + footage.map(\.entry), name: \.name).map { ($0.item, $0.range) }
    }

    /// The words as Text, each name with its kind's icon in place of "@" and in the director's color.
    @MainActor static func text(_ text: String, footage: [FootageName]) -> Text {
        let found = found(in: text, footage: footage)
        guard !found.isEmpty else { return Text(verbatim: text) }
        var out = Text(verbatim: ""), at = text.startIndex
        for (entry, range) in found {
            let name = text[text.index(after: range.lowerBound)..<range.upperBound]
            out = Text("\(out)\(Text(verbatim: String(text[at..<range.lowerBound])))\(Text("\(Image(systemName: icon(entry.kind)))\u{2009}\(Text(verbatim: String(name)))").foregroundStyle(Gate.Voice.director))")
            at = range.upperBound
        }
        return Text("\(out)\(Text(verbatim: String(text[at...])))")
    }
}

/// What a field names, as chips under it: for the brief's text fields, which can't show an icon in their words.
struct MentionChips: View {
    var text: String
    var footage: [FootageName] = []
    var body: some View {
        let found = Mentions.found(in: text, footage: footage)
        var seen = Set<String>()
        let shown = found.map(\.entry).filter { seen.insert($0.id).inserted }
        if !shown.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(shown) { e in
                    HStack(spacing: 4) {
                        Image(systemName: Mentions.icon(e.kind)).font(.system(size: 10, weight: .semibold))
                        Text(e.name).font(Gate.Font.caption).lineLimit(1)
                    }
                    .foregroundStyle(Gate.Voice.director)
                    .padding(.horizontal, 7).frame(height: Gate.Size.chip)
                    .background(RoundedRectangle(cornerRadius: Gate.Radius.chip, style: .continuous).fill(Gate.Voice.directorWash))
                    .help("\(e.name): \(Mentions.label(e.kind)). \(e.summary)")
                    .accessibilityElement(children: .combine).accessibilityLabel("Names the \(Mentions.label(e.kind)) \(e.name)")
                }
            }
        }
    }
}

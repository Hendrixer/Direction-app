import SwiftUI
import DirectionCore

// Keep as a rule (styles.md › Keep as a rule): an answer whose note said something the director wants
// every time can be kept, in the film's style or the house style, and every turnover after follows it.

extension FilmModel {
    /// What this film follows: the house style with its own style over it (samples in previews).
    var appliedStyle: AppliedStyle {
        if isPreview { return StyleSamples.applied(brief.style) }
        return (try? store?.appliedStyle()) ?? StyleLibrary.applied(nil, folder: SharedSettings.stylesFolder)
    }

    func keepRule(_ text: String, area: String?, inFilmStyle: Bool, replacing: [String], noteID: String?) {
        guard !isPreview else { return }
        perform { s in
            let kept = try s.keepRule(text, area: area, inFilmStyle: inFilmStyle, replacing: replacing, noteID: noteID)
            toast = Toast(title: "Kept as a rule", detail: kept.styleID == StyleLibrary.houseID ? "Every film follows it from its next turnover." : "\(kept.styleName) films follow it from their next turnover.")
        }
    }
}

/// "Keep as a rule": the editor's wording to edit, and where it goes.
struct KeepRulePopover: View {
    var model: FilmModel
    var note: ReviewComment
    var suggestion: RuleSuggestion?
    var done: () -> Void
    private let applied: AppliedStyle
    @State private var text: String
    @State private var inStyle: Bool

    init(model: FilmModel, note: ReviewComment, suggestion: RuleSuggestion?, done: @escaping () -> Void) {
        self.model = model; self.note = note; self.suggestion = suggestion; self.done = done
        let applied = model.appliedStyle
        self.applied = applied
        _text = State(initialValue: suggestion?.text ?? "")
        _inStyle = State(initialValue: applied.style != nil && suggestion?.scope != "house")
    }

    /// The rules this one takes the place of, as the editor named them.
    private var replaced: [AppliedStyle.Rule] {
        let ids = Set(suggestion?.replaces ?? [])
        return applied.rules.filter { ids.contains($0.rule.id) }
    }

    var body: some View {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep as a rule").font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
            GateTextArea(text: $text, placeholder: "Text never covers my face.", minHeight: 56)
            if let style = applied.style {
                HStack(spacing: 12) {
                    Text("For").font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
                    GateSegmented(options: [(true, "\(style.name) films"), (false, "Every film")], selection: $inStyle)
                }
            }
            Text(inStyle && applied.style != nil
                 ? "It goes into \(applied.style!.name). Films in that style follow it from their next turnover."
                 : "It goes into your house style. Every film follows it, unless its style says otherwise.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
            if !replaced.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("In place of").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    ForEach(replaced, id: \.rule.id) { r in
                        Text("\u{201C}\(r.rule.text)\u{201D} \u{00B7} \(r.styleName)").font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).strikethrough().lineLimit(2)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: done).buttonStyle(.gate(.normal, .small)).keyboardShortcut(.cancelAction)
                Button("Keep") {
                    model.keepRule(words, area: suggestion?.area, inFilmStyle: inStyle && applied.style != nil, replacing: replaced.map(\.rule.id), noteID: note.id)
                    done()
                }
                .buttonStyle(.gate(.steel, .small)).disabled(words.isEmpty || words.count > 300)
            }
        }
        .padding(16).frame(width: 380)
    }
}

import SwiftUI
import DirectionCore

// Where made things show (made-media.md): the Made chip and its provenance popover (61),
// and the money on a spend question (62). Recipes: design/spec/css/made.css.

/// `.chip.made`: a neutral steel chip with the editor's diamond before the word. Opens the provenance.
struct MadeChip: View {
    @Bindable var film: FilmModel
    var record: MadeRecord
    /// Which chip opened the popover: an answer row and an option tile can show the same clip.
    var place: String
    private var key: String { place + ":" + record.assetID }
    private var open: Bool { film.made.provenanceID == key }

    var body: some View {
        Button { film.made.provenanceID = open ? nil : key } label: {
            HStack(spacing: 6) { GemMark(size: 5); Text("Made") }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(open ? Gate.Text.primary : Gate.Text.secondary)
                .lineLimit(1).fixedSize()
                .padding(.leading, 6).padding(.trailing, 7).frame(height: Gate.Size.chip)
                .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(open ? Gate.Surface.hover : Gate.Surface.raised)
                    .overlay(RoundedRectangle(cornerRadius: Gate.Radius.chip).strokeBorder(open ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Snapshots draw the popover where NSPopover puts it; NSPopover doesn't render offscreen.
        .popover(isPresented: Binding(get: { open && !film.isPreview }, set: { if !$0, open { film.made.provenanceID = nil } }), arrowEdge: .bottom) {
            MadeProvenance(film: film, record: record).background(Gate.Surface.panel)
        }
        .help("Made with \(record.versionName). Where it came from")
        .accessibilityLabel("Made with \(record.versionName)")
        .accessibilityHint("Shows what the editor asked for and what it cost")
    }
}

/// The provenance popover (frame 61): `.pop.sec.prov`, 320 wide.
struct MadeProvenance: View {
    var film: FilmModel
    var record: MadeRecord
    var showsDailies = true
    private var playing: Bool { film.made.playingID == record.assetID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.prov-head`: a 14 pt column for the diamond, centered on the title's line, the sub-line under the title.
            HStack(alignment: .top, spacing: 8) {
                GemMark(size: 8).frame(width: 14, height: 17)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Made with \(record.versionName)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).frame(height: 17)
                    Text(record.provenanceLine).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).frame(height: 15)
                }
            }
            .section(first: true)
            if playing && record.kind.isPicture && !film.isPreview {
                PlayerSurface(player: film.made.playerForPicture).aspectRatio(film.aspect, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
                    .padding(.horizontal, 16).padding(.bottom, 14)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("What the editor asked for")
                Text("\u{201C}\(record.asked)\u{201D}").font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary).cssLineHeight(1.5, size: 12.5)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .section()
            VStack(spacing: 8) {
                fact("Version", record.version)
                if let length = record.lengthText { fact("Length", length) }
                fact("Spent", MadeFormat.money(record.spend))
                if let from = record.from { fact("From", (film.takeCode(from.assetID) ?? film.asset(from.assetID)?.name ?? "a take") + " at " + Timecode.format(from.start, fps: film.fps)) }
                fact("For", record.noteID.map { "Note \(film.noteNumber($0))" } ?? "Unasked")
            }
            .section()
            HStack(spacing: 8) {
                if record.kind != .still {
                    Button { film.made.playAlone(record, film: film) } label: { SmallIconLabel(playing ? "Stop" : "Play it alone", icon: playing ? "stop.fill" : "play.fill", size: 9) }
                        .buttonStyle(.gate(.ghost, .small)).help("Plays only what was made, from its start")
                }
                Spacer(minLength: 0)
                if showsDailies {
                    Button { film.made.showInDailies(record, film: film) } label: { SmallIconLabel("Show in Dailies", icon: "square.grid.2x2", size: 10) }
                        .buttonStyle(.gate(.ghost, .small))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(width: 320, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Made with \(record.versionName)")
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(Gate.Text.secondary).lineLimit(1).truncationMode(.middle)
        }
        .frame(height: 15)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// `.pop-sec`: 14/16 padding, a hairline above all but the first.
    func section(first: Bool = false) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .overlay(alignment: .top) { if !first { Hairline() } }
    }
}

enum MadeText {
    /// Words with every "$0.00" in SF Mono (product-model.md › Formats: money is always SF Mono).
    static func money(in text: String, size: CGFloat, mono: CGFloat) -> Text {
        var out = AttributedString(), rest = Substring(text)
        while let r = rest.range(of: #"\$[0-9]+\.[0-9]{2}"#, options: .regularExpression) {
            var before = AttributedString(String(rest[..<r.lowerBound])); before.font = .system(size: size)
            var money = AttributedString(String(rest[r])); money.font = .system(size: mono, weight: .medium, design: .monospaced).monospacedDigit()
            out += before + money
            rest = rest[r.upperBound...]
        }
        var tail = AttributedString(String(rest)); tail.font = .system(size: size)
        return Text(out + tail)
    }
}

// MARK: 62 · A spend question

/// `.spend`: "About $3.20. This turnover would reach $6.10 of your $5.00 limit." Money in SF Mono.
struct SpendLine: View {
    var spend: SpendAsk
    var body: some View {
        line.cssLineHeight(1.5, size: 12.5).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("About \(MadeFormat.money(spend.estimate)). This turnover would reach \(MadeFormat.money(spend.total)) of your \(MadeFormat.money(spend.limit)) limit.")
    }
    private var line: Text {
        func plain(_ s: String, _ c: Color) -> AttributedString { var a = AttributedString(s); a.font = .system(size: 12.5); a.foregroundColor = c; return a }
        func money(_ d: Double, _ c: Color) -> AttributedString { var a = AttributedString(MadeFormat.money(d)); a.font = .system(size: 12, weight: .medium, design: .monospaced).monospacedDigit(); a.foregroundColor = c; return a }
        var out = plain("About ", Gate.Text.secondary) + money(spend.estimate, Gate.Text.primary) + plain(". ", Gate.Text.secondary)
        out += plain("This turnover would reach ", Gate.Text.tertiary) + money(spend.total, Gate.Text.secondary) + plain(" of your ", Gate.Text.tertiary) + money(spend.limit, Gate.Text.secondary) + plain(" limit.", Gate.Text.tertiary)
        return Text(out)
    }
}

/// A spend question's choice (`.choice`): the take, the editor's diamond on its recommendation, money in SF Mono.
struct SpendChoiceRow: View {
    var model: FilmModel
    var question: EditorQuestion
    var choice: QuestionChoice
    var on: Bool
    var pick: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RadioDot(on: on)
            thumb
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text(choice.label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary).lineHeight(12.5, 1.45)
                    if choice.recommended { GemMark(size: 7).help("I\u{2019}d pick this").accessibilityLabel("The editor would pick this") }
                }
                if let detail = choice.detail { detailText(detail).lineHeight(11, 1.45).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(Gate.Surface.raised))
        .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(on ? Gate.Text.primary : Gate.Line.subtle, lineWidth: on ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { pick() }
    }

    private func detailText(_ detail: String) -> Text { MadeText.money(in: detail, size: 11, mono: 10.5).foregroundColor(Gate.Text.tertiary) }

    @ViewBuilder private var thumb: some View {
        if let id = choice.assetID {
            // "Reframe only" shows the reframe the question names ("1.6×").
            TakeThumb(model: model, assetID: id, fallbackScene: model.dailies.scene(for: id)?.number ?? 3)
                .scaleEffect(reframe, anchor: UnitPoint(x: 0.39, y: 0.6)).clipShape(RoundedRectangle(cornerRadius: 4))
        } else if ["find", "search"].contains(where: { choice.label.lowercased().hasPrefix($0) }) {
            RoundedRectangle(cornerRadius: 4).fill(Gate.Surface.sunken).frame(width: 64, height: 36)
                .overlay(Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary))
        }
    }
    private var reframe: CGFloat {
        guard choice.label.lowercased().hasPrefix("reframe"), let r = question.text.range(of: "[0-9]+(\\.[0-9]+)?\u{00D7}", options: .regularExpression),
              let v = Double(question.text[r].dropLast()), v > 1, v < 4 else { return 1 }
        return CGFloat(v)
    }
}

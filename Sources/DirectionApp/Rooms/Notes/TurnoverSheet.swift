import SwiftUI
import AppKit
import DirectionCore

/// Frame 22: hand the whole sheet to the editor at once, with how much room it has.
/// Latitude here applies to this turnover only; the film's default lives in Settings › Editor.
struct TurnoverSheet: View {
    @Bindable var model: FilmModel
    @State private var latitude: Latitude = .faithful
    @State private var waitForOK = true
    @FocusState private var latitudeFocused: Bool

    private var notes: [ReviewComment] { model.readyNotes }
    private var drafts: Int { model.draftNotes.count }
    private var locked: Int { notes.filter(model.isInLockedScene).count }

    var body: some View {
        AttachedSheet(width: 600, onDismiss: cancel) {
            SheetHeader(title: notes.count == 1 ? "Turn over 1 note" : "Turn over \(notes.count) notes",
                        subtitle: waitForOK ? "The editor reads back its plan for each note, and cuts \(model.nextCutName) when you OK it." : "The editor reads back its plan for each note, then cuts \(model.nextCutName).")
            VStack(alignment: .leading, spacing: 14) {
                if drafts > 0 {
                    Text(drafts == 1 ? "1 draft stays behind." : "\(drafts) drafts stay behind.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                }
                CompactNoteList(model: model, notes: notes) { c in model.sheet = nil; model.notesTab = .sheet; model.showNote(c) }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("How much room for this turnover")
                    ForEach(Latitude.allCases, id: \.self) { value in
                        LatitudeCard(value: value, on: latitude == value) { latitude = value }
                    }
                }
                .focusable()
                .focused($latitudeFocused)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { step(-1); return .handled }
                .onKeyPress(.downArrow) { step(1); return .handled }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("How much room for this turnover")
                Toggle(isOn: $waitForOK) { Text("Wait for my OK before cutting").lineHeight(13, 1.45) }.toggleStyle(GateCheckStyle())
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            SheetFooter {
                Text(caption).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            } trailing: {
                Button("Cancel", action: cancel).buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button(action: turnOver) { HStack(spacing: 6) { Image(systemName: "arrow.right"); Text("Turn over"); KeyHint("\u{2318}\u{21A9}") } }
                    .buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command).disabled(notes.isEmpty)
            }
        }
        .onAppear {
            latitude = Latitude(rawValue: model.defaultLatitude) ?? model.directing.latitude
            waitForOK = model.waitForReadBack
            latitudeFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notes.count == 1 ? "Turn over 1 note" : "Turn over \(notes.count) notes")
        .accessibilityAddTraits(.isModal)
    }

    private var caption: String {
        let base = "Notes can\u{2019}t be edited after turnover, only replied to."
        guard locked > 0 else { return base }
        return base + " " + (locked == 1 ? "1 note touches a locked scene." : "\(locked) notes touch a locked scene.") + " The editor will ask before unlocking."
    }
    private func step(_ by: Int) {
        let all = Latitude.allCases, i = all.firstIndex(of: latitude) ?? 1
        latitude = all[max(0, min(all.count - 1, i + by))]
    }
    private func cancel() { model.sheet = nil }
    private func turnOver() {
        guard !notes.isEmpty else { return }
        model.turnOver(latitude: latitude, waitForOK: waitForOK)
        model.notesTab = .sheet
        model.notesUI.cuttingSide = .progress
        model.clearComposer()
        model.selectedNoteID = nil
    }
}

/// `.rcard`: one latitude choice. Selected: raised fill and a 1.5 pt text-1 ring.
struct LatitudeCard: View {
    var value: Latitude
    var on: Bool
    var pick: () -> Void
    var body: some View {
        Button(action: pick) {
            HStack(alignment: .top, spacing: 10) {
                RadioDot(on: on).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(value.label).font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.primary).lineHeight(13, 1.45)
                    Text(value.detail).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.4)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(on ? Gate.Surface.raised : Gate.Surface.panel))
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(on ? Gate.Text.primary : Gate.Line.subtle, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value.label). \(value.detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// `.tlist`: numbered notes on one line each: number, where, words, kind.
struct CompactNoteList: View {
    var model: FilmModel
    var notes: [ReviewComment]
    var onPick: ((ReviewComment) -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, c in
                row(c).padding(.top, index > 0 ? 1 : 0).overlay(alignment: .top) { if index > 0 { Hairline() } }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
    }

    private func row(_ c: ReviewComment) -> some View {
        HStack(spacing: 10) {
            NoteNumber(note: c, size: 12).frame(width: 22, alignment: .leading)
            Group {
                if c.isOutside { Chip(model.anchorStart(c)) } else { Chip(model.anchorStart(c), style: .director) }
            }
            .frame(width: 64, alignment: .leading)
            Mentions.text(c.person.map { "\(c.text) · \($0.name)" } ?? c.text, footage: model.footageNames)
                .font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.isInLockedScene(c) { Chip("Locked scene", icon: "lock.fill", mono: false) }
            else if let kind = c.kind { LabelChip(kind.label) }
            else { Text("\u{2014}").font(.system(size: 12.5)).foregroundStyle(Gate.Text.disabled) }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture { onPick?(c) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.spokenNote(c))
    }
}

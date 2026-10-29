import SwiftUI
import AppKit
import DirectionCore

/// The 380 pt notes sheet: head, tabs (Sheet, Questions, Outside), the list, and a foot.
/// After a turnover the Sheet tab holds the editor's read-back.
struct NotesSheet: View {
    @Bindable var model: FilmModel
    /// Gives keyboard focus back to the room.
    var onLeave: () -> Void

    enum Mode { case notes, questions, outside, readBack(Turnover), waiting(Turnover) }

    private var mode: Mode {
        switch model.notesTab {
        case .questions: return .questions
        case .outside: return .outside
        case .sheet:
            guard let t = model.notesTurnover, model.notesUI.cuttingSide != .notes else { return .notes }
            if t.state == .waiting { return .waiting(t) }
            if t.state == .readBack && !t.readBackApproved { return .readBack(t) }
            return model.notesUI.cuttingSide == .readBack ? .readBack(t) : .notes
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            SheetTabs(model: model)
            content.frame(maxHeight: .infinity, alignment: .top)
            foot
        }
    }

    // MARK: Head

    private var head: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title).font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                MoreMenu(label: "More") { menuItems }
            }
            .frame(height: Gate.Size.controlSmall)
            Text(status).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 16).padding(.horizontal, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A question asked during the read-back (a spend question, frame 62) keeps the read-back's head and foot.
    private var waitingReadBack: Turnover? { model.notesTurnover.flatMap { $0.state == .readBack && !$0.readBackApproved ? $0 : nil } }

    private var title: String {
        switch mode {
        case .readBack, .waiting: "Read-back for \(model.nextCutName)"
        case .questions where waitingReadBack != nil: "Read-back for \(model.nextCutName)"
        default: "Notes on \(model.notesCutName)"
        }
    }

    private var status: String {
        switch mode {
        case .questions where waitingReadBack != nil: return readBackStatus(waitingReadBack!)
        case .readBack(let t): return readBackStatus(t)
        case .waiting(let t):
            let count = t.noteIDs.count == 1 ? "1 note" : "\(t.noteIDs.count) notes"
            return "\(count) turned over at \(model.clockTime(t.createdAt)) · waiting for the editor"
        default:
            return model.sheetStatus
        }
    }

    private func readBackStatus(_ t: Turnover) -> String {
        let when = model.notesUI.now.timeIntervalSince1970 - t.createdAt < 90 ? "just now" : "at \(model.clockTime(t.createdAt))"
        let count = t.noteIDs.count == 1 ? "1 note" : "\(t.noteIDs.count) notes"
        return model.isCutting(t) ? "\(count) turned over \(when) · cutting now" : "\(count) turned over \(when) · waiting for your OK"
    }

    @ViewBuilder private var menuItems: some View {
        if let t = model.notesTurnover {
            let side = model.notesUI.cuttingSide, cutting = model.isCutting(t)
            if cutting { Button("Show Progress") { show(.progress) }.disabled(side == .progress) }
            Button("Show Read-back") { show(.readBack) }
                .disabled(cutting ? side == .readBack || t.readBack.isEmpty : side != .notes)
            Button("Write Notes for the Next Turnover") { show(.notes) }.disabled(side == .notes)
            if [.waiting, .readBack].contains(t.state) && !t.readBackApproved {
                Divider()
                Button("Take Notes Back") { model.takeNotesBack(); model.clearComposer() }
            }
            if !model.runs.startsEditor {
                Divider()
                Button("Copy Request for Your Editor") { model.copyEditorRequest() }
            }
        } else {
            Button("Turn Over…") { model.sheet = .turnover }.disabled(model.readyNotes.isEmpty)
            Toggle("Show Dropped Notes", isOn: $model.showDropped)
            if !model.runs.startsEditor {
                Divider()
                Button("Copy Request for Your Editor") { model.copyEditorRequest() }
            }
        }
    }

    private func show(_ side: CuttingSide) {
        model.notesUI.cuttingSide = side
        model.notesTab = .sheet
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        switch mode {
        case .notes: NoteList(model: model, onLeave: onLeave)
        case .questions: QuestionsTab(model: model)
        case .outside: OutsideTab(model: model)
        case .readBack(let t): ReadBackBody(model: model, turnover: t, onLeave: onLeave)
        case .waiting(let t): WaitingBody(model: model, turnover: t)
        }
    }

    @ViewBuilder private var foot: some View {
        switch mode {
        case .notes:
            NotesComposer(model: model, onLeave: onLeave)
        case .questions:
            if let t = waitingReadBack { ReadBackFoot(model: model, turnover: t) }
            else if let t = model.notesTurnover, model.isCutting(t) { CuttingStatusFoot(model: model, turnover: t) }
        case .outside:
            OutsideFoot(model: model)
        case .readBack(let t):
            ReadBackFoot(model: model, turnover: t)
        case .waiting:
            HStack { Text("Notes can\u{2019}t be edited after turnover, only replied to.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 13).padding(.horizontal, 16).padding(.bottom, 14).hairlineBorder(.top)
        }
    }
}

// MARK: Tabs

/// Sheet · Questions · Outside, each with a mono count. ⌘⌥1–⌘⌥3.
struct SheetTabs: View {
    @Bindable var model: FilmModel
    var body: some View {
        HStack(spacing: 2) {
            tab(.sheet, "Sheet", model.sheetNotes.count, "1")
            tab(.questions, "Questions", model.openQuestions.count, "2")
            tab(.outside, "Outside", model.inbox.count, "3")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 49)
        .hairlineBorder(.bottom)
        .accessibilityElement(children: .contain).accessibilityLabel("Notes tabs")
    }

    private func tab(_ value: NotesTab, _ title: String, _ count: Int, _ key: Character) -> some View {
        let on = model.notesTab == value
        let fresh = value == .questions && count > 0 && !on
        return Button {
            model.notesTab = value
            if value == .sheet, let t = model.notesTurnover, model.isCutting(t), model.notesUI.cuttingSide == .readBack { model.notesUI.cuttingSide = .progress }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(on ? Gate.Text.primary : Gate.Text.tertiary)
                Text("\(count)").font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(fresh ? Gate.Voice.agent : Gate.Text.disabled)
                    .padding(.horizontal, 8).offset(y: -1.5)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .padding(.top, 8).padding(.bottom, 11)
            .overlay(alignment: .bottom) { if on { Gate.Text.primary.frame(height: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [.command, .option])
        .help("\(title) (⌥⌘\(String(key)))" as String)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(gateAnimation(Gate.Motion.snap), value: count)
    }
}

// MARK: Note list

struct NoteList: View {
    @Bindable var model: FilmModel
    var onLeave: () -> Void
    var body: some View {
        let notes = model.sheetNotes
        if notes.isEmpty {
            EmptyStateView(title: "No notes on \(model.notesCutName) yet.", message: "Screen it first, or press N anywhere.") {
                Button("Screen \(model.notesCutName)") { model.go(.screening) }.buttonStyle(.gate(.ghost)).disabled(!model.isEnabled(.screening))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes) { c in
                            NoteRow(model: model, note: c, onSelect: { model.showNote(c); onLeave() })
                                .id(c.id)
                                .transition(.opacity)
                        }
                    }
                    .animation(gateAnimation(Gate.Motion.settle), value: notes.map(\.id))
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.selectedNoteID) { _, id in if let id { withAnimation(gateAnimation(Gate.Motion.snap)) { proxy.scrollTo(id) } } }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Notes on \(model.notesCutName)")
        }
    }
}

/// One numbered note (`.nt`). Number column 26 pt, a meta row of chips, then the words.
struct NoteRow: View {
    @Bindable var model: FilmModel
    var note: ReviewComment
    var onSelect: () -> Void
    @State private var hovered = false

    private var selected: Bool { model.selectedNoteID == note.id }
    private var isDraft: Bool { note.lifecycle == .draft }
    private var writingHere: Bool { selected && isDraft && (model.notesUI.composerFocused || !model.draftText.isEmpty) }
    private var regionHere: Bool { note.region != nil || (selected && isDraft && model.anchorMode == .region) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 4) {
                NoteNumber(note: note)
                if note.lifecycle == .turnedOver { GemMark(size: 5).help("Turned over") }
            }
            .lineHeight(14, 1.25, mono: true)
            .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                FlowLayout(spacing: 5, lineSpacing: 5) { chips }
                words
                if note.lifecycle == .answered, let answer = note.latestAnswer {
                    HStack(alignment: .top, spacing: 8) {
                        GemMark(size: 6).padding(.top, 4)
                        Text(answer.summary).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary).lineHeight(12.5, 1.45)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 12).padding(.bottom, 13).padding(.leading, 14).padding(.trailing, 16)
        .background(selected || hovered ? Gate.Surface.panel : Color.clear)
        .overlay(alignment: .leading) { if selected { Gate.Voice.director.frame(width: 2) } }
        .overlay(alignment: .topTrailing) {
            if hovered && !model.playing {
                MoreMenu(label: "Note \(note.number.map(String.init) ?? "") actions") { NoteContextMenu(model: model, note: note) }
                    .padding(.top, 9).padding(.trailing, 10)
            }
        }
        .hairlineBorder(.bottom)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.editInComposer(note) })
        .contextMenu { NoteContextMenu(model: model, note: note) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spokenNote(note))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "Edit") { model.editInComposer(note) }
        .accessibilityAction(named: "Drop") { model.dropFromSheet(note) }
    }

    @ViewBuilder private var chips: some View {
        if note.isOutside { Chip(model.anchorText(note), icon: model.anchorIcon(note)) }
        else { Chip(model.anchorText(note), style: .director, icon: model.anchorIcon(note)) }
        if regionHere { Chip("Region", icon: "viewfinder") }
        if isDraft {
            if !regionHere { LabelChip("From screening") }
        } else if let kind = note.kind {
            LabelChip(kind.label)
        }
        if note.lifecycle == .reopened { LabelChip("Reopened") }
        if model.isBeforeTurnover(note) && model.isInLockedScene(note) {
            Chip("Locked scene", icon: "lock.fill", mono: false)
                .help("The editor can\u{2019}t change this scene. Unlock it, or keep the note for later.")
        }
        if let person = note.person { Avatar(person: person, size: 18).help(person.role.map { "\(person.name), \($0)" } ?? person.name) }
    }

    @ViewBuilder private var words: some View {
        if isDraft {
            Text(writingHere ? "Writing\u{2026}" : "Add a note, or press \u{232B} to drop this mark.")
                .font(.system(size: 13)).italic().foregroundStyle(Gate.Text.tertiary).lineHeight(13, 1.45)
        } else if note.lifecycle == .dropped {
            Text(note.text).font(.system(size: 13)).strikethrough().foregroundStyle(Gate.Text.disabled).lineHeight(13, 1.45)
        } else {
            Text(note.text).font(.system(size: 13)).foregroundStyle(Gate.Text.primary).lineHeight(13, 1.45)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Outside

struct OutsideTab: View {
    @Bindable var model: FilmModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "eye").font(.system(size: 11, weight: .medium))
                Text("The editor won\u{2019}t see these until you accept them.")
            }
            .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hairlineBorder(.bottom)
            if model.inbox.isEmpty {
                EmptyStateView(title: "No outside notes.", message: "Share a screening link to collect notes from your producer or client.") {
                    Button("Share \(model.notesCutName)\u{2026}") { model.sheet = .share }.buttonStyle(.gate(.ghost))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.inbox) { c in OutsideCard(model: model, note: c).transition(.opacity) }
                    }
                    .animation(gateAnimation(Gate.Motion.settle), value: model.inbox.map(\.id))
                }
            }
        }
    }
}

/// A note from someone with a screening link (`.on-card`). Never amber.
struct OutsideCard: View {
    @Bindable var model: FilmModel
    var note: ReviewComment
    private var person: Person { note.person ?? Person(name: note.author) }
    private var selected: Bool { model.notesUI.selectedOutsideID == note.id }
    private var reaction: Bool { ReactionDetector.isReaction(note.text) }
    private var otherCut: ReviewCut? { note.cutID.flatMap { id in id == model.notesCut?.id ? nil : model.cuts.first { $0.id == id } } }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(person: person, size: 22).help(person.role.map { "\(person.name), \($0)" } ?? person.name)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(person.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    Text([person.role, model.ago(note.createdAt)].compactMap { $0 }.joined(separator: " · ")).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                }
                .lineLimit(1)
                .frame(height: 22)
                HStack(spacing: 5) {
                    Chip(model.anchorStart(note))
                    if reaction { LabelChip("No change asked") }
                    if let otherCut { Chip("On \(otherCut.name)", mono: false) }
                }
                Text(note.text).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).lineHeight(13, 1.45).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) { actions }.padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 14).padding(.bottom, 15).padding(.horizontal, 16)
        .background(selected ? Gate.Surface.panel : Color.clear)
        .hairlineBorder(.bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.name)\(person.role.map { ", \($0.lowercased())" } ?? ""), \(model.anchorStart(note).lowercased()): \(note.text)")
    }

    @ViewBuilder private var actions: some View {
        if reaction {
            Button { model.declineOutside(note.id) } label: { Label("Got it", systemImage: "checkmark") }
                .buttonStyle(.gate(.ghost, .small)).help("Clear it from the inbox")
            Button("Make it a note") { model.acceptOutside(note.id) }.buttonStyle(.gate(.ghost, .small))
        } else {
            Button { model.acceptOutside(note.id) } label: { Label("Accept", systemImage: "checkmark") }
                .buttonStyle(.gate(.normal, .small)).help("Add it to the sheet as the next note")
            Button("Edit first") { model.editOutsideFirst(note) }.buttonStyle(.gate(.ghost, .small)).help("Edit first (E)")
            Button("Decline") { decline() }.buttonStyle(.gate(.ghost, .small)).help("Decline (⌫)")
        }
    }

    private func pick() {
        model.notesUI.selectedOutsideID = note.id
        if let t = model.noteTime(note) ?? model.anchorScene(note)?.start { model.pause(); model.seek(t) }
    }
    private func decline() {
        model.declineOutside(note.id)
        model.toast = Toast(title: "Declined \(person.name)\u{2019}s note")
    }
}

struct OutsideFoot: View {
    var model: FilmModel
    private var people: Int { Set(model.notes.filter { $0.isOutside && $0.cutID == model.notesCut?.id }.compactMap { $0.person?.name }).count }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.system(size: 11, weight: .medium))
            Text(people > 0 ? "Screening link for \(model.notesCutName) · \(people == 1 ? "1 person" : "\(people) people")" : "No screening link for \(model.notesCutName) yet").lineLimit(1)
            Spacer(minLength: 0)
            Button("Manage") { model.sheet = .share }.buttonStyle(.gate(.ghost, .small))
        }
        .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
        .padding(.top, 13).padding(.horizontal, 16).padding(.bottom, 14)
        .hairlineBorder(.top)
    }
}

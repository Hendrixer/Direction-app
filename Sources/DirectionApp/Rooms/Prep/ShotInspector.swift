import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DirectionCore

/// The selected shot (specs/breakdown.md › A shot): what we see, framing, move, source, the rows it plays
/// under, and what to do about it now: add footage you have, decide about a missing shot, answer the editor.
struct ShotInspector: View {
    @Bindable var model: FilmModel
    var breakdown: Breakdown
    var shot: BreakdownShot
    var coverage: ShotCoverage
    @State private var what: String
    @State private var noteText = ""
    @State private var noteKind: NoteKind?
    @State private var dropping = false
    @FocusState private var whatFocus: Bool

    private let rowNumber: [String: Int]

    init(model: FilmModel, breakdown: Breakdown, shot: BreakdownShot, coverage: ShotCoverage, rowNumber: [String: Int]) {
        self.model = model; self.breakdown = breakdown; self.shot = shot; self.coverage = coverage; self.rowNumber = rowNumber
        _what = State(initialValue: shot.what)
    }

    private var script: AVScript { model.script ?? AVScript() }
    private var setup: BreakdownSetup? { breakdown.setup(shot.setupID) }
    private var notes: [PrepNote] { breakdown.notes.filter { $0.state != .dropped && ($0.shotIDs ?? []).contains(shot.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(shot.code).font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary)
                if let s = setup { Text(s.name).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1) }
                Spacer()
                if coverage == .missing, shot.missing == nil { Chip("Missing", style: .bad, mono: false) }
                else if coverage.isIn, breakdown.isOK { Chip("Got it", style: .ok, icon: "checkmark", mono: false) }
            }
            .padding(.horizontal, 16).frame(height: 52)
            .hairlineBorder(.bottom)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    picture
                    if coverage == .missing { missing }
                    if let q = shot.question, q.isOpen { RowQuestion(question: q) { model.answerShot(shot.id, choice: $0) } }
                    SectionLabel("What we see")
                    TextField("", text: $what, axis: .vertical).textFieldStyle(.plain).font(.system(size: 13)).lineLimit(2...5)
                        .padding(.horizontal, 10).padding(.vertical, 8).background(GateFieldBackground(focused: whatFocus))
                        .focused($whatFocus).onSubmit(commitWhat).onChange(of: whatFocus) { _, on in if !on { commitWhat() } }
                        .padding(.top, -6)
                    field("Framing") {
                        GateSelect(options: [(ShotSize?.none, "\u{2014}")] + ShotSize.allCases.map { (Optional($0), $0.label) }, selection: Binding(get: { shot.size }, set: { model.editShot(shot.id, size: .some($0)) }))
                    }
                    field("Move") {
                        GateSelect(options: [(ShotMove?.none, "\u{2014}")] + ShotMove.allCases.map { (Optional($0), $0.label) }, selection: Binding(get: { shot.move }, set: { model.editShot(shot.id, move: .some($0)) }))
                    }
                    field("Length") {
                        HStack(spacing: 8) {
                            Text(Timecode.duration(shot.seconds)).font(Gate.Font.timecode).foregroundStyle(Gate.Text.primary)
                            Text("from \(rowsLabel)").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                        }
                    }
                    field("Source") {
                        let sources = (shot.source == .sound ? [ShotSource.sound] : []) + [ShotSource.shoot, .screen, .make, .have]
                        GateSegmented(options: sources.map { ($0, $0.label) }, selection: Binding(get: { shot.source }, set: { model.editShot(shot.id, source: $0) }))
                    }
                    if shot.source == .make { makeDetail }
                    playsUnder
                    if !notes.isEmpty { VStack(spacing: 0) { ForEach(notes) { n in PrepNoteRow(note: n, anchor: shot.code) { model.dropShotNote(n.id) } } }.padding(.horizontal, -16) }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
            composer
        }
        .background(Gate.Surface.ground)
        .hairlineBorder(.leading)
    }

    private var rowsLabel: String {
        let n = shot.rowIDs.compactMap { rowNumber[$0] }
        return n.count == 1 ? "row \(n[0])" : "rows \(EditorJobs.rowList(n))"
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) { Text(title).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary).frame(width: 64, alignment: .leading); content(); Spacer(minLength: 0) }
    }

    private func commitWhat() {
        let t = what.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != shot.what { model.editShot(shot.id, what: t) }
    }

    // MARK: The picture: a board, the circled take, or a place for footage you have

    @ViewBuilder private var picture: some View {
        if shot.source == .have, !coverage.isIn {
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 22)).foregroundStyle(Gate.Text.tertiary)
                Text("Drop footage here").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.primary)
                Text("A file from Finder, or a take from Dailies").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                HStack(spacing: 8) {
                    Button("Choose a file\u{2026}") { model.chooseFootage(for: shot.id) }.buttonStyle(.gate(.normal, .small))
                    if !model.footage.isEmpty {
                        Menu("Choose a take") {
                            ForEach(model.footage.prefix(40), id: \.id) { a in Button(a.name) { model.attachTake(shot.id, assetID: a.id) } }
                        }.menuStyle(.borderlessButton).fixedSize().buttonStyle(.gate(.normal, .small))
                    }
                }.padding(.top, 2)
            }
            .frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 10).fill(Gate.Surface.sunken))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(dropping ? Gate.Text.primary : Gate.Line.strong))
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                Task { @MainActor in if let url = await FootageFiles.urls(from: providers).first { model.attachFootage(shot.id, url: url) } }
                return true
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ShotPicture(model: model, shot: shot, coverage: coverage, label: [shot.size?.label, shot.move?.label].compactMap { $0 }.joined(separator: " \u{00B7} ").nilIfBlank).aspectRatio(16 / 9, contentMode: .fit)
                if case .got(let ids) = coverage, breakdown.isOK {
                    Text(ids.count == 1 ? "1 take. Circle a different one in Dailies." : "\(ids.count) takes. Circle the one you want in Dailies.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                } else if shot.source != .sound {
                    Text("Drawn by the editor. The take takes its place when it comes in.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                }
            }
        }
    }

    // MARK: A shot that didn't come in

    private var missing: some View {
        let free = shot.estimate == nil
        let choices: [(MissingChoice, String, String)] = [
            (.make, "Make it", free ? "The editor makes it in Direction, for free." : "The editor makes it. About \(PrepDollars.text(shot.estimate ?? 0)), and asks first if it\u{2019}s more."),
            (.pickup, "Pick it up", "It goes on the pickup list for your next shoot."),
            (.without, "Do without it", "Its rows play over the shots around them."),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) { GemMark().padding(.top, 5); Text("No take came in for \(shot.code). What should happen?").font(.system(size: 13)).foregroundStyle(Gate.Text.primary) }
            VStack(spacing: 8) {
                ForEach(choices, id: \.0) { c in
                    Button { model.decideMissing(shot.id, shot.missing == c.0 ? nil : c.0) } label: {
                        HStack(spacing: 10) {
                            RadioDot(on: shot.missing == c.0)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.1).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
                                Text(c.2).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Gate.Surface.raised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(shot.missing == c.0 ? Gate.Text.primary : Gate.Line.subtle, lineWidth: shot.missing == c.0 ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Gate.Surface.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Gate.Voice.agent.opacity(0.35)))
    }

    private var makeDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shot.makePlan ?? (shot.estimate == nil ? "A graphic Direction draws. Free." : "The editor plans how to make it.")).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
            if let e = shot.estimate { Text("About \(PrepDollars.text(e)) to make").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) }
        }
    }

    private var playsUnder: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Plays under")
            ForEach(shot.rowIDs.prefix(4).compactMap { id in rowNumber[id].map { (id, script.rows[$0 - 1]) } }, id: \.0) { id, r in
                // A story's beat is named by its title; under it, what we hear there, like a script's line.
                let lead = r.story.map(ScriptImport.beatLead)
                let kind = r.sound.kind == .onCamera ? (r.sound.speaker ?? "On camera") : r.sound.kind.label
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROW \(rowNumber[id] ?? 0) \u{00B7} \((lead?.title ?? kind).uppercased())").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.6).foregroundStyle(Gate.Text.tertiary)
                    Text(r.sound.text.isEmpty ? (lead?.body ?? r.sound.kind.label) : r.sound.text).font(.system(size: 13)).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Gate.Surface.sunken)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Gate.Line.subtle))
            }
        }
    }

    private var composer: some View {
        let ready = !noteText.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary)
                Text("Note \(breakdown.nextNoteNumber) on").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                Chip(shot.code, style: .director)
            }
            GateTextArea(text: $noteText, placeholder: "Tell the editor what to change\u{2026}", minHeight: 52, onSubmit: { if ready { add() } })
            HStack {
                KindPicker(kind: $noteKind)
                Spacer()
                Button { add() } label: { HStack(spacing: 6) { Text("Add"); KeyHint("\u{21A9}") } }.buttonStyle(.gate(.normal, .regular)).disabled(!ready)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        .hairlineBorder(.top)
    }

    private func add() {
        model.addShotNote(shots: [shot.id], kind: noteKind, text: noteText.trimmingCharacters(in: .whitespacesAndNewlines))
        noteText = ""; noteKind = nil
    }
}

enum PrepDollars {
    static func text(_ d: Double) -> String { d < 10 ? String(format: "$%.2f", d) : String(format: "$%.0f", d) }
}

extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}

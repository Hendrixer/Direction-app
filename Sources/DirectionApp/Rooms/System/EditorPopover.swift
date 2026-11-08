import SwiftUI
import AppKit
import DirectionCore

/// Frame 41: the one place that shows the editor's whole state. Opens from the titlebar pill or
/// Film › Editor… (⇧⌘E). Status, how much freedom, recent activity, pause and settings.
struct EditorPopover: View {
    @Bindable var model: FilmModel
    @State private var connecting = false

    var body: some View {
        // While a run Direction started works or is paused: frame 57's activity popover.
        if !connecting, model.runs.startsEditor, let run = model.runs.current, run.state.isActive || run.state == .paused {
            EditorActivityPopover(model: model, run: run)
                .onExitCommand { model.showEditorPopover = false }
        } else {
            idle
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 0) {
            if connecting { ConnectEditorPage(model: model) { connecting = false } }
            else {
                status
                latitude
                speedAndQuality
                if !activity.isEmpty { recent }
                footer
            }
        }
        .frame(width: 360)
        .background(Gate.Surface.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor")
        .onExitCommand { if connecting { connecting = false } else { model.showEditorPopover = false } }
    }

    // MARK: Status

    private var pill: EditorPillState { model.pill }
    private var nextCut: String { model.openTurnover?.kind == "assembly" || model.cuts.isEmpty ? "the assembly" : "Cut \(model.cuts.count + 1)" }

    private var chip: (String, ChipStyle) {
        switch pill {
        case .ready: ("Ready", .ok)
        case .cutReady: ("Cut ready", .agent)
        case .waiting: ("Turned over", .agent)
        case .readingBack: ("Reading back", .agent)
        case .readBackReady: ("Waiting for you", .agent)
        case .working, .assembling: (model.openTurnover?.kind == "assembly" ? "Assembling" : "Cutting", .agent)
        case .asks(let n): (n == 1 ? "1 question" : "\(n) questions", .agent)
        case .cant(let n): ("Can\u{2019}t do \(n)", .bad)
        case .stopped: ("Stopped", .bad)
        case .needsFootage: ("Waiting for footage", .bad)
        case .paused: ("Paused", .plain)
        case .offline: ("Offline", .plain)
        case .notSetUp: ("Not set up", .plain)
        case .looking: ("Looking at footage", .agent)
        case .listening: ("Listening", .agent)
        case .readyToCut(let s): (s, .plain)
        }
    }

    private var sentence: String {
        let notes = model.openTurnover?.noteIDs.count ?? model.readyNotes.count
        switch pill {
        case .ready:
            if model.cuts.isEmpty { return model.circledCount > 0 ? "Nothing in progress. Ask for the assembly when your circles are in." : "Nothing in progress. Circle takes in Dailies, then ask for the assembly." }
            let n = model.readyNotes.count, cut = model.watchedCut?.name ?? "this cut"
            return n == 0 ? "Nothing in progress. Write notes on \(cut) and turn them over when you\u{2019}re done." : "Nothing in progress. Your \(n == 1 ? "note" : "\(n) notes") on \(cut) \(n == 1 ? "is" : "are") waiting. Turn them over when you\u{2019}re done."
        case .cutReady where model.assemblyAwaitsScreening:
            return "The assembly is ready. Nobody else sees it until you\u{2019}ve screened it; watch it once all the way through before giving notes."
        case .cutReady:
            let n = model.unreviewedAnswers.count, cut = model.latestCut?.name ?? "The new cut"
            return "\(cut) is ready. \(n == 1 ? "1 answer is" : "\(n) answers are") waiting in the Cut room."
        case .waiting:
            return model.openTurnover?.kind == "assembly" ? "You asked for the assembly. It starts when your editor picks it up." : "You turned over \(notes == 1 ? "1 note" : "\(notes) notes"). They\u{2019}re waiting for your editor to pick them up."
        case .readingBack: return "Reading your \(notes) notes. A plan will be ready in a moment."
        case .readBackReady: return "The plan for \(nextCut) is ready for your OK."
        case .working, .assembling:
            if model.directing.editorPaused { return "Pausing after note \(currentNoteNumber ?? "–")\u{2026}" }
            let detail = model.editorStatus?.detail ?? model.openTurnover?.phase
            let lead = model.openTurnover?.kind == "assembly" ? "Building the assembly from your circled takes." : "Cutting \(nextCut)."
            return [lead, detail.map { $0.hasSuffix(".") ? $0 : $0 + "." }].compactMap { $0 }.joined(separator: " ")
        case .asks(let n): return "I need your call on \(n == 1 ? "one thing" : "\(n) things") before I finish \(nextCut)."
        case .cant: return model.openQuestions.first { $0.kind == "cant" }?.text ?? "I can\u{2019}t do one of your notes as written."
        case .stopped:
            if let r = model.runs.failed { return [EditorStopCopy.title(r.reason ?? .stoppedWithoutFinishing, run: r), model.runs.stopBody(r, film: model)].filter { !$0.isEmpty }.joined(separator: " ") }
            return model.openTurnover?.message ?? "I stopped before finishing. Your notes are safe; try again when you\u{2019}re ready."
        case .paused: return "Paused. Nothing will change until you resume."
        case .needsFootage: return "\(model.missingTakes == 1 ? "1 take is" : "\(model.missingTakes) takes are") missing. I can\u{2019}t cut scenes that use them until you find the footage."
        case .offline: return "You\u{2019}re offline. An editor that works online picks up when you\u{2019}re back."
        case .notSetUp: return "Choose who edits, and Direction starts the editor whenever there\u{2019}s work."
        case .looking(let done, let total): return "Looking at your footage before logging it: \(done) of \(total) takes so far."
        case .listening(let done, let total): return "Transcribing what\u{2019}s said before the editor logs it: \(done) of \(total) takes so far."
        case .readyToCut: return "\(model.runs.held.map { Self.work($0.job) } ?? "Your notes are turned over"). Start the editor when you\u{2019}re ready."
        }
    }

    private static func work(_ job: EditorJob) -> String {
        switch job {
        case .turnover: "Your notes are turned over"
        case .assemble: "You asked for the assembly"
        case .finish: "Picture is locked"
        case .logFootage: "Your footage is in"
        case .style: "You asked for a style"
        case .technique: "You gave it a video to learn from"
        case .script: "Your script is in"
        case .breakdown: "You OK\u{2019}d the script"
        }
    }

    private var currentNoteNumber: String? {
        guard let t = model.openTurnover else { return nil }
        return t.noteIDs.first { t.progress[$0] == .working }.map(model.noteNumber)
    }

    private var status: some View {
        section {
            HStack(spacing: 8) {
                GemMark(size: 8)
                Text("Editor").font(Gate.Font.brandS).foregroundStyle(Gate.Text.primary)
                Spacer(minLength: 8)
                Chip(chip.0, style: chip.1, icon: pill == .offline ? "wifi.slash" : pill == .paused ? "pause.fill" : nil)
            }
            Text(sentence).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).cssLineHeight(1.45, size: 12).fixedSize(horizontal: false, vertical: true)
            // Your own session: Direction shows what it does but can't start or stop it (specs/editor.md).
            if !model.runs.startsEditor && !model.isPreview {
                Text("Your own session. Direction shows what it does but can\u{2019}t start or pause it.").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            if case .working = pill, let t = model.openTurnover, t.kind != "assembly" { checklist(t) }
            statusActions
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusActions: some View {
        let connected = model.editorStatus != nil || !model.cuts.isEmpty || model.isPreview || model.runs.startsEditor
        switch pill {
        case .readyToCut:
            Button("Start") { model.runs.start(model); model.showEditorPopover = false }.buttonStyle(.gate(.normal, .small)).keyboardShortcut(.defaultAction)
        case .notSetUp:
            Button("Set up\u{2026}") { model.showEditorPopover = false; model.sheet = .editorSetup }.buttonStyle(.gate(.normal, .small)).keyboardShortcut(.defaultAction)
        case .stopped:
            if let r = model.runs.failed { EditorStopActions(model: model, run: r, small: true) }
        case .cutReady where model.assemblyAwaitsScreening:
            Button("Watch it") { model.showEditorPopover = false; model.watchThrough() }.buttonStyle(.gate(.normal, .small)).keyboardShortcut(.defaultAction)
        case .readBackReady:
            Button("Open read-back") { model.notesTab = .sheet; open(.cut) }.buttonStyle(.gate(.normal, .small)).keyboardShortcut(.defaultAction)
        case .asks:
            // Before the first cut the assembly's questions wait in Dailies; after, in the Cut room.
            Button("Answer") { model.notesTab = .questions; open(model.cuts.isEmpty ? .dailies : .cut) }.buttonStyle(.gate(.normal, .small)).keyboardShortcut(.defaultAction)
        case .cant:
            Button("Show me") { model.notesTab = .questions; open(model.cuts.isEmpty ? .dailies : .cut) }.buttonStyle(.gate(.normal, .small)).keyboardShortcut(.defaultAction)
        case .waiting where !model.runs.startsEditor:
            HStack(spacing: 8) {
                Button("Copy request for your editor") { model.copyEditorRequest(); model.showEditorPopover = false }.buttonStyle(.gate(.normal, .small))
                if !connected { Button("Connect an editor\u{2026}") { connecting = true }.buttonStyle(.gate(.ghost, .small)) }
            }
        default:
            if !connected {
                HStack(spacing: 8) {
                    Text("No editor has opened this film yet.").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
                    Spacer(minLength: 4)
                    Button("Connect an editor\u{2026}") { connecting = true }.buttonStyle(.gate(.ghost, .small))
                }
            }
        }
    }

    private func checklist(_ t: Turnover) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(t.noteIDs, id: \.self) { id in
                let p = t.progress[id] ?? .queued
                HStack(spacing: 8) {
                    Group {
                        switch p {
                        case .done: Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Gate.State.approve)
                        case .working: RingSpinner(size: 11)
                        case .cant, .stopped: Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Gate.State.alert)
                        case .queued: Circle().strokeBorder(Gate.Line.strong, lineWidth: 1).frame(width: 9, height: 9)
                        }
                    }.frame(width: 14)
                    Text(model.noteNumber(id)).font(Gate.Font.mono).foregroundStyle(Gate.Voice.director)
                    Text(model.note(id)?.text ?? "").font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(p == .queued ? Gate.Text.disabled : Gate.Text.secondary)
                }
            }
        }
    }

    // MARK: Latitude

    private var latitudeLocked: Bool {
        if pill == .offline { return true }
        if case .working = pill { return true }
        if case .assembling = pill { return true }
        return false
    }

    private var latitude: some View {
        section {
            SectionLabel("How much freedom")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Latitude.allCases, id: \.self) { l in
                    let on = model.directing.latitude == l
                    Button { LatitudeSetting.set(l, film: model) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            RadioDot(on: on).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(l.label).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13)
                                Text(Self.detail(l)).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.45, size: 11.5).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                    .accessibilityHint(Self.detail(l))
                }
            }
            .disabled(latitudeLocked)
            .opacity(latitudeLocked ? 0.5 : 1)
            .accessibilityElement(children: .contain).accessibilityLabel("How much freedom")
            if latitudeLocked, pill != .offline { Text("Applies from the next turnover.").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary) }
        }
    }

    // MARK: Speed and quality

    /// The film's own. Locked while the editor works or has work under way (waiting on an answer, paused):
    /// the run keeps the stop it started with, and so do the shots it makes.
    private var speedAndQuality: some View {
        let working: Bool = { if case .working = pill { return true }; if case .assembling = pill { return true }; return false }()
        let locked = working || model.runs.runs.contains { $0.invocations > 0 && [.starting, .working, .waitingForYou, .paused].contains($0.state) }
        return section {
            SectionLabel("Speed and quality")
            SpeedQualityControl(quality: Binding(get: { model.directing.speedAndQuality }, set: { model.setQuality($0) }))
                .disabled(locked)
            if locked { Text("Change it once the editor finishes what it\u{2019}s doing.").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary) }
        }
    }

    static func detail(_ l: Latitude) -> String {
        switch l {
        case .exact: "Changes only what each note names. Asks when unclear."
        case .faithful: "Interprets intent. Cuts Feeling notes two ways."
        case .free: "May suggest changes you didn\u{2019}t ask for, marked Unasked."
        }
    }

    // MARK: Recent

    struct Activity: Identifiable {
        var id: String
        var lead: String?
        var text: String
        var at: Double
        var room: Room
        var cutID: String?
    }

    /// The editor's last three acts, newest first: cuts, read-backs, logging, questions.
    private var activity: [Activity] {
        var out: [Activity] = []
        for cut in model.cuts {
            out.append(Activity(id: cut.id, lead: "\(cut.name) is ready.", text: "", at: cut.createdAt, room: .cut, cutID: cut.id))
        }
        for t in model.turnovers where !t.readBack.isEmpty {
            let approved = t.readBackApproved ? (t.adjustments.isEmpty ? " You approved all of them." : " You adjusted \(t.adjustments.count).") : ""
            out.append(Activity(id: t.id + "-rb", text: "Read back \(t.readBack.count) \(t.readBack.count == 1 ? "note" : "notes").\(approved)", at: t.updatedAt, room: .cut))
        }
        if let logged = model.dailies.updatedAt, !model.dailies.takes.isEmpty {
            out.append(Activity(id: "dailies", text: "Logged \(model.dailies.takes.count) \(model.dailies.takes.count == 1 ? "take" : "takes").", at: logged, room: .dailies))
        }
        for q in model.questions {
            out.append(Activity(id: q.id, text: q.kind == "cant" ? "Couldn\u{2019}t do note \(q.noteIDs.first.map(model.noteNumber) ?? "–")." : "Asked: \(q.text)", at: q.createdAt, room: .cut))
        }
        return out.sorted { $0.at > $1.at }.prefix(3).map { a in
            guard let id = a.cutID, let cut = model.cuts.first(where: { $0.id == id }) else { return a }
            var a = a
            let answered = model.answers(in: cut).count
            let tail = [answered == 0 ? nil : "Answered \(answered) \(answered == 1 ? "note" : "notes")", model.previousCutDelta(cut)].compactMap { $0 }.joined(separator: ", ")
            a.text = tail.isEmpty ? "" : tail + "."
            return a
        }
    }

    private var recent: some View {
        section {
            SectionLabel("Recent")
            ForEach(Array(activity.enumerated()), id: \.element.id) { i, a in
                Button { if let id = a.cutID, let cut = model.cuts.first(where: { $0.id == id }) { model.watch(cut) }; open(a.room) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        GemMark(size: 7, solid: i > 0).frame(width: 14).padding(.top, 4)
                        TextRun.line([TextRun(a.lead.map { $0 + " " } ?? "", Gate.Text.primary, .medium), TextRun(a.text, Gate.Text.secondary)], size: 12.5)
                            .cssLineHeight(1.45, size: 12.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Self.when(a.at)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled).lineLimit(1).fixedSize().padding(.top, 2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Today 14:20", "Yesterday", "Oct 26 14:20".
    static func when(_ t: Double) -> String {
        let date = Date(timeIntervalSince1970: t), cal = Calendar.current
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if cal.isDateInToday(date) { return "Today \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) \(time)"
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let paused = model.editorIsPaused
            Button { model.setEditorPaused(!paused) } label: {
                Label(paused ? "Resume editor" : "Pause editor", systemImage: paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.gate(.ghost, .small))
            Spacer(minLength: 8)
            OpenSettingsButton(tab: .engines) { Label("Editor settings\u{2026}", systemImage: "gearshape") }
                .buttonStyle(.gate(.ghost, .small))
                .simultaneousGesture(TapGesture().onEnded { model.showEditorPopover = false })
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .overlay(alignment: .top) { SystemHairline() }
    }

    // MARK: Helpers

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { SystemHairline() }
    }

    private func open(_ room: Room) { model.showEditorPopover = false; model.go(room) }
}

/// Connect an editor: the MCP configuration for Claude Code, Codex or any MCP client.
struct ConnectEditorPage: View {
    var model: FilmModel?
    var back: () -> Void
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button(action: back) { Image(systemName: "chevron.left") }.buttonStyle(.gate(.ghost, .small, icon: true)).help("Back")
                Text("Connect an editor").font(Gate.Font.brandS).foregroundStyle(Gate.Text.primary)
            }
            Text("Your editor is an agent like Claude Code or Codex. Add Direction to it as an MCP server, then ask it to open this film.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).cssLineHeight(1.45, size: 12).fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(EditorConnection.mcpConfig).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.secondary).textSelection(.enabled).padding(10)
            }
            .background(SystemCardBackground(radius: 8, fill: Gate.Surface.sunken))
            if !EditorConnection.isBundled {
                Text("This copy of Direction runs outside its app bundle, so this path may not exist. Build the app with scripts/build-app.sh.")
                    .font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                copyButton("Copy configuration", EditorConnection.mcpConfig)
                copyButton("Copy Claude Code command", EditorConnection.claudeCommand)
            }
            if let model, model.url != nil {
                SystemHairline().padding(.vertical, 2)
                Text("Then paste this into your editor to start:").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
                copyButton("Copy request for your editor", model.editorRequest)
            }
        }
        .padding(16)
    }

    private func copyButton(_ title: String, _ text: String) -> some View {
        Button {
            SystemSupport.copy(text); copied = title
            Task { try? await Task.sleep(for: .seconds(1.6)); if copied == title { copied = nil } }
        } label: {
            if copied == title { Label("Copied", systemImage: "checkmark") } else { Text(title) }
        }
        .buttonStyle(.gate(.normal, .small))
    }
}

extension FilmModel {
    /// "−12 s": the cut's length change from the cut before it.
    fileprivate func previousCutDelta(_ cut: ReviewCut) -> String? {
        guard let i = cuts.firstIndex(where: { $0.id == cut.id }), i > 0, let store else { return nil }
        guard let a = try? store.read(revision: cuts[i - 1].editRevision).sequence(cuts[i - 1].sequenceID).duration.seconds,
              let b = try? store.read(revision: cut.editRevision).sequence(cut.sequenceID).duration.seconds else { return nil }
        let d = (b - a).rounded()
        return d == 0 ? nil : (d < 0 ? "\u{2212}" : "+") + "\(Int(abs(d))) s"
    }
}

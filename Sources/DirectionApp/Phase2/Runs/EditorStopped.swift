import SwiftUI
import AppKit
import DirectionCore

// Frame 58: the editor stopped. Every reason has an action that leaves the screen.

extension EditorRunsModel {
    /// Frame 58's body for a reason. Turnovers add what's safe: "Cut 4 isn't finished; notes 1–7 are still turned over."
    func stopBody(_ run: EditorRun, film: FilmModel) -> String {
        let program = EditorProgram(rawValue: run.program) ?? .claudeCode
        let tail: String? = film.openTurnover.flatMap { t in
            guard t.id == run.turnoverID else { return nil }
            if t.kind == "assembly" { return "The assembly isn\u{2019}t finished; your circles are safe." }
            return "\(film.nextCutName) isn\u{2019}t finished; \(Self.noteRange(t, film: film)) \(t.noteIDs.count == 1 ? "is" : "are") still turned over."
        }
        var body: String
        switch run.reason ?? .stoppedWithoutFinishing {
        case .notInstalled: body = "Direction couldn\u{2019}t find \(program.name) on this Mac."
        case .notSignedIn: body = "Open Terminal, run \(program == .claudeCode ? "claude" : "codex login"), and sign in. Then try again."
        case .offline: body = "It will try again when this Mac is back online."
        case .programQuit: return run.detail ?? "It quit without saying why."
        case .stoppedWithoutFinishing:
            switch run.job {
            case .turnover: body = "It ended without delivering \(film.nextCutName)."
            case .assemble: body = "It ended without delivering the assembly."
            case .logFootage: body = "It ended before every take was logged."
            case .finish: body = "It ended before finishing was done."
            case .style: body = "It ended before the style was saved."
            case .technique: body = "It ended before the technique was saved."
            case .script: body = "It ended before the picture column was written."
            case .breakdown: body = "It ended before the breakdown was done."
            }
            return body
        case .spendCap: return run.detail ?? "Services can\u{2019}t make anything more this month."
        case .pausedByQuit, .stoppedByYou: return ""
        }
        if let tail, run.reason != .notInstalled { body += " " + tail }
        return body
    }

    /// "notes 1–7" or "notes 2, 4 and 6".
    static func noteRange(_ t: Turnover, film: FilmModel) -> String {
        let n = t.noteIDs.compactMap { film.note($0)?.number }.sorted()
        guard let first = n.first, let last = n.last else { return "your notes" }
        if n.count == 1 { return "note \(first)" }
        if n == Array(first...last) { return "notes \(first)\u{2013}\(last)" }
        return "notes " + n.dropLast().map(String.init).joined(separator: ", ") + " and \(last)"
    }
}

/// The actions for a stopped editor, in frame 58's order. `inTurnover` is the Notes notice, where
/// Try again is the titlebar's steel button and the notice offers Take the turnover back.
struct EditorStopActions: View {
    @Bindable var model: FilmModel
    var run: EditorRun
    var inTurnover = false
    var small = false
    @State private var copied = false

    var body: some View {
        let program = EditorProgram(rawValue: run.program) ?? .claudeCode
        let size: GateButtonSize = small ? .small : .regular
        HStack(spacing: 8) {
            switch run.reason ?? .stoppedWithoutFinishing {
            case .notInstalled:
                Button(copied ? "Copied" : "Copy install command") { SystemSupport.copy(program.installCommand); flashCopied() }.buttonStyle(.gate(.normal, size))
                OpenSettingsButton(tab: .engines) { Text("Choose another editor\u{2026}") }.buttonStyle(.gate(.ghost, size))
            case .notSignedIn:
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) } label: { Label("Open Terminal", systemImage: "terminal") }.buttonStyle(.gate(.normal, size))
                if inTurnover { takeBack(size) } else { tryAgain(size) }
            case .offline:
                if inTurnover { takeBack(size) } else { tryAgain(size) }
            case .programQuit:
                if !inTurnover { tryAgain(size) }
                Button(copied ? "Copied" : "Copy details") { SystemSupport.copy(details); flashCopied() }.buttonStyle(.gate(inTurnover ? .normal : .ghost, size))
                if inTurnover { takeBack(size) }
            case .stoppedWithoutFinishing:
                if !inTurnover { tryAgain(size) }
                if model.openTurnover?.id == run.turnoverID, run.turnoverID != nil { takeBack(size) }
            case .spendCap:
                OpenSettingsButton(tab: .engines) { Text("Change limit\u{2026}") }.buttonStyle(.gate(.normal, size))
                Button("Continue without services") { model.runs.continueWithoutServices(model) }.buttonStyle(.gate(.ghost, size))
            case .pausedByQuit:
                Button("Resume") { model.setEditorPaused(false) }.buttonStyle(.gate(.normal, size))
                Button("Not now") { model.runs.dismissQuitBanner(model) }.buttonStyle(.gate(.ghost, size))
            case .stoppedByYou:
                Button("Start") { model.runs.start(model) }.buttonStyle(.gate(.normal, size))
            }
        }
    }

    private func tryAgain(_ size: GateButtonSize) -> some View {
        Button { model.runs.retry(model) } label: { Label("Try again", systemImage: "arrow.uturn.backward") }.buttonStyle(.gate(.normal, size))
    }
    private func takeBack(_ size: GateButtonSize) -> some View {
        Button("Take the turnover back") { model.runs.takeTurnoverBack(model) }.buttonStyle(.gate(.ghost, size))
    }
    private var details: String {
        ["\(EditorStopCopy.title(run.reason ?? .programQuit, run: run))", run.detail, "Run \(run.id) · \([run.program, run.version, run.effort ?? ""].filter { !$0.isEmpty }.joined(separator: " ")) · session \(run.session ?? "–")"].compactMap { $0 }.joined(separator: "\n")
    }
    private func flashCopied() { copied = true; Task { try? await Task.sleep(for: .seconds(1.6)); copied = false } }
}

/// `.notice.err` at the top of the Notes sheet while a turnover's run is stopped (frame 58).
struct EditorStoppedNotice: View {
    @Bindable var model: FilmModel
    var run: EditorRun
    var body: some View {
        let title = "The editor stopped: " + EditorStopCopy.title(run.reason ?? .stoppedWithoutFinishing, run: run)
        let body = model.runs.stopBody(run, film: model)
        Notice(tone: .error) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.State.alert).padding(.top, 2.5)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).lineHeight(13, 1.35).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(model.clockTime(run.endedAt ?? run.updatedAt)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45, mono: true)
            }
            EditorStopBody(text: body, mono: run.reason == .programQuit, program: EditorProgram(rawValue: run.program) ?? .claudeCode)
            EditorStopActions(model: model, run: run, inTurnover: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: "\(title) \(body)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}

/// The body, with the program's command set in SF Mono ("run `claude`, and sign in").
struct EditorStopBody: View {
    var text: String
    var mono = false
    var program: EditorProgram = .claudeCode
    var body: some View {
        if mono {
            Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Gate.Text.secondary).lineHeight(11.5, 1.45, mono: true).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } else {
            styled.font(Gate.Font.body).foregroundStyle(Gate.Text.primary).lineHeight(13, 1.45).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var styled: Text {
        let command = program == .claudeCode ? "claude" : "codex login"
        guard let r = text.range(of: "run \(command),") else { return Text(text) }
        let before = String(text[..<r.lowerBound]) + "run ", after = String(text[text.index(r.upperBound, offsetBy: -1)...])
        return Text("\(before)\(Text(command).font(.system(size: 12, design: .monospaced)))\(after)")
    }
}

/// A full-width banner under the titlebar: the editor was paused when Direction quit, or stopped
/// somewhere the Notes notice doesn't show (logging, the assembly, finishing).
struct EditorRunBanner: View {
    @Bindable var model: FilmModel
    var body: some View {
        if let r = model.runs.pausedByQuit, model.runs.startsEditor {
            Banner(icon: "pause.circle", title: EditorStopCopy.title(.pausedByQuit, run: r), detail: "Resume?") {
                EditorStopActions(model: model, run: r, small: true)
            }
        } else if let r = model.runs.failed, model.runs.startsEditor, !shownInNotes(r) {
            Banner(icon: "exclamationmark.triangle", title: "The editor stopped: " + EditorStopCopy.title(r.reason ?? .stoppedWithoutFinishing, run: r), detail: model.runs.stopBody(r, film: model), alert: true) {
                EditorStopActions(model: model, run: r, small: true)
            }
        }
    }
    /// A stopped turnover shows its own notice in the Cut room (frame 58).
    private func shownInNotes(_ r: EditorRun) -> Bool {
        model.room == .cut && model.onboardingStep == nil && r.turnoverID != nil && r.turnoverID == model.openTurnover?.id
    }
}

/// The read-back panel before the editor has read back, when Direction starts it: no request to copy.
struct EditorWaitingNotice: View {
    @Bindable var model: FilmModel
    var turnover: Turnover
    var body: some View {
        let held = model.pill == .readyToCut("Ready to cut")
        Notice(tone: held ? .plain : .voice, inset: false) {
            HStack(spacing: 8) {
                if held { Image(systemName: "clock").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary) } else { GemMark(size: 8) }
                Text(held ? "Ready when you are" : "The editor is reading your notes").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            }
            NoticeText(text: held ? "Start the editor and its read-back appears here before anything is cut." : "Its read-back appears here before anything is cut.",
                       small: "Turned over at \(model.clockTime(turnover.createdAt)) \u{00B7} \(turnover.latitude.label)")
            HStack(spacing: 8) {
                if held { Button("Start the editor") { model.runs.start(model) }.buttonStyle(.gate) }
                Button("Take notes back") { model.runs.takeTurnoverBack(model); model.clearComposer() }.buttonStyle(.gate(.ghost))
                    .help("Return these notes to written so you can change them")
            }
        }
    }
}

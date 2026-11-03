import SwiftUI
import DirectionCore

/// Settings › Engines › Who edits (frame 43, specs/editor.md › 43). Choosing a program that isn't
/// installed keeps the choice and shows how to install it; work waits with "Editor not set up".
struct EditorWhoEditsGroup: View {
    var app: AppModel?
    var preview = false
    private var programs: EditorPrograms { EditorPrograms.shared }

    var body: some View {
        let _ = programs.changes
        let runsOn = EditorSetup.runsOn, own = runsOn == .yourOwn, program = runsOn.program ?? .claudeCode
        SettingsGroup(label: "Who edits") {
            runsOnRow(runsOn)
            EditorPicksRow(program: program)
                .disabled(own)
            SettingsRow(label: "Start work", detail: "When notes are turned over or footage arrives.") {
                GateSelect(options: [(false, "Right away"), (true, "Ask me first")], selection: Binding(get: { EditorSetup.asksFirst }, set: { EditorSetup.setAsksFirst($0) }))
            }
            .disabled(own)
            SettingsRow(label: "Let the editor run scripts", detail: "Only inside its own folder in the film, with no internet. Some graphics and looks need it.") {
                GateSwitch(isOn: Binding(get: { EditorSetup.runsScripts }, set: { EditorSetup.setRunsScripts($0) }))
            }
            .disabled(own)
        }
        .task { if !preview { programs.refreshIfNeeded() } }
    }

    /// "Editor runs on" with what was found under it.
    private func runsOnRow(_ runsOn: EditorRunsOn) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Editor runs on").font(Gate.Font.body).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13)
                found(runsOn)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GateSegmented(options: EditorRunsOn.allCases.map { ($0, $0.label) }, selection: Binding(get: { runsOn }, set: { choose($0) }),
                          images: Dictionary(uniqueKeysWithValues: EditorRunsOn.allCases.compactMap { c in c.program?.icon.map { (c, $0) } }))
                .fixedSize()
                .accessibilityLabel("Editor runs on")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func found(_ runsOn: EditorRunsOn) -> some View {
        let detail = Font.system(size: 11.5)
        if let p = runsOn.program {
            if let install = programs.install(p) {
                let signedIn = EditorSetup.signedIn(p)
                Text([p.name + (install.version.map { " \($0)" } ?? ""), signedIn == true ? "signed in" : signedIn == false ? "not signed in" : nil].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(detail).foregroundStyle(signedIn == false ? Gate.State.alert : Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5)
            } else if programs.checked {
                HStack(spacing: 8) {
                    Text("Not installed. Install it, then come back.").font(detail).foregroundStyle(Gate.Text.tertiary)
                    Button("Copy install command") { SystemSupport.copy(p.installCommand) }.buttonStyle(.gate(.ghost, .small))
                }
            } else {
                Text("Looking for \(p.name)\u{2026}").font(detail).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5)
            }
        } else {
            Text("Run Claude Code or Codex yourself. Direction shows what it does but can\u{2019}t start or pause it. \(Text("How to connect").foregroundColor(Gate.Text.secondary))")
                .font(detail).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5).fixedSize(horizontal: false, vertical: true)
                .onTapGesture { EditorConnection.presentAlert() }
                .accessibilityAction(named: "How to connect") { EditorConnection.presentAlert() }
        }
    }

    private func choose(_ c: EditorRunsOn) {
        EditorSetup.choose(c)
        if let p = c.program { programs.checkSignIn(p) }
        app?.film?.refresh(force: true)
    }
}

/// Who edits › Version and effort: Direction picks for each job; Change per job… opens the list
/// (specs/editor.md › Version and effort).
struct EditorPicksRow: View {
    var program: EditorProgram
    @State private var open = false
    private var programs: EditorPrograms { EditorPrograms.shared }
    var body: some View {
        let _ = programs.changes
        let changed = EditorSetup.changed(program).count
        SettingsRow(label: "Version and effort", detail: "How long the editor thinks before each step. Direction gives more to judgement (cutting, notes, a style) and less where the editor writes at length. More is slower and uses more of your plan.") {
            Text("Chosen for each job" + (changed > 0 ? " \u{00B7} \(changed) set by you" : "")).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary)
            Button("Change per job\u{2026}") { open = true }.buttonStyle(.gate)
                .gatePopover(isPresented: $open, arrowEdge: .bottom) { EditorPicksPanel(program: program) }
        }
    }
}

/// The popover: every job's version and effort, and Restore Direction’s picks.
struct EditorPicksPanel: View {
    var program: EditorProgram
    private var programs: EditorPrograms { EditorPrograms.shared }
    var body: some View {
        let _ = programs.changes
        VStack(alignment: .leading, spacing: 10) {
            EditorPicksList(program: program)
                .background(SystemCardBackground())
                .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SettingsNote("A run keeps what it started with; a change applies to the next one.")
                Button("Restore Direction\u{2019}s picks") { EditorSetup.restorePicks(program) }
                    .buttonStyle(.gate(.ghost, .small)).disabled(EditorSetup.changed(program).isEmpty)
            }
        }
        .padding(12).frame(width: 500).background(Gate.Surface.panel)
    }
}

/// Each job with its version and effort. A job the director changed says what Direction would pick.
struct EditorPicksList: View {
    var program: EditorProgram
    private var programs: EditorPrograms { EditorPrograms.shared }
    var body: some View {
        let _ = programs.changes
        let changed = Set(EditorSetup.changed(program))
        VStack(spacing: 0) {
            ForEach(Array(EditorJob.byFilm.enumerated()), id: \.element) { i, job in
                let version = EditorSetup.version(program, for: job)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.workName).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                        if changed.contains(job) {
                            Text("Direction\u{2019}s pick: " + pickLine(job)).font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    VersionSelect(program: program, version: Binding(get: { version }, set: { EditorSetup.setVersion($0, for: program, job: job) }), minWidth: 156)
                    GateSelect(options: program.efforts(version).map { ($0.id, $0.name) }, selection: Binding(get: { EditorSetup.effort(program, for: job) }, set: { EditorSetup.setEffort($0, for: program, job: job) }), minWidth: 104)
                }
                .padding(.leading, 12).padding(.trailing, 8).frame(minHeight: 42)
                .overlay(alignment: .top) { if i > 0 { SystemHairline() } }
                .accessibilityElement(children: .contain).accessibilityLabel(job.workName)
            }
        }
    }

    /// What the job would run on with nothing changed, where it differs: "High", "Claude Opus 5.5", or both.
    private func pickLine(_ job: EditorJob) -> String {
        let v = program.defaultVersion, effort = EditorSetup.pickedEffort(program, for: job, on: v)
        let version = EditorSetup.version(program, for: job) == v ? nil : program.versionName(v)
        let level = EditorSetup.effort(program, for: job) == effort ? nil : program.efforts(v).first { $0.id == effort }?.name ?? effort
        return [version, level].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

/// Before cutting › When notes conflict: the order as text and Change…, which opens the
/// reorderable list (same rows, same keys) and Restore default in a popover.
struct ConflictOrderRow: View {
    @Binding var order: String
    @State private var open = false
    var body: some View {
        SettingsRow(label: "When notes conflict") {
            Text(SettingsKey.conflictKinds(order).map(\.label).joined(separator: " \u{203A} ")).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary)
            Button("Change\u{2026}") { open = true }.buttonStyle(.gate)
                .gatePopover(isPresented: $open, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        ConflictOrderList(order: $order)
                            .background(SystemCardBackground())
                            .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous))
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            SettingsNote("The higher kind wins, and the editor tells you in the read-back. Drag to reorder. The default follows Walter Murch\u{2019}s Rule of Six.")
                            Button("Restore default") { withAnimation(SettingsKey.reducesMotion ? nil : Gate.Motion.settle) { order = SettingsKey.defaultConflictOrder } }
                                .buttonStyle(.gate(.ghost, .small)).disabled(order == SettingsKey.defaultConflictOrder)
                        }
                    }
                    .padding(12).frame(width: 440).background(Gate.Surface.panel)
                }
        }
    }
}

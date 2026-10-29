import SwiftUI
import DirectionCore

/// Settings › Editor › Who edits (frame 43, specs/editor.md › 43). Choosing a program that isn't
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
            SettingsRow(label: "Version") {
                VersionSelect(program: program, version: Binding(get: { EditorSetup.version(program) }, set: { EditorSetup.setVersion($0, for: program) }))
            }
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
            GateSegmented(options: EditorRunsOn.allCases.map { ($0, $0.label) }, selection: Binding(get: { runsOn }, set: { choose($0) }))
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
            (Text("Run Claude Code or Codex yourself. Direction shows what it does but can\u{2019}t start or pause it. ") + Text("How to connect").foregroundColor(Gate.Text.secondary))
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

/// Before cutting › When notes conflict: the order as text and Change…, which opens the
/// reorderable list (same rows, same keys) and Restore default in a popover.
struct ConflictOrderRow: View {
    @Binding var order: String
    @State private var open = false
    var body: some View {
        SettingsRow(label: "When notes conflict") {
            Text(SettingsKey.conflictKinds(order).map(\.label).joined(separator: " \u{203A} ")).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary)
            Button("Change\u{2026}") { open = true }.buttonStyle(.gate)
                .popover(isPresented: $open, arrowEdge: .bottom) {
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

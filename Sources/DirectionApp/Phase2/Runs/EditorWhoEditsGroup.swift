import SwiftUI
import DirectionCore

/// Settings › Engines › Who edits (frame 43, specs/editor.md › 43): the open film's editor, and the one a new
/// film starts with. Choosing a program that isn't installed keeps the choice and shows how to install it;
/// work waits with "Editor not set up".
struct EditorWhoEditsGroup: View {
    var app: AppModel?
    var preview = false
    private var programs: EditorPrograms { EditorPrograms.shared }

    var body: some View {
        let _ = programs.changes
        let runsOn = app?.film?.runs.runsOn ?? EditorSetup.runsOn, own = runsOn == .yourOwn
        SettingsGroup(label: "Who edits") {
            runsOnRow(runsOn)
            SettingsRow(label: "Start work", detail: "When notes are turned over or footage arrives.") {
                GateSelect(options: [(false, "Right away"), (true, "Ask me first")], selection: Binding(get: { EditorSetup.asksFirst }, set: { EditorSetup.setAsksFirst($0) }))
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
            // The agents found on this Mac, the one chosen even when it's gone, then your own session.
            GateSelect(options: Self.choices(runsOn, installed: programs.installed).map { ($0, $0.label) }, selection: Binding(get: { runsOn }, set: { choose($0) }))
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
                let signedIn = EditorSetup.signedIn(p), why = programs.couldNotCheck[p]
                HStack(spacing: 8) {
                    Text([p.name + (install.version.map { " \($0)" } ?? ""), signedIn == true ? (EditorSetup.usesShellKey(p) ? "signed in with your shell\u{2019}s API key" : "signed in") : signedIn == false ? "not signed in" : why != nil ? "couldn\u{2019}t check sign-in" : nil].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .font(detail).foregroundStyle(signedIn == false ? Gate.State.alert : Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5)
                        .help(why ?? "")
                    if programs.signingIn.contains(p) { GateSpinner() }
                    else if signedIn != true { Button("Check again") { programs.checkSignIn(p, force: true) }.buttonStyle(.gate(.ghost, .small)) }
                }
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

    /// What "Editor runs on" offers: only agents installed here, plus the current choice so it never vanishes.
    static func choices(_ current: EditorRunsOn, installed: [EditorProgram]) -> [EditorRunsOn] {
        var list = installed.map(EditorRunsOn.init)
        if current != .yourOwn, !list.contains(current) { list.append(current) }
        return list + [.yourOwn]
    }

    private func choose(_ c: EditorRunsOn) {
        if let film = app?.film { film.chooseEditor(c) } else { EditorSetup.choose(c) }
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

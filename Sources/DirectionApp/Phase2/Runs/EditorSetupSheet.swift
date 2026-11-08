import SwiftUI
import AppKit
import DirectionCore

/// Frame 56: Who's editing? Opens on every new film, with the editor chosen last; the film keeps the choice
/// (DirectingState.editor) and nothing of its starts until it's made. Also shown the first time an older film
/// needs the editor and none is chosen, and from the pill's Set up…. Cancel leaves the film on the editor in
/// Settings › Engines, or with "Editor not set up" when there's none, and nothing is lost.
struct EditorSetupSheet: View {
    @Bindable var model: FilmModel
    @State private var choice: EditorProgram = .claudeCode
    @State private var asksFirst = false
    @State private var quality: FilmQuality = .balanced
    @State private var qualityLoaded = false
    @State private var ownSession = false
    private var programs: EditorPrograms { EditorPrograms.shared }

    var body: some View {
        AttachedSheet(width: 560, onDismiss: cancel) {
            if ownSession { ownSessionPage } else { chooser }
        }
        .onAppear(perform: load)
        .onChange(of: programs.checked) { _, _ in load() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Who\u{2019}s editing?")
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Choosing a program

    private var foundAny: Bool { EditorProgram.allCases.contains { programs.install($0) != nil } }

    @ViewBuilder private var chooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who\u{2019}s editing?").font(Gate.Font.brand(size: 22, width: 120)).foregroundStyle(Gate.Text.primary).accessibilityAddTraits(.isHeader)
            Text("Direction starts the editor on this Mac whenever this film has work, and you can pause or stop it anytime. It uses your own sign-in.")
                .font(Gate.Font.body).foregroundStyle(Gate.Text.secondary).cssLineHeight(1.5, size: 13).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 490, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 6)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(EditorProgram.allCases, id: \.self) { p in card(p) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain).accessibilityLabel("Who edits")
            if let step = signInStep { step }
            VStack(spacing: 0) {
                SettingsRow(label: "Start work", first: true, minHeight: 48) {
                    GateSegmented(options: [(false, "Right away"), (true, "Ask me first")], selection: $asksFirst)
                }
                SettingsRow(label: "Speed and quality", detail: quality.detail, minHeight: 64) {
                    StopSlider(stops: FilmQuality.allCases.map { ($0, $0.label) }, selection: $quality, label: "Speed and quality").frame(width: 200)
                }
            }
            .background(SystemCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous))
            SettingsNote("Change the speed and quality anytime the editor isn\u{2019}t working, from the editor button at the top of the window.")
                .padding(.horizontal, 2)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 20)
        SheetFooter {
            Button { ownSession = true } label: {
                HStack(spacing: 4) { Text("I\u{2019}ll run my own session instead"); Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Gate.Text.disabled) }
                    .font(.system(size: 12)).foregroundStyle(Gate.Text.secondary)
            }.buttonStyle(.plain)
        } trailing: {
            Button("Cancel", action: cancel).buttonStyle(.gate).keyboardShortcut(.cancelAction)
            Button(action: confirm) { HStack(spacing: 6) { Text(primaryTitle); KeyHint("\u{2318}\u{21A9}") } }
                .buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var primaryTitle: String { foundAny ? "Use \(choice.name)" : "Check again" }

    /// The Freedom card recipe: raised, radius 10, padding 14, a 1.5 pt text-1 ring when chosen.
    private func card(_ p: EditorProgram) -> some View {
        let on = choice == p && programs.install(p) != nil
        let install = programs.install(p), signedIn = EditorSetup.signedIn(p)
        // A program that isn't installed shows how to install it; it can't be chosen here.
        return Button { guard install != nil else { return }; choice = p } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    AgentIcon(program: p, size: 20)
                    Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                }
                if let install {
                    HStack(spacing: 7) {
                        Circle().fill(signedIn == false ? Gate.State.alert : Gate.State.approve).frame(width: 6, height: 6)
                        Text(["Found", install.version, signedIn == false ? "not signed in" : signedIn == true ? "signed in" : programs.couldNotCheck[p] != nil ? "couldn\u{2019}t check sign-in" : nil].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(.system(size: 12)).foregroundStyle(Gate.Text.secondary).lineLimit(1)
                        if programs.signingIn.contains(p) { GateSpinner() }
                    }
                } else {
                    Text("Not installed").font(.system(size: 12)).foregroundStyle(Gate.Text.tertiary)
                    CopyableCommand(text: p.installCommand).padding(.horizontal, -8).padding(.top, 3)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).fill(on ? Gate.Surface.hover : Gate.Surface.raised))
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).strokeBorder(on ? Gate.Text.primary : Gate.Line.subtle, lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Gate.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(p.name)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    /// Found but not signed in: "Open Terminal, run claude, and sign in." Or the check couldn't tell, and why.
    /// Either way Check again asks now, and the work can start regardless: a run that finishes settles it.
    private var signInStep: AnyView? {
        guard programs.install(choice) != nil else { return nil }
        let why = programs.couldNotCheck[choice]
        guard EditorSetup.signedIn(choice) == false || why != nil else { return nil }
        return AnyView(HStack(spacing: 10) {
            if let why { Text("Direction couldn\u{2019}t check the sign-in: \(why). You can start anyway.").font(Gate.Font.body).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true) }
            else { EditorStopBody(text: "Open Terminal, run \(choice == .claudeCode ? "claude" : "codex login"), and sign in.", program: choice) }
            Spacer(minLength: 8)
            Button { programs.checkSignIn(choice, force: true) } label: { Text("Check again") }.buttonStyle(.gate).disabled(programs.signingIn.contains(choice))
            if why == nil { Button { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) } label: { Label("Open Terminal", systemImage: "terminal") }.buttonStyle(.gate) }
        })
    }

    // MARK: Your own session

    @ViewBuilder private var ownSessionPage: some View {
        SheetHeader(title: "Run your own session", subtitle: "Direction shows what your editor does, but can\u{2019}t start, pause or stop it.")
        VStack(alignment: .leading, spacing: 12) {
            // The tools are inside the app; a copy built from a checkout links them with the checkout's script.
            Text(EditorConnection.isBundled ? "Add Direction\u{2019}s tools to Claude Code or Codex in Terminal, then ask your editor to open this film." : "Install Direction\u{2019}s tools for Claude Code or Codex, then ask your editor to open this film.").font(Gate.Font.body).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
            if EditorConnection.isBundled {
                CopyableCommand(text: EditorConnection.claudeCommand)
                CopyableCommand(text: EditorConnection.codexCommand)
            } else {
                CopyableCommand(text: "./scripts/install-local.sh")
                CopyableCommand(text: EditorConnection.claudeCommand)
            }
            if model.url != nil {
                Text("Then paste this into your editor to start:").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
                CopyableCommand(text: model.editorRequest, copyLabel: "Copy request for your editor")
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        SheetFooter {
            Button { ownSession = false } label: { HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold)); Text("Who\u{2019}s editing?") }.font(.system(size: 12)).foregroundStyle(Gate.Text.secondary) }.buttonStyle(.plain)
        } trailing: {
            Button { model.chooseEditor(.yourOwn); model.setQuality(quality); close() } label: { HStack(spacing: 6) { Text("Done"); KeyHint("\u{2318}\u{21A9}") } }
                .buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: Actions

    private func load() {
        programs.refreshIfNeeded()
        if let p = model.runs.runsOn.program, programs.install(p) != nil { choice = p }
        else { choice = EditorProgram.allCases.first { programs.install($0) != nil } ?? .claudeCode }
        asksFirst = EditorSetup.asksFirst
        // Once: a later look for the programs mustn't undo a stop the director just chose.
        if !qualityLoaded { quality = model.directing.quality ?? EditorSetup.defaultQuality; qualityLoaded = true }
        if programs.install(choice) != nil { programs.checkSignIn(choice) }
    }

    private func confirm() {
        guard foundAny, programs.install(choice) != nil else { programs.refresh(); return }
        model.chooseEditor(EditorRunsOn(rawValue: choice.rawValue) ?? .claudeCode)
        EditorSetup.setAsksFirst(asksFirst)
        model.setQuality(quality)
        programs.checkSignIn(choice)
        // Right away: the film's work starts now (findWork runs on refresh, once the sheet is closed).
        close()
    }

    /// The film still starts with the speed and quality shown, as it would from a choice.
    private func cancel() {
        if model.directing.quality == nil { model.setQuality(quality) }
        close()
    }
    private func close() { model.sheet = nil; model.refresh(force: true) }
}

/// `.cmdline`: a copyable command in SF Mono 11.5 on a sunken chip.
struct CopyableCommand: View {
    var text: String
    var copyLabel: String? = nil
    @State private var copied = false
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Gate.Text.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            Button {
                SystemSupport.copy(text); copied = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary).frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(copyLabel ?? "Copy")
            .accessibilityLabel(copied ? "Copied" : (copyLabel ?? "Copy \(text)"))
        }
        .padding(.leading, 8).padding(.trailing, 3).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Gate.Surface.sunken).overlay(RoundedRectangle(cornerRadius: Gate.Radius.chip).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
    }
}

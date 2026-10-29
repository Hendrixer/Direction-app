import SwiftUI
import AppKit
import DirectionCore
import DirectionTools

/// Frame 39: Share a cut. Screening links need a hosted service Direction doesn't have yet,
/// so the sheet keeps the design's structure, says plainly that links aren't available, and
/// offers what works today: export a screening copy, and bring the notes back through the editor.
struct ShareSheet: View {
    @Bindable var model: FilmModel
    @State private var cutID: String?
    @State private var export: ScreeningCopy.State = .idle
    @State private var copiedRequest = false

    @AppStorage(SettingsKey.linkNotes) private var linkNotes = true
    @AppStorage(SettingsKey.linkExpiry) private var linkExpiry = 7
    @AppStorage(SettingsKey.linkDownload) private var linkDownload = false
    @AppStorage(SettingsKey.linkPassword) private var linkPassword = false

    private var cut: ReviewCut? { cutID.flatMap { id in model.cuts.first { $0.id == id } } ?? model.watchedCut }
    private var cutName: String { cut?.name ?? "this cut" }

    var body: some View {
        SystemSheet(width: 580, label: "Share \(cutName)", onDismiss: close) {
            SystemSheetHead(title: "Share \(cutName)", subtitle: "Screening links will let people watch \(cutName) in a browser and send notes to your Outside inbox. The editor never sees those notes until you accept one.")
            VStack(alignment: .leading, spacing: 14) {
                unavailable
                linkRow
                options
                yourself
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            SystemSheetFoot {
                Spacer(minLength: 0)
                if model.cuts.count > 1 {
                    Menu {
                        ForEach(model.cuts.reversed()) { c in Button(c.name) { cutID = c.id; export = .idle } }
                    } label: { Text("Share a different cut\u{2026}") }
                    .menuStyle(.button).buttonStyle(.gate(.ghost)).menuIndicator(.hidden).fixedSize()
                }
                Button("Done", action: close).buttonStyle(.steel).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func close() { model.sheet = nil }

    /// The inline `.banner`: why there's no link.
    private var unavailable: some View {
        HStack(spacing: 10) {
            Image(systemName: model.offline ? "wifi.slash" : "link").font(.system(size: 12)).foregroundStyle(Gate.Text.secondary)
            TextRun.line([
                TextRun("Sharing isn\u{2019}t set up on this Mac. ", Gate.Text.primary, .semibold),
                TextRun("Direction has no screening service yet. You can still share a copy yourself.", Gate.Text.secondary),
            ], size: 12.5)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(SystemCardBackground())
        .accessibilityElement(children: .combine)
    }

    private var linkRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                Text("No link yet").font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: Gate.Size.control).background(GateFieldBackground())
            Button("Copy link") {}.buttonStyle(.gate).disabled(true)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("Screening link, not available")
    }

    /// The link's options, showing the defaults from Settings › Sharing.
    private var options: some View {
        VStack(spacing: 0) {
            SettingsRow(label: "Viewers can leave notes", detail: "Notes arrive in Notes › Outside for you to accept, edit or decline.", first: true) { GateSwitch(isOn: .constant(linkNotes)) }
            SettingsRow(label: "Link expires") { GateSelect(options: [(linkExpiry, expiryText)], selection: .constant(linkExpiry)) }
            SettingsRow(label: "Require a password") { GateSwitch(isOn: .constant(linkPassword)) }
            SettingsRow(label: "Allow download", detail: "Off: viewers can only stream, with a watermark of their name.") { GateSwitch(isOn: .constant(linkDownload)) }
        }
        .background(SystemCardBackground())
        .disabled(true)
    }

    private var expiryText: String {
        guard linkExpiry > 0 else { return "Never" }
        let date = Calendar.current.date(byAdding: .day, value: linkExpiry, to: Date()) ?? Date()
        return "In \(linkExpiry) \(linkExpiry == 1 ? "day" : "days") · \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// What works today, on this Mac.
    private var yourself: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Share it yourself").padding(.top, 4)
            VStack(spacing: 0) {
                SettingsRow(label: "Export a screening copy", detail: exportDetail, first: true) { exportControl }
                SettingsRow(label: "Bring their notes in", detail: "Paste what people send you into your editor. Their notes land in Notes › Outside for you to accept.") {
                    Button {
                        SystemSupport.copy(outsideRequest); copiedRequest = true
                        Task { try? await Task.sleep(for: .seconds(1.6)); copiedRequest = false }
                    } label: { if copiedRequest { Label("Copied", systemImage: "checkmark") } else { Text("Copy request") } }
                    .buttonStyle(.gate).disabled(model.url == nil && !model.isPreview)
                    .help("Copies words you can paste into Claude Code or Codex, followed by the notes you got.")
                }
            }
            .background(SystemCardBackground())
        }
    }

    private var exportDetail: String {
        switch export {
        case .idle: "An H.264 file of \(cutName) to send any way you like."
        case .running: "Exporting \(cutName)\u{2026} You can close this sheet."
        case .done(let url): "Saved \(url.lastPathComponent)."
        case .failed(let message): message
        }
    }

    @ViewBuilder private var exportControl: some View {
        switch export {
        case .idle, .failed:
            Button("Export\u{2026}") { startExport() }.buttonStyle(.gate).disabled(model.runtime == nil || cut == nil)
        case .running:
            HStack(spacing: 8) { RingSpinner(); Text("Exporting").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
        case .done(let url):
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.gate)
        }
    }

    private var outsideRequest: String {
        let path = model.url?.path ?? "my film"
        return "Add outside notes to my Direction film at \(path) on \(cutName) with direction_add_outside_note. Use each person's name and role, and the timecode when they give one. Keep them in my Outside inbox; don't act on them until I accept them. Here are the notes:\n\n"
    }

    private func startExport() {
        guard let cut, let runtime = model.runtime else { return }
        let panel = NSSavePanel()
        panel.title = "Export a screening copy"; panel.prompt = "Export"
        panel.nameFieldStringValue = "\(model.filmName) \u{2013} \(cut.name).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        export = .running
        Task {
            do {
                let response = try await runtime.invoke("direction_export", arguments: .object(["path": .string(url.path), "preset": .string("h264"), "revision": .number(Double(cut.editRevision)), "sequenceID": .string(cut.sequenceID)]))
                let job = try response.value.decode(JobRecord.self)
                ScreeningCopy.jobIDs.insert(job.id)
                _ = try await runtime.waitForJob(job.id)
                export = .done(url)
                model.toast = Toast(title: "\(cut.name) is exported", detail: url.lastPathComponent)
            } catch { export = .failed(error.localizedDescription) }
        }
    }
}

/// Exports started from the Share sheet: screening copies, not deliveries.
@MainActor
enum ScreeningCopy {
    enum State: Equatable { case idle, running, done(URL), failed(String) }
    static var jobIDs: Set<String> = []
}

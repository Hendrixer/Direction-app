import SwiftUI
import AppKit
import DirectionCore

/// Settings › Cutting › Color (frame 54, specs/settings.md › 54). Both settings live in the shared
/// defaults suite, so the editor's tools and the renderer read the same folder and the same switch.
struct FootageColorGroup: View {
    var preview = false
    @AppStorage(SharedSettings.LookKey.looksFolder, store: SharedSettings.defaults) private var folder = SharedSettings.defaultLooksFolder
    @AppStorage(SharedSettings.LookKey.convertLog, store: SharedSettings.defaults) private var convertLog = true

    var body: some View {
        SettingsGroup(label: "Color") {
            SettingsRow(label: "Looks folder", first: true) {
                HStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                    Text(displayPath).font(.system(size: 12)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(width: 260, height: Gate.Size.control).background(GateFieldBackground())
                .help(expanded)
                .accessibilityElement(children: .combine).accessibilityLabel("Looks folder, \(displayPath)")
                Button("Change\u{2026}") { choose() }.buttonStyle(.gate)
                Button("Show in Finder") { reveal() }.buttonStyle(.gate)
            }
            SettingsRow(label: "Convert log footage automatically", detail: "Apple Log, S-Log3, LogC and V-Log become normal video before any look. Camera LUTs live in the Camera folder.") {
                GateSwitch(isOn: $convertLog)
            }
        }
    }

    private var expanded: String { NSString(string: folder.isEmpty ? SharedSettings.defaultLooksFolder : folder).expandingTildeInPath }
    private var displayPath: String { preview ? "~/Movies/Direction/Looks" : (expanded as NSString).abbreviatingWithTildeInPath }

    private func choose() {
        guard !preview else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a looks folder"; panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: expanded)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
        _ = try? SharedSettings.ensureLooksFolder()
    }

    /// The folder is made on first use, with its Camera folder, so there's always something to show.
    private func reveal() {
        guard !preview, let url = try? SharedSettings.ensureLooksFolder() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

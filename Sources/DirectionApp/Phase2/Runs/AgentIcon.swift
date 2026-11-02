import SwiftUI
import AppKit

extension EditorProgram {
    /// The program's own app icon, unchanged: Claude's from Claude.app and Codex's from the ChatGPT app,
    /// which ships it (Resources/Agents, copied 2026-11-01). The diamond stays the editor's mark; this says
    /// which program the editor is.
    @MainActor var icon: NSImage? { AgentIcons.images[self] ?? nil }
}

@MainActor private enum AgentIcons {
    static let images: [EditorProgram: NSImage?] = Dictionary(uniqueKeysWithValues: EditorProgram.allCases.map { p in
        let name = p == .claudeCode ? "AgentClaudeCode" : "AgentCodex"
        let url = Bundle.module.url(forResource: name, withExtension: "png") ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Agents")
        return (p, url.flatMap(NSImage.init(contentsOf:)))
    })
}

/// A program's icon at a size; nothing when there's no program or no icon.
struct AgentIcon: View {
    var program: EditorProgram?
    var size: CGFloat = 14
    var body: some View {
        if let image = program?.icon {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
                .accessibilityLabel(program?.name ?? "")
        }
    }
}

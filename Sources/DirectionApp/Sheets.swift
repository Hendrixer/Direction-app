import SwiftUI
import AppKit
import DirectionCore

struct AgentToolsSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            UtilitySheetHeader(symbol: "terminal", title: "Agent tools") { dismiss() }
            Text("Connect a local agent through MCP, or use the same tools from the CLI. Feedback is available whenever the agent next requests it.").font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
            SectionLabel(text: "MCP stdio configuration")
            Text(config).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .lineSpacing(4).padding(16).frame(maxWidth: .infinity, alignment: .leading).directionField(cornerRadius: 10)
            HStack { Button("Copy MCP configuration", action: model.copyMCPConfig).buttonStyle(QuietButton(prominent: true)); Spacer(); Text("Local files · no cloud service").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            DirectionDivider()
            SectionLabel(text: "CLI")
            Text("\(shellQuote(model.cliPath)) inspect --project \(shellQuote(model.projectURL?.path ?? "Project.direction"))").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            Text("Use direction tools to list schemas. direction api serves the same tools as newline-delimited JSON on stdin/stdout.").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(28).frame(width: 650).background(Palette.panel).foregroundStyle(Palette.text)
    }
    private var config: String {
        let value: JSONValue = .object(["mcpServers": .object(["direction": .object(["command": .string(model.cliPath), "args": .array([.string("mcp"), .string("--project"), .string(model.projectURL?.path ?? "Project.direction")])])])])
        return (try? String(decoding: value.data(pretty: true), as: UTF8.self)) ?? ""
    }
    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Export video").font(.system(size: 20, weight: .medium)).tracking(-0.3)
            DirectionDivider()
            HStack(spacing: 16) {
                Image(systemName: "film").font(.system(size: 20, weight: .light)).foregroundStyle(Palette.muted).frame(width: 28)
                VStack(alignment: .leading, spacing: 6) { Text(model.project?.name ?? "Direction").font(.system(size: 14, weight: .medium)); Text("\(model.cutLabel) · revision \(model.displayedProject?.editRevision ?? 0)").font(.system(size: 11)).foregroundStyle(Palette.muted); Text("\(model.sequence?.width ?? 0) × \(model.sequence?.height ?? 0) · \(timecode(model.duration))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted) }
            }
            Picker("Format", selection: $model.exportPreset) { Text("H.264 · MP4").tag("h264"); Text("HEVC · MP4").tag("hevc"); Text("ProRes 422 · MOV").tag("prores") }.font(.system(size: 12))
            Text("Exports pin this edit. You can continue reviewing while the native renderer finishes.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
            HStack { Button("Cancel") { dismiss() }.buttonStyle(QuietButton()); Spacer(); Button("Choose destination…", action: model.chooseExport).buttonStyle(QuietButton(prominent: true)).disabled(model.duration == 0) }
        }.padding(28).frame(width: 520).background(Palette.panel).foregroundStyle(Palette.text)
    }
}

struct ActivitySheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UtilitySheetHeader(symbol: "clock.arrow.circlepath", title: "Project activity") { dismiss() }
            DirectionDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.jobs.isEmpty { SectionLabel(text: "Jobs") }
                    ForEach(model.jobs) { job in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(job.kind.capitalized).font(.system(size: 12, weight: .medium)); Spacer(); Text(job.status).font(.system(size: 10)).foregroundStyle(job.status == "completed" ? Palette.audio : Palette.muted); if !job.isTerminal { Button("Cancel") { model.cancelJob(job) }.buttonStyle(.plain).font(.system(size: 10)) } }
                            Text(job.error ?? job.phase).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                            if let path = job.result?["path"].string { Button("Reveal output") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.accent) }
                        }.padding(.vertical, 12).overlay(alignment: .bottom) { DirectionDivider() }
                    }
                    SectionLabel(text: "Recent activity")
                    ForEach(model.events.reversed()) { event in HStack(alignment: .top, spacing: 12) { Text("r\(event.revision)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.accent); Text(event.summary).font(.system(size: 11)); Spacer(); if event.kind == "edit.committed" { Button("Review") { model.showRevision(event.revision); dismiss() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted) } } }
                }
            }
        }.padding(26).frame(width: 620, height: 520).background(Palette.panel).foregroundStyle(Palette.text)
    }
}

private struct UtilitySheetHeader: View {
    let symbol: String
    let title: String
    var done: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(Palette.muted)
                .frame(width: 22)
            Text(title).font(.system(size: 20, weight: .medium)).tracking(-0.3)
            Spacer()
            Button("Done", action: done).buttonStyle(QuietButton())
        }
    }
}

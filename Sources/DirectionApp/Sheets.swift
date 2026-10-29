import SwiftUI
import AppKit
import DirectionCore

struct AgentToolsSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Gate.Space.s4) {
            UtilitySheetHeader(symbol: "terminal", title: "Agent tools") { dismiss() }
            Text("Connect a local agent through MCP, or use the same tools from the CLI. Feedback is available whenever the agent next requests it.").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary).lineSpacing(4)
            SectionLabel(text: "MCP stdio configuration")
            Text(config).font(Gate.Font.timecode).textSelection(.enabled)
                .lineSpacing(4).padding(16).frame(maxWidth: .infinity, alignment: .leading).directionField(cornerRadius: Gate.Radius.control)
            HStack { Button("Copy MCP configuration", action: model.copyMCPConfig).buttonStyle(QuietButton(prominent: true)); Spacer(); Text("Local files · no cloud service").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) }
            DirectionDivider()
            SectionLabel(text: "CLI")
            Text("\(shellQuote(model.cliPath)) inspect --project \(shellQuote(model.projectURL?.path ?? "Project.direction"))").font(Gate.Font.timecode).textSelection(.enabled)
            Text("Use direction tools to list schemas. direction api serves the same tools as newline-delimited JSON on stdin/stdout.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
        }.padding(Gate.Space.s8).frame(width: 650).background(Gate.Surface.ground).foregroundStyle(Gate.Text.primary)
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
        VStack(alignment: .leading, spacing: Gate.Space.s6) {
            Text("Export video").font(Gate.Font.title)
            DirectionDivider()
            HStack(spacing: Gate.Space.s4) {
                Image(systemName: "film").font(.system(size: 20, weight: .light)).foregroundStyle(Gate.Text.tertiary).frame(width: 28)
                VStack(alignment: .leading, spacing: 6) { Text(model.project?.name ?? "Direction").font(Gate.Font.title); Text(model.cutLabel).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary); Text("\(model.sequence?.width ?? 0) × \(model.sequence?.height ?? 0) · \(timecode(model.duration, frames: false))").font(Gate.Font.timecode).foregroundStyle(Gate.Text.tertiary) }
            }
            Picker("Format", selection: $model.exportPreset) { Text("H.264 · MP4").tag("h264"); Text("HEVC · MP4").tag("hevc"); Text("ProRes 422 · MOV").tag("prores") }.font(Gate.Font.body)
            Text("Export this cut. You can keep reviewing while it finishes.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineSpacing(3)
            HStack { Button("Cancel") { dismiss() }.buttonStyle(QuietButton()); Spacer(); Button("Export…", action: model.chooseExport).buttonStyle(QuietButton(prominent: true)).disabled(model.duration == 0) }
        }.padding(Gate.Space.s8).frame(width: 520).background(Gate.Surface.ground).foregroundStyle(Gate.Text.primary)
    }
}

struct ActivitySheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Gate.Space.s4) {
            UtilitySheetHeader(symbol: "clock.arrow.circlepath", title: "Project activity") { dismiss() }
            DirectionDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.jobs.isEmpty { SectionLabel(text: "Jobs") }
                    ForEach(model.jobs) { job in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(job.kind.capitalized).font(Gate.Font.control); Spacer(); Text(job.status).font(Gate.Font.caption).foregroundStyle(job.status == "completed" ? Gate.Text.secondary : Gate.Text.tertiary); if !job.isTerminal { Button("Cancel") { model.cancelJob(job) }.buttonStyle(.plain).font(Gate.Font.caption) } }
                            Text(job.error ?? job.phase).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).textSelection(.enabled)
                            if let path = job.result?["path"].string { Button("Reveal output") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.buttonStyle(.plain).font(Gate.Font.caption).foregroundStyle(Gate.Text.secondary) }
                        }.padding(.vertical, 12).overlay(alignment: .bottom) { DirectionDivider() }
                    }
                    SectionLabel(text: "Recent activity")
                    ForEach(model.events.reversed()) { event in HStack(alignment: .top, spacing: 12) { Text(cutLabel(for: event.revision)).font(Gate.Font.timecode).foregroundStyle(Gate.Text.secondary); Text(event.summary).font(Gate.Font.caption); Spacer(); if event.kind == "edit.committed" { Button("Review cut") { model.showRevision(event.revision); dismiss() }.buttonStyle(.plain).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) } } }
                }
            }
        }.padding(Gate.Space.s8).frame(width: 620, height: 520).background(Gate.Surface.ground).foregroundStyle(Gate.Text.primary)
    }
    private func cutLabel(for revision: Int) -> String {
        model.cuts.first { $0.editRevision == revision }?.name ?? "Edit"
    }

}

private struct UtilitySheetHeader: View {
    let symbol: String
    let title: String
    var done: () -> Void
    var body: some View {
        HStack(spacing: Gate.Space.s3) {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(Gate.Text.tertiary)
                .frame(width: 22)
            Text(title).font(Gate.Font.title)
            Spacer()
            Button("Done", action: done).buttonStyle(QuietButton())
        }
    }
}

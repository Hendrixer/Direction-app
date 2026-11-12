import Foundation
import DirectionCore
import DirectionTools

/// What every run reads first, read for it and put in the job (docs/editor-runs.md › Fewer steps). In the runs of
/// 11 Nov 2026 each job's first two to four steps were always the same: its playbook, its notes from last time,
/// then the turnover, the cut and the brief. Each of those steps resent everything said so far and waited on the
/// editor to ask; Direction knows what they'll be, so it reads them as the run starts.
enum EditorOpening {
    /// The most one answer may add, and all of them together, in characters; past these the editor reads it itself.
    static let most = 32_000, budget = 80_000

    /// The tools read for a job as it starts, in order, most needed first. Only tools that change nothing.
    static func reads(_ job: EditorJob, hasScript: Bool, hasStyle: Bool) -> [(name: String, arguments: JSONValue)] {
        let style: [(String, JSONValue)] = hasStyle ? [("direction_style", .object([:]))] : []
        switch job {
        case .turnover: return [("direction_turnovers", .object([:])), ("direction_timeline", .object([:]))] + style
        case .assemble:
            return [("direction_turnovers", .object([:])), ("direction_dailies", .object([:])), ("direction_timeline", .object([:]))] + style
                + (hasScript ? [("direction_breakdown", .object(["includeScript": .bool(true)]))] : [])
        // The finishing list is in the job itself.
        case .finish: return [("direction_timeline", .object([:]))]
        case .script: return style + [("direction_script", .object([:]))]
        case .breakdown: return style + [("direction_breakdown", .object(["includeScript": .bool(true)]))]
        case .logFootage, .style, .technique: return []
        }
    }
    /// What a continuation reads again: what the director may have changed while the editor waited.
    static func readsAgain(_ job: EditorJob) -> [(name: String, arguments: JSONValue)] {
        switch job {
        case .turnover, .assemble: [("direction_turnovers", .object([:])), ("direction_questions", .object([:]))]
        default: [("direction_questions", .object([:]))]
        }
    }

    /// A tool's call as a script writes it: direction.timeline({}).
    static func call(_ name: String, _ arguments: JSONValue) -> String {
        let text = (try? arguments.data()).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "direction." + (name.hasPrefix("direction_") ? String(name.dropFirst("direction_".count)) : name) + "(" + text + ")"
    }

    /// The section added to the job: the playbook and the editor's notes on a first invocation, then each answer.
    /// Anything that fails or is too long is left for the editor to read, and said so.
    /// The longest the reads may take before the editor starts with what there is.
    static let longest: Double = 20

    static func text(for run: EditorRun, store: ProjectStore, folder: URL, continuing: Bool) async -> String {
        let started = Date()
        var parts: [String] = [], left = budget, unread: [String] = []
        if !continuing {
            if let playbook = try? String(contentsOf: folder.appendingPathComponent(EditorJobs.skillPath(run.job)), encoding: .utf8) {
                parts.append("### The `\(run.job.skill)` playbook (`\(EditorJobs.skillPath(run.job))`)\n\n" + body(playbook))
                left -= playbook.count
            }
            if let notes = try? String(contentsOf: folder.appendingPathComponent("NOTES.md"), encoding: .utf8), notes.count <= most {
                parts.append("### Your notes from earlier runs (`NOTES.md`)\n\n" + notes.trimmingCharacters(in: .whitespacesAndNewlines))
                left -= notes.count
            }
        }
        let reads: [(name: String, arguments: JSONValue)]
        if continuing { reads = readsAgain(run.job) }
        else { reads = self.reads(run.job, hasScript: ((try? store.script())?.rows.isEmpty == false), hasStyle: (try? store.appliedStyle().style) != nil) }
        if !reads.isEmpty, let runtime = try? ToolRuntime(store: store) {
            for read in reads {
                guard !Task.isCancelled else { return "" }
                guard Date().timeIntervalSince(started) < longest else { unread.append(call(read.name, read.arguments)); continue }
                // Only what changes nothing: a job's start must not move the film.
                guard ToolCatalog.definitions.first(where: { $0.name == read.name })?.readOnly == true else { continue }
                guard let answer = try? await Deadline.run(seconds: longest, error: { DirectionError("opening_slow", "Reading for the editor took too long.") }, { try await runtime.invoke(read.name, arguments: read.arguments).value }), let data = try? answer.data() else { unread.append(call(read.name, read.arguments)); continue }
                let text = String(decoding: data, as: UTF8.self)
                guard text.count <= most, text.count <= left else { unread.append(call(read.name, read.arguments)); continue }
                left -= text.count
                parts.append("### `\(call(read.name, read.arguments))` answered\n\n" + text)
            }
        }
        guard !parts.isEmpty else { return "" }
        let lead = continuing
            ? "Direction read these again for you as the director answered. Don\u{2019}t read them again; start from them."
            : "Direction read these for you as the job started: the playbook, your notes, and what you\u{2019}d read first. Don\u{2019}t read them again; start from them, and read only what isn\u{2019}t here."
        let rest = unread.isEmpty ? "" : "\n\nToo long to put here, so read \(unread.count == 1 ? "it" : "them") yourself: " + unread.map { "`\($0)`" }.joined(separator: ", ") + "."
        return ToolCatalog.scriptNames("## Read for you\n\n" + lead + rest) + "\n\n" + parts.joined(separator: "\n\n") + "\n"
    }

    /// A skill's text without its front matter.
    static func body(_ skill: String) -> String {
        guard skill.hasPrefix("---"), let end = skill.range(of: "\n---", range: skill.index(skill.startIndex, offsetBy: 3)..<skill.endIndex) else { return skill.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(skill[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

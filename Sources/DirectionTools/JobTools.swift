import Foundation
import DirectionCore

// Each job is given the tools it uses (specs/editor.md › Tools). An editor Direction starts reaches them only through
// direction_run: its instructions carry the job's tools in full, as the functions a script calls, and direction.help()
// in a script lists the rest and gives any of them in full, so a job is never short of a tool. Every step is a script,
// so a step of several calls is one step, and only what it returns goes back into the editor's context. Your own
// session gets every tool directly.
extension ToolCatalog {
    /// What every job reads and reports with.
    static let everyJob: Set<String> = ["direction_brief", "direction_style", "direction_turnovers", "direction_questions", "direction_ask", "direction_editor_status", "direction_job", "direction_cancel_job"]
    /// Reading the footage.
    static let looking: Set<String> = ["direction_dailies", "direction_index", "direction_shots", "direction_contact_sheet", "direction_frame", "direction_watch", "direction_screen_text", "direction_search_footage", "direction_transcript", "direction_inspect"]
    /// Changing the cut and hearing it, and bringing files into the working folder for graphics, looks and effects.
    static let cutting: Set<String> = ["direction_timeline", "direction_edit", "direction_edit_catalog", "direction_restore", "direction_preview", "direction_measure_audio", "direction_library", "direction_import", "direction_graphic", "direction_graphic_examples", "direction_techniques", "direction_technique", "direction_copy"]

    /// The tools a job is given; direction.help() has the rest.
    public static func names(for job: EditorJob) -> Set<String> {
        switch job {
        case .logFootage: everyJob.union(looking).union(["direction_log_dailies", "direction_transcribe", "direction_sync_takes", "direction_import", "direction_timeline", "direction_edit"])
        case .assemble: everyJob.union(looking).union(cutting).union(["direction_breakdown", "direction_script", "direction_turnover_update", "direction_turnover_complete", "direction_cut_points", "direction_check"])
        // A note can ask for anything: a made shot, a look, a graphic, an import, an earlier version.
        case .turnover: everyJob.union(looking).union(cutting).union(["direction_turnover_update", "direction_turnover_complete", "direction_finishing", "direction_looks", "direction_make_look",
                                                                       "direction_make", "direction_estimate", "direction_services", "direction_sync_takes", "direction_transcribe", "direction_study_frames",
                                                                       "direction_cuts", "direction_feedback_reply", "direction_breakdown", "direction_script", "direction_cut_points", "direction_check"])
        case .finish: everyJob.union(cutting).union(["direction_frame", "direction_watch", "direction_transcript", "direction_inspect", "direction_contact_sheet", "direction_finishing",
                                                     "direction_looks", "direction_make_look", "direction_turnover_update", "direction_turnover_complete", "direction_export", "direction_check"])
        case .style: everyJob.union(cutting).union(["direction_styles", "direction_save_style", "direction_study_frames", "direction_looks", "direction_make_look", "direction_transcript",
                                                    "direction_frame", "direction_watch", "direction_contact_sheet", "direction_inspect"])
        case .technique: everyJob.union(cutting).union(["direction_save_technique", "direction_study_frames", "direction_frame", "direction_watch", "direction_contact_sheet", "direction_shots",
                                                        "direction_search_footage", "direction_transcript", "direction_inspect"])
        case .script: everyJob.union(["direction_script", "direction_script_update", "direction_library"])
        case .breakdown: everyJob.union(["direction_breakdown", "direction_breakdown_update", "direction_script", "direction_estimate", "direction_services", "direction_library"])
        }
    }

    /// What the tool list shows: every tool in your own session; for a job, direction_run alone.
    public static func listed(for job: EditorJob?) -> [ToolDefinition] {
        guard job != nil else { return definitions }
        return definitions.filter { $0.name == runName }
    }

    /// A job's tools in full, as the functions a script calls: what the editor's instructions carry. A host may cut a
    /// tool's description short (Claude Code keeps 2,048 characters); instructions are kept whole.
    public static func reference(for job: EditorJob) -> String {
        let own = names(for: job)
        return definitions.filter { own.contains($0.name) }.map { "### " + call($0, film: true) + "\n" + $0.description }.joined(separator: "\n\n")
    }

    /// One tool as a script calls it, every argument typed. film: the server was started for a film (a job's always
    /// is), so projectPath, on every tool, is left out.
    static func call(_ d: ToolDefinition, film: Bool = false) -> String {
        var schema = d.inputSchema
        if film, case .object(var o) = schema, case .object(var properties) = o["properties"] { properties["projectPath"] = nil; o["properties"] = .object(properties); schema = .object(o) }
        return "direction." + scriptName(d.name) + "(" + typeScript(schema, depth: 0) + ")"
    }
    static func scriptName(_ name: String) -> String { name.hasPrefix("direction_") ? String(name.dropFirst("direction_".count)) : name }

    /// A schema as TypeScript-like types, which reads more easily than JSON Schema and is shorter:
    /// `{at: number, range?: {start: number, end?: number}}`. A field's own words follow it as a comment.
    static func typeScript(_ s: JSONValue, depth: Int) -> String {
        if let shapes = s["anyOf"].array { return shapes.map { typeScript($0, depth: depth) }.joined(separator: " | ") }
        if let options = s["enum"].array, !options.isEmpty {
            return options.map { o in o.string.map { "\"\($0)\"" } ?? o.double.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? "any" }.joined(separator: " | ")
        }
        // A field of more than one kind: {"type": ["string", "integer"]}.
        if let kinds = s["type"].array?.compactMap(\.string), !kinds.isEmpty {
            return kinds.map { kind in typeScript(.object(["type": .string(kind)]), depth: depth) }.joined(separator: " | ")
        }
        switch s["type"].string {
        case "string": return "string"
        case "number": return "number"
        case "integer": return "integer"
        case "boolean": return "boolean"
        case "array":
            let item = typeScript(s["items"], depth: depth)
            return (item.contains(" | ") ? "(\(item))" : item) + "[]"
        default:
            if case .object(let properties) = s["properties"], !properties.isEmpty {
                let required = Set(s["required"].array?.compactMap(\.string) ?? [])
                let keys = properties.keys.sorted { (required.contains($0) ? 0 : 1, $0) < (required.contains($1) ? 0 : 1, $1) }
                let fields = keys.map { key -> (text: String, words: String?) in
                    let p = properties[key]!
                    return ("\(key)\(required.contains(key) ? "" : "?"): \(typeScript(p, depth: depth + 1))", p["description"].string)
                }
                let inline = "{" + fields.map(\.text).joined(separator: ", ") + "}"
                if fields.allSatisfy({ $0.words == nil }), inline.count <= 110 { return inline }
                let pad = String(repeating: "  ", count: depth + 1)
                return "{\n" + fields.map { pad + $0.text + "," + ($0.words.map { "  // " + $0.replacingOccurrences(of: "\n", with: " ") } ?? "") }.joined(separator: "\n") + "\n" + String(repeating: "  ", count: depth) + "}"
            }
            if case .object = s["additionalProperties"] { return "{[key: string]: \(typeScript(s["additionalProperties"], depth: depth))}" }
            // A tool that takes nothing.
            if case .object = s["properties"] { return "{}" }
            return s["type"].string == "object" ? "object" : "any"
        }
    }

    /// direction.help in a script: with no name, the tools this job wasn't given (every tool, in your own session), a
    /// line each; with a name or a list of names, each in full.
    static func help(_ a: JSONValue, job: EditorJob?) throws -> JSONValue {
        let asked = a.string.map { [$0] } ?? a.array?.compactMap(\.string) ?? a["name"].string.map { [$0] } ?? []
        guard !asked.isEmpty else {
            let own = job.map(names(for:)) ?? []
            let rest = definitions.filter { !own.contains($0.name) && $0.name != runName }.map { JSONValue.object(["name": .string(scriptName($0.name)), "does": .string(firstSentence($0.description))]) }
            return .object(["tools": .array(rest), "next": .string("direction.help(\"name\") gives one in full: its arguments and what it does." + (job == nil ? "" : " This job\u{2019}s own tools are in your instructions."))])
        }
        return .array(try asked.map { name in
            let full = name.hasPrefix("direction_") ? name : "direction_" + name
            guard full != runName, let d = definitions.first(where: { $0.name == full }) else {
                throw DirectionError("unknown_tool", "Direction has no tool \(name). direction.help() lists them.")
            }
            return .object(["call": .string(call(d, film: job != nil)), "description": .string(d.description)])
        })
    }

    /// A description's first sentence, for a line in the list.
    static func firstSentence(_ text: String) -> String {
        let end = text.range(of: ". ").map { text[..<$0.lowerBound] + "." } ?? Substring(text)
        return end.count > 200 ? String(end.prefix(199)) + "\u{2026}" : String(end)
    }
}

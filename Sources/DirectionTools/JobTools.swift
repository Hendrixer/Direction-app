import Foundation
import DirectionCore

// Each job is given the tools it uses (specs/editor.md › Tools), so the program has them all from the start
// instead of searching through 60-odd for the one it needs. direction_more_tools lists the rest and runs any of
// them, checked like a direct call, so a job is never short of a tool. Your own session gets every tool.
extension ToolCatalog {
    public static let moreToolsName = "direction_more_tools"

    /// What every job reads and reports with.
    static let everyJob: Set<String> = ["direction_brief", "direction_style", "direction_turnovers", "direction_questions", "direction_ask", "direction_editor_status", "direction_job", "direction_cancel_job"]
    /// Reading the footage.
    static let looking: Set<String> = ["direction_dailies", "direction_index", "direction_shots", "direction_contact_sheet", "direction_frame", "direction_watch", "direction_screen_text", "direction_search_footage", "direction_transcript", "direction_inspect"]
    /// Changing the cut and hearing it.
    static let cutting: Set<String> = ["direction_timeline", "direction_edit", "direction_edit_catalog", "direction_restore", "direction_preview", "direction_measure_audio", "direction_library", "direction_import", "direction_graphic", "direction_graphic_examples", "direction_techniques", "direction_technique"]

    /// The tools a job is given; direction_more_tools has the rest.
    public static func names(for job: EditorJob) -> Set<String> {
        switch job {
        case .logFootage: everyJob.union(looking).union(["direction_log_dailies", "direction_transcribe", "direction_sync_takes", "direction_import", "direction_timeline", "direction_edit"])
        case .assemble: everyJob.union(looking).union(cutting).union(["direction_breakdown", "direction_script", "direction_turnover_update", "direction_turnover_complete"])
        // A note can ask for anything: a made shot, a look, a graphic, an import, an earlier version.
        case .turnover: everyJob.union(looking).union(cutting).union(["direction_turnover_update", "direction_turnover_complete", "direction_finishing", "direction_looks", "direction_make_look",
                                                                       "direction_make", "direction_estimate", "direction_services", "direction_sync_takes", "direction_transcribe", "direction_study_frames",
                                                                       "direction_cuts", "direction_feedback_reply", "direction_breakdown", "direction_script"])
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

    /// What the tool list shows: every tool in your own session; a job's own, then direction_more_tools.
    public static func listed(for job: EditorJob?) -> [ToolDefinition] {
        guard let job else { return definitions }
        let own = names(for: job)
        return definitions.filter { own.contains($0.name) } + [moreTools]
    }

    static let moreTools = definition(moreToolsName, "Direction\u{2019}s other tools. This job was given the ones it usually needs; when a step needs one you don\u{2019}t have, it\u{2019}s here. With no arguments: the rest, a line each. With name: that tool\u{2019}s full description and arguments. With name and arguments: runs it, checked exactly like a direct call, and returns what it returns.",
                                      ["name": noted(string, "A tool\u{2019}s name, like direction_looks."), "arguments": noted(object, "The tool\u{2019}s own arguments, as its description gives them.")])

    /// What direction_more_tools does with its arguments: answer at once (the list, one tool's description), or
    /// run a tool.
    public enum MoreToolsRequest: Sendable { case answer(JSONValue), run(String, JSONValue) }

    public static func moreTools(_ a: JSONValue, job: EditorJob) throws -> MoreToolsRequest {
        var problems: [String] = []
        check(a, schema: moreTools.inputSchema, path: "arguments", into: &problems)
        guard problems.isEmpty else { throw DirectionError("invalid_arguments", problems.joined(separator: " ") + " Nothing was run; call \(moreToolsName) again with that put right.") }
        let own = names(for: job)
        guard let name = a["name"].string else {
            let rest = definitions.filter { !own.contains($0.name) }.map { JSONValue.object(["name": .string($0.name), "does": .string(firstSentence($0.description))]) }
            return .answer(.object(["tools": .array(rest), "next": .string("Call \(moreToolsName) with name for one tool\u{2019}s arguments, then with name and arguments to run it.")]))
        }
        guard let definition = definitions.first(where: { $0.name == name }) else {
            throw DirectionError("unknown_tool", "Direction has no tool \(name). Call \(moreToolsName) with no arguments for the list.")
        }
        guard a["arguments"] != .null else {
            var value: [String: JSONValue] = ["name": .string(name), "description": .string(definition.description), "arguments": definition.inputSchema]
            if own.contains(name) { value["note"] = .string("You already have \(name): call it directly.") }
            return .answer(.object(value))
        }
        DirectionLog.info("The \(job.rawValue) job ran \(name) through \(moreToolsName)", "tools")
        return .run(name, a["arguments"])
    }

    /// A description's first sentence, for a line in the list.
    static func firstSentence(_ text: String) -> String {
        let end = text.range(of: ". ").map { text[..<$0.lowerBound] + "." } ?? Substring(text)
        return end.count > 200 ? String(end.prefix(199)) + "\u{2026}" : String(end)
    }
}

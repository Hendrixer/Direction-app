import Foundation
import DirectionCore

// The editor's runs and activity (specs/editor.md). Runs are the app's to start and stop, so there
// are no run tools; the editor's side is only the activity its calls leave behind.
extension ToolCatalog {
    static var runsDefinitions: [ToolDefinition] { [] }
}

extension ToolRuntime {
    func invokeRuns(_ name: String, _ a: JSONValue) async throws -> ToolResponse? { nil }

    /// Called at the start of every tool call, in every process, so activity shows whether Direction
    /// started the editor or you did (specs/editor.md › Tool call → Activity).
    func noteToolCall(_ name: String, _ a: JSONValue) {
        guard EditorActivityLog.isEnabled else { return }
        EditorActivityLog.record(name, a, store: store, runID: EditorActivityLog.runID)
    }
}

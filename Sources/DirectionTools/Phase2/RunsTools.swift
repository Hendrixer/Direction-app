import Foundation
import DirectionCore

// The editor's runs and activity (specs/editor.md).
extension ToolCatalog {
    static var runsDefinitions: [ToolDefinition] { [] }
}

extension ToolRuntime {
    func invokeRuns(_ name: String, _ a: JSONValue) async throws -> ToolResponse? { nil }

    /// Called at the start of every tool call, in every process, so activity shows whether Direction
    /// started the editor or you did (specs/editor.md › Tool call → Activity).
    func noteToolCall(_ name: String, _ a: JSONValue) {}
}

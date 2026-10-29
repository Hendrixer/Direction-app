import Foundation
import DirectionCore

// The editor's timeline and edit functions (specs/agent-timeline.md).
extension ToolCatalog {
    static var timelineDefinitions: [ToolDefinition] { [] }
}

extension ToolRuntime {
    func invokeTimeline(_ name: String, _ a: JSONValue) async throws -> ToolResponse? { nil }
}

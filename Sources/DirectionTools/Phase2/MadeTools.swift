import Foundation
import DirectionCore

// Made picture and sound (specs/made-media.md).
extension ToolCatalog {
    static var madeDefinitions: [ToolDefinition] { [] }
}

extension ToolRuntime {
    func invokeMade(_ name: String, _ a: JSONValue) async throws -> ToolResponse? { nil }
}

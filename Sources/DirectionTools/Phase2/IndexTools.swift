import Foundation
import DirectionCore

// Looking at footage (specs/footage-index.md).
extension ToolCatalog {
    static var indexDefinitions: [ToolDefinition] { [] }
}

extension ToolRuntime {
    func invokeIndex(_ name: String, _ a: JSONValue) async throws -> ToolResponse? { nil }
}

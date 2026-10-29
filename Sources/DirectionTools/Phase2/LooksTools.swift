import Foundation
import DirectionCore

// Looks (specs/looks.md).
extension ToolCatalog {
    static var looksDefinitions: [ToolDefinition] { [] }
}

extension ToolRuntime {
    func invokeLooks(_ name: String, _ a: JSONValue) async throws -> ToolResponse? { nil }
}

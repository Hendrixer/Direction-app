import Foundation
import DirectionCore

// Graphics (specs/graphics.md).
extension ToolCatalog {
    static var graphicsDefinitions: [ToolDefinition] { [] }
}

extension ToolRuntime {
    func invokeGraphics(_ name: String, _ a: JSONValue) async throws -> ToolResponse? { nil }
}

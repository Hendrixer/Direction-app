import Foundation
import DirectionCore

// Phase 2 tools. Each area registers its definitions and handles its calls in its own file.
extension ToolCatalog {
    static var phase2Definitions: [ToolDefinition] {
        runsDefinitions + indexDefinitions + syncDefinitions + timelineDefinitions + looksDefinitions + graphicsDefinitions + madeDefinitions + styleDefinitions
    }
}

extension ToolRuntime {
    func invokePhase2(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        if let r = try await invokeRuns(name, a) { return r }
        if let r = try await invokeIndex(name, a) { return r }
        if let r = try await invokeSync(name, a) { return r }
        if let r = try await invokeTimeline(name, a) { return r }
        if let r = try await invokeLooks(name, a) { return r }
        if let r = try await invokeGraphics(name, a) { return r }
        if let r = try await invokeMade(name, a) { return r }
        if let r = try await invokeStyles(name, a) { return r }
        return nil
    }
}

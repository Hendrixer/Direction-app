import Foundation
import MCP
import DirectionCore

public enum DirectionMCPServer {
    /// Told when a tool call has run 5, 15 and 30 minutes: crash reports take every thread's stack then, so a
    /// report shows where it's stuck. The call itself is logged either way.
    nonisolated(unsafe) public static var onStuck: (@Sendable (String, Int) -> Void)?
    static let stuckMarks = [5, 15, 30]

    public static func run(runtime: ToolRuntime) async throws { try await run(router: ProjectRouter(runtime: runtime)) }
    public static func run(router: ProjectRouter) async throws {
        let server = Server(name: "Direction", version: "0.2.0", capabilities: .init(tools: .init(listChanged: false)))
        await server.withMethodHandler(ListTools.self) { _ in
            let tools = try ToolCatalog.definitions.map { definition in
                Tool(name: definition.name, description: definition.description, inputSchema: try JSONDecoder().decode(Value.self, from: definition.inputSchema.data()), annotations: .init(readOnlyHint: definition.readOnly, destructiveHint: false, openWorldHint: false))
            }
            return .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { params in
            do {
                let data = try JSONEncoder().encode(params.arguments ?? [:])
                let arguments = try JSONDecoder().decode(JSONValue.self, from: data)
                let name = params.name
                let watch = Task {
                    var waited = 0
                    for mark in stuckMarks {
                        try await Task.sleep(for: .seconds((mark - waited) * 60)); waited = mark
                        DirectionLog.warning("\(name) has been running for \(mark) min", "tools")
                        onStuck?(name, mark)
                    }
                }
                defer { watch.cancel() }
                let response = try await router.invoke(params.name, arguments: arguments)
                var content: [Tool.Content] = [.text(text: String(decoding: try response.value.data(pretty: true), as: UTF8.self), annotations: nil, _meta: nil)]
                for path in response.imagePaths { content.append(.image(data: try Data(contentsOf: URL(fileURLWithPath: path)).base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil)) }
                for path in response.audioPaths { content.append(.audio(data: try Data(contentsOf: URL(fileURLWithPath: path)).base64EncodedString(), mimeType: "audio/wav", annotations: nil, _meta: nil)) }
                return .init(content: content, isError: false)
            } catch {
                let error = error as? DirectionError ?? DirectionError("operation_failed", error.localizedDescription)
                return .init(content: [.text(text: String(decoding: try JSONEncoder.direction.encode(error), as: UTF8.self), annotations: nil, _meta: nil)], isError: true)
            }
        }
        try await server.start(transport: EditorClientTransport())
        await server.waitUntilCompleted()
        await router.cancelAll()
    }
}

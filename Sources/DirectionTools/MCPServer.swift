import Foundation
import MCP
import DirectionCore

public enum DirectionMCPServer {
    /// Told when a tool call has run 5 minutes, half its limit: crash reports take every thread's stack then, so a
    /// report shows where it's stuck. The call itself is logged either way.
    nonisolated(unsafe) public static var onStuck: (@Sendable (String, Int) -> Void)?
    static let stuckMark = 5
    /// No tool call waits longer than this: long work runs as jobs and returns at once, so a call still going after
    /// ten minutes is stuck. The editor is told, and carries on (hang recovery).
    nonisolated(unsafe) public static var callLimit: Double = 600
    /// Calls whose long work happens inside the call, not as a job, so they have no limit and aren't reported as
    /// stuck: an import makes its SDR or seekable copy of the whole file before it returns (ToolRuntime › import).
    public static let unlimited: Set<String> = ["direction_import"]

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
                let name = params.name, limited = !unlimited.contains(name)
                let watch = Task {
                    guard limited else { return }
                    // Awake time: a Mac asleep isn't a call taking too long.
                    try await Task.sleep(for: .seconds(stuckMark * 60), clock: .suspending)
                    DirectionLog.warning("\(name) has been running for \(stuckMark) min", "tools")
                    onStuck?(name, stuckMark)
                }
                defer { watch.cancel() }
                let limit = callLimit
                let call: @Sendable () async throws -> ToolResponse = { try await router.invoke(name, arguments: arguments) }
                let response = !limited ? try await call() : try await Deadline.run(seconds: limit, error: {
                    DirectionLog.error("\(name) didn\u{2019}t finish in \(Int(limit / 60)) min and was stopped", "tools")
                    return DirectionError("tool_stuck", "\(name) didn\u{2019}t finish in \(Int(limit / 60)) minutes and was stopped. Don\u{2019}t call it the same way again: try a shorter passage or fewer frames, or look at what you changed there last (an effect or graphic that never finishes). Then carry on.")
                }, call)
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

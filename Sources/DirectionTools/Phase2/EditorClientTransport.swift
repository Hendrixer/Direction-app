import Foundation
import Logging
import MCP
import DirectionCore

/// Stdio for the editor's MCP client, made tolerant of capabilities the Swift SDK can't decode.
/// Codex 0.164 sends `capabilities.experimental: {"codex/auth-change": {}}`; the SDK reads
/// `experimental` as `[String: String]` and fails the handshake, so Codex never sees Direction's
/// tools. Experimental capabilities mean nothing to Direction, so they're dropped on the way in.
public actor EditorClientTransport: Transport {
    private let inner: StdioTransport
    public nonisolated var logger: Logger { inner.logger }
    public init(_ inner: StdioTransport = StdioTransport()) { self.inner = inner }

    public func connect() async throws { try await inner.connect() }
    public func disconnect() async { await inner.disconnect() }
    public func send(_ data: Data) async throws { try await inner.send(data) }
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let upstream = inner
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await data in await upstream.receive() { continuation.yield(Self.sanitized(data)) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// An `initialize` request without `params.capabilities.experimental`; anything else untouched.
    public static func sanitized(_ data: Data) -> Data {
        guard data.range(of: Data("\"experimental\"".utf8)) != nil,
              var message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              capabilities["experimental"] != nil else { return data }
        capabilities.removeValue(forKey: "experimental")
        params["capabilities"] = capabilities; message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? data
    }
}

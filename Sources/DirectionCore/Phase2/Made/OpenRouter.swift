import Foundation
import Security

/// OpenRouter: the one service behind made media and, optionally, looking at footage
/// (specs/made-media.md › Services). Direction makes every request; the key never reaches the editor.
public enum OpenRouter {
    public static let base = URL(string: "https://openrouter.ai/api/v1")!

    /// The director's key, kept in the login keychain as Direction's own item.
    public enum Key {
        static let service = "dev.direction.openrouter", account = "default"

        public static func read() -> String? {
            if let key = ProcessInfo.processInfo.environment["DIRECTION_OPENROUTER_KEY"], !key.isEmpty { return key }
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        public static func save(_ key: String) throws {
            remove()
            let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                       kSecAttrLabel as String: "Direction · OpenRouter key", kSecValueData as String: Data(key.utf8)]
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw DirectionError("keychain_failed", "Couldn't save the key to the keychain (\(status)).") }
        }

        public static func remove() {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        }
    }

    /// Tests swap the transport; everything else uses URLSession.
    nonisolated(unsafe) public static var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    /// One JSON request. Throws OpenRouter's own message on a non-2xx reply.
    public static func request(_ method: String, _ path: String, body: JSONValue? = nil, key: String? = nil) async throws -> Data {
        guard let key = key ?? Key.read() else { throw DirectionError("no_openrouter_key", "Add an OpenRouter key in Settings › Services.") }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("https://direction.film", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Direction", forHTTPHeaderField: "X-OpenRouter-Title")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]["message"].string ?? String(data: data, encoding: .utf8) ?? ""
            throw DirectionError("openrouter_error", "OpenRouter said: \(message) (\(status))")
        }
        return data
    }

    /// A non-streaming chat completion. Returns the whole response object.
    public static func chat(_ body: JSONValue, key: String? = nil) async throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: await request("POST", "chat/completions", body: body, key: key))
    }
}

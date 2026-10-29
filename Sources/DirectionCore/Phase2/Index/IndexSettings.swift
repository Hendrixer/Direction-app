import Foundation

/// Settings › Footage › Looking at footage, in the shared suite so the MCP server indexes the way
/// the director chose (settings.md › 54).
extension SharedSettings {
    public enum IndexKey {
        public static let engine = "lookEngine"
        public static let detail = "lookDetail"
        public static let openRouterVersion = "lookOpenRouterVersion"
        public static let automatic = "lookAutomatically"
    }

    public enum LookEngine: String, CaseIterable, Sendable { case thisMac, openRouter }

    /// The three local versions, all mlx-community 4-bit conversions that mlx-vlm loads.
    /// `label` is the select's copy; `bytes` is the real download, used for the disk check and progress.
    public struct LookDetail: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var repo: String
        public var label: String
        public var bytes: Int64
        /// Memory the Mac needs to run it at all.
        public var minimumMemory: UInt64
    }

    public static let lookDetails: [LookDetail] = [
        .init(id: "quick", name: "Qwen2.5-VL 3B", repo: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit", label: "Quick \u{00B7} 2.4 GB", bytes: 3_090_000_000, minimumMemory: 8 << 30),
        .init(id: "standard", name: "Qwen3-VL 8B", repo: "mlx-community/Qwen3-VL-8B-Instruct-4bit", label: "Standard \u{00B7} 5.8 GB", bytes: 5_780_000_000, minimumMemory: 16 << 30),
        .init(id: "best", name: "Qwen3-VL 30B-A3B", repo: "mlx-community/Qwen3-VL-30B-A3B-Instruct-4bit", label: "Best \u{00B7} 17 GB", bytes: 18_270_000_000, minimumMemory: 32 << 30),
    ]

    /// OpenRouter vision versions offered in the Detail select, default first.
    public static let lookOpenRouterVersions: [(id: String, name: String)] = [
        ("google/gemini-3.1-flash-lite", "Gemini 3.1 Flash Lite"),
        ("google/gemini-3.8-flash", "Gemini 3.8 Flash"),
        ("qwen/qwen3-vl-8b-instruct", "Qwen3 VL 8B"),
        ("anthropic/claude-haiku-5.5", "Claude Haiku 5.5"),
        ("openai/gpt-5.4-mini", "GPT-5.4 Mini"),
    ]

    public static var lookEngine: LookEngine {
        defaults.string(forKey: IndexKey.engine).flatMap(LookEngine.init(rawValue:)) ?? .thisMac
    }
    public static var lookDetail: LookDetail {
        let id = defaults.string(forKey: IndexKey.detail) ?? "standard"
        return lookDetails.first { $0.id == id } ?? lookDetails[1]
    }
    public static var lookOpenRouterVersion: String {
        defaults.string(forKey: IndexKey.openRouterVersion) ?? lookOpenRouterVersions[0].id
    }
    /// Off: footage is indexed only when the editor asks or the director chooses Look at Footage.
    public static var lookAutomatically: Bool {
        defaults.object(forKey: IndexKey.automatic) as? Bool ?? true
    }
}

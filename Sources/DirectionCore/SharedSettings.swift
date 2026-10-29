import Foundation

/// App-wide settings that the MCP server and CLI read too. The app writes them from Settings;
/// every process reads the same defaults suite, so the editor's tools follow what the director chose.
public enum SharedSettings {
    public static let suiteName = "dev.direction.shared"
    public static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    public enum Key {
        public static let transcriptionEngine = "transcriptionEngine"
        public static let whisperModel = "whisperModel"
    }

    public enum TranscriptionEngine: String, CaseIterable, Sendable { case apple, whisper }

    /// mlx-community repos, smallest first. Turbo keeps 4 of large-v3's 32 decoder layers.
    public static let whisperModels: [(id: String, name: String)] = [
        ("mlx-community/whisper-large-v3-turbo", "Large v3 Turbo"),
        ("mlx-community/whisper-large-v3-mlx", "Large v3"),
    ]

    public static var transcriptionEngine: TranscriptionEngine {
        defaults.string(forKey: Key.transcriptionEngine).flatMap(TranscriptionEngine.init(rawValue:)) ?? .apple
    }
    public static var whisperModel: String {
        defaults.string(forKey: Key.whisperModel) ?? whisperModels[0].id
    }
}

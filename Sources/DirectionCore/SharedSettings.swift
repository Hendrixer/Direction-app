import Foundation

/// App-wide settings that the MCP server and CLI read too. The app writes them from Settings;
/// every process reads the same defaults suite, so the editor's tools follow what the director chose.
public enum SharedSettings {
    public static let suiteName = "dev.direction.shared"
    /// Tests point this at a throwaway suite so they never touch the director's settings.
    nonisolated(unsafe) public static var defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    public enum Key {
        public static let transcriptionEngine = "transcriptionEngine"
        public static let whisperModel = "whisperModel"
        public static let loudnessTarget = "loudnessTarget"
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
    /// Settings › Cutting › Loudness target, in LUFS: the mix is brought to it, and a delivery is checked against it.
    public static var loudnessTarget: Double { defaults.object(forKey: Key.loudnessTarget) as? Double ?? -14 }
    /// No peak goes over this, in dBTP (true peak): what the streaming services ask for.
    public static let truePeakCeiling = -1.0
    /// How far from the target still counts as on it, in LU.
    public static let loudnessTolerance = 1.0

    /// Settings written before a setting was shared move to the shared suite once, so the tools read the
    /// director's choice and not the default.
    public static func adopt(_ keys: [String], from old: UserDefaults) {
        for key in keys where defaults.object(forKey: key) == nil { if let value = old.object(forKey: key) { defaults.set(value, forKey: key) } }
    }
}

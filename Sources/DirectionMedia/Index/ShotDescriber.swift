import Foundation
import DirectionCore

/// Step 4: a line about each shot. A vision engine looks at three keyframes (10%, 50%, 90%) at
/// 672 px with the take's words for that range, and fills `ShotLook`. Greedy decoding, 160 tokens,
/// validated against the shape with one retry.
public protocol ShotDescriber: Sendable {
    /// Provenance stored on each shot: "mlx-vlm · mlx-community/Qwen3-VL-8B-Instruct-4bit".
    var engine: String { get }
    /// How many shots to describe at once.
    var concurrency: Int { get }
    /// How many one-frame shots one batched request can carry (1: no batching).
    var batchSize: Int { get }
    func describe(_ request: DescribeRequest) async throws -> DescribeResult
    /// Several shots in one go; nil for a shot whose reply never fit the shape.
    func describeBatch(_ requests: [DescribeRequest]) async throws -> [DescribeResult?]
    /// Called when a job is done with it.
    func finish() async
}

extension ShotDescriber {
    public var batchSize: Int { 1 }
    public func describeBatch(_ requests: [DescribeRequest]) async throws -> [DescribeResult?] {
        var out: [DescribeResult?] = []
        for r in requests {
            do { out.append(try await describe(r)) }
            catch let e as DirectionError where e.code == "description_invalid" { out.append(nil) }
        }
        return out
    }
}

public struct DescribeRequest: Sendable {
    public var images: [URL]
    /// What's said during the shot, if anything.
    public var words: String
    public init(images: [URL], words: String) { self.images = images; self.words = words }
}

public struct DescribeResult: Sendable {
    public var look: ShotLook
    /// Dollars, when a service charged for it.
    public var spend: Double?
    public init(look: ShotLook, spend: Double? = nil) { self.look = look; self.spend = spend }
}

public enum DescribePrompt {
    public static let maxTokens = 160

    public static func text(words: String, retry: Bool = false, frames: Int = 3) -> String {
        var lines = [
            frames == 1 ? "You log footage for a film editor. The image is the middle of one continuous shot that doesn\u{2019}t move." : "You log footage for a film editor. The images are three moments of one continuous shot, at 10%, 50% and 90% of it.",
        ]
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !w.isEmpty { lines.append("Words spoken during the shot: \u{201C}\(w.prefix(600))\u{201D}") }
        lines += [
            "Reply with only this JSON object, nothing else:",
            "{\"description\": \"\", \"size\": \"\", \"movement\": \"\", \"people\": [], \"setting\": \"\", \"flags\": []}",
            "- description: what you see, logged the way an assistant editor would: 18 words at most, present tense, starting with the shot size and what it's on (\u{201C}Wide on\u{2026}\u{201D}, \u{201C}Close on\u{2026}\u{201D}), then what happens or changes. Describe only these images. Don't mention frames, images or video. Never guess anyone's name.",
            "- size: one of wide, medium, close, insert.",
            "- movement: one of static, pan, tilt, push, pull, handheld.",
            "- people: what is visible of each person, like \"woman, dark hair\". Empty if nobody.",
            "- setting: where and when in a few words, like \"kitchen, dusk\".",
            "- flags: any of soft, shaky, overexposed, underexposed. Empty if the picture is fine.",
        ]
        if retry { lines.append("Your last reply wasn't that JSON. Reply with the JSON object only.") }
        return lines.joined(separator: "\n")
    }

    private struct Loose: Decodable {
        var description: String?
        var size: String?
        var movement: String?
        var people: [String]?
        var setting: String?
        var flags: [String]?
        enum CodingKeys: CodingKey { case description, size, movement, people, setting, flags }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            description = try? c.decode(String.self, forKey: .description)
            size = try? c.decode(String.self, forKey: .size)
            movement = try? c.decode(String.self, forKey: .movement)
            setting = try? c.decode(String.self, forKey: .setting)
            // Small versions sometimes answer a list with one string.
            people = (try? c.decode([String].self, forKey: .people)) ?? (try? c.decode(String.self, forKey: .people)).map { $0.isEmpty ? [] : [$0] }
            flags = (try? c.decode([String].self, forKey: .flags)) ?? (try? c.decode(String.self, forKey: .flags)).map { $0.isEmpty ? [] : [$0] }
        }
    }

    /// Reads a reply: the first JSON object in it (code fences and chatter around it are ignored).
    public static func parse(_ text: String) -> ShotLook? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        guard let loose = try? JSONDecoder().decode(Loose.self, from: Data(text[open...close].utf8)), let d = loose.description else { return nil }
        return ShotLook.validated(ShotLook(description: d, size: loose.size, movement: loose.movement, people: loose.people ?? [], setting: loose.setting, flags: loose.flags ?? []))
    }

    /// One attempt, then one retry with a reminder; a reply that never fits the shape fails the shot.
    /// `attempt` sends a prompt and returns the reply and what it cost, if anything.
    public static func run(words: String, frames: Int = 3, _ attempt: (_ prompt: String) async throws -> (String, Double?)) async throws -> DescribeResult {
        var spend = 0.0, spent = false
        for retry in [false, true] {
            let (reply, cost) = try await attempt(text(words: words, retry: retry, frames: frames))
            if let cost { spend += cost; spent = true }
            if let look = parse(reply) { return DescribeResult(look: look, spend: spent ? spend : nil) }
        }
        throw DirectionError("description_invalid", "The reply didn't fit the description's shape twice.")
    }
}

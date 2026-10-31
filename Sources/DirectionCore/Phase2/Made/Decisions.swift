import Foundation

/// Fast decisions (specs/decisions.md): one narrow question answered by choosing among answers Direction
/// writes, with a probability for each, in well under a second and for a fraction of a cent. Nothing is
/// written back. Same key, same ledger as made media; OpenRouter serves them at `/api/alpha/decisions`.
public enum Decisions {
    public static let base = URL(string: "https://openrouter.ai/api/alpha")!
    /// Direction picks the versions, as for made media, and pins them: OpenRouter's "latest" aliases move.
    /// OpenAI's GPT-6 Luna decisions is built on a model that sees; TypeSafe calls Jev 1.14's images
    /// experimental. Until Direction has compared them on what the director keeps, frames go to both.
    public static let luna = "openai/gpt-6-luna-decisions"
    public static let jev = "typesafe/jev-1.14"
    public static let frameVersions = [luna, jev]
    /// Jev takes PNG or JPEG, each side 256 to 1,568 px; Luna takes those sizes too.
    public static let frameSize = 1024

    /// What the questions are about: words, and JPEG frames in the order they're listed. Frames go inline as
    /// `image_url` parts, the one shape every version takes, so questions name them by place ("frame 3 of 5").
    public enum Part: Sendable, Equatable {
        case text(String)
        case image(Data)
        var json: JSONValue {
            switch self {
            case .text(let s): .string(s)
            case .image(let d): .object(["type": .string("image_url"), "image_url": .object(["url": .string(MadeMedia.dataURL(d, mime: "image/jpeg"))])])
            }
        }
    }

    /// A question with the answers to choose from, each described in plain words.
    public struct Question: Sendable, Equatable {
        public var instructions: String
        /// Answer label and what it means, in the order they're offered.
        public var choices: [(label: String, means: String)]
        public init(_ instructions: String, _ choices: [(label: String, means: String)]) { self.instructions = instructions; self.choices = choices }
        public static func == (a: Self, b: Self) -> Bool { a.instructions == b.instructions && a.choices.map(\.label) == b.choices.map(\.label) && a.choices.map(\.means) == b.choices.map(\.means) }
        var json: JSONValue {
            .object(["type": .string("choice"), "instructions": .string(instructions),
                     "criteria": .object(Dictionary(uniqueKeysWithValues: choices.map { ($0.label, JSONValue.string($0.means)) }))])
        }
    }

    public struct Answer: Codable, Hashable, Sendable {
        public var choice: String
        public var probabilities: [String: Double]
        /// How concentrated the answer is, not how likely it's right.
        public var confidence: Double?
        public init(choice: String, probabilities: [String: Double] = [:], confidence: Double? = nil) { self.choice = choice; self.probabilities = probabilities; self.confidence = confidence }
    }

    public struct Reply: Sendable {
        public var answers: [String: Answer]
        /// The version that answered, as OpenRouter names it ("typesafe/jev-1.14-20261014").
        public var version: String
        public var cost: Double?
        public init(answers: [String: Answer], version: String, cost: Double? = nil) { self.answers = answers; self.version = version; self.cost = cost }
    }

    /// Asks every question about the same `state` at once; they're answered in parallel and can't see each
    /// other. With `spend`, the cost goes in the ledger under that kind.
    public static func ask(_ questions: [String: Question], state: [Part], version: String, spend: SpendKind? = nil, filmID: String? = nil, turnoverID: String? = nil, key: String? = nil) async throws -> Reply {
        let body: JSONValue = .object(["model": .string(version), "state": .array(state.map(\.json)), "questions": .object(questions.mapValues(\.json))])
        let json = try await OpenRouter.send("POST", "decisions", body: body, key: key, timeout: 30, root: base).json
        var answers: [String: Answer] = [:]
        for name in questions.keys {
            let a = json["answers"][name]
            guard let choice = a["choice"].string else { continue }
            var probabilities: [String: Double] = [:]
            for label in questions[name]!.choices.map(\.label) { if let p = a["probabilities"][label].double { probabilities[label] = p } }
            answers[name] = Answer(choice: choice, probabilities: probabilities, confidence: a["confidence"].double)
        }
        guard !answers.isEmpty else { throw DirectionError("no_answers", "OpenRouter sent no answers.") }
        let cost = json["usage"]["cost"].double
        if let spend, let cost, cost > 0 {
            try? SpendLedger.record(SpendEntry(kind: spend, version: version, estimate: cost, spend: cost, filmID: filmID, turnoverID: turnoverID))
        }
        return Reply(answers: answers, version: json["model"].string ?? version, cost: cost)
    }
}

import Testing
import Foundation
@testable import DirectionCore

/// Direction's own look at made shots (decisions.md › Judging made shots). No request leaves this Mac.
struct MadeCheckTests {
    private let moments = MadeChecker.moments(duration: 5)
    private func reply(_ answers: [String: String]) -> Decisions.Reply {
        var all = ["look1": "clean", "look2": "clean", "look3": "clean", "look4": "clean", "look5": "clean", "morph": "moves", "same": "same", "asked": "yes"]
        all.merge(answers) { _, b in b }
        return Decisions.Reply(answers: all.mapValues { Decisions.Answer(choice: $0) }, version: Decisions.version, cost: 0.0003)
    }

    @Test func everyFrameIsNamedAndAskedAbout() {
        #expect(moments == [0, 1.25, 2.5, 3.75, 4.9])
        let (state, questions) = MadeChecker.questions(kind: .shot, ask: "Slow push in. Steam rises from the cup.", moments: moments)
        #expect(Set(questions.keys) == ["look1", "look2", "look3", "look4", "look5", "morph", "same", "asked"])
        // Each image is cited in the state, and each frame's question names only its own.
        for i in 1...5 { #expect(state.contains("frame_\(i)")) }
        #expect(questions["look3"]!.instructions.contains("frame_3") && !questions["look3"]!.instructions.contains("frame_2"))
        #expect(questions["same"]!.instructions.contains("frame_1") && questions["same"]!.instructions.contains("frame_5"))
        #expect(state.contains("\u{201C}Slow push in. Steam rises from the cup.\u{201D}"))
        // A still is one frame: broken or not, and whether it's what was asked.
        let still = MadeChecker.questions(kind: .still, ask: "A coffee cup at dawn.", moments: [0])
        #expect(Set(still.questions.keys) == ["look1", "asked"] && still.state.hasPrefix("A still made for a film: frame_1."))
        // Sharpening and slow motion work on real footage; they aren't checked.
        #expect(MadeChecker.checks(.bridge) && MadeChecker.checks(.still) && !MadeChecker.checks(.slowMotion) && !MadeChecker.checks(.upscale) && !MadeChecker.checks(.music))
    }

    @Test func theVerdictIsTheWorstThingFoundInWords() {
        let clean = MadeChecker.check(from: reply([:]), moments: moments)
        #expect(clean.verdict == .clean && clean.findings.isEmpty && clean.short == "Looks clean" && clean.shadow)

        let broken = MadeChecker.check(from: reply(["look3": "minor", "look4": "broken", "look5": "broken", "same": "drifted"]), moments: moments)
        #expect(broken.verdict == .broken && broken.short == "Looks broken at 0:04")
        #expect(broken.findings == ["Something looks broken at 0:04 and 0:05.", "A person or the place turns into someone or somewhere else by the end.", "Slightly off at 0:03."])
        #expect(broken.frames.map(\.verdict) == [.clean, .clean, .minor, .broken, .broken])

        let partly = MadeChecker.check(from: reply(["asked": "partly"]), moments: moments)
        #expect(partly.verdict == .minor && partly.findings == ["It shows only part of what was asked."])
        #expect(MadeChecker.check(from: reply(["morph": "morphs"]), moments: moments).verdict == .broken)
        #expect(MadeChecker.check(from: reply(["asked": "no"]), moments: moments).findings == ["It doesn\u{2019}t show what was asked."])

        // What the editor reads: the verdict, the findings and each frame, without the probabilities.
        let editor = broken.forEditor
        #expect(editor["verdict"].string == "broken" && editor["shadow"].bool == true && editor["frames"].array?.count == 5 && editor["answers"] == .null)
    }

    @Test func askingSendsFramesAsAssetsAndRecordsTheSpend() async throws {
        let ledger = FileManager.default.temporaryDirectory.appendingPathComponent("spend-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledger); try? FileManager.default.removeItem(at: ledger.appendingPathExtension("lock")) }
        let sent = Sent()
        let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { r in
            sent.add(r)
            let answers: JSONValue = .object(["look1": .object(["type": .string("choice"), "choice": .string("broken"), "probabilities": .object(["clean": .number(0.1), "minor": .number(0.2), "broken": .number(0.7)]), "confidence": .number(0.42)])])
            let body: JSONValue = .object(["model": .string("typesafe/jev-1.14-20261014"), "answers": answers, "usage": .object(["input_tokens": .number(900), "output_tokens": .number(4), "cost": .number(0.00004)])])
            return (try body.data(), HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let frame = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let question = Decisions.Question("Look only at frame_1. Is anything in it broken?", [("clean", "Whole."), ("minor", "A little off."), ("broken", "Melted.")])
        let reply = try await OpenRouter.$overrides.withValue(OpenRouter.Overrides(transport: transport, key: "sk-or-v1-stub-secret", ledger: ledger)) {
            try await Decisions.ask(["look1": question], state: "A still made for a film: frame_1.", images: ["frame_1": frame], spend: .checking, filmID: "film-1", turnoverID: "turnover-1")
        }
        #expect(reply.answers["look1"] == Decisions.Answer(choice: "broken", probabilities: ["clean": 0.1, "minor": 0.2, "broken": 0.7], confidence: 0.42))
        #expect(reply.version == "typesafe/jev-1.14-20261014" && reply.cost == 0.00004)

        let request = try #require(sent.all.first)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/alpha/decisions" && request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-stub-secret")
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody))
        #expect(body["model"].string == "typesafe/jev-1.14")
        // Plain base64, no data: prefix; the key appears in the state so the frame is cited.
        #expect(body["assets"]["frame_1"] == .object(["type": .string("image"), "format": .string("jpg"), "data_base64": .string(frame.base64EncodedString())]))
        #expect(body["questions"]["look1"]["type"].string == "choice" && body["questions"]["look1"]["criteria"]["broken"].string == "Melted.")

        let entries = OpenRouter.$overrides.withValue(OpenRouter.Overrides(ledger: ledger)) { SpendLedger.entries() }
        #expect(entries.count == 1 && entries[0].kind == .checking && entries[0].spend == 0.00004 && entries[0].turnoverID == "turnover-1")
        #expect(SpendKind.checking.group == "Checking")
    }

    @Test func oldRecordsWithoutACheckStillRead() throws {
        let old = #"{"assetID":"a","kind":"shot","service":"openrouter","version":"minimax/hailuo-3","versionName":"H3","asked":"x","seconds":5,"spend":0.4,"estimate":0.4,"references":[],"file":"Made/x.mp4","createdAt":1}"#
        let r = try JSONDecoder().decode(MadeRecord.self, from: Data(old.utf8))
        #expect(r.check == nil)
    }
}

private final class Sent: @unchecked Sendable {
    private let lock = NSLock(); private var requests: [URLRequest] = []
    func add(_ r: URLRequest) { lock.withLock { requests.append(r) } }
    var all: [URLRequest] { lock.withLock { requests } }
}

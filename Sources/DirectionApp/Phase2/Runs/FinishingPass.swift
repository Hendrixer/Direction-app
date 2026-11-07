import Foundation
import DirectionCore
import DirectionTools

/// Finishing, the part that comes out the same every time (finish.md › What Direction does itself). Before the
/// editor starts on a locked picture, Direction lays captions from the words, rolls the director's credits and
/// brings the whole mix to the loudness target, each an edit of its own, and says what it did in the checklist
/// the editor reads first. What's left for the editor needs an eye and an ear: color, the balance of the mix,
/// titles, and checking the captions and the framing.
///
/// Each step runs when there's something for it to do, so Finish again never undoes the editor's work or the
/// director's: captions only while none are laid, the credits only when the director's differ from the ones
/// rolled, the loudness while the mix is off the target and sound isn't done. Stopping the run stops the pass between steps and inside one.
@MainActor enum FinishingPass {
    static func run(store: ProjectStore, runID: String) async {
        guard let runtime = try? ToolRuntime(store: store), let p = try? store.read(), let s = try? p.sequence(nil) else { return }
        // An item as the checklist has it now, and changed alone: the director may change others meanwhile.
        func item(_ id: String) -> FinishingItem? { ((try? store.directingState().finishing) ?? FinishingItem.defaults).first { $0.id == id } }
        func change(_ id: String, _ update: (inout FinishingItem) -> Void) {
            guard var i = item(id) else { return }
            update(&i)
            _ = try? store.updateFinishing([i])
        }
        func step(_ verb: String, _ object: String, _ op: JSONValue) async -> JSONValue? {
            guard !Task.isCancelled else { return nil }
            _ = try? store.recordActivity(.init(verb: verb, object: object, tool: "direction_edit"), runID: runID)
            do {
                return try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString),
                                                                                     "summary": .string("Finishing: \(verb.lowercased()) \(object)"), "operations": .array([op])])).value
            } catch {
                DirectionLog.info("Finishing step \(op["op"].string ?? "") didn\u{2019}t run: \(error.localizedDescription)", "editor")
                return nil
            }
        }
        func said(_ result: JSONValue?) -> String? { result?["operations"].array?.first?["summary"].string }
        let style = try? store.style(), state = try? store.directingState()
        let placed = Set(s.clips.filter { $0.layer > 0 }.compactMap { c in c.assetID.flatMap { id in p.assets.first { $0.id == id }?.graphic } })

        // Captions, once: while none are laid, unless the style keeps them off or the director checked them.
        if style?.tokens["captions"]["on"].bool != false, item("captions")?.state != "done", !placed.contains(where: { $0.hasPrefix("captions-") }),
           let result = await step("Captioning", "the cut", .object(["op": .string("captions")])) {
            change("captions") { $0.state = "working"; $0.detail = "Direction laid captions from the words: \(said(result)?.replacingOccurrences(of: "Laid captions from the words in ", with: "") ?? "the whole cut"). Check the line breaks and the names." }
        }
        // The director's credits, rolled after the last shot: when none are rolled, or theirs changed since.
        if let credits = state?.credits?.trimmingCharacters(in: .whitespacesAndNewlines), !credits.isEmpty,
           rolledCredits(store, placed) != credits, let result = await step("Rolling the credits in", "the cut", .object(["op": .string("credits")])) {
            change("titles") { item in
                let before = item.detail.components(separatedBy: " Direction rolled").first ?? item.detail
                let rolled = "Direction \(said(result).map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "rolled the credits")."
                item.detail = before.hasPrefix("Direction rolled") || before.isEmpty ? rolled : before + " " + rolled
            }
        }
        // Last, so it hears everything that's placed; not once sound is done, or while the mix is on target.
        let onTarget = (try? await runtime.invoke("direction_measure_audio"))?.value["target"]["ready"].bool ?? true
        if item("sound")?.state != "done", !onTarget, let result = await step("Setting the loudness of", "the mix", .object(["op": .string("loudness")])) {
            let held = (result["operations"].array?.first?["warnings"].array ?? result["warnings"].array ?? []).compactMap(\.string).first { $0.contains("peaks hold") }
            change("sound") { $0.detail = "Direction \(said(result).map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "set the mix to the target"). \(held ?? "Balance the tracks; run loudness again after changing the sound.")" }
        }
    }

    /// The credits the rolled credits graphic was made from (its credits.js), when one is in the cut.
    static func rolledCredits(_ store: ProjectStore, _ placed: Set<String>) -> String? {
        guard let name = placed.first(where: { $0 == "credits" || $0.hasPrefix("credits-") }),
              let text = try? String(contentsOf: store.graphicsFolder.appendingPathComponent(name, isDirectory: true).appendingPathComponent("credits.js"), encoding: .utf8),
              let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let given = try? JSONDecoder().decode(JSONValue.self, from: Data(text[a...b].utf8)) else { return nil }
        return given["text"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

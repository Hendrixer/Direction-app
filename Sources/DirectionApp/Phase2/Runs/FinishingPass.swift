import Foundation
import DirectionCore
import DirectionTools

/// Finishing, the part that comes out the same every time (finish.md › What Direction does itself). Before the
/// editor starts on a locked picture, Direction lays captions from the words, rolls the director's credits and
/// brings the whole mix to the loudness target, each an edit of its own, and says what it did in the checklist
/// the editor reads first. What's left for the editor needs an eye and an ear: color, the balance of the mix,
/// titles, and checking the captions and the framing.
@MainActor enum FinishingPass {
    static func run(store: ProjectStore, runID: String) async {
        guard let runtime = try? ToolRuntime(store: store) else { return }
        var items = (try? store.directingState().finishing) ?? FinishingItem.defaults
        func change(_ id: String, _ update: (inout FinishingItem) -> Void) { if let i = items.firstIndex(where: { $0.id == id }) { update(&items[i]) } }
        func step(_ verb: String, _ object: String, _ op: JSONValue) async -> JSONValue? {
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

        // Captions, unless the style keeps them off or the director already checked them.
        if style?.tokens["captions"]["on"].bool != false, items.first(where: { $0.id == "captions" })?.state != "done",
           let result = await step("Captioning", "the cut", .object(["op": .string("captions")])) {
            change("captions") { $0.state = "working"; $0.detail = "Direction laid captions from the words: \(said(result)?.replacingOccurrences(of: "Laid captions from the words in ", with: "") ?? "the whole cut"). Check the line breaks and the names." }
        }
        // The director's credits, rolled after the last shot.
        if let credits = state?.credits, !credits.isEmpty, let result = await step("Rolling the credits in", "the cut", .object(["op": .string("credits")])) {
            change("titles") { $0.detail = ($0.detail.isEmpty ? "" : $0.detail + " ") + "Direction \(said(result).map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "rolled the credits")." }
        }
        // Last, so it hears everything that's placed.
        if let result = await step("Setting the loudness of", "the mix", .object(["op": .string("loudness")])) {
            let held = (result["operations"].array?.first?["warnings"].array ?? result["warnings"].array ?? []).compactMap(\.string).first { $0.contains("peaks hold") }
            change("sound") { $0.detail = "Direction \(said(result).map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "set the mix to the target"). \(held ?? "Balance the tracks; run loudness again after changing the sound.")" }
        }
        _ = try? store.updateFinishing(items)
    }
}

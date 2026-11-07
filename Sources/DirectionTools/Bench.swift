import Foundation
import DirectionCore

/// The editor's work on a film, measured without a person (issue #6): a scorecard for one cut, and which measures
/// got worse since the last scorecard for the same film. Run against a set of real films before each release, so
/// the editor's cutting goes up measurably and never quietly drops (docs/bench.md).
///
/// What it measures: whether the cut holds to the brief (its length, the lines it must keep), whether the turnover's
/// notes were all answered, what Direction's own checks find (the sound against the target, the framing, and the
/// cuts: jump cuts and sound cut inside a word), how close it is to the director's own cut when there is one (cut points within
/// three frames, the same material), its pace, and what the run cost (time, tool calls, tokens, spend).
extension ToolRuntime {
    public func benchScore(cut wanted: String?, reference: String? = nil) async throws -> JSONValue {
        let cuts = try store.cuts()
        func find(_ name: String) throws -> ReviewCut {
            guard let c = cuts.first(where: { $0.id == name || $0.name.lowercased() == name.lowercased() }) else { throw DirectionError("bad_argument", "There's no cut \(name). Cuts: \(cuts.map(\.name).joined(separator: ", ")).") }
            return c
        }
        guard let cut = try wanted.map(find) ?? cuts.max(by: { $0.createdAt < $1.createdAt }) else { throw DirectionError("no_cut", "This film has no cut to score.") }
        let p = try store.read(revision: cut.editRevision), s = try p.sequence(cut.sequenceID), rate = s.frameRate.value
        func story(_ s: DirectionCore.Sequence) -> [Clip] { s.clips.filter { $0.kind == .video && $0.layer == s.storyLayer }.sorted { $0.start < $1.start } }
        func r(_ x: Double, _ places: Double = 100) -> JSONValue { .number((x * places).rounded() / places) }
        let shots = story(s), length = s.duration.seconds
        var measures: [String: JSONValue] = [:], value: [String: JSONValue] = ["film": .string(p.name), "cut": .string(cut.name), "editRevision": .number(Double(cut.editRevision)), "length": r(length)]

        // Pace: shot lengths, and the average in each quarter of the cut.
        let lengths = shots.map(\.duration.seconds).sorted()
        let quarters = (0..<4).map { q -> JSONValue in
            let a = length * Double(q) / 4, b = length * Double(q + 1) / 4
            let inside = shots.filter { $0.start.seconds >= a && $0.start.seconds < b }
            return inside.isEmpty ? .null : r(inside.map(\.duration.seconds).reduce(0, +) / Double(inside.count))
        }
        value["pace"] = .object(["shots": .number(Double(shots.count)), "averageShot": lengths.isEmpty ? .null : r(lengths.reduce(0, +) / Double(lengths.count)),
                                 "medianShot": lengths.isEmpty ? .null : r(lengths[lengths.count / 2]), "shortest": lengths.first.map { r($0) } ?? .null, "longest": lengths.last.map { r($0) } ?? .null,
                                 "averageShotByQuarter": .array(quarters)])

        // The brief: the length it asks for, and the lines it must keep, looked for in the words the cut plays.
        let brief = try store.brief()
        let off = max(0, (brief.lengthMin ?? 0) - length, length - (brief.lengthMax ?? .infinity))
        measures["lengthOffSeconds"] = r(off, 10)
        let transcripts = Dictionary(try store.transcripts().map { ($0.assetID, $0) }, uniquingKeysWith: { a, _ in a })
        func normalized(_ t: String) -> String { t.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) }.split(separator: " ").joined(separator: " ") }
        let heard = normalized(s.clips.filter { ($0.kind == .video && $0.layer == s.storyLayer) || ($0.kind == .audio && $0.layer == 0) }.sorted { $0.start < $1.start }.flatMap { c -> [String] in
            guard let t = c.assetID.flatMap({ transcripts[$0] }) else { return [] }
            return t.words.filter { $0.range.start >= c.sourceRange.start && $0.range.start < c.sourceRange.end }.map(\.text)
        }.joined(separator: " "))
        let keep = brief.mustKeep.map { ($0, !normalized($0).isEmpty && heard.contains(normalized($0))) }
        if !keep.isEmpty {
            value["mustKeep"] = .array(keep.map { .object(["item": .string($0.0), "inTheWords": .bool($0.1)]) })
            measures["mustKeepNotHeard"] = .number(Double(keep.filter { !$0.1 }.count))
        }

        // The turnover this cut answered: every note done, or why not.
        let turnover = try store.turnovers().first { $0.resultCutID == cut.id }
        if let t = turnover {
            let states = t.noteIDs.map { t.progress[$0] ?? .queued }
            value["notes"] = .object(["turnover": .number(Double(t.number)), "notes": .number(Double(t.noteIDs.count)), "done": .number(Double(states.filter { $0 == .done }.count)), "cant": .number(Double(states.filter { $0 == .cant }.count))])
            measures["notesNotDone"] = .number(Double(states.filter { $0 != .done }.count))
        }

        // Direction's own checks, on the cut as it was made.
        let check = try await invoke("direction_check", arguments: .object(["revision": .number(Double(cut.editRevision)), "checks": .array(["sound", "framing", "cuts"].map(JSONValue.string))])).value
        measures["soundOffTarget"] = .number(check["loudness"]["ready"].bool == false ? 1 : 0)
        measures["framingProblems"] = .number(Double(check["framing"].array?.count ?? 0))
        if let cuts = check["cuts"].array {
            measures["jumpCuts"] = .number(Double(cuts.filter { $0["kind"].string == "jumpCut" }.count))
            measures["cutsInsideWords"] = .number(Double(cuts.filter { $0["kind"].string == "midWord" }.count))
            // Past the check's list: counted, though not by kind.
            if let more = check["moreCutProblems"].double { measures["moreCutProblems"] = .number(more) }
        }
        value["check"] = check

        // The director's own cut: shared cut points within three frames, and how much of the cut is the same material.
        if let reference {
            let ref = try find(reference)
            let rs = try store.read(revision: ref.editRevision).sequence(ref.sequenceID)
            let theirs = story(rs)
            let mine = Set(shots.dropFirst().map(\.start.seconds)), points = Set(theirs.dropFirst().map(\.start.seconds))
            let near = 3 / rate
            let precision = mine.isEmpty ? 0 : Double(mine.filter { m in points.contains { abs($0 - m) <= near } }.count) / Double(mine.count)
            let recall = points.isEmpty ? 0 : Double(points.filter { t in mine.contains { abs($0 - t) <= near } }.count) / Double(points.count)
            let same = shots.reduce(0.0) { sum, c in
                sum + theirs.filter { $0.assetID == c.assetID }.reduce(0.0) { $0 + max(0, min($1.sourceRange.end.seconds, c.sourceRange.end.seconds) - max($1.sourceRange.start.seconds, c.sourceRange.start.seconds)) / c.speed }
            }
            let storyLength = shots.reduce(0) { $0 + $1.duration.seconds }
            measures["cutPointPrecision"] = r(precision); measures["cutPointRecall"] = r(recall)
            measures["sameMaterial"] = r(storyLength > 0 ? min(1, same / storyLength) : 0)
            value["reference"] = .object(["cut": .string(ref.name), "length": r(rs.duration.seconds), "shots": .number(Double(theirs.count))])
        }

        // What the run cost: the editor's runs for this turnover (or the assembly).
        let runs = try store.runs().filter { run in turnover.map { run.turnoverID == $0.id } ?? false || (turnover == nil && run.job == .assemble) }
        if !runs.isEmpty {
            let seconds = runs.compactMap { run in run.startedAt.flatMap { a in (run.endedAt ?? run.updatedAt) - a } }.reduce(0, +)
            let calls = try runs.reduce(0) { $0 + (try store.activity(runID: $1.id, limit: 100_000).count) }
            measures["runSeconds"] = r(seconds, 1); measures["toolCalls"] = .number(Double(calls))
            if let tokens = runs.compactMap(\.tokens).reduce(0, +) as Int?, tokens > 0 { measures["tokens"] = .number(Double(tokens)) }
            if let spend = runs.compactMap(\.spend).reduce(0, +) as Double?, spend > 0 { measures["spend"] = r(spend) }
            value["runs"] = .array(runs.map { .object(["job": .string($0.job.rawValue), "program": .string($0.program), "state": .string($0.state.rawValue), "invocations": .number(Double($0.invocations))]) })
        }
        value["measures"] = .object(measures)
        return .object(value)
    }
}

public enum Bench {
    /// Measures where more is better; everything else is better lower. Cost measures count as worse past a quarter more.
    static let higherIsBetter: Set<String> = ["cutPointPrecision", "cutPointRecall", "sameMaterial"]
    static let cost: Set<String> = ["runSeconds", "toolCalls", "tokens", "spend"]

    /// What got worse since `previous`, in plain words: "jumpCuts went from 1 to 3".
    public static func worse(than previous: JSONValue, _ now: JSONValue) -> [String] {
        guard case .object(let before) = previous["measures"], case .object(let after) = now["measures"] else { return [] }
        return after.keys.sorted().compactMap { key in
            guard let a = before[key]?.double, let b = after[key]?.double else { return nil }
            let worse = cost.contains(key) ? b > a * 1.25 + 1e-9 : higherIsBetter.contains(key) ? b < a - 1e-9 : b > a + 1e-9
            return worse ? "\(key) went from \(Interchange.number(a)) to \(Interchange.number(b))" : nil
        }
    }
}

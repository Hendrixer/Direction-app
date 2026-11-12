import Foundation
import DirectionCore

/// The editor's version and effort for each job at each stop of the film's speed and quality
/// (docs/speed-and-quality.md › The editor). From Artificial Analysis's index and time per task by effort,
/// the Vision Arena, and Anthropic's and OpenAI's own notes, read 8 Nov 2026. From Faster up, judgement (cutting,
/// notes, a style) stays on the strongest version and only its effort moves; the list-like jobs (a breakdown,
/// finishing) move to lighter versions. Fastest (11 Nov 2026) puts judgement on the second version too: Sonnet
/// 5.5 for Claude Code, and Sol for Codex, which is already Codex's at Faster (Astra costs about 4× Sol, so it
/// stays at Best). Nothing below medium on a job that looks at frames.
enum EditorPicks {
    struct Pick: Equatable { var version: String; var effort: String }

    static let readOn = "2026-11-08"

    private static let opus = "claude-opus-5-5", sonnet = "claude-sonnet-5-5", haiku = "claude-haiku-5-5"
    static let sol = "gpt-6.1-sol", terra = "gpt-6.1-terra", astra = "gpt-6-astra"

    private static func p(_ version: String, _ effort: String) -> Pick { .init(version: version, effort: effort) }

    /// Fastest, Faster, Balanced, Best.
    private static let claude: [EditorJob: [Pick]] = [
        .script: [p(sonnet, "medium"), p(sonnet, "medium"), p(opus, "medium"), p(opus, "high")],
        .breakdown: [p(haiku, "medium"), p(haiku, "medium"), p(sonnet, "medium"), p(opus, "medium")],
        .logFootage: [p(sonnet, "medium"), p(sonnet, "medium"), p(sonnet, "medium"), p(opus, "high")],
        .assemble: [p(sonnet, "medium"), p(opus, "medium"), p(opus, "high"), p(opus, "xhigh")],
        .turnover: [p(sonnet, "medium"), p(opus, "medium"), p(opus, "high"), p(opus, "xhigh")],
        .finish: [p(haiku, "medium"), p(haiku, "medium"), p(sonnet, "medium"), p(opus, "medium")],
        .style: [p(sonnet, "medium"), p(opus, "medium"), p(opus, "high"), p(opus, "xhigh")],
        .technique: [p(sonnet, "medium"), p(sonnet, "medium"), p(opus, "medium"), p(opus, "high")],
    ]
    private static let codex: [EditorJob: [Pick]] = [
        .script: [p(terra, "medium"), p(terra, "medium"), p(sol, "medium"), p(sol, "high")],
        .breakdown: [p(terra, "low"), p(terra, "low"), p(terra, "medium"), p(sol, "medium")],
        .logFootage: [p(terra, "medium"), p(terra, "medium"), p(terra, "medium"), p(sol, "high")],
        .assemble: [p(sol, "medium"), p(sol, "medium"), p(sol, "high"), p(astra, "high")],
        .turnover: [p(sol, "medium"), p(sol, "medium"), p(sol, "high"), p(astra, "high")],
        .finish: [p(terra, "low"), p(terra, "low"), p(terra, "medium"), p(sol, "medium")],
        .style: [p(sol, "medium"), p(sol, "medium"), p(sol, "high"), p(astra, "high")],
        .technique: [p(terra, "medium"), p(terra, "medium"), p(sol, "medium"), p(sol, "high")],
    ]

    /// What the table says, before checking what the installed program offers.
    static func listed(_ p: EditorProgram, _ job: EditorJob, _ q: FilmQuality) -> Pick {
        let row = (p == .claudeCode ? claude : codex)[job] ?? (p == .claudeCode ? claude : codex)[.turnover]!
        return row[FilmQuality.allCases.firstIndex(of: q) ?? 2]
    }

    /// The pick as the installed program can run it. A Codex that doesn't list the version falls back
    /// (Astra, then Sol, then Terra, then the program's own default); the effort is the nearest the
    /// version offers at or below the pick. `DIRECTION_EDITOR_VERSION` and `DIRECTION_EDITOR_EFFORT`
    /// replace both for every job, for testing and the bench.
    static func pick(_ p: EditorProgram, _ job: EditorJob, _ q: FilmQuality, environment: [String: String] = ProcessInfo.processInfo.environment, codexVersions: [String]? = nil) -> Pick {
        // An ACP agent runs on the version and effort set in the agent itself.
        if p.usesACP { return Pick(version: "", effort: "") }
        var pick = listed(p, job, q)
        if p == .codex {
            let offered = Set(codexVersions ?? p.versions.map(\.id))
            let next: [String: [String]] = [astra: [sol, terra], sol: [terra, astra], terra: [sol, astra]]
            pick.version = ([pick.version] + (next[pick.version] ?? [])).first(where: offered.contains) ?? ""
        }
        if let v = environment["DIRECTION_EDITOR_VERSION"], !v.isEmpty { pick.version = v }
        let effort = environment["DIRECTION_EDITOR_EFFORT"].flatMap { $0.isEmpty ? nil : $0 } ?? pick.effort
        pick.effort = EditorSetup.fitted(effort, p.efforts(pick.version).map(\.id))
        return pick
    }
}

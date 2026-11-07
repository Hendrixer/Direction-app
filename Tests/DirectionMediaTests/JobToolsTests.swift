import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

/// Each job lists the tools it uses; direction_more_tools has the rest, so no job is short of one.
struct JobToolsTests {
    @Test func everyJobsToolsExistAndTheRestAreOneCallAway() throws {
        let all = Set(ToolCatalog.definitions.map(\.name))
        #expect(ToolCatalog.listed(for: nil).count == all.count && !ToolCatalog.listed(for: nil).contains { $0.name == ToolCatalog.moreToolsName })
        for job in EditorJob.allCases {
            let own = ToolCatalog.names(for: job)
            #expect(own.isSubset(of: all), "\(job): \(own.subtracting(all).sorted())")
            let listed = ToolCatalog.listed(for: job).map(\.name)
            #expect(listed.last == ToolCatalog.moreToolsName && Set(listed.dropLast()) == own && listed.count < all.count, "\(job)")
            guard case .answer(let rest) = try ToolCatalog.moreTools(.object([:]), job: job) else { Issue.record("\(job): the list should answer at once"); continue }
            let names = Set(rest["tools"].array?.compactMap { $0["name"].string } ?? [])
            #expect(names.union(own) == all && names.isDisjoint(with: own), "\(job)")
            #expect(rest["tools"].array?.allSatisfy { ($0["does"].string ?? "").count <= 200 } == true)
        }
        // What the editors used in the runs so far is on their lists.
        #expect(ToolCatalog.names(for: .script).isSuperset(of: ["direction_script", "direction_script_update", "direction_turnovers", "direction_questions", "direction_style", "direction_brief"]))
        #expect(ToolCatalog.names(for: .finish).isSuperset(of: ["direction_measure_audio", "direction_frame", "direction_edit", "direction_finishing", "direction_graphic", "direction_watch", "direction_looks", "direction_library"]))
        #expect(ToolCatalog.names(for: .turnover).isSuperset(of: ["direction_import", "direction_cancel_job", "direction_feedback_reply", "direction_cuts", "direction_restore", "direction_preview"]))
        // Cutting jobs choose cut points and check their cuts.
        for job in [EditorJob.assemble, .turnover] { #expect(ToolCatalog.names(for: job).isSuperset(of: ["direction_cut_points", "direction_check"]), "\(job)") }
    }

    @Test func moreToolsDescribesAndRunsOneThisJobWasntGiven() throws {
        guard case .answer(let looks) = try ToolCatalog.moreTools(.object(["name": .string("direction_looks")]), job: .script) else { Issue.record("expected the description"); return }
        #expect(looks["description"].string?.hasPrefix("Read the looks.") == true && looks["arguments"]["type"].string == "object" && looks["note"] == .null)
        guard case .answer(let own) = try ToolCatalog.moreTools(.object(["name": .string("direction_script")]), job: .script) else { Issue.record("expected the description"); return }
        #expect(own["note"].string == "You already have direction_script: call it directly.")
        guard case .run(let name, let arguments) = try ToolCatalog.moreTools(.object(["name": .string("direction_looks"), "arguments": .object([:])]), job: .script) else { Issue.record("expected a run"); return }
        #expect(name == "direction_looks" && arguments == .object([:]))
        do { _ = try ToolCatalog.moreTools(.object(["name": .string("direction_nope")]), job: .script); Issue.record("an unknown tool should be refused") }
        catch let e as DirectionError { #expect(e.code == "unknown_tool") }
        do { _ = try ToolCatalog.moreTools(.object(["tool": .string("direction_looks")]), job: .script); Issue.record("a wrong field should be refused") }
        catch let e as DirectionError { #expect(e.code == "invalid_arguments" && e.message.contains("unknown field tool")) }
    }

    /// A job's list is a fraction of every tool's words, so the program loads them up front instead of searching.
    @Test func aJobsListIsMuchSmallerThanEveryTool() throws {
        func size(_ d: [ToolDefinition]) throws -> Int { try d.reduce(0) { try $0 + $1.description.count + JSONEncoder().encode($1.inputSchema).count } }
        let all = try size(ToolCatalog.definitions)
        for job in EditorJob.allCases where job != .turnover { #expect(try size(ToolCatalog.listed(for: job)) * 10 < all * 7, "\(job)") }
        #expect(try size(ToolCatalog.listed(for: .script)) * 5 < all)
    }
}

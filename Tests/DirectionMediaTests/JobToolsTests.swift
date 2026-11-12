import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

/// An editor Direction starts has one tool, direction_run; its instructions carry the job's tools in full, and
/// direction.help() in a script has the rest, so no job is short of one.
struct JobToolsTests {
    @Test func aJobListsOnlyTheScriptToolAndItsInstructionsCarryTheRest() throws {
        let all = Set(ToolCatalog.definitions.map(\.name))
        #expect(ToolCatalog.listed(for: nil).count == all.count)
        for job in EditorJob.allCases {
            let own = ToolCatalog.names(for: job)
            #expect(own.isSubset(of: all) && !own.contains(ToolCatalog.runName), "\(job): \(own.subtracting(all).sorted())")
            #expect(ToolCatalog.listed(for: job).map(\.name) == [ToolCatalog.runName], "\(job)")
            // Every tool of the job, in full, as a script calls it.
            let reference = ToolCatalog.reference(for: job)
            for name in own {
                let d = try #require(ToolCatalog.definitions.first { $0.name == name })
                #expect(reference.contains("### direction.\(ToolCatalog.scriptName(name))(") && reference.contains(ToolCatalog.scriptNames(d.description)), "\(job): \(name)")
                // Every other tool is named as a script calls it.
                #expect(!reference.contains("direction_\(ToolCatalog.scriptName(name))"), "\(job): \(name)")
            }
            // help() lists the rest, a line each.
            let rest = try ToolCatalog.help(.object([:]), job: job)
            let names = Set(rest["tools"].array?.compactMap { $0["name"].string }.map { "direction_" + $0 } ?? [])
            #expect(names.union(own).union([ToolCatalog.runName]) == all && names.isDisjoint(with: own), "\(job)")
            #expect(rest["tools"].array?.allSatisfy { ($0["does"].string ?? "").count <= 200 } == true)
        }
        // What the editors used in the runs so far is theirs.
        #expect(ToolCatalog.names(for: .script).isSuperset(of: ["direction_script", "direction_script_update", "direction_turnovers", "direction_questions", "direction_style", "direction_brief"]))
        #expect(ToolCatalog.names(for: .finish).isSuperset(of: ["direction_measure_audio", "direction_frame", "direction_edit", "direction_finishing", "direction_graphic", "direction_watch", "direction_looks", "direction_library", "direction_copy"]))
        #expect(ToolCatalog.names(for: .turnover).isSuperset(of: ["direction_import", "direction_cancel_job", "direction_feedback_reply", "direction_cuts", "direction_restore", "direction_preview"]))
        for job in [EditorJob.assemble, .turnover] { #expect(ToolCatalog.names(for: job).isSuperset(of: ["direction_cut_points", "direction_check"]), "\(job)") }
    }

    /// What the editor reads names tools as its scripts call them, so it never tries one as a tool of its own.
    @Test func toolsAreNamedAsAScriptCallsThem() {
        #expect(ToolCatalog.scriptNames("Call `direction_watch`, then direction_edit_catalog; direction_run stays, as do mcp__direction__direction_watch and my_direction_x.")
                == "Call `direction.watch`, then direction.edit_catalog; direction_run stays, as do mcp__direction__direction_watch and my_direction_x.")
    }

    @Test func helpGivesAnyToolInFull() throws {
        let looks = try ToolCatalog.help(.string("looks"), job: .script)
        #expect(looks.array?.first?["call"].string?.hasPrefix("direction.looks(") == true && looks.array?.first?["description"].string?.hasPrefix("Read the looks.") == true)
        #expect(try ToolCatalog.help(.array([.string("direction_edit"), .string("frame")]), job: nil).array?.count == 2)
        for bad in ["nope", "run"] {
            do { _ = try ToolCatalog.help(.string(bad), job: .script); Issue.record("\(bad) should be refused") }
            catch let e as DirectionError { #expect(e.code == "unknown_tool") }
        }
        // In your own session every tool is listed directly; help lists them all.
        #expect(try ToolCatalog.help(.object([:]), job: nil)["tools"].array?.count == ToolCatalog.definitions.count - 1)
    }

    /// Arguments read as TypeScript: shorter than JSON Schema, with a field's words beside it.
    @Test func argumentsReadAsTypes() throws {
        let measure = try #require(ToolCatalog.definitions.first { $0.name == "direction_measure_audio" })
        let call = ToolCatalog.call(measure)
        #expect(call.hasPrefix("direction.measure_audio({") && call.contains("ranges?: {end?: number, start?: number}[]") && call.contains("assetID?: string"))
        let s = JSONValue.object(["type": .string("object"), "required": .array([.string("to")]), "properties": .object([
            "to": .object(["type": .string("string"), "description": .string("Where it goes.")]),
            "kind": .object(["type": .string("string"), "enum": .array([.string("a"), .string("b")])]),
            "at": .object(["anyOf": .array([.object(["type": .string("number")]), .object(["type": .string("string")])])]),
            "ids": .object(["type": .string("array"), "items": .object(["anyOf": .array([.object(["type": .string("integer")]), .object(["type": .string("boolean")])])])]),
            "by": .object(["type": .string("object"), "additionalProperties": .object(["type": .string("number")])]),
        ])])
        #expect(ToolCatalog.typeScript(.object(["type": .array([.string("string"), .string("integer")])]), depth: 0) == "string | integer")
        #expect(ToolCatalog.typeScript(.object(["enum": .array([.number(1), .number(2.5)])]), depth: 0) == "1 | 2.5")
        let brief = try #require(ToolCatalog.definitions.first { $0.name == "direction_brief" })
        #expect(ToolCatalog.call(brief, film: true) == "direction.brief({})")
        #expect(ToolCatalog.typeScript(s, depth: 0) == "{\n  to: string,  // Where it goes.\n  at?: number | string,\n  by?: {[key: string]: number},\n  ids?: (integer | boolean)[],\n  kind?: \"a\" | \"b\",\n}")
    }

    /// What the instructions say a tool answers with is what it answers with: a script reads a field the first time.
    @Test func returnsAreWhatTheToolsAnswer() async throws {
        let all = Set(ToolCatalog.definitions.map(\.name))
        #expect(Set(ToolCatalog.returns.keys).isSubset(of: all))
        let reference = ToolCatalog.reference(for: .turnover)
        #expect(reference.contains("Returns {cut, editRevision, sequenceID, outline") && reference.contains("for setEffect and removeEffect") && reference.contains("every filmstrip comes back"))
        #expect(try ToolCatalog.help(.string("watch"), job: .turnover).array?.first?["returns"].string?.contains("imagePaths") == true)
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        func answer(_ name: String, _ arguments: [String: JSONValue] = [:]) async throws -> JSONValue { try await f.runtime.invoke(name, arguments: .object(arguments)).value }
        func has(_ v: JSONValue, _ keys: String...) -> Bool { keys.allSatisfy { v[$0] != .null } }
        let p = try f.store.read(), clip = try #require(p.sequences[0].clips.first { $0.kind != .audio })
        _ = try await answer("direction_edit", ["baseEditRevision": .number(Double(p.editRevision)), "operations": .array([.object(["op": .string("addEffect"), "clipID": .string(clip.id), "effect": .string("blur"), "params": .object(["radius": .number(4)])])])])
        let timeline = try await answer("direction_timeline")
        #expect(has(timeline, "cut", "editRevision", "sequenceID", "outline", "locks") && timeline["effects"].array?.first?["clipID"].string == clip.id && timeline["effects"].array?.first?["effectID"].string != nil && timeline["effects"].array?.first?["name"].string == "blur")
        let revision = try f.store.revision()
        let trial = try await answer("direction_edit", ["baseEditRevision": .number(Double(revision)), "validateOnly": .bool(true), "operations": .array([.object(["op": .string("trim"), "clipID": .string(clip.id), "edge": .string("tail"), "frames": .number(-3)])])])
        let step = trial["operations"].array?.first ?? .null, after = try f.store.revision()
        #expect(trial["committed"] == .bool(false) && has(trial, "editRevision", "oldLength", "newLength", "delta", "operations", "warnings") && has(step, "index", "op", "summary", "deltaText") && after == revision)
        let transcript = try await answer("direction_transcript"), watch = try await answer("direction_watch", ["start": .number(0), "end": .number(2)])
        #expect(has(transcript, "editRevision", "words", "total") && has(watch, "range", "start", "end", "revision", "watched", "words", "cells", "cuts"))
        let check = try await answer("direction_check", ["checks": .array([.string("cuts")])]), points = try await answer("direction_cut_points", ["range": .object(["start": .number(0), "end": .number(2)])])
        #expect(has(check, "editRevision", "cuts") && has(points, "points", "says"))
        let measured = try await answer("direction_measure_audio", ["ranges": .array([.object(["start": .number(0), "end": .number(2)])])]), frame = try await answer("direction_frame", ["times": .array([.number(0.5)])])
        #expect(has(measured, "editRevision", "ranges") && has(frame, "editRevision", "frames"))
        let brief = try await answer("direction_brief"), dailies = try await answer("direction_dailies"), questions = try await answer("direction_questions"), turnovers = try await answer("direction_turnovers")
        #expect(has(brief, "brief", "latitude", "preferences", "pictureLocked") && has(dailies, "assets", "dailies") && has(questions, "questions") && has(turnovers, "brief", "turnovers"))
    }

    /// Waiting on a job is one call.
    @Test func aJobIsWaitedForInOneCall() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let started = try await f.runtime.invoke("direction_export", arguments: .object(["path": .string(f.directory.appendingPathComponent("out.mov").path)])).value
        let id = try #require(started["id"].string)
        let done = try await f.runtime.invoke("direction_job", arguments: .object(["jobID": .string(id), "wait": .number(60)])).value
        #expect(done["status"].string == "completed", "\(done)")
    }

    /// The instructions carry each job's tools in full: bigger than a list of names, but read once and kept (a
    /// host caches them), where the tools as a list would have been searched for and cut short.
    @Test func eachJobsReferenceIsAReasonableSize() throws {
        for job in EditorJob.allCases {
            let size = ToolCatalog.reference(for: job).count
            #expect(size < 70_000, "\(job): \(size)")
        }
        #expect(ToolCatalog.reference(for: .script).count < 15_000)
    }
}

import Foundation
import Testing
import DirectionCore
@testable import DirectionApp

extension JSONValue {
    /// An array's item, or null.
    subscript(_ i: Int) -> JSONValue { array.flatMap { i >= 0 && i < $0.count ? $0[i] : nil } ?? .null }
}

/// The Agent Client Protocol side of the editor (EditorACP.swift): one invocation's conversation, played line by
/// line, without a program.
@Suite("Editor over ACP")
struct EditorACPTests {
    private let folder = URL(fileURLWithPath: "/films/One.direction/Editor")

    private func conversation(resume: String? = nil, scripts: Bool = true) -> ACPConversation {
        ACPConversation(cwd: folder, server: .init(command: "/A/direction", args: ["mcp", "--project", "/films/One.direction"], env: ["DIRECTION_RUN_ID": "run-1"]),
                        prompt: resume == nil ? "Role\n\n---\n\nLog the takes." : "Continue where you stopped.", wholeJob: "Role\n\n---\n\nLog the takes.\nContinue where you stopped.",
                        resume: resume, permissions: .init(folder: folder, scripts: scripts))
    }
    private func line(_ v: JSONValue) -> String { String(decoding: ACPConversation.line(v).dropLast(), as: UTF8.self) }
    private func json(_ s: String) -> JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null }

    @Test func helloSessionPromptAndTheAnswer() {
        var c = conversation()
        let hello = c.start()
        #expect(hello.count == 1 && hello[0]["method"].string == "initialize" && hello[0]["params"]["protocolVersion"].int == 1)
        // Direction offers no files or terminal: the agent works through its tools.
        #expect(hello[0]["params"]["clientCapabilities"]["terminal"].bool == false)
        var step = c.receive(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true}}}"#)
        #expect(step.send.first?["method"].string == "session/new")
        let server = step.send[0]["params"]["mcpServers"][0]
        #expect(server == json(#"{"name":"direction","command":"/A/direction","args":["mcp","--project","/films/One.direction"],"env":[{"name":"DIRECTION_RUN_ID","value":"run-1"}]}"#))
        #expect(step.send[0]["params"]["cwd"].string == folder.path)
        step = c.receive(#"{"jsonrpc":"2.0","id":2,"result":{"sessionId":"ses-1"}}"#)
        #expect(step.events == [.session("ses-1")])
        #expect(step.send.first?["method"].string == "session/prompt" && step.send[0]["params"]["prompt"][0]["text"].string == "Role\n\n---\n\nLog the takes.")
        // Direction's tool, as Claude Code names it; started once its input is known.
        #expect(c.receive(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"ses-1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"direction_direction_log_dailies","kind":"other","status":"pending"}}}"#).events.isEmpty)
        step = c.receive(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"ses-1","update":{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"in_progress","rawInput":{"takes":{}}}}}"#)
        #expect(step.events == [.toolStarted(id: "t1", name: "mcp__direction__direction_log_dailies", input: json(#"{"takes":{}}"#))])
        step = c.receive(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"ses-1","update":{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"failed","content":[{"type":"content","content":{"type":"text","text":"No such take."}}]}}}"#)
        #expect(step.events == [.toolFinished(id: "t1", isError: true, text: "No such take.")])
        #expect(c.receive(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"ses-1","update":{"sessionUpdate":"usage_update","used":10,"size":100,"cost":{"amount":0.31,"currency":"USD"}}}}"#).events == [.cost(0.31)])
        _ = c.receive(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"ses-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"{\"finished\": true, "}}}}"#)
        _ = c.receive(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"ses-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"\"summary\": \"Logged.\", \"needsYou\": []}"}}}}"#)
        step = c.receive(#"{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}"#)
        #expect(step.done && c.done)
        guard case .result(let text, false) = step.events.first else { Issue.record("No result: \(step.events)"); return }
        #expect(EditorResult.parse(text) == EditorResult(finished: true, summary: "Logged.", needsYou: []), "text: \(text)")
        #expect(c.cancel()?["method"].string == "session/cancel")
    }

    /// A saved session is loaded, its replay ignored, and only the continuation said. One that won't load is
    /// replaced by a new session that hears the whole job again.
    @Test func aSavedSessionLoadsOrTheWholeJobIsSaidAgain() {
        var c = conversation(resume: "ses-1")
        _ = c.start()
        var step = c.receive(#"{"jsonrpc":"2.0","id":1,"result":{"agentCapabilities":{"loadSession":true}}}"#)
        #expect(step.send.first?["method"].string == "session/load" && step.send[0]["params"]["sessionId"].string == "ses-1")
        #expect(c.receive(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"ses-1","update":{"sessionUpdate":"tool_call","toolCallId":"old","title":"Read","kind":"read","status":"completed","rawInput":{}}}}"#).events.isEmpty)
        step = c.receive(#"{"jsonrpc":"2.0","id":2,"result":{}}"#)
        #expect(step.events == [.session("ses-1")] && step.send.first?["params"]["prompt"][0]["text"].string == "Continue where you stopped.")

        var failing = conversation(resume: "ses-1")
        _ = failing.start()
        _ = failing.receive(#"{"jsonrpc":"2.0","id":1,"result":{"agentCapabilities":{"loadSession":true}}}"#)
        step = failing.receive(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32002,"message":"Session not found"}}"#)
        #expect(step.send.first?["method"].string == "session/new" && !step.done)
        step = failing.receive(#"{"jsonrpc":"2.0","id":3,"result":{"sessionId":"ses-2"}}"#)
        #expect(step.events == [.session("ses-2")] && step.send.first?["params"]["prompt"][0]["text"].string == "Role\n\n---\n\nLog the takes.\nContinue where you stopped.")

        var cannot = conversation(resume: "ses-1")
        _ = cannot.start()
        #expect(cannot.receive(#"{"jsonrpc":"2.0","id":1,"result":{"agentCapabilities":{}}}"#).send.first?["method"].string == "session/new")
    }

    @Test func notSignedInEndsTheInvocation() {
        var c = conversation()
        _ = c.start()
        _ = c.receive(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
        let step = c.receive(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"Authentication required"}}"#)
        #expect(step.done)
        guard case .failure(let text) = step.events.first else { Issue.record("No failure"); return }
        #expect(EditorFailure.reason(text) == .notSignedIn)
    }

    /// The same rules as Claude Code's allowed tools: Direction's tools, reading, changes inside its folder;
    /// commands only with scripts on; never the web. Anything else Direction doesn't offer is refused.
    @Test func permissionFollowsClaudeCodesRules() {
        var c = conversation(scripts: false)
        func answer(_ kind: String, _ title: String, paths: [String] = []) -> String? {
            let locations = paths.map { #"{"path":"\#($0)"}"# }.joined(separator: ",")
            let req = #"{"jsonrpc":"2.0","id":"r1","method":"session/request_permission","params":{"sessionId":"s","toolCall":{"toolCallId":"x\#(kind)\#(title.count)","title":"\#(title)","kind":"\#(kind)","locations":[\#(locations)]},"options":[{"optionId":"ok","name":"Allow","kind":"allow_once"},{"optionId":"no","name":"Reject","kind":"reject_once"}]}}"#
            let reply = c.receive(req).send.first
            #expect(reply?["id"].string == "r1")
            return reply?["result"]["outcome"]["optionId"].string
        }
        #expect(answer("other", "direction_watch (direction MCP Server)") == "ok")
        #expect(answer("read", "Read /etc/passwd") == "ok")
        #expect(answer("edit", "Edit NOTES.md", paths: ["\(folder.path)/NOTES.md"]) == "ok")
        #expect(answer("edit", "Edit relative", paths: ["graphics/title.js"]) == "ok")
        #expect(answer("edit", "Edit outside", paths: ["/films/One.direction/project.sqlite"]) == "no")
        #expect(answer("edit", "Sneaky", paths: ["\(folder.path)/../project.sqlite"]) == "no")
        #expect(answer("execute", "ffmpeg -version") == "no")
        #expect(answer("fetch", "Fetch a page") == "no")
        var scripted = conversation(scripts: true)
        let run = scripted.receive(#"{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{"sessionId":"s","toolCall":{"toolCallId":"y","title":"node draw.js","kind":"execute"},"options":[{"optionId":"always","name":"Always","kind":"allow_always"}]}}"#).send.first
        #expect(run?["result"]["outcome"]["optionId"].string == "always")
        let terminal = scripted.receive(#"{"jsonrpc":"2.0","id":8,"method":"terminal/create","params":{}}"#).send.first
        #expect(terminal?["error"]["code"].int == -32601)
    }

    @Test func toolNamesAreClaudeCodes() {
        func name(_ s: String) -> String { ACPConversation.name(json(s)) }
        #expect(name(#"{"title":"direction_direction_watch"}"#) == "mcp__direction__direction_watch")
        #expect(name(#"{"title":"direction__direction_edit"}"#) == "mcp__direction__direction_edit")
        #expect(name(#"{"title":"direction_frame (direction MCP Server)","kind":"other"}"#) == "mcp__direction__direction_frame")
        #expect(name(#"{"title":"Reading NOTES.md","kind":"read"}"#) == "Read")
        #expect(name(#"{"title":"npm test","kind":"execute"}"#) == "Bash")
        #expect(ACPConversation.input(json(#"{"kind":"read","locations":[{"path":"/f/NOTES.md"}]}"#))["path"].string == "/f/NOTES.md")
    }

    /// Each agent's own `--help` says how it speaks ACP; one that lists none is too old for Direction.
    @Test func theACPFormComesFromTheProgramsHelp() {
        #expect(EditorDiscovery.acpForm(.opencode, help: "Commands:\n  opencode run [message..]\n  opencode serve    Start a headless server\n") == nil)
        #expect(EditorDiscovery.acpForm(.opencode, help: "Commands:\n  opencode acp                 Start ACP (Agent Client Protocol) server\n") == ["acp"])
        #expect(EditorDiscovery.acpForm(.goose, help: "Commands:\n  acp  Start ACP server\n  run  Run goose") == ["acp"])
        #expect(EditorDiscovery.acpForm(.gemini, help: "Options:\n  --experimental-acp  Starts the agent in ACP mode") == ["--experimental-acp"])
        #expect(EditorDiscovery.acpForm(.gemini, help: "Options:\n  --acp  Starts in ACP mode\n  --experimental-acp  Deprecated") == ["--acp"])
        #expect(EditorDiscovery.acpForm(.cline, help: "  --acp-port <n>") == nil)
        #expect(EditorDiscovery.acpForm(.cline, help: "  --acp, -a  Run as an ACP agent") == ["--acp"])
    }

    /// Only agents found on this Mac are offered, with the one chosen kept even when it's gone, and your own session.
    @Test func onlyInstalledAgentsAreOffered() {
        #expect(EditorWhoEditsGroup.choices(.claudeCode, installed: [.claudeCode, .opencode]) == [.claudeCode, .opencode, .yourOwn])
        #expect(EditorWhoEditsGroup.choices(.gemini, installed: [.codex]) == [.codex, .gemini, .yourOwn])
        #expect(EditorWhoEditsGroup.choices(.yourOwn, installed: []) == [.yourOwn])
        #expect(EditorPicks.pick(.opencode, .assemble, .best) == .init(version: "", effort: ""))
        #expect(EditorProgram.opencode.efforts("").map(\.id) == [""])
        #expect(EditorRunsOn(.goose) == .goose && EditorProgram.cursor.commands == ["cursor-agent", "agent"])
    }
}

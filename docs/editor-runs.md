# Editor runs

How Direction starts the editor (Claude Code, Codex or Gemini CLI, whichever are installed on the Mac), follows it, and shows it working. The product spec is `design/spec/specs/editor.md` (frames 41, 43, 56–58); this page is for whoever changes the code.

## Where things live

| Piece | File |
|---|---|
| Run and Activity records, their tables and store API | `Sources/DirectionCore/Phase2/Runs/RunsStore.swift` |
| Tool call → Activity (every tool, by name) | `Sources/DirectionTools/Phase2/EditorActivityMapping.swift`, called from `noteToolCall` in `RunsTools.swift` |
| Programs, versions and **every command-line flag** | `Sources/DirectionApp/Phase2/Runs/EditorPrograms.swift` |
| Version and effort for each job at the film's speed and quality | `EditorPicks.swift` (docs/speed-and-quality.md) |
| Settings › Engines › Who edits values | `EditorSetup.swift` (keys `editorRunsOn`, `filmQuality` (what a new film starts with), `editorStartWork`, `editorSignedIn.<program>`) |
| Stream parsing, failure reasons, the run state machine | `EditorStream.swift` |
| Processes, queue, pause/resume/stop, quit, recovery | `EditorRunner.swift` (app-wide singleton) |
| Job text | `Resources/Editor/jobs/*.md`, filled by `EditorJobs.swift` |
| Per-film state, finding work, the actions the UI calls | `EditorRunsModel.swift` (`film.runs`) |
| UI | `EditorActivityPopover.swift` (57), `EditorSetupSheet.swift` (56), `EditorStopped.swift` (58 notice, banners), `EditorWhoEditsGroup.swift` (43), `EditorPlayhead.swift` (the editor playhead on scene strips) |
| Frames | `RunsFixtures.swift`: `43-settings-editor`, `56-editor-setup`, `57-editor-working`, `58-editor-stopped` |

## Activity

Every tool call runs `ToolRuntime.noteToolCall` first, in whatever process handles it. In the `direction` CLI (the MCP server the editor talks to) that records an Activity row in the film's store; in the app it's switched off (`EditorActivityLog.isEnabled = false`) because the app's own calls are the director's. So a session you run yourself shows activity exactly like one Direction started.

- The row's `runID` comes from `DIRECTION_RUN_ID`, which Direction sets in the MCP config it writes for each run. Your own session has none.
- `EditorActivityLog.activity(for:_:context:)` is the table from editor.md. New tools map by name there; unknown `direction_*` tools read as "Reading the <name>". Housekeeping (`direction_editor_status`, `direction_job(s)`, `direction_events`…) records nothing.
- `direction_edit` accepts both today's `{batch: {operations: [{type…}]}}` and the edit functions' `{operations: [{op…}], notes}`. The verb is the first operation's (`editVerbs`), the object the scenes touched, the detail a delta and the note.
- `recordActivity` merges consecutive rows with the same run, verb and object, and emits an `editor.activity` event so the app refreshes.
- Calls Direction's tools don't see (Claude's Read/Write, Codex's commands and file changes) are recorded by the runner from the stream.

## Runs

A run is one job for one film: `logFootage`, `assemble`, `turnover`, `finish`. Answering a question or approving a read-back **continues the same run** on the program's saved session; it isn't a new job.

```
queued ─(capacity, not held)─▶ starting ─(first tool call)─▶ working ─┬─▶ done
  ▲ held: Start work = Ask me first                                   ├─▶ waitingForYou ─(answer / OK)─▶ starting
  │                                                                   ├─▶ paused ─(Resume)─▶ starting
  └──────────── Try again / not installed ◀── failed(reason) ◀────────┤
                                                                      └─▶ stopped (by you)
```

- `RunStateMachine.outcome` decides what an exit means. Direction's own intent wins (pause, quit, stop), then the store: the job's finishing work is done (`EditorRunner.finished`), a service hit the monthly cap, the program's words say not signed in or offline, the program stopped to wait for you (`waitingForYou`), a non-zero exit (program quit, with stderr's last line), else "The editor stopped before finishing."
- Finished means the store says so, not the program: every take logged; the turnover delivered; every editor finishing item done or needsYou. (`direction_log_dailies` doesn't accept `final: true` yet, so logging is finished when every take is logged.)
- A failed run on a turnover sets the turnover to `failed` and its working note to `stopped`, so the Notes cutting panel shows frame 58. Starting again puts it back.
- Stop discards the unfinished cut (restores the turnover's base revision) and returns the turnover to waiting; Start makes a new run. Take the turnover back does the same and cancels the turnover.
- One run per film works at a time; two films at once (`maxConcurrent`); the rest queue. Offline retries every 30 s.
- Quit: `QuitGuard` asks, then `pauseAllForQuit` SIGINTs every program and marks its run paused by quit; the next launch's `recover` pauses anything a previous Direction left working, and the banner offers Resume.

## Command lines

All flags are in `EditorPrograms.swift`. `EditorJobTests.flagsStillExistInTheInstalledPrograms` runs `claude --help`, `codex exec --help` and `codex exec resume --help` when the programs are installed and fails if a flag disappears; `commandLinesUseOnlyTheCheckedFlags` fails if a command line uses a flag that isn't in the checked list.

- Claude Code: `claude --print <job> --output-format stream-json --verbose --model <v> --mcp-config Editor/.mcp.json --strict-mcp-config --tools Read,Glob,Grep,Edit,Write --allowedTools mcp__direction,Read,Glob,Grep,Edit(./**),Write(./**) --append-system-prompt <role> --permission-mode dontAsk [--resume <session>]`. `--tools` offers only the file tools: no shell, no web.
- Codex: `codex exec --json --skip-git-repo-check [--model <v>] --config mcp_servers.direction.… --output-schema Editor/.direction/result.schema.json --config mcp_servers.direction.tool_timeout_sec=3600 --cd Editor --sandbox workspace-write "<role>\n\n---\n\n<job>"`; continue with `codex exec resume … <session> <prompt>`. The role leads the first message: Codex has no system prompt to add to (before 2026-11-11 Codex never got the role).
- Gemini CLI, over ACP: `gemini --acp` (or `--experimental-acp`, whichever its `--help` lists), stdin and stdout piped. `ACPConversation` (EditorACP.swift) is pure: `start()` gives the hello, `receive(line)` gives the events and the lines to write, and the runner writes them. `initialize` → `session/new` (or `session/load` on the saved session) with Direction's MCP server → one `session/prompt` with the role leading it → the prompt's answer ends it. Permission requests follow Claude Code's allowed tools (Direction's tools, reads, edits inside the folder, never commands or the web). The sign-in check is the hello and a session, no prompt.
- The working folder is `<film>.direction/Editor/` (Graphics, Looks, Effects, NOTES.md). Every skill is copied to `Editor/.claude/skills/<skill>/SKILL.md`, and the job names its own from the app bundle's `Resources/Skills` (`scripts/build-app.sh`) or, in development, the checkout's `plugins/direction/skills`.
- The `direction` helper is `Direction.app/Contents/Helpers/direction`, else the `direction` next to the app's executable (`.build/<config>/direction`), else `~/.local/bin/direction`.

## Job text

Templates are versioned files (`<!-- direction-job <name> vN -->` on the first line) with `{{placeholders}}`: film, brief, latitude, preferences, ids, notes, the skill and its path. `editor-role.md` is the appended system prompt, including the final-message shape `{"finished", "summary", "needsYou"}`. `EditorJobTests.everyTemplateShipsAndFillsCompletely` fails on a missing template or a placeholder left unfilled.

## Tests

`Tests/DirectionAppTests/EditorRunsTests.swift`: Claude and Codex streams from canned samples, the activity table, the state machine, templates, command lines, and the runner end to end against `Tests/FakeEditor/fake-claude` (scenarios `done`, `unfinished`, `auth`, `slow`, `crash`, chosen by `Editor/.fake-scenario`) and `Tests/FakeEditor/fake-acp`, a stand-in ACP agent (`done`, `unfinished`, `auth`, `slow`, `refusal`) that records the prompt, the MCP servers and every permission answer. `EditorACPTests.swift` plays conversations line by line. With `DIRECTION_LIVE_ACP=1`, every ACP agent installed on this Mac answers the sign-in check (free: no prompt). Tests use `EditorPrograms.shared.setPreview` so nothing touches the defaults, and `EditorRunner.shared.programOverride` / `helperOverride` so no real program runs.

## Fewer steps

Every step an agent takes resends everything said so far, so on an API key a run's cost follows its number of steps more than anything else ("Coded love", 1 Nov 2026: five runs on Opus 5.5, $71 at API prices, $47 of it one round of notes with about 130 steps). The tools answer in fewer, fuller calls:

- A `direction_edit` batch that changes the sound (`gain`, `fade`, `duck`, `audio`, `placeMusic`, `parts`, `loudness`, `syncSound`) with `measure: true` answers with `mix`: the whole mix as it now measures (integrated loudness, true peak, the target's verdict, the loudest stretches, anything over the ceiling). That film had 20 sound edits each followed by a measure. It's asked for rather than always on: measuring a long cut takes seconds, and made the music tests four times slower when every sound edit measured.
- `direction_measure_audio` takes `ranges` (up to 20 stretches in one answer), and its whole-cut answer has the profile (loudness every second, the loudest stretches, the peaks), so the editor never measures window by window.
- `direction_frame` takes `times` (up to 8 frames, each its own image, 640 by default). That film had 23 single frames in a row.
- `direction_run` is an editor's only tool, so every step is a script and any loop is one step: the editor writes a short JavaScript whose functions are Direction's tools, and only what it returns comes back (specs/editor.md › Tools and › Scripts). `ToolCatalog.listed(for:)` lists it alone for a job; `ToolCatalog.reference(for:)` writes the job's tools in full for the role (`EditorJobs.role(for:)`), each as its call with TypeScript-like argument types (`typeScript`) and its description; `ToolCatalog.help` answers `direction.help` in a script, with the job from `ScriptRunner.job`, which the tool server sets for each call. `ScriptRunner` (DirectionTools/Phase2/ScriptTools.swift) starts `direction script` for each one; `ScriptHost` reads the script, warms JavaScriptCore, closes itself off with `sandbox_init` and the pure-computation profile (it won't run if that fails), runs the script, and writes each tool call as a line on stdout, reading the answer on stdin. The runner answers through `ToolRuntime.invoke` inside `DirectionMCPServer.limited`, with a direct call's limits; `direction_run` itself is exempt there, having its own. It reads the helper's lines on the pipe's own handler, split on the newline byte alone (JSON writes U+2028 and its kin raw), so scripts running at once never wait on each other, and a line over 8 MB stops the helper. It stops the helper and cancels the call in flight at 4 minutes of the script's own awake time (time outside its tool calls) or 2 GB of memory; past 300 calls each call is refused. The helper also ends itself if Direction goes away (its parent changes) and by `RLIMIT_CPU` (the script's own work; waiting on a call takes no CPU), not by wall time, since one call can take minutes. Text leaves the script well formed (`toWellFormed`), arguments that aren't JSON are refused rather than run with none, the answer is cut to 40,000 characters in the helper, and Direction's own functions are kept out of the script's reach. Inside a script only non-read-only calls are recorded as activity (`ScriptRunner.running`). Asks and read-backs made in a script aren't in the program's stream, so `EditorRunner.noteAsked` reads them from the film when a `direction_run` call finishes (a read-back against the one the invocation began with). Everything an editor Direction started reads names the tools as its scripts call them (`ToolCatalog.scriptNames`: the role, job text and continuations in `EditorJobs.fill`, the tool reference, `direction.help` in a job, and its copy of each skill), since an editor that read `direction_turnover_update` tried calling it directly. Two calls came from the runs of 11 Nov 2026: `direction_measure_audio` with `levels` gives the level every frame over a stretch (each window's peak and RMS in dBFS, up to 6,000 windows) of the cut's mix or a take's own track (`Levels.swift`), where the Best run had measured a narration 217 calls at a time from a scratch copy of the cut; and `direction_watch` with `changed: true` watches every passage the open notes turnover changed and hasn't watched since, a filmstrip each (`unwatched(turnoverID:)`, which delivery's check uses too), where every run had delivery refused once. Hang recovery gives a script in flight `restartAfterScript` (30 minutes) and one whose code imports `restartAfterLongCall`. `direction_copy` (CopyTools.swift) is the editor's `cp`: a font by name (CoreText), a library item, or a path from what Direction made for the film, the film, the library folders, a take's file or the fonts folders, into the working folder (no hidden folders, no agent instructions, never over a folder, never through a link: each folder on the way is checked once made, since Codex's commands or a shared film could point one anywhere and Direction writes outside the editor's sandbox), converting images by ending.
- From the step logs of 11 Nov 2026 (Claude Code's session files: a Fastest run is 15 to 35 steps of 2 to 6 s each, so its time is its step count; a Best run's is its output, about 100 tokens a second, most of it thinking):
  - `EditorOpening` (app) reads what every run opened with and appends it to the job as "Read for you": the playbook (front matter off), `NOTES.md`, and each tool's answer under its script call. `EditorRunner.launch` computes it in `preparing` like the finishing pass, then starts again with `opening:`. `reads(_:)` is per job, `readsAgain(_:)` for a continuation; only `readOnly` tools, 32,000 characters an answer, 80,000 in all.
  - `keep` in a script stays between scripts (`KeptValues`, ScriptTools.swift): the helper gets it with the code and sends it back with `done` or `failed`; the runner writes it to `<cache>/Scripts/keep-<run>.json` (DIRECTION_RUN_ID), or holds it in memory in your own session.
  - `ToolCatalog.returns` says what the most used tools answer with; the reference and `direction.help("name")` carry it. `JobToolsTests.returnsAreWhatTheToolsAnswer` holds the fields to real answers.
  - `direction_timeline` answers with `effects` (clip, effect id, name); `direction_job` takes `wait`.
  - Word times are held to the sound (`WordEdges`, footage-index.md), so the editor cuts on words instead of measuring levels.
- The role, the skills (edit-video, finish) and the finish job say so, and that sound edits answer with the mix.

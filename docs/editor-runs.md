# Editor runs

How Direction starts the editor (Claude Code or Codex), follows it, and shows it working. The product spec is `design/spec/specs/editor.md` (frames 41, 43, 56–58); this page is for whoever changes the code.

## Where things live

| Piece | File |
|---|---|
| Run and Activity records, their tables and store API | `Sources/DirectionCore/Phase2/Runs/RunsStore.swift` |
| Tool call → Activity (every tool, by name) | `Sources/DirectionTools/Phase2/EditorActivityMapping.swift`, called from `noteToolCall` in `RunsTools.swift` |
| Programs, versions and **every command-line flag** | `Sources/DirectionApp/Phase2/Runs/EditorPrograms.swift` |
| Settings › Engines › Who edits values | `EditorSetup.swift` (keys `editorRunsOn`, `editorVersion…`, `editorStartWork`, `editorRunsScripts`, `editorSignedIn.<program>`) |
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
- Calls Direction's tools don't see (Claude's Read/Write/Bash, Codex's commands and file changes) are recorded by the runner from the stream.

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

- Claude Code: `claude --print <job> --output-format stream-json --verbose --model <v> --mcp-config Editor/.mcp.json --strict-mcp-config --allowedTools mcp__direction,Read,Glob,Grep,Edit(./**),Write(./**)[,Bash] --append-system-prompt <role> --permission-mode dontAsk [--settings <sandbox>] [--resume <session>]`
- Codex: `codex exec --json --skip-git-repo-check [--model <v>] --config mcp_servers.direction.… --output-schema Editor/.direction/result.schema.json --cd Editor --sandbox workspace-write|read-only <job>`; continue with `codex exec resume … <session> <prompt>`.
- The working folder is `<film>.direction/Editor/` (Graphics, Looks, Effects, NOTES.md). Every skill is copied to `Editor/.claude/skills/<skill>/SKILL.md`, and the job names its own from the app bundle's `Resources/Skills` (`scripts/build-app.sh`) or, in development, the checkout's `plugins/direction/skills`.
- The `direction` helper is `Direction.app/Contents/Helpers/direction`, else the `direction` next to the app's executable (`.build/<config>/direction`), else `~/.local/bin/direction`.

## Job text

Templates are versioned files (`<!-- direction-job <name> vN -->` on the first line) with `{{placeholders}}`: film, brief, latitude, preferences, ids, notes, the skill and its path. `editor-role.md` is the appended system prompt, including the final-message shape `{"finished", "summary", "needsYou"}`. `EditorJobTests.everyTemplateShipsAndFillsCompletely` fails on a missing template or a placeholder left unfilled.

## Tests

`Tests/DirectionAppTests/EditorRunsTests.swift`: Claude and Codex streams from canned samples, the activity table, the state machine, templates, command lines, and the runner end to end against `Tests/FakeEditor/fake-claude` (scenarios `done`, `unfinished`, `auth`, `slow`, `crash`, chosen by `Editor/.fake-scenario`). Tests use `EditorPrograms.shared.setPreview` so nothing touches the defaults, and `EditorRunner.shared.programOverride` / `helperOverride` so no real program runs.

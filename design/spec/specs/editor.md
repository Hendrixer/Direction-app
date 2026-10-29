# The editor at work

Frames 43 (Who edits), 56–58, and the Editor popover (41). Read `product-model.md › EditorSetup, Run, Activity` first.

Direction starts the editor itself whenever there's work: footage to log, an assembly to build, a turnover to cut. The director never copies a request into another app. While the editor works, the window shows what it's doing, where in the film it's looking, and what it has spent, and the director can pause or stop it.

---

## Two ways the editor connects

| Connection | What happens | Control |
|---|---|---|
| **Direction starts it** (default) | Direction runs Claude Code or Codex on this Mac for each job, with Direction's tools connected and a job written for it. | Start, pause, resume, stop, retry. Activity, spend. |
| **Your own session** | You run Claude Code or Codex yourself and connect it over MCP (`./scripts/install-local.sh`). Direction shows what it does from its tool calls. | Activity only. Direction can't start, pause or stop it; the pill's popover says "Your own session" and shows the request to copy, as today. |

Settings › Editor › "Editor runs on" has three segments: Claude Code, Codex, Your own session.

## Programs

| Program | Found by | Versions offered (Settings) | Default |
|---|---|---|---|
| Claude Code (`claude`) | `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, npm global bin, then `zsh -lc 'command -v claude'` | Claude Opus 5.5, Claude Sonnet 5.5, Claude Haiku 5.5, Other… | Claude Opus 5.5 |
| Codex (`codex`) | the same folders, then `zsh -lc 'command -v codex'` | The program's default, Other… (a text field) | The program's default |

- The version list ships with the app and is updated with it. "Other…" accepts any version string the program accepts.
- **Signed in** is checked once at setup and after a failure. Direction runs the program with a job that only replies `ready` (no tools). No reply within 30 s or an auth error shows "Not signed in" with the sign-in step.
- The program uses the director's own sign-in and plan. Direction never stores the program's credentials.
- Check every flag below against `claude --help` and `codex exec --help` when building; programs change. Keep the command lines in one file, `EditorPrograms.swift`, with a test that runs `--help` and fails if a flag disappears.

## How Direction runs a job

1. **Working folder.** `<film>.direction/Editor/` holds everything the editor writes: graphics (`Graphics/`), looks (`Looks/`), shaders (`Effects/`), scripts, and `NOTES.md` (its own notes between runs). The program runs with this folder as its working directory.
2. **Tools.** Direction's MCP server for this film (`direction mcp --project <film>`), passed per run, so the director's other MCP servers aren't loaded:
   - Claude Code: `claude -p <job> --output-format stream-json --verbose --model <version> --mcp-config <Editor/.mcp.json> --strict-mcp-config --allowedTools <list> --append-system-prompt <role>`; continue with `--resume <session>`.
   - Codex: `codex exec --json --model <version> --cd <Editor> --sandbox workspace-write -c 'mcp_servers.direction.command="<direction>"' -c 'mcp_servers.direction.args=["mcp","--project","<film>"]' --output-schema <schema.json> <job>`; continue with `codex exec resume <session>`.
3. **Allowed tools.** Every `direction_*` tool, plus file read and write inside the working folder. Running scripts (Bash) is allowed only when Settings › Editor › "Let the editor run scripts" is on (default on), and only inside the working folder: Codex's `workspace-write` sandbox; Claude Code's sandbox with `Bash` allowed. Network access from scripts is off. Services are reached through Direction's tools, never directly.
4. **The job text.** Direction writes it from a template in the app bundle (`Resources/Editor/jobs/<job>.md`), filled with: the film's name, the brief, latitude and what it means, preferences (two ways, ask before guessing, conflict order, handles), the job's ids (turnover, notes), and the skill to follow. Templates are versioned files with tests, not strings in code.
5. **The result.** Each job's final message must match `{"finished": Bool, "summary": String, "needsYou": [String]}`. The real work arrives through Direction's tools, which validate it: the dailies log, the read-back, answers, questions. A run that ends without calling its job's finishing tool fails with "The editor stopped before finishing."
6. **Activity.** Direction reads the program's event stream (Claude: `tool_use` blocks in `assistant` events; Codex: `item.started` and `item.completed` for MCP tool calls, commands and file changes) and turns each Direction tool call into an Activity with the table below. The editor's prose is not shown.
7. **Your own session.** The MCP server records the same Activity rows in the film's store as it handles each call, so the pill and the editor's playhead work there too.

### Tool call → Activity

| Call | Verb | Object | Time (editor's playhead) |
|---|---|---|---|
| `direction_frame`, `direction_watch` | Watching | the passage, `01:12:08–01:14:00` | the time or range start |
| `direction_frame` with assetID, `direction_contact_sheet` | Looking at | the take, `3B T2` | — |
| `direction_transcribe`, `direction_audio` reads | Listening to | the take, `2A T5` | — |
| `direction_search_footage` | Searching footage for | the words, "Maya laughing" | — |
| `direction_timeline_apply`, `direction_edit` | Cutting | the scene(s) touched, `scene 2` | the first changed time |
| `direction_make` | Making | "music for note 4" | — |
| `direction_graphic` | Drawing | the graphic, "the title for note 8" | its start |
| `direction_make_look` | Making a look | for note n | — |
| `direction_turnover_update` (read-back) | Reading back | `7 notes` | — |
| `direction_ask` | Asking you | "about line 12" | — |
| `direction_turnover_complete` | Delivering | `Cut 4` | — |
| Anything else (reading the brief, notes, files) | Reading | "the notes" / "the brief" | — |

Consecutive calls with the same verb and object merge into one row with the latest time.

## Jobs

| Job | Starts when | Skill | Finishing tool | Pill while working |
|---|---|---|---|---|
| Log footage | Footage arrives and the index has found shots | `start-project` | `direction_log_dailies` with `final: true` | Logging 42 of 214 |
| Assemble | Assemble from circles | `assemble` | `direction_turnover_complete` (assembly) | Building the assembly |
| Turnover | Turn over | `take-turnover` | `direction_turnover_complete` | Reading back → Cutting 3 of 7 |
| Continue | You answer a question or approve a read-back | the same skill | — (continues the same session) | — |
| Finish | Lock picture | `finish` | `direction_finishing` with every item done | Finishing 2 of 5 |

- **Start: Ask me first.** Instead of starting, the pill shows "Ready to cut" with a small Start button inside the popover, and the room's primary becomes "Start the editor". Default is Right away.
- **One run per film.** Work that arrives while a run is working queues behind it. Two films may run at once; a third waits.
- **Answering a question** (frame 20) or approving a read-back (frame 23) resumes the same session with the answer, so the editor keeps its context.

## Control

| Action | Where | What happens |
|---|---|---|
| Pause | Popover; Film › Pause Editor (`⌥⌘.`) | Interrupts after the current tool call (SIGINT, then the program saves its session). Pill: "Paused". Edits already made stay; nothing is delivered. |
| Resume | Popover; the same menu item, now "Resume Editor" | Starts the program again with the saved session and "Continue where you stopped." |
| Stop | Popover (text button, alert color); confirm alert | Ends the run. The turnover stays turned over and the unfinished cut is discarded. Alert: "Stop the editor? Cut 4 isn't finished. Your notes stay turned over, and you can start again." Stop / Cancel. |
| Retry | Frame 58 primary | Starts a new run of the same job with the previous session if it still exists. |
| Take the turnover back | Frame 58 | Same as the existing cancel turnover. |

- **Quitting** while the editor works: the existing quit guard says "The editor is cutting Cut 4. Quit and pause it?" Quit pauses the run and keeps the session; the next launch shows a banner "The editor was paused when Direction quit. Resume?" with Resume / Not now.
- **Sleep.** While a run works, Direction holds a `ProcessInfo` activity so the Mac doesn't sleep. Display sleep is allowed.
- **Spend.** Claude Code reports the run's cost in its result event; Codex reports tokens. Show "$0.84 so far" when a cost is known; show nothing when it isn't (a plan sign-in often reports none). Spend on services (made media) is separate and always known; see `made-media.md`.

## What you see while the editor works

- **The pill** shows the current Activity: "Watching 01:12", "Cutting scene 2", "Making music". Shimmer (prism, 2.4 s) while working. Truncate the object at 18 characters.
- **The editor's playhead.** On every scene strip, a 9 pt prism diamond rides the top edge at the latest Activity time, with a 1 pt prism line down through the strip. It glides (Settle) between times and fades out 2 s after the last Activity that had a time. It never moves the director's playhead and isn't drawn in Screening.
- **The window edge.** While a run is working (not paused), a 1 pt prism line runs around the inside of the window's content, under the titlebar's hairline. It shimmers once every 2.4 s; with Reduce Motion it's static. Not drawn in Screening or when the window is full screen.
- **The popover** (frame 57) lists what the editor did, newest first.
- **Notifications.** "Cut 4 is ready" is unchanged. New: "The editor stopped" with the reason as the body and **Show me**.

---

## 43 · Settings, Editor (updated)
Frame: `screens/43-settings-editor.html` · 720 × 860.

A new first group, **Who edits**, above Freedom. The Follow the brief row and the conflict list are compacted so the pane stays under 860.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Who edits | Editor runs on | Seg: Claude Code / Codex / Your own session | Claude Code if installed, else Codex, else Your own session | Which program Direction starts. Sub-label shows what was found: "Claude Code 2.4.1 · signed in", "Not installed. Install it, then come back." with **Copy install command**, or for Your own session "Run Claude Code or Codex yourself. Direction shows what it does but can't start or pause it. How to connect". |
| Who edits | Version | Select (Claude: Claude Opus 5.5 · Claude Sonnet 5.5 · Claude Haiku 5.5 · Other…) | Claude Opus 5.5 | `--model` for every job. Disabled for Your own session. |
| Who edits | Start work | Select: Right away / Ask me first | Right away | Sub-label: "When notes are turned over or footage arrives." |
| Who edits | Let the editor run scripts | Switch | On | Sub-label: "Only inside its own folder in the film, with no internet. Some graphics and looks need it." |
| Freedom | unchanged | | | |
| Before cutting | Wait for my OK on read-backs; Cut Feeling notes two ways; Ask before guessing | unchanged | | |
| Before cutting | When notes conflict | The order as text-2 "Feeling › Story › Pace › Picture › Sound" and **Change…** (`.btn`) | Murch's order | Change… opens a popover anchored to the button with the reorderable list from the previous frame 43 (same rows, same keys) and Restore default. |

Note under Before cutting: "The editor reads the brief before every cut."

**Acceptance:**
- [ ] Choosing Codex when it isn't installed keeps the choice and shows the install row; work waits with the pill "Editor not set up".
- [ ] Changing Version applies to the next run, not the one working.
- [ ] Your own session disables Version, Start work and Let the editor run scripts.

---

## 56 · Who's editing? (setup sheet)
Frame: `screens/56-editor-setup.html` · film window, sheet 560 wide.

Shown the first time a film needs the editor (after Bring footage, before logging) when no editor has been set up, and from Settings › Editor › Set up again… Over the Footage step (frame 04's state behind the scrim).

- Title (Archivo 22): "Who's editing?"
- Body (13 text-2): "Direction starts the editor on this Mac whenever there's work, and you can pause or stop it anytime. It uses your own sign-in."
- Two program cards side by side (`--raised`, radius 10, padding 14, the same selection ring as the Freedom cards):
  - **Claude Code**: "Found · 2.4.1 · signed in" with a green dot (`--approve`). Selected.
  - **Codex**: "Not installed" text-3, and under it SF Mono 11.5 `npm install -g @openai/codex` with a copy icon.
- Version row: label "Version", select "Claude Opus 5.5".
- Start work row: seg "Right away / Ask me first".
- A text link (text-2, 12): "I'll run my own session instead". It turns the sheet into the MCP instructions (the install script and the "Copy request for your editor" text), with **Done**.
- Buttons: Cancel (plain) · **Use Claude Code** (steel). The steel label follows the selected card.

States: neither program found shows both cards as "Not installed" with their install commands, and the primary becomes "Check again". Found but not signed in shows "Found · not signed in" and the step "Open Terminal, run `claude`, and sign in." with **Open Terminal**.

**Acceptance:**
- [ ] Cancel leaves the film on the Footage step with the pill "Editor not set up". Nothing is lost; footage stays.
- [ ] Choosing starts logging immediately when Start work is Right away.

---

## 57 · The editor at work
Frame: `screens/57-editor-working.html` · 1440 × 900.

The Notes room while the editor cuts Cut 4 (state of frame 25), with the popover open from the pill.

- Pill: shimmering "Cutting 3 of 7".
- Window edge: the 1 pt prism line.
- Scene strip: the editor's playhead at 01:12:08 in scene 3 (note 3's anchor).
- Popover (320 wide, `.pop`), under the pill:
  - Header: diamond + "Cutting Cut 4" (13/600), sub "Claude Code · Claude Opus 5.5 · 4 min" (11.5 text-3).
  - Activity list (rows 30 tall, time-ago in SF Mono 11 text-4 on the left, verb in text-1 and object in text-2):
    - now · **Watching** 01:12:08–01:14:00 (shimmer on this row)
    - 12 s · **Reframed** 3B T2 to 1.6× · note 3
    - 40 s · **Trimmed** scene 1 · −4.2 s · note 1
    - 1 min · **Listening to** 2A T5 · note 2
    - 3 min · **Read back** 7 notes · you said OK
  - Spend row: "Spent so far" text-3 · "$0.84" SF Mono, right.
  - Buttons: **Pause** (`.btn`) and **Stop** (text button, alert color), right-aligned.
  - Footer link: "Editor settings…"

The list keeps the newest 6. "Show all" appears under it when there are more and opens the run's full list in the same popover, scrollable.

**Acceptance:**
- [ ] The playhead diamond moves when the editor watches another passage, within 0.5 s.
- [ ] Pause changes the pill to "Paused" and removes the window edge within 2 s.
- [ ] Nothing in this frame moves during playback except the director's playhead and time.

---

## 58 · The editor stopped
Frame: `screens/58-editor-stopped.html` · 1440 × 900.

The Notes room after a run failed during Cut 4.

- Pill: "Stopped" in alert red (`--alert` text, alert wash), no shimmer.
- A banner at the top of the Notes sheet (the cutting-error banner from frame 28, alert): title "The editor stopped: Claude Code isn't signed in." Body: "Open Terminal, run claude, and sign in. Then try again. Cut 4 isn't finished; notes 1–7 are still turned over." Buttons in the banner: **Open Terminal**, **Take the turnover back**.
- Titlebar primary (steel): **Try again**.

| Reason | Title | Body | Actions |
|---|---|---|---|
| Not installed | "The editor isn't installed." | "Direction couldn't find Claude Code on this Mac." | Copy install command · Choose another editor… |
| Not signed in | "Claude Code isn't signed in." | as above | Open Terminal · Try again |
| No internet | "The editor is offline." | "It will try again when this Mac is back online." | (retries automatically every 30 s) |
| Program quit | "The editor quit unexpectedly." | The last line of its error output, in SF Mono 11.5. | Try again · Copy details |
| Stopped without finishing | "The editor stopped before finishing." | "It ended without delivering Cut 4." | Try again · Take the turnover back |
| Spend cap | "You've reached this month's limit." | "$50.00 spent on services this month." | Change limit… · Continue without services |
| Paused by quitting | "The editor was paused when Direction quit." | — | Resume · Not now |

**Acceptance:**
- [ ] Every reason has at least one action that leaves the screen; there's no dead end.
- [ ] Try again keeps the read-back and answers the editor already gave.

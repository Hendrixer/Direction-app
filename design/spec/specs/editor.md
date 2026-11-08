# The editor at work

Frames 43 (Who edits), 56–58, and the Editor popover (41). Read `product-model.md › EditorSetup, Run, Activity` first.

Direction starts the editor itself whenever there's work: footage to log, an assembly to build, a turnover to cut. The director never copies a request into another app. While the editor works, the window shows what it's doing, where in the film it's looking, and what it has spent, and the director can pause or stop it.

---

## Two ways the editor connects

| Connection | What happens | Control |
|---|---|---|
| **Direction starts it** (default) | Direction runs Claude Code or Codex on this Mac for each job, with Direction's tools connected and a job written for it. | Start, pause, resume, stop, retry. Activity, spend. |
| **Your own session** | You run Claude Code or Codex yourself and connect it over MCP: the sheet gives `claude mcp add direction -- "<the app's Helpers/direction>" mcp` and the same for `codex`, or, in a copy built from source, `./scripts/install-local.sh`. Direction shows what it does from its tool calls. | Activity only. Direction can't start, pause or stop it; the pill's popover says "Your own session" and shows the request to copy, as today. |

Settings › Engines › "Editor runs on" has three segments: Claude Code, Codex, Your own session.

## Programs

| Program | Found by | Versions offered (Settings) | Default |
|---|---|---|---|
| Claude Code (`claude`) | `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, npm global bin, then `zsh -lc 'command -v claude'` | Claude Opus 5.5, Claude Fable 5.1, Claude Sonnet 5.5, Claude Haiku 5.5, Other… | Claude Opus 5.5 |
| Codex (`codex`) | the same folders, then `zsh -lc 'command -v codex'` | The program's default, Other… (a text field) | The program's default |

- The version list ships with the app and is updated with it. "Other…" accepts any version string the program accepts.
- **Signed in** is checked at setup, at every launch while the answer was no, after a sign-in failure, and on **Check again**. Direction runs the program with a job that only replies `ready` (no tools) and reads its answer (Claude Code's result JSON, Codex's events), never searching the reply for error words. It answers "ready": signed in. It says it isn't signed in (an invalid key, "run /login", a 401 status): "Not signed in" with the sign-in step; that answer is remembered. Anything else (no reply within 45 s, another error): "Couldn't check sign-in" with why and **Check again**, remembered as nothing, and the work can start anyway. A run that finishes means signed in. Each answer goes to Direction's log with its reason.
- **The shell's settings.** An app opened from the Dock gets none of what the person's shell sets, so Direction reads it once from their interactive shell, started clean as a new Terminal window is (.zshrc included), through a file so nothing it starts can hold Direction up: its PATH, and the settings an editor reads for its sign-in and the network (`ANTHROPIC_*`, `CLAUDE_CODE_*`, `CLAUDE_CONFIG_DIR`, `CODEX_*`, `OPENAI_*`, Bedrock and Vertex, proxies and certificates). API keys (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY`, `CODEX_API_KEY`) are billed per use, so they go only when the program isn't signed in without one and is with it; Settings then says "signed in with your shell's API key".
- The program uses the director's own sign-in and plan. Direction never stores the program's credentials.
- **Without Apple's developer tools**, `/usr/bin/python3`, `git` and the rest are placeholders that open an installer when run. Direction never runs them (`DeveloperTools`, from `xcode-select -p`), and the editor's role says not to, naming the commands macOS has instead.
- Check every flag below against `claude --help` and `codex exec --help` when building; programs change. Keep the command lines in one file, `EditorPrograms.swift`, with a test that runs `--help` and fails if a flag disappears.

## How Direction runs a job

1. **Working folder.** `<film>.direction/Editor/` holds everything the editor writes: graphics (`Graphics/`), looks (`Looks/`), shaders (`Effects/`), scripts, and `NOTES.md` (its own notes between runs). The program runs with this folder as its working directory.
2. **Tools.** Direction's MCP server for this film and this job (`direction mcp --project <film> --job <job>`), passed per run, so the director's other MCP servers aren't loaded:
   - Claude Code: `claude -p <job> --output-format stream-json --verbose --model <version> [--effort <level>] --mcp-config <Editor/.mcp.json> --strict-mcp-config --allowedTools <list> --append-system-prompt <role>`; continue with `--resume <session>`.
   - Codex: `codex exec --json --model <version> [-c 'model_reasoning_effort="<level>"'] --cd <Editor> --sandbox workspace-write -c 'mcp_servers.direction.command="<direction>"' -c 'mcp_servers.direction.args=["mcp","--project","<film>","--job","<job>"]' --output-schema <schema.json> <job>`; continue with `codex exec resume <session>`.
3. **Allowed tools.** The job's own `direction_*` tools (below), plus file read and write inside the working folder. Running scripts (Bash) is allowed only when Settings › Engines › "Let the editor run scripts" is on (default on), and only inside the working folder: Codex's `workspace-write` sandbox; Claude Code's sandbox with `Bash` allowed. Network access from scripts is off. Services are reached through Direction's tools, never directly.
4. **The job text.** Direction writes it from a template in the app bundle (`Resources/Editor/jobs/<job>.md`), filled with: the film's name, the brief (ending with **Already decided**: every question the director answered on the script or the breakdown, with their answer, never asked again in any job), latitude and what it means, preferences (two ways, ask before guessing, conflict order, handles), the job's ids (turnover, notes), and the skill to follow. Templates are versioned files with tests, not strings in code.
5. **The result.** Each job's final message must match `{"finished": Bool, "summary": String, "needsYou": [String]}`. The real work arrives through Direction's tools, which validate it: the dailies log, the read-back, answers, questions. A run that ends without calling its job's finishing tool fails with "The editor stopped before finishing."
6. **Activity.** Direction reads the program's event stream (Claude: `tool_use` blocks in `assistant` events; Codex: `item.started` and `item.completed` for MCP tool calls, commands and file changes) and turns each Direction tool call into an Activity with the table below. The editor's prose is not shown.
7. **Your own session.** The MCP server records the same Activity rows in the film's store as it handles each call, so the pill and the editor's playhead work there too.

### Tools

Each job is given the tools it uses, so the program has them all from the start instead of searching through Direction's sixty-odd for the one it needs (Claude Code defers a long list behind its own search). Every job reads the brief, the style, the turnovers and its questions, asks, and says what it's doing. Then:

| Job | Its own tools |
|---|---|
| Log footage | the footage (dailies, index, shots, contact sheets, frames, watch, screen text, search, words), logging, transcribing, syncing takes, importing, the timeline and edits |
| Assemble | the footage, the cut (timeline, edits and their catalog, restore, preview, measuring sound, the library, importing, graphics, techniques), the script and breakdown, read-back and delivery |
| Turnover (notes) | everything assembling has, and finishing, looks, made shots and their prices, syncing, transcribing, studying frames, saved cuts and the older comment replies: a note can ask for anything |
| Finish | the cut, frames, watching, words, contact sheets, finishing, looks, read-back and delivery, export, and the delivery check |
| Style, Technique | the cut, frames and watching, studying frames, and their own styles or techniques |
| A/V script, Breakdown | the script (and the breakdown), the library, prices |

`direction_more_tools` is always there too: with nothing, it lists the rest a line each; with a name, one tool's description and arguments; with a name and arguments, it runs it, checked exactly like a direct call. Each use is logged, so a job that keeps reaching for a tool gets it on its list. Your own session (`direction mcp` with no `--job`) has every tool.

### Tool call → Activity

| Call | Verb | Object | Time (editor's playhead) |
|---|---|---|---|
| `direction_frame`, `direction_watch` | Watching | the passage, `01:12:08–01:14:00` | the time or range start |
| `direction_frame` with assetID, `direction_contact_sheet` | Looking at | the take, `3B T2` | — |
| `direction_transcribe`, `direction_measure_audio` on a take | Listening to | the take, `2A T5` | — |
| `direction_search_footage` | Searching footage for | the words, "Maya laughing" | — |
| `direction_screen_text` | Reading the screen in | the take, `1A T1` | — |
| `direction_edit` | The first operation's verb: Trimming, Rolling, Swapping takes, Reframing, Ducking … | the scene(s) touched, `scene 2` | the first changed time |
| `direction_make` | Making | "music for note 4" | — |
| `direction_graphic` | Drawing | the graphic, "the title for note 8" | its start |
| `direction_make_look` | Making a look | for note n | — |
| `direction_turnover_update` (read-back) | Reading back | `7 notes` | — |
| `direction_ask` | Asking you | "about line 12" | — |
| `direction_turnover_complete` | Delivering | `Cut 4` | — |
| `direction_check` | Checking | the cut as it delivers | — |
| Anything else (reading the brief, notes, files) | Reading | "the notes" / "the brief" | — |

Consecutive calls with the same verb and object merge into one row with the latest time.

## Skills

A skill is a short playbook in Markdown (`plugins/direction/skills/<name>/SKILL.md`) that Claude Code and Codex load by name. It doesn't run anything. It tells the editor how to do one kind of job well: which Direction tools to call, in what order, and the rules (read back before cutting, footage first, watch what you changed). Direction ships them with the app and names the skill in each job, so the editor follows the same playbook whether Direction started it or you did.

| Skill | Job | What it teaches |
|---|---|---|
| `start-project` | Log footage | Read the index, name people, sort takes into scenes and setups, flag problems, suggest takes |
| `assemble` | Assemble | Build the first cut from circles in script order, using `insert`, `roll` and `splitEdit` |
| `take-turnover` | Turnover | Read back, cut with edit functions, ask when unsure, watch every change, answer every note |
| `make-graphic` | Graphics for a note | Start from an example, keep words in `words`, check with `direction_graphic`, place with `placeGraphic` |
| `propose-look` | A look note | Make two or three looks with `direction_make_look`, offer them as Options or a question, never apply one |
| `make-shot` | Picture the footage doesn't have | Footage first; stills before motion; price the plan with `direction_estimate` and ask once only when it's over the limit; recipes for changed shots, extensions, bridges, inserts, pickups, slow motion and sharpening (`made-media.md`) |
| `finish` | After picture lock | Balance and match shots, balance the mix, check what Direction laid (captions, credits, loudness), check the cut as it delivers |

## Jobs

| Job | Starts when | Skill | Finishing tool | Pill while working |
|---|---|---|---|---|
| Log footage | Footage arrives and the index has found shots | `start-project` | `direction_log_dailies` with `final: true` | Logging 42 of 214 |
| Assemble | Assemble from circles | `assemble` | `direction_turnover_complete` (assembly) | Building the assembly |
| Turnover | Turn over | `take-turnover` | `direction_turnover_complete` | Reading back → Cutting 3 of 7 |
| Continue | You answer a question or approve a read-back | the same skill | — (continues the same session) | — |
| Finish | Lock picture. Direction first lays captions, rolls the credits and sets the loudness itself (finish.md › What Direction does itself) | `finish` | `direction_finishing` with every item done | Finishing 2 of 5 |

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
- **Nothing keeps running.** Every program Direction starts (the editor, Whisper, the vision helper and its downloads, the checks on the editor programs) has a process group of its own, which whatever it starts joins: the `direction` tool server, a shell's `ffmpeg … &`. Pause, Stop and Quit signal the whole group: SIGINT (the program keeps its session), SIGTERM after 4 s if anything is left, SIGKILL 2 s later. Quit goes ahead only once the groups are gone. When a program ends on its own, whatever it left in its group is stopped. The `direction` tool server, stopped, stops what it started first. If Direction goes away without doing any of this (a crash, Force Quit), the reaper it starts at launch (`direction reap`, reading the running groups from a pipe) sees the pipe close and stops them the same way. The editor doesn't carry on without Direction: nothing would record how the run ended, start the next job or show its questions.
- **Sleep.** While a run works, Direction holds a `ProcessInfo` activity so the Mac doesn't sleep. Display sleep is allowed.
- **Spend.** Claude Code reports the session's running total in its result event, and a resumed session's total includes what came before, so a run adds only what's new since the session's last report (`EditorRun.sessionSpend`); Codex reports tokens. Show "$0.84 so far" when a cost is known; show nothing when it isn't (a plan sign-in often reports none). Spend on services (made media) is separate and always known; see `made-media.md`.

## What you see while the editor works

- **The pill** shows the current Activity: "Watching 01:12", "Cutting scene 2", "Making music". Shimmer (prism, 2.4 s) while working. Truncate the object at 18 characters.
- **The editor's playhead.** On every scene strip, a 9 pt prism diamond rides the top edge at the latest Activity time, with a 1 pt prism line down through the strip. It glides (Settle) between times and fades out 2 s after the last Activity that had a time. It never moves the director's playhead and isn't drawn while you watch through.
- **No window edge.** The pill and the editor's playhead are enough. A line around the window's content fought the window's rounded corners, so it was dropped.
- **The popover** (frame 57) lists what the editor did, newest first.
- **Notifications.** "Cut 4 is ready" is unchanged. New: "The editor stopped" with the reason as the body and **Show me**.

---

## 43 · Who edits (in Settings › Engines)
Frame: `screens/43-settings-editor.html` drew it as the Editor tab's first group; it now sits in Settings › Engines under This Mac (settings.md › 54), with transcription, looking at footage and OpenRouter. The Editor tab keeps Freedom and Before cutting (720 × 585).

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Who edits | Editor runs on | Seg: Claude Code / Codex / Your own session | Claude Code if installed, else Codex, else Your own session | Which program Direction starts. Sub-label shows what was found: "Claude Code 2.4.1 · signed in", "Not installed. Install it, then come back." with **Copy install command**, or for Your own session "Run Claude Code or Codex yourself. Direction shows what it does but can't start or pause it. How to connect". |
| Who edits | Start work | Select: Right away / Ask me first | Right away | Sub-label: "When notes are turned over or footage arrives." |
| Who edits | Let the editor run scripts | Switch | On | Sub-label: "Only inside its own folder in the film, with no internet. Some graphics and looks need it." |
| Freedom | unchanged | | | |
| Before cutting | Wait for my OK before cutting; Cut Feeling notes two ways; Ask before guessing | unchanged | | |
| Before cutting | When notes conflict | The order as text-2 "Feeling › Story › Pace › Picture › Sound" and **Change…** (`.btn`) | Murch's order | Change… opens a popover anchored to the button with the reorderable list from the previous frame 43 (same rows, same keys) and Restore default. |

Note under Before cutting: "The editor reads the brief before every cut."

### Speed and quality
One setting per film, a slider with three stops: **Faster · Balanced · Best** (decided 2026-11-08, replacing the version and effort per job of 2026-11-03 and Made with). The director never chooses a version or an effort: Direction picks both for each job, and the version for each made request, from the film's stop. The picks, their sources and how they're refreshed are in `docs/speed-and-quality.md`.

- **Where.** The editor popover (frame 41), under How much freedom, and Who's editing? (frame 56) when a film starts. Nowhere in Settings. The film keeps it (`DirectingState.quality`, nil is Balanced); a new film starts with the last one chosen.
- **When.** Any time the editor isn't working. While it works (Your own session's idle popover), the slider is disabled with "Applies from the next turnover." A run takes the film's setting when it starts and keeps it, resumed and continued runs included; a run that hasn't started takes it again when it launches.
- **The control.** `.slider` with stops: the 4 pt track, steel-8 fill to the knob, the 16 pt steel-9 knob, a 6 pt dot at each stop, and the stops' names under it (11.5, the chosen one text-1 medium, the others text-3). Click or drag anywhere and it lands on the nearest stop; a name picks its stop; ←/→ and VoiceOver move one stop. Under it, one line (11.5 text-3):
  - Faster: "The editor works quicker and made shots come back sooner. Good for a first pass or a quick cut."
  - Balanced: "The editor takes its time cutting and answering notes, and moves quickly through the rest."
  - Best: "The editor takes its time on everything, and made shots use the best versions. Slower, and spends more."

| Job | Faster | Balanced | Best |
|---|---|---|---|
| A/V script | Sonnet 5.5 · Medium | Opus 5.5 · Medium | Opus 5.5 · High |
| Breakdown | Haiku 5.5 · Medium | Sonnet 5.5 · Medium | Opus 5.5 · Medium |
| Logging takes | Sonnet 5.5 · Medium | Sonnet 5.5 · Medium | Opus 5.5 · High |
| Assembly, Notes, Styles | Opus 5.5 · Medium | Opus 5.5 · High | Opus 5.5 · Extra high |
| Finishing | Haiku 5.5 · Medium | Sonnet 5.5 · Medium | Opus 5.5 · Medium |
| Techniques | Sonnet 5.5 · Medium | Opus 5.5 · Medium | Opus 5.5 · High |

- Codex: the same shape on GPT-6.1 Terra (the list-like jobs), GPT-6.1 Sol (judgement) and GPT-6 Astra (judgement at Best). A version the installed Codex doesn't list falls to the next one it does, else its own default.
- An effort the version doesn't take falls to the nearest it does below it, else the program's default.
- Claude Code: `--model <version> --effort <level>`; Codex: `--model <version> --config model_reasoning_effort="<level>"`, on resumed runs too.
- The activity popover's program line names both: "Claude Opus 5.5 · Extra high effort · 4 min" (with the program's default version the program's name stands in: "Codex · High effort · 4 min").
- For testing and the bench, `DIRECTION_EDITOR_VERSION` and `DIRECTION_EDITOR_EFFORT` pin both for every job.
- Not yet measured on real films: Opus at Medium against Sonnet at High for an assembly, and Astra against Sol for notes (docs/bench.md).

**Acceptance:**
- [ ] Choosing Codex when it isn't installed keeps the choice and shows the install row; work waits with the pill "Editor not set up".
- [ ] Moving the slider applies to the film's next run, not the one working; the next new film starts with it.
- [ ] At Balanced an assembly starts with `--model claude-opus-5-5 --effort high`; at Faster a breakdown with `--model claude-haiku-5-5 --effort medium`.
- [ ] Your own session disables Start work and Let the editor run scripts.

---

## 56 · Who's editing? (setup sheet)
Frame: `screens/56-editor-setup.html` · film window, sheet 560 wide.

Opens on every new film (New Film…, from a script or a story, a dropped folder), over its first step, with the editor chosen last already picked; nothing of the film's starts until it's answered (2026-11-04). The film keeps the choice (`DirectingState.editor`), so films can be edited by different programs, and the next new film starts from it. Settings › Engines › Who edits changes the open film's editor and the one new films start with. A film started before films kept their own follows Settings. It also shows itself the first time an older film needs the editor (takes to log, or a script whose picture isn't written) when none has been chosen, and from the pill's Set up…. Frame 56 draws it over the Footage step (frame 04's state behind the scrim).

- Title (Archivo 22): "Who's editing?"
- Body (13 text-2): "Direction starts the editor on this Mac whenever this film has work, and you can pause or stop it anytime. It uses your own sign-in."
- Two program cards side by side (`--raised`, radius 10, padding 14, the same selection ring as the Freedom cards):
  - **Claude Code**: "Found · 2.4.1 · signed in" with a green dot (`--approve`). Selected.
  - **Codex**: "Not installed" text-3, and under it SF Mono 11.5 `npm install -g @openai/codex` with a copy icon.
- Start work row: seg "Right away / Ask me first".
- Speed and quality row: the slider (200 wide), its line as the row's detail (Speed and quality, above). Starts on the last one chosen.
- Under the card, a note (11.5 text-3): "Change the speed and quality anytime the editor isn't working, from the editor button at the top of the window."
- A text link (text-2, 12): "I'll run my own session instead". It turns the sheet into the MCP instructions (the install script and the "Copy request for your editor" text), with **Done**.
- Buttons: Cancel (plain) · **Use Claude Code** (steel). The steel label follows the selected card.

States: neither program found shows both cards as "Not installed" with their install commands, and the primary becomes "Check again". Found but not signed in shows "Found · not signed in" and the step "Open Terminal, run `claude`, and sign in." with **Check again** and **Open Terminal**. A check that couldn't tell shows "Found · couldn't check sign-in" and "Direction couldn't check the sign-in: <why>. You can start anyway." with **Check again**.

**Acceptance:**
- [ ] Cancel leaves the film on the Footage step: on the editor in Settings, or with the pill "Editor not set up" when none was ever chosen. Nothing is lost; footage stays.
- [ ] Choosing starts logging immediately when Start work is Right away.

---

## 57 · The editor at work
Frame: `screens/57-editor-working.html` · 1440 × 900.

The Cut room while the editor cuts Cut 4 (state of frame 25), with the popover open from the pill.

- Pill: shimmering "Cutting 3 of 7".
- Scene strip: the editor's playhead at 01:12:08 in scene 3 (note 3's anchor).
- Popover (320 wide, `.pop`), under the pill:
  - Header: diamond + "Cutting Cut 4" (13/600), sub "Claude Opus 5.5 · Extra high effort · 4 min" (11.5 text-3; see Speed and quality).
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
- [ ] Pause changes the pill to "Paused" and stops its shimmer within 2 s.
- [ ] Nothing in this frame moves during playback except the director's playhead and time.

---

## 58 · The editor stopped
Frame: `screens/58-editor-stopped.html` · 1440 × 900.

The Cut room after a run failed during Cut 4.

- Pill: "Stopped" in alert red (`--alert` text, alert wash), no shimmer.
- A banner at the top of the Notes sheet (the cutting-error banner from frame 28, alert): title "The editor stopped: Claude Code isn't signed in." Body: "Open Terminal, run claude, and sign in. Then try again. Cut 4 isn't finished; notes 1–7 are still turned over." Buttons in the banner: **Open Terminal**, **Take the turnover back**.
- Titlebar primary (steel): **Try again**.

| Reason | Title | Body | Actions |
|---|---|---|---|
| Not installed | "The editor isn't installed." | "Direction couldn't find Claude Code on this Mac." | Copy install command · Choose another editor… |
| Not signed in | "Claude Code isn't signed in." | as above | Open Terminal · Try again |
| Out of date | "Claude Code needs updating." | "It's older than Direction needs. In Terminal, run claude update, then try again." (Codex: `npm install -g @openai/codex@latest`, or `brew upgrade codex` for Homebrew's.) Read from the program refusing an option ("unknown option '--effort'"); the sign-in check says the same as "couldn't check". | Copy update command · Open Terminal · Try again |
| Stuck | "The editor got stuck." | "It stopped answering twice, the last time while "Watching 0:15". Direction started it again once, and it got stuck again." plus the turnover's line. Fifteen quiet minutes the first time is a restart on the same session, not a stop (system.md › Hangs). | Try again · Take back (in a turnover) |
| No internet | "The editor is offline." | "It will try again when this Mac is back online." | (retries automatically every 30 s) |
| Program quit | "The editor quit unexpectedly." | The last line of its error output, in SF Mono 11.5. | Try again · Copy details |
| Stopped without finishing | "The editor stopped before finishing." | "It ended without delivering Cut 4." | Try again · Take the turnover back |
| Spend cap | "You've reached this month's limit." | "$50.00 spent on services this month." | Change limit… · Continue without services |
| Paused by quitting | "The editor was paused when Direction quit." | — | Resume · Not now |

**Acceptance:**
- [ ] Every reason has at least one action that leaves the screen; there's no dead end.
- [ ] Try again keeps the read-back and answers the editor already gave.

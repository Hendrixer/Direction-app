# Direction product model

This file is the behavior contract behind the screens. If a screen and this file disagree, this file wins, and the screen is a bug.

Direction is a Mac app where a human **director** makes a film with an AI **editor** (the agent). The director never edits the timeline. They choose takes, watch, mark, write notes, and approve. The agent logs footage, assembles, cuts, answers notes, and asks questions. The relationship copies how features are finished: dailies → assembly → screening → notes session → recut → lock → finishing.

## Vocabulary (use these words in the UI, exactly)

| Word | Meaning | Never say |
|---|---|---|
| Editor | The agent, as the UI names it. Always shown with the diamond. | AI, assistant, bot, Claude |
| Film | A project. One film has one picture. | Project, workspace |
| Brief | The director's written intent for the film. | Prompt, instructions |
| Footage | Everything imported. | Assets, media files |
| Scene | A story unit. Numbered `1`, `2`, `3`. | Section, chapter |
| Setup | One camera position within a scene. `2A`, `2B`. | Angle |
| Take | One recording of a setup. `T1`, `T2`. | Clip |
| Circle | The director's choice of a take. | Favorite, like, star |
| Suggestion | The agent's recommended take. A diamond, never a circle. | — |
| Cut | One complete version of the film: Assembly, Cut 2, Cut 3 … | Revision, version, draft |
| Screening | Watching a cut straight through. | Preview, review |
| Mark | A timestamp dropped during a screening, without words yet. | Bookmark, flag |
| Note | One numbered instruction from the director. | Comment, feedback, task |
| Kind | Feeling, Story, Pace, Picture, Sound. | Category, tag |
| Turnover | Handing the whole notes sheet to the agent. | Submit, send |
| Read-back | The agent's plan for each note, in concrete terms, before cutting. | Summary, plan |
| Answer | What the agent did for one note in a new cut. | Resolution, fix |
| Options | Two versions of one note, A and B. | Variants, alternatives |
| Changes | Only the passages that moved between cuts, with handles. | Diff |
| Handle | Seconds of untouched picture shown either side of a change. | Padding |
| Lock | Making a scene or the whole picture untouchable. | Freeze, finalize |
| Outside note | A note from someone else (producer, client) via a share link. | Guest comment |
| Question | The agent asking the director to decide something. | Prompt, alert |
| Latitude | How much freedom the agent has to interpret notes. | Creativity, temperature |
| Shot | One continuous stretch of picture inside a take, found when footage is logged. | Segment, clip |
| Search footage | Finding shots by what's in them ("Maya laughing"). | Semantic search, query |
| Look | The film's color and texture: a LUT at a strength plus filters. The director chooses it. | Preset, style, grade |
| Filter | One texture or lens quality inside a look: Grain, Halation, Vignette … | Effect, FX |
| Graphic | Words or shapes the editor draws over the picture: titles, lower thirds, end cards. | Motion graphic, template, overlay |
| Made | Picture or sound the editor made with a service instead of finding it in the footage. | Generated, synthetic, AI |
| Service | An outside company the editor can use to make picture or sound, with your key. | Provider, API, integration |
| Spend | Money a service charges for something made. Shown before it's spent. | Credits, tokens |

The director is never named in the UI; it's "you". The agent speaks in first person as the editor.

Never show the words "AI", "generate", "prompt", "model", "revision", "comment", "task", or "magic".

**Program names.** Settings › Editor, Settings › Footage (Whisper, mlx-whisper, mlx-vlm, OpenRouter, and versions such as "Qwen3-VL 8B"), Settings › Services, the editor setup sheet (frame 56), the Editor popover (frames 41, 57) and a stopped editor's message (frame 58) may name the programs and services the director installs and pays for: Claude Code, Codex, OpenRouter, and each one's version ("Claude Opus 5.5", "Veo 3.1", "Lyria 3 Clip"). Provenance of made media names its version and service ("Made with Lyria 3 Clip · OpenRouter"), and so does anything that asks the director to spend with one: a spend question (frame 62) or a read-back line that plans to make something. Nowhere else. A version is a "version", never a "model". What the editor asked a service for is "What the editor asked for", never a prompt.

## Objects

```
Film
  id, title, brief: Brief, scenes: [Scene], footage: [Take], cuts: [Cut]
  latitude: .exact | .faithful | .free          // default .faithful
  pictureLocked: Bool, lockedAt: Date?
  finishing: Finishing?                           // exists only after picture lock

Brief
  logline: String          // one sentence, required
  feeling: String          // "how it should feel", required
  length: Duration range   // target, e.g. 3:00–4:00
  audience: String?
  mustKeep: [String]       // lines or moments that can never be cut
  references: [Reference]  // clip, link or still, each with a "why"
  avoid: [String]?

Scene
  number: Int, title: String, setups: [Setup], locked: Bool
  scriptText: [Line]?      // from transcript or an imported script

Setup   code: "2A", description: "Wide, window light", takes: [Take]

Take
  code: "T2", setup, duration, transcript: [Line]
  circled: Bool            // only the director sets this
  suggestion: Suggestion?  // agent: reason String ("warmest read")
  flags: [.flubbed(at) | .soft(at) | .noAudio | .broll]

Line     // one sentence of dialogue across takes
  id, speaker, text, coverage: [Take]   // which takes contain this line (lined script)

Cut
  number: Int (0 = Assembly), name: "Assembly" | "Cut N"
  state: .building | .ready | .watched | .superseded | .locked
  duration, createdAt, basedOn: Cut?
  answers: [Answer], changes: [Change]

Screening   cut, startedAt, endedAt?, marks: [Mark], completed: Bool

Mark     time: Timecode, screening, becameNote: Note?

Note
  number: Int              // project-wide, permanent, never reused
  author: Director | OutsidePerson
  anchor: .moment(tc) | .range(tc, tc) | .region(tc, rect) | .line(Line.id) | .scene(n) | .wholeCut
  kind: Kind?              // optional; agent proposes one if empty
  text: String
  scriptAction: .strike | .hold | .move(after: Line.id) | .reading(Take) | nil
  state: .draft | .written | .turnedOver | .readBack | .answered | .accepted | .reopened | .dropped
  thread: [Reply]          // director/agent back-and-forth on this note
  cutRaised: Cut           // which cut it was written against

ReadBack   turnover, lines: [ReadBackLine], state: .waiting | .approved | .adjusted
ReadBackLine  note, plan: String ("Trim three pauses, −2.4 s"), options: Bool, conflictWith: Note?

Answer   note, cut, summary, delta: String ("−4.2 s" | "crop" | "−6 dB"), change: Change, options: (A, B)?, pick: A|B?, inCut: A|B?
         // each option is a revision; using one puts it in the cut (changes.md › 30)
Change   range in new cut, range in old cut, scene, note, revertible: Bool

Question  id, asked: Date, text, choices: [Choice] (2–4, each may show a still or take), freeText: Bool, blocks: [Note]?
OutsideNote  from: Person, cut, anchor, text, state: .inbox | .accepted (becomes Note) | .edited | .declined
ShareLink  cut, url, canNote: Bool, expires: Date?, password: Bool, viewers: [Person]

// The editor's working life (specs/editor.md)
EditorSetup   // app-wide, Settings › Editor
  program: .claudeCode | .codex           // the program that runs the editor on this Mac
  picks: [Job: (version, effort)]         // per job; Direction's unless the director changed one ("claude-opus-5-5" → "Claude Opus 5.5", "xhigh" → "Extra high")
  start: .rightAway | .askFirst           // when work is waiting for the editor
  connection: .direction | .yourOwn       // Direction starts the editor, or you run your own session that connects over MCP
Run           // one stretch of the editor's work. Internal word; the UI says what the editor is doing.
  job: .logFootage | .assemble | .turnover(Turnover) | .question(Question) | .look(Note) | .graphic(Note) | .finish
  state: .starting | .working | .waitingForYou | .paused | .stopped(reason) | .failed(reason) | .done
  version, effort                         // its job's, from when it was made; kept once it starts
  activity: [Activity], startedAt, endedAt?, spend: Money?, session: String   // to resume
Activity  at: Date, verb: "Watching" | "Listening to" | "Trimming" | "Moving" | "Making" | "Reading" …, object: "scene 2" | "note 4" | "01:12:08–01:14:00",
          time: Timecode?    // where in the cut or take; drives the editor's playhead on the strip

// What the editor can see (specs/footage-index.md)
Shot      take, range (source), keyframes: [Still], description: "Medium on Maya at the window. She looks down.",
          size: .wide | .medium | .close | .insert, movement: .static | .pan | .tilt | .push | .handheld,
          people: [String], flags: [.soft | .shaky | .overexposed | .underexposed | .noAudio]
Sound     take, range, kind: .speech | .laughter | .music | .applause | .wind | .traffic | .silence
Index     per take: .waiting | .looking | .done | .failed, engine: .thisMac(version) | .gemini(version)

// What the editor can make (specs/agent-timeline.md, looks.md, graphics.md, made-media.md)
Look      name, lut: LUT?, strength: 0–1, filters: [Filter], by: .you | .editor | .folder
          film has one look; a scene may have its own. The director chooses; the editor only proposes.
Filter    kind: .grain | .halation | .bloom | .vignette | .gateWeave | .chromaticAberration | .soften | .letterbox | .blackAndWhite | .splitTone | .fade
          amount: 0–1, option?   // e.g. letterbox ratio
LUT       file (.cube), use: .camera | .look, size: 17–65, from: .folder | .film | .editor
Graphic   name: "Title · Launch day", source: folder in the film (HTML + JavaScript), duration, words: [GraphicWord], note: Note?
GraphicWord  key, label: "Title", text, maxLength?    // the director may change words directly
Made      kind: .music | .soundEffect | .voice | .still | .shot | .extension | .bridge | .changedShot | .slowMotion | .upscale,
          service ("openrouter" | "local"), version, asked: String, from: (Take, range)?, first/last: (Take or Still, time)?, sharpened: Size?,
          spend: Money, note: Note?, file      // appears in Dailies under Made, and in History with its provenance
Service   name, uses: [Made.kind], key (Keychain), state: .notSet | .ready | .failing(reason), spentThisMonth: Money
Spending  askAbove: Money per turnover, stopAt: Money per month
```

## Lifecycles

### Note
```
mark (screening) ─▶ draft ──write──▶ written ──Turn over──▶ turnedOver ─▶ readBack
                     │                                          (agent plans)   │
                     └─⌫─▶ dropped                       director approves ◀────┘
                                                                    │
                                     cut builds ─▶ answered ─Accept─▶ accepted
                                                       │
                                                       └─Reply / Not quite─▶ reopened ─▶ (next turnover)
```
- Number is assigned when the draft is created and is never reused, even when dropped.
- A note written against Cut 3 keeps its number in Cut 4, Cut 5, and in the changelog.
- A written note can be edited until turnover. After turnover it can only be replied to.

### Cut
```
building (agent working, shimmer) ─▶ ready (prism sweep once, toast) ─▶ watched ─▶ superseded by next
                                                                    └─▶ locked (picture lock)
```

### Turnover → new cut (the core loop)
1. Director presses **Turn over** (`⌘↩`) in Notes. A sheet lists the notes and the latitude for this turnover.
2. Agent returns a **read-back** within seconds: one plain line per note with concrete numbers, flags conflicts, marks which notes it will cut two ways.
3. If Settings › Editor › "Wait for my OK before cutting" is on (default), the director approves or adjusts lines. Otherwise cutting starts immediately and the read-back stays visible.
4. Agent cuts. Status pill shows progress per note. The director can keep watching the previous cut or work in Dailies.
5. Agent may raise a **question** (blocks only the notes it names) or report it **can't** do a note (missing footage, locked scene, contradicts the brief's must-keep).
6. New cut is ready: one prism sweep across the window top edge (900 ms), toast "Cut 4 is ready", Changes room unlocks.
7. Director plays changes, picks options, accepts or replies per answer.

### Conflicts
When two notes pull against each other, the agent resolves them in the order Feeling > Story > Pace > Picture > Sound, and says so in the read-back: "Notes 2 and 5 conflict. Following 2 (Feeling) over 5 (Pace). Change it?" The director can flip it.

### Locking
- Any scene can be locked from the scene strip (context menu or `⌘L` on the current scene). Locked scenes are hatched and grayscale in every strip.
- The agent can't recut a locked scene; its color and sound stay open, as after picture lock. A note that would require recutting it gets a "can't" with the reason and an **Unlock scene 4** button.
- **Lock picture** is available when every open note is accepted or dropped. It shows a confirmation, then moves the film to Finishing. Unlocking picture is possible from the Film menu and is logged.

### Latitude
| Value | Label in UI | Agent behavior |
|---|---|---|
| exact | Do what I wrote | Changes only what each note names. Never offers options. Asks when unclear. |
| faithful | Read between the lines (default) | Interprets intent, may touch adjacent shots, offers options for Feeling notes. |
| free | Take a pass | May propose changes no note asked for. Each appears as an unrequested answer labeled "Unasked" that the director must accept. |

### Outside notes
Viewers of a share link can drop notes. They land in **Notes › Outside**, never in the main sheet. The director accepts (becomes a numbered Note authored by that person), edits then accepts, or declines. The agent never sees an outside note until the director accepts it.

### Prep: the A/V script and the breakdown
A film can start from a script (specs/script.md, specs/breakdown.md). Writing and research happen outside Direction; the script comes in once, as a file, and Direction's copy is the shooting script from then on.
- **Script** lays it out as an A/V script: one row per beat, the picture (what we see) beside the sound (the script's words, voice-over or on camera). The editor writes the picture from the film's style; the director types in any cell, leaves notes on rows, turns them over for a pass, and OKs it. What the director types is theirs: the editor changes it only when a note on that row asks.
- **Breakdown** turns the OK'd script into shots grouped by setup (a place and its light), each with a source: shoot, screen recording, make, footage you have, sound only. Once OK'd, shot numbers (2C) are the slates; Dailies gets a scene per setup and a setup per shot, and takes are filed by the slate said at their head or in their file name. After the shoot it shows coverage: what came in, what's missing, and for each gap make it, pick it up, or do without.
Films that start from footage (a documentary, an interview) skip both and begin with Bring footage.

## Agent behavior rules (UI must never imply otherwise)
- Never circles a take. Only suggests.
- Never recuts a locked scene (its color and sound stay open).
- Never changes anything without a note, except with latitude "free", and then labeled "Unasked".
- Every change in a new cut points to exactly one note number (or "Unasked").
- Always writes in first person, short, concrete: "Trimmed three pauses. −2.4 s." Never apologises twice, never says "Great note".
- Questions carry 2–4 concrete choices; free text is optional.
- Uses the footage first. Makes picture or sound with a service only when a note asks for something the footage doesn't have, or with latitude "free" (then labeled "Unasked").
- Never spends past the turnover's limit without a spend question (frame 62), and never past the monthly cap at all.
- Every made thing shows where it came from: service, what the editor asked for, spend.
- Never changes the look. It may propose looks as Options or in a question.
- Never changes a graphic's words after the director has changed them, unless a note asks.
- Watches every passage it changed before delivering a cut.

## Rooms (top-level navigation)
Titlebar segmented control, `⌘1`–`⌘7`, in the order a film is made:
1. **Script**: the A/V script, picture beside sound; edit cells, notes on rows, OK.
2. **Breakdown**: shots by setup with their sources and slates; coverage after the shoot. Enabled once the script is OK'd.
3. **Dailies**: footage, scenes, setups, takes, circles.
4. **Screening**: full-bleed playback of the current cut, marks only.
5. **Notes**: the notes sheet for the current cut, questions, outside notes, turnover, read-back.
6. **Changes**: the latest cut's answers, options, play changes, changelog. Badge shows unreviewed answers.
7. **Finish**: appears enabled only after picture lock (before: disabled with tooltip "Lock picture first").

The agent status pill in the titlebar is always visible and clickable (opens the Agent popover).

## Windows
- Main window, min 1180 × 740 pt, design size 1440 × 900 pt. Full-screen supported (Screening defaults to full-screen when the window is already full-screen).
- Films window (project list), 1080 × 720.
- Settings window, 720 pt wide, height fits pane, toolbar-style tabs (9: General, Editor, Footage, Cutting, Services, Notifications, Shortcuts, Storage, Sharing).
- Sheets attach to the main window titlebar.

## Menus
See `specs/system.md` for the full menu bar.

## The editor's side (phase 2)

The director's side stays simple: no timeline, no effect controls. Everything below lives in the editor's tools, and the director sees only results, provenance and choices.

| Spec | What it covers | Frames |
|---|---|---|
| `specs/editor.md` | Direction starts the editor (Claude Code or Codex), shows what it's doing, and lets you pause or stop it. | 43, 56–58, 41 |
| `specs/footage-index.md` | Shots, contact sheets, descriptions, sounds and search, made when footage is logged. | 05, 54, 59, 60 |
| `specs/agent-timeline.md` | The full timeline the editor reads and writes, as OpenTimelineIO, with effects, layers and keyframes. | — |
| `specs/looks.md` | LUTs, filters, the Look sheet. | 54, 63 |
| `specs/graphics.md` | Graphics written in JavaScript, rendered by Direction, words the director can fix. | 64 |
| `specs/made-media.md` | Made media through OpenRouter: the key, versions, spend, provenance. | 55, 61, 62 |

## Formats
- Timecode: `MM:SS:FF` under an hour (`01:12:08` = 1 min 12 s frame 8), `H:MM:SS:FF` over. Always SF Mono, tabular.
- Ranges: `00:46:00–00:58:12` (en dash, no spaces).
- Durations: `3:40`, `0:46`, deltas `−4.2 s` (true minus sign U+2212), `+1.6 s`, `−6 dB`.
- Money: `$0.40`, `$12.80`, always two decimals, SF Mono. Estimates are "about $3.20".
- Cut names: `Assembly`, `Cut 2`, `Cut 3`. Scene: `3 The ridge`. Setup: `2A`. Take: `T3`, or `2A T3` out of context.
- Times of day: `Today 14:20`, `Yesterday`, `Oct 12`.

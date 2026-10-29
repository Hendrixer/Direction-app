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

The director is never named in the UI; it's "you". The agent speaks in first person as the editor.

Never show the words "AI", "generate", "prompt", "model", "revision", "comment", "task", or "magic".

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

Answer   note, cut, summary, delta: String ("−4.2 s" | "crop" | "−6 dB"), change: Change, options: (A, B)?, pick: A|B?
Change   range in new cut, range in old cut, scene, note, revertible: Bool

Question  id, asked: Date, text, choices: [Choice] (2–4, each may show a still or take), freeText: Bool, blocks: [Note]?
OutsideNote  from: Person, cut, anchor, text, state: .inbox | .accepted (becomes Note) | .edited | .declined
ShareLink  cut, url, canNote: Bool, expires: Date?, password: Bool, viewers: [Person]
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
3. If Settings › Agent › "Wait for my OK on read-backs" is on (default), the director approves or adjusts lines. Otherwise cutting starts immediately and the read-back stays visible.
4. Agent cuts. Status pill shows progress per note. The director can keep watching the previous cut or work in Dailies or Script.
5. Agent may raise a **question** (blocks only the notes it names) or report it **can't** do a note (missing footage, locked scene, contradicts the brief's must-keep).
6. New cut is ready: one prism sweep across the window top edge (900 ms), toast "Cut 4 is ready", Changes room unlocks.
7. Director plays changes, picks options, accepts or replies per answer.

### Conflicts
When two notes pull against each other, the agent resolves them in the order Feeling > Story > Pace > Picture > Sound, and says so in the read-back: "Notes 2 and 5 conflict. Following 2 (Feeling) over 5 (Pace). Change it?" The director can flip it.

### Locking
- Any scene can be locked from the scene strip (context menu or `⌘L` on the current scene). Locked scenes are hatched and grayscale in every strip.
- The agent can't change a locked scene. A note that would require it gets a "can't" with the reason and an **Unlock scene 4** button.
- **Lock picture** is available when every open note is accepted or dropped. It shows a confirmation, then moves the film to Finishing. Unlocking picture is possible from the Film menu and is logged.

### Latitude
| Value | Label in UI | Agent behavior |
|---|---|---|
| exact | Do what I wrote | Changes only what each note names. Never offers options. Asks when unclear. |
| faithful | Read between the lines (default) | Interprets intent, may touch adjacent shots, offers options for Feeling notes. |
| free | Take a pass | May propose changes no note asked for. Each appears as an unrequested answer labeled "Unasked" that the director must accept. |

### Outside notes
Viewers of a share link can drop notes. They land in **Notes › Outside**, never in the main sheet. The director accepts (becomes a numbered Note authored by that person), edits then accepts, or declines. The agent never sees an outside note until the director accepts it.

### Script (text-based direction)
The Script room shows the cut's dialogue as a screenplay-style transcript with a lined-script coverage bar per line. The director does not edit text. Every gesture creates a note with a `line` anchor:
- Strike a line (select, `⌫` or the Strike button): note "Lose this line." kind Story.
- Hold (bracket a passage, `H`): note "Let this breathe." kind Pace.
- Move (drag a paragraph): note "Move this after line N." kind Story.
- Other readings (click line number or `R`): opens all takes containing that line; circling one creates a note "Use T3's reading." kind Feeling.
These notes appear in the Notes sheet like any other, with a script icon. They do nothing until turnover.

## Agent behavior rules (UI must never imply otherwise)
- Never circles a take. Only suggests.
- Never changes a locked scene.
- Never changes anything without a note, except with latitude "free", and then labeled "Unasked".
- Every change in a new cut points to exactly one note number (or "Unasked").
- Always writes in first person, short, concrete: "Trimmed three pauses. −2.4 s." Never apologises twice, never says "Great note".
- Questions carry 2–4 concrete choices; free text is optional.

## Rooms (top-level navigation)
Titlebar segmented control, `⌘1`–`⌘6`:
1. **Dailies**: footage, scenes, setups, takes, circles.
2. **Script**: dialogue as text; strike, hold, move, readings.
3. **Screening**: full-bleed playback of the current cut, marks only.
4. **Notes**: the notes sheet for the current cut, questions, outside notes, turnover, read-back.
5. **Changes**: the latest cut's answers, options, play changes, changelog. Badge shows unreviewed answers.
6. **Finish**: appears enabled only after picture lock (before: disabled with tooltip "Lock picture first").

The agent status pill in the titlebar is always visible and clickable (opens the Agent popover).

## Windows
- Main window, min 1180 × 740 pt, design size 1440 × 900 pt. Full-screen supported (Screening defaults to full-screen when the window is already full-screen).
- Films window (project list), 1080 × 720.
- Settings window, 720 pt wide, height fits pane, toolbar-style tabs.
- Sheets attach to the main window titlebar.

## Menus
See `specs/system.md` for the full menu bar.

## Formats
- Timecode: `MM:SS:FF` under an hour (`01:12:08` = 1 min 12 s frame 8), `H:MM:SS:FF` over. Always SF Mono, tabular.
- Ranges: `00:46:00–00:58:12` (en dash, no spaces).
- Durations: `3:40`, `0:46`, deltas `−4.2 s` (true minus sign U+2212), `+1.6 s`, `−6 dB`.
- Cut names: `Assembly`, `Cut 2`, `Cut 3`. Scene: `3 The ridge`. Setup: `2A`. Take: `T3`, or `2A T3` out of context.
- Times of day: `Today 14:20`, `Yesterday`, `Oct 12`.

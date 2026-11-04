# Components

Build these once in SwiftUI, with every state, before building screens. Each one maps to a class in `gate.css` (the exact recipe) and to the `data-c` names used in frames. Values are tokens from `tokens.json`.

Suggested module layout: `Gate/Tokens.swift` (generated), `Gate/Materials.swift`, `Gate/Controls/*.swift`, `Gate/Marks.swift`, `Gate/Strip/*.swift`, `Gate/Notes/*.swift`, `Gate/Editor/*.swift`.

## Window and navigation

| Component | CSS | data-c | SwiftUI notes | States |
|---|---|---|---|---|
| Titlebar | `.tb` | `titlebar` | Full-size content view, `.windowStyle(.hiddenTitleBar)`, custom 52 pt bar. Traffic lights stay system-drawn at x 20. | normal · over picture (`.tb.over`, transparent with 70%→0 black gradient) · hidden (watching through, idle) |
| Crumb | `.crumb` | `crumb` | Two menu buttons: film (opens Films menu), cut (picker of cuts, newest first). | hover: raised fill · open |
| Room switcher | `.rooms` | `rooms` | Custom segmented control, centered in the window, not in the toolbar's flow. Script · Breakdown · Dailies · Cut · Finish, `⌘1`–`⌘5`, fixed to each room. It shows the rooms the film uses: one started from its footage with no script has no Script or Breakdown (they come back when a script or a story is brought in, File › Bring In a Script…). Badge: on Cut, the editor's answers to look at and its questions in ion, otherwise drafts and outside notes in amber (`cut.md` › The Cut tab's count); the editor's open questions on Script and Breakdown, in ion. | on · off (Finish before lock, text-4, tooltip "Lock picture first") · badge |
| Editor pill | `.agent` | `agent-pill` | Opens Editor popover (frame 41). Text is the live status. | ready · readingBack · working (prism border shimmer, meter) · asks (ion) · blocked (alert) · offline (text-4, offline icon) |
| Primary button | `.btn.steel` | `primary` | Exactly one per window state, rightmost in the titlebar. `⌘↩` triggers it. | rest · hover · press · disabled (40%) · focus ring |
| Sidebar list | `.side`, `.nav .it` | `sidebar` | 240 pt. Rows 30 pt, radius 7. | rest · hover (raised 50%) · selected (raised + line) · drop target (line-2 dashed) |
| Sheet tabs | `.sheet-tabs` | `sheet-tabs` | Underline tabs inside the notes sheet. Count in mono. | on · off · has-new (count in ion or amber) |

## Controls

| Component | CSS | States |
|---|---|---|
| Button | `.btn` (+ `.ghost`, `.lg`, `.sm`, `.icon`, `.danger`) | rest · hover · press · disabled · focus. Icon 15 pt, gap 6. Inline key hint `kbd` at 55%. Count `.n` in mono. |
| Text field | `.input` (single line), `.field` / `.field.area` (multi-line) | rest · placeholder · focus (text-2 border + 3 pt white 8% ring) · error (alert border + wash ring) · disabled |
| Select | `.select` | NSPopUpButton look in Gate colors. |
| Segmented | `.seg` | Same recipe as the room switcher, smaller use. |
| Switch | `.switch` | off (hover track) · on (steel-9 track, dark knob). Never colored. |
| Checkbox, radio | `.check`, `.radio` | off · on (steel-9) · mixed (checkbox, a dash) |
| Slider | `.slider` | Track 4 pt, knob 16 pt. |
| Kind picker | `.kinds`, `.kind` | off · on · suggested by editor (`.kind.sug`, ion border). Five kinds only, in this order: Feeling, Story, Pace, Picture, Sound. |
| Key cap | `.kbd` | Static. |
| Chip | `.chip` (+ `.d` director, `.a` editor, `.ok`, `.bad`, `.k` plain label) | Timecodes are `.chip.d` when they anchor a director note. |
| Progress | `.progress`, `.progress.agent` (prism fill), `.spinner` | determinate · indeterminate (prism moving 2.4 s loop) |

## Marks and materials

| Component | CSS | Rule |
|---|---|---|
| Pin | `.mk.pin` | Director's mark. 10 pt teardrop, amber. Outside person's: `.mk.pin.out`, text-2. |
| Ring / hand-drawn circle | `.mk.ring`, `#i-circle` | Director's circle on a take. The hand-drawn path, 1.8 pt amber stroke. Draws on with a 220 ms stroke-dashoffset. |
| Diamond | `.mk.gem` | Editor. 8 pt square rotated 45°, prism fill (or `.solid` ion). |
| Lock + hatching | `#i-lock`, `.hatch` | Locked scenes and things the editor can't touch. |
| Glass | `.glass` | Only over picture: dock, HUD tags, toasts while watching through. |
| Steel | `.btn.steel` | Only the primary action. |
| Prism edge | `.prism-edge`, `.readback` | Editor-authored containers (read-back). 1 pt. |
| Arrival sweep | `.sweep-edge` | 2 pt prism line under the titlebar; sweeps left→right once in 900 ms when a cut is ready. |

## Picture and time

| Component | CSS | data-c | Notes |
|---|---|---|---|
| Picture | `.frame-pic` | `picture` | AVPlayerLayer, aspect-fit, black. Radius 2 pt. Never under grain. |
| Region | `.region` | `region` | Amber 1.5 pt rect, 35% black outside, label tab "3 · region", 7 pt handles at corners when editing. |
| HUD tag | `.hud .glass` | `hud` | Timecode or A/B label over picture. |
| Scene strip | `.strip` | `scene-strip` | Replaces the scrubber everywhere. Scenes proportional to duration, 2 pt gaps. It runs from 0 to the end of the cut: a stretch with no story under it (a title alone on V3, black at the end) is a plain passage, unnamed, showing whatever plays there; a scene the cut comes back to has a tile each time. A tile keeps to its width: the name where it fits, then only the lock, then only the picture. Click seeks; drag scrubs; ⌥- or ⇧-drag selects a range (amber); scene context menu (frame 53). Marks row under it: pins and diamonds. States per scene: normal · current (brighter) · changed in this cut (2 pt prism top edge) · locked (grayscale 30%, hatching, lock icon before name). Tall variant 64 pt for Finish. |
| Transport | `.transport` | `transport` | Play, timecode `MM:SS:FF / m:ss`, strip, mark button. Space plays, J/K/L shuttle, ←/→ one frame, ⇧←/→ one second, N marks. |
| Timecode | `.tc` | `timecode` | SF Mono 12, tabular. Total in text-4. |

## Notes

| Component | CSS | data-c | Notes |
|---|---|---|---|
| Notes sheet | `.sheet` | `notes-sheet` | 380 pt right panel in the Cut room: head, tabs (Notes, Questions, Outside), the answered notes with each answer under its note, the notes for the next turnover, composer (`cut.md` › Answers on the sheet). |
| Note row | `.nt` | `note-row` | Number column 26 pt, amber mono number; meta row of chips (anchor, kind, script icon for script notes, region chip); text 13 pt. States: draft (italic, text-3) · written · selected (panel + 2 pt amber bar) · turned over (number gets a small diamond after it) · answered (reply line with diamond) · accepted (check chip) · reopened · dropped (strikethrough, text-4, only in "Show dropped"). |
| Composer | `.sheet-foot` | `composer` | Anchor line (`At 00:46:12` chip + anchor select: Moment, Range, Region, Scene, Whole cut, Line), text area, kinds, Add (`↩`; `⇧↩` newline). |
| Outside note row | `.nt` + `.no.out` + avatar | `outside-note` | Initials avatar 20 pt steel, name, role, Accept / Edit / Decline. |

## Editor voice

| Component | CSS | data-c | Notes |
|---|---|---|---|
| Say line | `.say` | `editor-says` | Diamond + one or two sentences, first person. Secondary line text-3. |
| Read-back | `.readback` | `readback` | Prism-edged card: header ("Here's how I read your notes"), numbered lines (`rb-line`): amber number, plan in text-1/2, right side delta or flags (`Two ways`, `Conflicts with 1`). |
| Question | `.question`, `.choices`, `.choice` | `question` | Ion border. 2–4 choices, each may show a take thumbnail. Optional "Something else…" text field. |
| Answer row | `.ans` | `answer-row` | Note number, 96 pt thumbnail with prism top edge, what changed, delta, actions (Accept, Reply). States: unreviewed · selected · accepted (55%, check) · reopened. |
| Option card | `.opt` | `option` | A or B: picture, label, one-line description, "Editor prefers" ion chip on one. Selected: 2 pt text-1 ring. |

## Overlays

| Component | CSS | Notes |
|---|---|---|
| Sheet | `.modal` over `.scrim` | Attached under the titlebar, 560 pt default width, slides down 360 ms (Glide). `esc` closes, `⌘↩` confirms. While a sheet is open, the titlebar's steel button renders as a plain inactive button under the scrim, so the sheet's confirm is the only steel button. |
| Popover | `.pop` | Arrow-less, 12 pt radius, panel fill. Settle 220 ms fade+scale from 0.98. |
| Menu | `.pop.menu .mi` | Use native NSMenu in the app; this only fixes the content and order. |
| Toast | `.toast` | Bottom-right 20 pt inset (top-right while watching through, glass). Auto-dismiss 5 s unless it has an action. |
| Tooltip | `.tip` | Native help tags are fine. |
| Banner | `.banner` | Full-width under titlebar, 36 pt. Offline, missing footage. |
| Empty state | `.empty` | Archivo title, one sentence, one action. |

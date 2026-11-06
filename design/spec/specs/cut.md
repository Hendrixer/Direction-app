# Cut room (frames 13–33)

**Room overview.** The Cut room is where a director works on a cut: watches it, notes it, hands the notes to the editor, and looks at what the editor did with them. It used to be three rooms (Screening, Notes, Changes) that showed the same picture and the same notes three ways. On 2026-11-03 they became one room, so the director's sequence (watch, note, turn over, look at the answers, watch again) happens in one place, in the order it always has. Cutting (frames 25–28, `cutting.md`) is a state of this room, not a room.

The room bar is **Script · Breakdown · Dailies · Cut · Finish**, showing only the rooms the film uses (`components.md` › Room switcher), on `⌘1`–`⌘5`. Watch through and Play changes take the whole window. Older cuts open from the cut's name in the crumb; there's no history room.

## The room

The window is split in two: the picture **stage** on `--canvas` (left, flexible) and the **sheet** on `--ground` (right, 380 wide, `--sheet-w`).

- **Stage:** the picture fitted at its aspect, with a 1 pt `--line-2` hairline just outside its edge so black in the picture reads apart from the stage around it, and the shape's tag bottom-left: a small frame drawn in the cut's shape and its name, **Vertical**, **Wide**, **Square**, **Portrait** or **Widescreen** (the ratio and size are in its tooltip; snapshot `17-tall-cut`). The shape is never a number beside a time: "9:16" next to "0:23" read as nine minutes sixteen. Then the transport. From the left: play, the time, scene strip, the four note tools (Making a note), **Play changes** (when the cut on screen has changes) and **Watch through**. Both are ghost buttons; their keys (`⇧⌘P`, `W`) are in their tooltips.
- **Times** read the way a video player says them: "0:23 / 0:53", "1:12:08" past an hour. Frames show only where they mean something and say what they are: stepping with `←` `→`, the time reads "0:23 · frame 8 of 24" for a few seconds, and its tooltip always says "0:23 and 7 frames, at 24 frames a second". Copy Time and Go to a Time use minutes and seconds.
  - Marks on the strip: amber pins for your notes not yet answered, and prism diamonds for the editor's answers in the cut on screen. In the Outside tab, steel pins for outside notes. Every changed scene has a 2 pt prism top edge.
  - The stage changes for some answers. It shows two pictures for an answer with two options (30) or for Compare (33). It shows the lock bar once everything is accepted (34, `finish.md`), and a graphic answer's card (64).
- **Sheet:** head, tabs, list.
  - Head: "Notes on Cut 4" (the cut on screen) and one status line. When you're looking back at an older cut, a ghost **Back to Cut 5** sits before the More menu.
  - Tabs: **Notes · Questions · Outside**, each with a mono count (`⌥⌘1`–`⌥⌘3`).
  - The Notes tab holds the answered notes, then the notes for the next turnover (below). Each note is written in its own row.

## Answers on the sheet

When the editor delivers a cut from your notes, each answer shows **under the note it answers**, on the sheet. Answers don't have a room of their own. The notes come first: you read what you asked, then what the editor did.

- **Answered in Cut 4** heads them: a prism diamond, then "2 to look at · 1 done". Under it is one row per answer:
  - The note's number (amber) and your words (13 pt, `--text-1`).
  - The answer: a 72 × 41 picture of the changed passage with the 2 pt prism top edge. Beside it, "**Scene.** what the editor did" (12.5 pt) with the delta after it in mono `--text-3` ("partly" in red).
  - The actions: **Accept**, **Reply** (ghost) and **Play it** (ghost). An answer with two options shows **Pick A or B** in place of Accept. An answer the editor only partly did has no Accept, and Reply is the default button.
  - Selected: `--panel` and a 2 pt editor-blue left bar.
  - The answer's tooltip says where it sits: "In Cut 4 01:08:00–01:16:20, was 01:12:08–01:21:04 in Cut 3".
- **Done** rows (accepted, an option used, or reopened) quiet down:
  - Your words are in `--text-3`, and the answer is at 70% without its picture.
  - On the right: "✓ Accepted", "✓ Used B", or an amber "Reopened" or "Reverting" chip.
  - Hovering an accepted row offers **Keep as a Rule…** when the editor read something lasting in the note (`styles.md` › Keep as a rule). Hovering a revert offers **Put back**.
- An answer you act on stays where it is, done, until you leave the room, so the list doesn't jump while you work through it.
- Once nothing is left to look at, the answered notes **fold to one line**: "Answered in Cut 4 · all 7 answered", with a chevron that opens them again. More › Show Every Answer does the same.
- **Notes on Cut 4** heads the notes under them: drafts from watching through, written notes, reopened notes, and notes with the editor. These are `.nt` rows (frame 17).
- One row is selected at a time, an answer or a note. `↑`/`↓` walk the answers, then the notes.
- A reply (32) opens in place under its row. Sending it reopens the note, which goes into your next turnover with its thread.
- Unasked changes (latitude "Take a pass") show an ion diamond in the number column and "Unasked" in place of your words.
- Right-click an answer for: Accept, Reply…, Play This Change, Keep as a Rule…, Show in Cut 3, then Revert This Change… (or Put Back).
- **Revert This Change…** opens a popover on the row:
  - It reads: "Revert note 5's change in Cut 4? This reopens note 5 and asks the editor to put it back the way it was in Cut 3. It goes into your next turnover; nothing changes until then."
  - Buttons: Cancel and Revert.
  - It's disabled for a change in a locked scene ("Unlock 5 Launch day to revert"), once a later cut changed it again, and when the note is already reopened.

## The one button

The titlebar's steel button follows what's waiting, in this order:

1. While the editor waits for your OK on its read-back: **Start cutting**.
2. While the editor cuts: **Watch Cut 3** (the cut on screen). After a failed cut: **Retry**.
3. Looking back at an older cut: **Watch Cut 2**.
4. Once you've written a note: **Turn over N**.
5. While answers wait: **Accept N**, counting the answers that can be accepted at once (an answer with two options waits for your pick). It asks first: "Accept 6 answers? They stay in Cut 4."
6. Once every answer is accepted and nothing new is written: **Lock picture…** (34).
7. Otherwise **Turn over**, disabled, with the tooltip "Write a note first".

There's no steel button while you watch through or play changes. Before the assembly has been watched, every room's button is **Watch the assembly** (`start.md` › 06).

## Turning over

Turn over hands the whole sheet to the editor at once (22). You can turn over before you've looked at every answer. What you don't push back on stays in the cut, the way it does in a cutting room:
- The answers you haven't replied to are accepted with the turnover.
- The turnover sheet says so: "2 answers you didn't reply to are kept."
- Your replies go with the turnover, as reopened notes.

## The Cut tab's count

The Cut tab's badge counts what waits on you. The editor's answers to look at and its questions come first, in its color (`--ion`). Otherwise it counts your marks still to write up and outside notes to decide, in yours (amber).

## Keys

Room keys never fire while a text field has focus.

| Key | Action |
|---|---|
| `Space` | Play / pause |
| `N` | Mark at the playhead (a draft). Never pauses. |
| `W` | Watch through |
| `⇧⌘P` | Play changes |
| `↑` / `↓` | Previous / next answer or note (seeks the picture) |
| `←` / `→` | One frame; with `⇧`, one second |
| `J` `K` `L` | Shuttle |
| `↩` | Write the selected note in its row; in the row, keep it; on an answer with two options, compare them |
| `⇧↩` | New line in a note |
| `⇥` | Accept the editor's suggested kind |
| `⌥1`…`⌥5` | Kind: Feeling, Story, Pace, Picture, Sound |
| `A` | Accept the selected answer; with two options, use A |
| `B` | With two options, use B |
| `R` | Reply to the selected answer; otherwise draw a box (a new note) |
| `⌘R` | Reply to the selected answer |
| `I` / `O` | The selected stretch starts / ends at the playhead; with none, a new two-second stretch from (or up to) here |
| `⌫` on a selected note | Remove it, with its stretch or box. Its number is retired. |
| `⌘⌫` | Revert the selected answer's change |
| `⇧⌘A` | Accept every answer that can be (asks first) |
| `⌘↩` | The one button |
| `⌘Y` | Every cut (the cuts list) |
| `⌘L` | Lock the scene under the playhead |
| `⌥⌘1/2/3` | Notes / Questions / Outside |
| `esc` | Close a reply or a comparison; stop drawing a stretch or a box; close the note being written as it was; back to the Notes tab; back to the latest cut |

## Older cuts

The cut's name in the crumb ("Cut 4 ▾") opens **every cut**, newest first, in a popover 360 wide.

- Each cut shows:
  - A diamond: prism for the latest, steel for older ones.
  - The name in Archivo 14/700, the date in mono `--text-4`, and the length right-aligned.
  - A line under it: "Answered 7 notes · 3:31 · −9 s", or for the assembly "From 31 circles · 4:12".
- The cut on screen is raised. Hovering a cut shows **Watch through** and **Compare with Cut 3**.
- Picture locks, scene locks, looks and changed words sit between the cuts as event lines with their glyph and time.
- Foot: "Every cut is kept."
- Picking a cut shows it in the Cut room: its picture, and the notes it answered with their answers, all shown and done.
  - It's for looking back: the steel button watches it.
  - Esc or **Back to Cut 5** returns to the latest.
- The cuts list also opens from Cut › Every Cut… (`⌘Y`), Go to Cut, and the scene strip's menu.

## Changing the shape

The shape is chosen in the brief (start.md › 03 · Shape). Changing it once there's a cut works the way a cutting room would:
- **Black bars** never lose picture, so Direction does it at once, as the director's own edit on the latest cut: every shot whole, with black where it doesn't reach. A toast says "Cut 4 is 9:16 now", with what was placed for the old frame ("2 titles and 1 layout were placed for 16:9. Look at them in the new shape."). The cuts list shows it as an event line, "Shape: 9:16", with the aspect-ratio glyph. `⌘Z` puts the brief and the cut back.
- **Fill the frame** loses picture, so it's the editor's, and you watch it like any cut. Direction puts the bars in at once (the cut plays in its new shape straight away) and writes a picture note on the whole cut: "Fill the 9:16 frame: crop each shot instead of the black bars." It goes in your next turnover. The editor frames shot by shot (the `reframe` skill: following faces, stacking a camera and a screen, a blurred fill where a crop would lose what matters) and answers the note once, naming the shots it made a call on. Play changes plays every shot it framed.
- Neither happens while picture is locked or while the editor is making the next cut.

A cut with shots of another shape (a phone shot in a 16:9 cut) plays them whole, with black at their sides; a note can ask the editor to fill them, or to put them on a blurred fill of themselves (`backdrop`).

**Leaving.** Going to any other room (the switcher, `⌘1`–`⌘5`) stops the cut where it is and leaves Watch through or Play changes. The playhead stays. Nothing plays in a room the picture isn't in.

---

# Watch through (frames 13–16)

**Overview.** Watch through is for watching a cut straight through, the way a director watches in a dark room: no sidebar, no edit controls, nothing that invites stopping. The only act is a **mark** (`N`), which drops an amber pin at the current time without pausing. Marks become draft notes on the sheet. The picture is letterboxed full-bleed on `--canvas`. All chrome is glass or overlay and hides after 2 s of no pointer movement.

Shared layout (frames 13–16):
- Window 1440 × 900. Picture at the cut's own aspect, fitted to the window width and centered vertically. At 2.39:1 that's 1440 × 602 at y 149. A 16:9 cut fits 900 tall and pillarboxes.
- **Titlebar overlay** (`.tb.over`): 52 tall, transparent with a 70% → 0% black gradient. Same content as the main titlebar, except the crumb has no chevrons and the right side shows the editor pill plus **Back to notes** (`esc`), a ghost button. There's no steel button in the titlebar during playback.
- **Dock** (`.dock.glass`): 960 × 54, centered, 24 from the bottom, radius 16. From the left: play/pause (ghost icon 28, 18 pt glyph), timecode, scene strip (flex), mark count chip (`.chip.d`), volume, full screen.
- Grain overlay stays on the chrome, never on the picture. In frame 14 it's off entirely.

Keys while watching through:

| Key | Action |
|---|---|
| `space` | Play / pause |
| `N` | Drop a mark at the playhead. Never pauses. |
| `⌘Z` | Undo the last mark |
| `←` / `→` | Back / forward 5 s (shows the chrome) |
| `⇧←` / `⇧→` | Previous / next scene |
| `J` `K` `L` | Shuttle |
| `F` / `⌃⌘F` | Full screen |
| `esc` or `W` | Back to notes (frame 16) |
| `⌘1`…`⌘5` | Rooms (leaving ends watching, and marks are kept) |

## 13 · Watching through
Frame: `screens/13-screening.html` · Render: `renders/13-screening@2x.png`

**Arrives from / leads to:**
- Arrives from **Watch through** in the transport or `W` in the Cut room, Cut › Watch Through (`⇧⌘↩`), **Watch through** in a ready cut's notice, **Watch the assembly**, or a cut in the cuts list.
- Leads to frame 14 (2 s idle), frame 15 (`N`) and frame 16 (end of the cut, or `esc`).

**Layout:**
- Picture: 0, 149, 1440 × 602.
- Titlebar overlay: 0, 0, 1440 × 52. Rooms control centered at 522, 12 (396 × 28).
- Editor pill: 1192, 12. Back to notes: 1275, 12 (153 × 28).
- Dock: 240, 822, 960 × 54. Play at 251, 837. Timecode at 289, 845. Strip at 410, 829 (612 × 44). Mark count at 1032, 841. Volume at 1119, 837. Full screen at 1157, 837.
- Hint: centered, 112 from the bottom, 12 pt `--text-3`.

**Content:**
- Crumb: "Launch film / Cut 3".
- Timecode: "01:12:08 / 3:40". The current time is `--text-1`; "/ 3:40" is `--text-4`.
- Strip: scenes 1–5 at flex 14, 22, 18, 26, 20, with names in 10 pt mono, ellipsized. Scene 5 is hatched and grayscale, with a lock glyph before the name.
- Two pins at 8.2% and 21%. Playhead at 32.7%.
- "2 marks" chip.
- Hint "Press N to mark a moment. Playback won't stop." Show it only the first two times a film is watched through, then never again.

**States and variants:**
- Drawn: playing, chrome visible.
- Paused: the play glyph replaces pause, the chrome stays visible, and the hint hides.
- Buffering: a `.spinner` replaces the play glyph. The timecode keeps running from the last frame shown.
- Zero marks: the mark chip reads "No marks" in `.chip.k`.
- Current scene: the strip's `.sc.cur` at 80% footage opacity.
- Changed scenes (watching a new cut): a 2 pt prism top edge on each `.sc.chg`.

**Interactions:**
- Click the picture to toggle play.
- Click the strip to seek. Drag the playhead to scrub; the picture follows, with no audio while scrubbing.
- Hover a pin to see its time in a `.tip`. Click a pin to seek to it.
- Right-click the strip for the scene context menu: Lock scene, Go to scene, Show in Script.
- The mark count chip is display only.
- Double-click the picture to toggle full screen.

**Motion:**
- Chrome shows and hides with Settle (220 ms) opacity, using `--e-out`.
- Nothing else moves during playback except the playhead and the timecode.

**Accessibility:**
- Dock items in order: Play/Pause ("Pause, Cut 3 at 1 minute 12"), timecode (a static text label), scene strip (adjustable, "Scene 3, The ridge, 1 minute 12 of 3 minutes 40"), marks ("2 marks"), Volume, Full screen.
- `N` is announced as "Mark 3 dropped at 1 minute 12".
- Focus never lands on the picture.

**Acceptance:**
- [ ] No sidebar, notes, editor text or edit controls are visible.
- [ ] `N` never pauses or stutters playback.
- [ ] The picture is fitted to width, centered, and with black letterbox bars.
- [ ] The dock is 960 wide, 24 from the bottom, glass with blur 18 and saturate 1.4.
- [ ] The titlebar has no steel button.
- [ ] Locked scene 5 is hatched and grayscale, with a lock glyph.

## 14 · Watching through, controls hidden
Frame: `screens/14-screening-quiet.html` · Render: `renders/14-screening-quiet@2x.png`

**Arrives from / leads to:**
- Arrives from frame 13 after 2 s with no pointer movement while playing.
- Leads back to frame 13 on any pointer movement or key except `N`, `space`, `J`, `K` and `L`. Leads to frame 15 on `N`.

**Layout:**
- Picture as in frame 13. Everything else is hidden, including the traffic lights and the cursor.
- Quiet timecode: 11 pt mono, `--text-4`, right 24 and bottom 20.
- Quiet mark count: a pin tinted `--steel-6` plus the count, left 24 and bottom 18.

**Content:** "01:10:21" and the pin with "2".

**States and variants:**
- Settings › General › "Show time while screening" (default on) controls the quiet timecode. When it's off, only the picture shows.
- Mark count: hidden when it's 0.

**Interactions:**
- Pointer movement returns to frame 13. `space` pauses and shows the chrome.
- Marking from this state doesn't wake the chrome; see frame 15.

**Motion:** Fade out over Settle after 2 s idle. The cursor hides at the same moment.

**Accessibility:**
- VoiceOver users never get the auto-hide; the chrome stays visible while VoiceOver is running.
- Reduce Motion has no effect here, because it's only a fade.

**Acceptance:**
- [ ] After 2.0 s idle, everything except the picture and the two quiet labels is gone.
- [ ] The quiet labels are `--text-4` and don't change brightness while playing.
- [ ] No grain overlay is drawn.

## 15 · Watching through, mark dropped
Frame: `screens/15-screening-mark.html` · Render: `renders/15-screening-mark@2x.png`

**Arrives from / leads to:**
- Arrives from frame 13 or 14 on `N`.
- Returns to the prior state after the toast's 3 s. Undo (`⌘Z`) removes the mark and the toast.

**Layout:**
- Same as frame 13.
- The new pin sits in the strip at the playhead (32.7%) with the `.mk.pin.fresh` halo.
- Toast (`.toast.glass`): right 20, top 68 (16 below the titlebar), about 292 wide. It holds a pin, a two-line text block and a ghost small **Undo** with `⌘Z`.

**Content:**
- Toast: "Mark 3 at 01:12:08", where the timecode is SF Mono. Second line: "Keep watching. Write it after."
- Mark count: "3 marks".
- Mark numbers count up within a watch. On the sheet, each mark gets the next permanent note number, so mark 3 here becomes note 3 in frame 17.

**States and variants:**
- From frame 14, where the chrome is hidden: only the toast appears, top-right. The dock stays hidden. The quiet mark count updates to 3.
- Two marks within 1 s merge into one, and the toast re-times. Marks closer than 0.5 s are ignored.
- Marking inside a locked scene is allowed. The draft note is flagged on the sheet.

**Interactions:**
- `⌘Z` or **Undo** removes the mark.
- The toast doesn't take focus and can't be clicked except for Undo.
- Hovering the toast pauses its 3 s timer.

**Motion:**
- The pin drops from 6 pt above (`drop`, Settle).
- The halo fades over 900 ms.
- The toast enters with Glide (360 ms) from 8 pt right plus opacity, and leaves with Settle opacity.
- With Reduce Motion, all of these are opacity only.

**Accessibility:**
- Announce "Mark 3 at 1 minute 12" politely; don't interrupt.
- The toast isn't in the focus order. Undo is reachable through `⌘Z` only.

**Acceptance:**
- [ ] Playback doesn't pause or drop frames when the mark is made.
- [ ] The pin appears at the playhead within one frame.
- [ ] The toast disappears after 3 s, or stays while hovered.
- [ ] Undo restores the previous count.

## 16 · Back from watching through
Snapshot `16-watch-back`

**Arrives from / leads to:**
- Arrives from the end of the cut, `esc`, `W` or **Back to notes** while watching through.
- It's frame 17's room: the sheet, with the marks from this watch waiting as drafts.

**Content:**
- The marks are notes with no words yet, the first one open to write in its row. ↩ keeps it and opens the next mark from this watch.
- The playhead sits on the first mark.
- Without marks, the room is as you left it, the playhead where you stopped.

**States and variants:**
- There's no end card. Watch again is `W`; Lock picture is the steel button once everything is accepted.
- Notifications held while watching (Settings › Notifications) arrive now.

**Acceptance:**
- [ ] Nothing asks for a click between the end of the cut and the sheet.
- [ ] The first mark of this watch is selected and its moment is on screen.
- [ ] Marks from an earlier watch stay where they are.

---

# Writing notes (frames 17–24)

The sheet is the notes session. The director writes up marks as numbered notes, gives each a kind, triages outside notes, answers the editor's questions, and turns the whole sheet over at once. After turnover, the sheet shows the editor's **read-back** for approval.

**"@" names something in the library** (techniques.md › The library): typing "@" in any note field opens a list at the "@" (icon, name, one line; up to six that match what follows the "@"), ↑↓ move, ↩ or ⇥ picks and writes "@Name ", esc closes it. Names from the library show in the director's amber. The editor reads what each named one is and how to make it with the note.

**"@" names footage too** (Naming footage): the film's scenes, setups and takes are in the same list, by the names Dailies shows: "Scene 2" (its title under it), "2A" (what it is and its scene), "2A Take 3" (its caption, and Circled when it is). A take with no setup is "Scene 4 Take 2"; one not in a scene yet goes by its file's name ("MVI_0001", "Not logged yet"). With nothing typed after the "@" the library comes first; after that both are searched, names that start with what's typed first, and words in a caption find its take ("@laughs"). Their icons: `film` for a scene, `video` for a setup, `play.rectangle` for a take. Only whole names count, longest first, so "@2A Take 3" is the take, not the setup, and "@Scene 2" isn't found in "@Scene 20". The editor reads each named one with the note (the turnover's `footageNamed`, and under the note in its job): which take it is (its file and assetID), its scene and setup, its caption, circled or not usable, and where it is in the cut ("In the cut at 1:10–1:22", or "Not in the cut"); a setup or scene with its takes and the circled ones. It uses that take, not one that seems like it.

## Making a note

A note starts by pointing at something, and it's a note at once: it's on the sheet straight away, with no words yet, and its row opens to write in. There's no separate place to type a note and no anchor to choose. On 2026-11-05 a director drew a box, took it away, drew another later in the cut and wrote a note on it; the note was saved at the first box's moment, because the composer kept the time it pinned for the first box. Notes made at once can't do that.

The four tools sit under the picture, after the strip, each a ghost icon with its key and gesture in its tooltip. The same icon is on every note's chip, so a note says what it's on:

| Tool | Icon | Makes |
|---|---|---|
| Mark this moment (`N`) | the amber pin | a note on this frame |
| Mark a stretch | `arrow.left.and.right` | turns on; the next drag along the strip draws a stretch and letting go makes its note. `⌥`- or `⇧`-drag on the strip, and `I` / `O`, do the same without the tool. |
| Draw a box (`R`) | `viewfinder` | turns on; the next drag on the picture draws a box and letting go makes its note, on this frame. |
| Note on the whole cut | `text.bubble` | a note on the whole cut |

A scene's menu on the strip has **Note on This Scene** (`film`). While a tool is on, its icon is amber on the amber wash, a glass hint sits at the top of the picture ("Drag along the timeline to mark a stretch. esc cancels." / "Drag a box around what you mean. esc cancels."), and `esc` or the tool again turns it off with nothing made. Turning one on pauses the picture.

- **Writing it.** The new note's row opens: its chip, the field ("What should it feel like?"), the kinds, and **Done ↩** under them. `↩` keeps the words, `⇧↩` adds a line, `esc` closes it as it was. A note left with no words stays on the sheet, "Click to write this note.", and a click opens it. Making another note, or picking another, keeps what was typed in this one. Written notes open again with a double-click, `↩` or Edit Note.
- **While it plays.** `N` while the cut plays, or while watching through, only drops the mark: the picture never stops and the mark waits to be written. Paused, its row opens.
- **Many at once.** Each stretch, box or mark is its own note; there's no single one being made. The selected note's stretch shows on the strip with grips (pull either end, drag the middle to move it), and its box shows on the picture for ±12 frames around its moment with handles (drag to move, a handle to resize, `⇧` keeps its shape). Letting go keeps the change on the note; what it rests on in the footage and the words under it move with it. A drag on the picture away from the box draws a new box, and a new note.
- **Taking it away.** A note's hover shows **✕** (Remove, `⌫`) beside its More menu; it goes with its stretch or box, and `⌘Z` puts it back. **Remove Box** (the note's menu, or the picture's) takes only the box away and leaves the note on its moment.
- Turned-over notes, outside notes and an older cut's notes show their stretch and box but can't be moved.

Shared layout (frames 17–24, in pt):
- **Titlebar:** 0, 0, 1440 × 52.
  - Crumb: film and cut menus with chevrons.
  - Rooms: centered. The Cut tab's count: see The Cut tab's count.
  - Right side: editor pill, Share (ghost icon), then the primary.
- **Stage:** 0, 52, 1060 × 848.
  - Viewer padding 28/28/8. The picture fits width at its aspect: 1004 × 565 at 28, 171 for 16:9.
  - The shape's tag (glass): bottom-left, 12 inset.
- **Transport:** 0, 834, 1060 × 66.
  - Play (28 icon btn), the time, scene strip, the four note tools (ghost icons: the amber pin, stretch, box, whole cut), then Play changes and Watch through.
  - Note pins show in the strip, and the selected note's stretch as a `.range` band with grips. Outside people's marks use `.mk.pin.out` (steel).
- **Sheet:** 1060, 52, 380 × 848. It's a grid with four rows: head, tabs, list (scrolls), foot.
  - Head: `.brand-m` title and a 12 pt status line.
  - Tabs: Notes, Questions, Outside, each with a mono count.
  - Note rows (`.nt`): 26 number column, about 69 tall for one line of text. Selected rows get a `--panel` background and a 2 pt amber left bar.
- No foot: notes are written in their rows.

## 17 · Notes, drafts after watching through
Frame: `screens/17-notes-drafts.html` · Render: `renders/17-notes-drafts@2x.png`

**Arrives from / leads to:**
- Arrives from frame 16, or the Cut tab (`⌘4`).
- Leads to frame 18 (click a note with no words, or start typing on it), frame 19 (`R`) and frame 22 (**Turn over**).

**Layout:**
- Picture: 28, 171, 1004 × 565.
- Strip: 187, 840 (809 × 44).
- Sheet tabs: 1061, 129 (379 × 49). Note rows from y 178, each about 69 tall.
- Primary: 1304, 12 (124 × 28).

**Content:**
- Title "Notes on Cut 3". Status line "2 written · 2 waiting for words".
- Tabs "Sheet 4 · Questions 0 · Outside 0".
- Notes 1 and 2 are written: chips "0:18" Pace and "0:46–0:58" Feeling, each with its tool's icon (the pin, the stretch), with their text from story.md.
- Notes 3 and 4 have no words yet: chips "1:12" and "1:43", each with the pin. The italic `--text-3` line reads "Click to write this note."
- Primary: "Turn over 2". It counts written notes only.
- Note text wraps to any number of lines. Chips never wrap inside themselves; the meta row wraps between chips.

**States and variants:**
- Drawn: drafts present, note 2 selected.
- Empty sheet: the list shows the empty state, "No notes on Cut 3 yet." with "Press N to mark a moment, or point at something with the tools under the picture." and a ghost **Watch Cut 3** button. The primary is disabled and reads "Turn over".
- Hover on a row: `--panel` background, a ghost **✕** (Remove, `⌫`) and a ghost `more` icon at the right. Its menu: Play from Note, Write / Edit Note, Kind, Copy Time, Copy Link, Show Its Answer, Remove Box (a box note), Remove Note.
- Drafts in a locked scene: an extra `.chip.ui` with a lock icon and "Locked scene", and the tooltip "The editor can't change this scene. Unlock it, or keep the note for later."
- Written notes open in their row on double-click until turnover.

**Interactions:**
- Click a written note to select it and seek the picture to it (a stretch starts at its in point). Click a note with no words to open it.
- Click a strip pin to select that note.
- Type with a note with no words selected to start writing it (see frame 18).
- **Turn over** opens frame 22. It's disabled while drafts are the only notes.
- Drafts don't block turnover; they stay behind as drafts.

**Motion:**
- Selection changes are instant.
- A new note row inserts with Settle (height plus opacity).
- The badge count changes with Snap.

**Accessibility:**
- The list is a table named "Notes on Cut 3". Each row reads "Note 2, Feeling, 46 seconds to 58 seconds: I want to feel how tired she was here. Let it sit."
- Notes with no words read "Note 3, mark, 1 minute 12, no words yet".
- Focus order: titlebar, picture controls, tabs, list.

**Acceptance:**
- [ ] Note numbers are amber SF Mono 14 semibold and never change.
- [ ] Draft text is italic `--text-3`, written note text is `--text-1`.
- [ ] Turn over counts only written notes.
- [ ] Every anchor shows in the strip; the selected note's pin matches the playhead.
- [ ] The sheet is exactly 380 wide at every window width.

## 18 · Writing a note
Snapshot `18-notes-writing`

**Arrives from / leads to:**
- Arrives from frame 17 (click note 3, start typing on it, or make a new note), or from any of the four tools.
- **Done ↩** keeps it; a mark from this watch opens the next one.

**Layout:** as frame 17. Row 3 is open: its chip, then the field (`.field.focus`, 44 tall, growing to 160), the kinds row, and a line with the suggestion hint on the left and **Done ↩** (small, regular) on the right. The row never grows past the sheet's width.

**Content:**
- Field: "Tighter on her. The sky is winning", with the caret at the end.
- The kind suggestion appears once the text is at least 3 words: "Editor suggests Picture. Press ⇥ to take it." Only "Editor suggests Picture." is in `--agent`.
- Primary still reads "Turn over 2". Turn over keeps what's being written first.

**States and variants:**
- Kind chosen: that kind is `.kind.on`, the suggestion styling is removed, and the hint hides.
- Kind left empty: the note saves without a kind. The editor proposes one at read-back ("Picture?").

**Interactions:**
- `⇥` accepts the suggestion. Click any kind to set it; click again to clear. `⌥1`…`⌥5` pick one.
- `esc` closes it as it was; a note with no words stays a mark.
- The kind suggestion runs on-device; the editor doesn't see the note's text until turnover.

**Accessibility:** the field is labeled "Note 3 words". Kinds form a radio group, "Kind", that can be empty.

**Acceptance:**
- [ ] The suggested kind uses ion blue and the diamond, never amber and never preselected.
- [ ] Moving the playhead while writing never moves the note.
- [ ] Making another note keeps these words.

## 19 · A box
Snapshots `19-notes-region` (note 3's box, being written), `19b-notes-drawing-box` (Draw a box on, half drawn), `19c-notes-stretch` (note 4's stretch selected on the strip)

**Arrives from / leads to:** Draw a box (`R`, the box under the picture, or the picture's menu), then a drag on the picture: letting go makes the note and opens frame 18 on it. `esc` while drawing makes nothing.

**Layout:**
- The box (`.region`): 1.5 pt amber border, radius 2, and outside it a 35% black dim. A tab label "3 · box" sits above its top-left corner. Eight 7 × 7 amber handles while it's drawn or hovered.
- While drawing: a glass hint centered 14 from the picture's top, "Drag a box around what you mean. esc cancels.", and a size HUD bottom-right ("24 × 58%").

**States and variants:**
- One box per note. A drag on the picture away from the selected note's box draws a new box and a new note.
- The selected note's box shows for ±12 frames around its moment, and moves and resizes until it's turned over.
- Playback pauses while drawing.

**Accessibility:** the box is announced as "Region, 24 by 58 percent, at left 31, top 20".

**Acceptance:**
- [ ] Box color is `--director` only; coordinates are fractions of the frame.
- [ ] A box drawn after another was taken away is on its own frame (the 2026-11-05 bug).
- [ ] The label tab reads "<note number> · box".

## 20 · The editor's questions
Frame: `screens/20-notes-questions.html` · Render: `renders/20-notes-questions@2x.png`

**Arrives from / leads to:**
- Arrives from the editor raising a question while cutting. Clicking the "1 question" editor pill or the Questions tab gets here.
- **Answer** sends the choice, and the editor continues (frame 25). With no other questions open, the tab returns to Sheet.

**Layout:**
- The sheet's Questions tab is active. Content padding is 14/12.
- The question card (`.question`) is 355 wide, with an ion border at 35%. From the top:
  - Header: diamond, "Editor asks" in `--agent` 500, and the time on the right.
  - Body: 13.5 pt.
  - "Holds" row.
  - Three `.choice` rows, each with a 64 × 36 thumbnail.
  - A free-text input.
  - The steel **Answer** button, right-aligned.
- The sheet foot shows cutting progress: diamond, text, time estimate, and a `.progress.agent` bar.
- The stage shows the moment in question: picture at 00:52:16, dimmed to the take in focus.
- Titlebar: the editor pill is `.agent.asks` "1 question". There's no titlebar primary, because the steel button is in the card.

**Content:**
- Status line: "Turned over · the editor is cutting Cut 4".
- Tabs: "Sheet 7 · Questions 1 · Outside 0".
- Question: "Line 12 has two good readings. T2 is warmer; T5 sounds more tired, which fits note 2. Which one?"
- "Holds" chip, then an amber "2" chip, then "Everything else keeps cutting."
- Choices:
  - **Use T2**: "2A · "Editing was the part nobody wanted.""
  - **Use T5** (selected): "2A · slower, a breath before "nobody""
  - **Cut both ways**: "You pick on the sheet"
- Input placeholder: "Or tell me in your words…"
- Caption: "Answered questions stay here, under the note they belong to."
- Foot: "Cutting Cut 4 · 3 of 7 notes", "about 2 min", progress at 42%.

**States and variants:**
- Several questions: they stack as cards, oldest first. The tab count and pill read "2 questions".
- Answered: the card collapses to one `.say` line: "You chose T5." in `--text-3`. A copy also appears in the note's thread on the Sheet tab.
- No choice selected: **Answer** is disabled, unless the input has text.
- Questions that block the whole cut (no "Holds" row): the foot reads "Waiting for you", and the pill uses `.agent.asks` without the meter.

**Interactions:**
- Click a choice to select it (radio).
- Click a choice's play glyph, or its thumbnail, to play that take in the stage. `space` plays it.
- Typing in the input deselects the choices.
- `↩` sends. `⌘1`…`⌘3` pick a choice while the card is focused.

**Motion:**
- New questions slide in from 8 pt above with Glide.
- The pill changes state with a Snap crossfade.
- The progress meter moves continuously, with no shimmer on the bar itself; the pill shimmers when Cutting.

**Accessibility:**
- The card is a group labeled "Question from the editor".
- Choices are a radio group. Each thumbnail's label is the take code.
- When a question arrives, it's announced: "The editor has a question about note 2."

**Acceptance:**
- [ ] The card uses ion and the diamond only. No amber except the "2" note-number chip.
- [ ] 2–4 choices, plus optional free text.
- [ ] Answering never requires leaving the room.
- [ ] The steel button is in the card, and there's none in the titlebar.

## 21 · Outside notes inbox
Frame: `screens/21-notes-outside.html` · Render: `renders/21-notes-outside@2x.png`

**Arrives from / leads to:**
- Arrives from someone with a screening link leaving notes (see share.md). The toast "Priya left a note on Cut 3" or the Outside tab gets here.
- **Accept** turns the item into a numbered note on the Sheet, with the next number and the person's initials. **Edit first** accepts it and opens it in its row to write. **Decline** removes it.

**Layout:**
- The Outside tab is active.
- An info row (eye icon, 12 pt `--text-3`) sits under the tabs.
- Outside cards (`.on-card`), each with these parts:
  - A 22 avatar with initials in steel.
  - Name 600, plus role and time in `--text-3`.
  - A neutral anchor chip (`.chip`, never amber).
  - Text.
  - Actions in `.btn.sm`.
- Foot: link icon, link status, and **Manage** (ghost small).
- The strip shows outside marks as steel pins (`.mk.pin.out`) at 40.9%, 57% and 95.5%.

**Content:**
- Status line: "6 written · 3 from people you shared with".
- Tabs: "Sheet 6 · Questions 0 · Outside 3".
- Info: "The editor won't see these until you accept them."
- Cards:
  1. Priya Shah, Producer · 1 h ago. "Scene 4". "Show the team earlier, it feels like she did it alone." Actions: Accept · Edit first · Decline.
  2. Tom Reyes, Client · 40 min ago. "03:31:00". "Can the logo be bigger at the end?" Same actions.
  3. Tom Reyes · 38 min ago. "01:30:00" plus "No change asked". "Love the ridge shot." Actions: Got it · Make it a note.
- Foot: "Screening link for Cut 3 · 2 people".
- Primary: "Turn over 6". The Notes badge reads 3.

**States and variants:**
- Empty: the empty state reads "No outside notes." with "Share a screening link to collect notes from your producer or client." and a ghost **Share Cut 3…** button.
- Accepted: the card leaves the inbox. On the Sheet, the new note shows its number in `.no.out` (steel) and an `.av.s` avatar chip in its meta.
- Declined: the card collapses with Settle. "Undo" stays in a toast for 5 s.
- Reaction detection ("No change asked") is a heuristic on-device classifier. The director can still make it a note.
- Notes left on an older cut: an extra `.chip.ui` reads "On Cut 2", and Accept re-anchors to the same moment in the current cut.

**Interactions:**
- Click a card to seek to its anchor.
- Accept is `⌘↩` on the focused card, Decline is `⌫`, and Edit first is `E`.
- Hovering an avatar shows their email and the link they used.

**Motion:** Cards leave with Settle (height plus opacity). Accepted notes appear in the Sheet count with Snap.

**Accessibility:** Each card reads "Priya Shah, producer, scene 4: Show the team earlier… Actions: Accept, Edit first, Decline."

**Acceptance:**
- [ ] Outside content never uses amber.
- [ ] The editor never receives an outside note's text before acceptance.
- [ ] Accepted notes get the next permanent number.
- [ ] Reactions can't be turned over without "Make it a note".

## 22 · Turnover sheet
Frame: `screens/22-turnover.html` · Render: `renders/22-turnover@2x.png`

**Arrives from / leads to:**
- Arrives from **Turn over N** in the titlebar, or `⌘↩` in the Cut room.
- **Turn over** sends the notes. With "Wait for my OK" on, it leads to frame 23; with it off, frame 25. **Cancel** or `esc` returns to frame 17.

**Layout:**
- A 55% scrim covers the window.
- The sheet (`.modal`) is 600 wide, attached under the titlebar at 420, 52, and 685 tall at this content. Corner radius is 0 0 14 14.
- Head: `.brand-l` title and a 12 pt subtitle.
- Body, in order:
  - The note list (`.tlist`, 556 wide; rows 36 tall, columns 22 / 64 / text / kind).
  - The "How much room" label and three radio cards (`.rcard`), with the selected one at 61 tall and a 1.5 pt `--text-1` ring.
  - The "Wait for my OK" checkbox.
- Foot: a caption on the left, then Cancel and steel **Turn over ⌘↩**.
- The titlebar's own Turn over becomes an inert regular button under the scrim, so only one steel button shows.

**Content:**
- Title: "Turn over 7 notes". Subtitle: "The editor reads back its plan for each note, and cuts Cut 4 when you OK it." (With the checkbox off: "…, then cuts Cut 4.")
- Rows 1–7: number, the anchor's start (`00:46:00`, `Line 14`, `Scene 4`) and the text ellipsized to one line.
  - Row 7 shows "· Priya Shah" and a steel number.
  - Each row ends with its kind.
- Latitude cards:
  - "Do what I wrote": "Change only what each note names. No options."
  - "Read between the lines" (default; it's the film's latitude): "Interpret the intent. Try Feeling notes two ways."
  - "Take a pass": "Also suggest changes you didn't ask for, marked Unasked."
- Checkbox: "Wait for my OK before cutting" (default from Settings › Editor). It's about cutting, not the editor's questions, which always wait for you.
- Caption: "Notes can't be edited after turnover, only replied to."

**States and variants:**
- Notes without a kind: the kind cell reads "—", and the editor proposes a kind in the read-back.
- Drafts present: a line above the list reads "2 drafts stay behind." in `--text-3`.
- Answers not looked at yet: the same line adds "2 answers you didn't reply to are kept." They're accepted with the turnover (Turning over).
- A note anchored in a locked scene: its kind cell is replaced by a lock chip, and the caption adds "1 note touches a locked scene. The editor will ask before unlocking." (Only recutting needs the unlock; color and sound notes go ahead.)
- Latitude changes here apply to this turnover only. The film default lives in Settings › Editor.

**Interactions:**
- `↑` / `↓` move between the latitude cards; `space` selects.
- `⌘↩` turns over and `esc` cancels.
- Clicking a row closes the sheet and selects that note, which acts as a quick edit.

**Motion:**
- The sheet slides down from under the titlebar with Glide (y −16 → 0, plus opacity). The scrim fades in with Settle.
- On turnover, the sheet leaves with Settle. The editor pill shows "Reading back" with the shimmer.

**Accessibility:**
- It's a modal dialog, "Turn over 7 notes".
- Focus starts on the selected latitude card, then goes to the checkbox, Cancel and Turn over.

**Acceptance:**
- [ ] Exactly one visible steel button.
- [ ] It lists every written note, and only written notes.
- [ ] The latitude defaults to the film's setting.
- [ ] After turnover, the notes become read-only and the Notes badge clears.

## 23 · Read-back, waiting for your OK
Frame: `screens/23-readback.html` · Render: `renders/23-readback@2x.png`

**Arrives from / leads to:**
- Arrives a few seconds after turnover (frame 22).
- **Start cutting** (`⌘↩`, in the titlebar or the foot) leads to frame 25. Clicking a line, or **Change a line**, leads to frame 24.

**Layout:**
- The sheet head reads "Read-back for Cut 4".
- The read-back block (`.readback`, 1 pt prism border) is 355 wide at 1073, 192. Inside:
  - Header: diamond, "Here's what I'll do", and the latitude in `--text-4` on the right.
  - Lines (`.rb-line`: columns 24 / text / right). Each has the plan in `--text-1` 500 and the source note in 11.5 pt `--text-4`, quoted and ellipsized. The right column holds a delta (`.delta`) or a chip.
  - One conflict callout (`.conflict`) sits right after the higher-priority note.
- Foot: a length estimate, the caption "Nothing is cut until you say so. Click a line to change it.", then a ghost **Change a line** and, on the right, a default-style **Looks right, start cutting ⌘↩** (the titlebar's Start cutting, where the director is reading; it isn't steel, so the titlebar's stays the only steel button). A first director typed "sounds good" into a line's correction to approve, because the only approval was in the titlebar.
- Titlebar: the pill is `.agent.ready` "Read-back ready", and the primary is steel "Start cutting ⌘↩".
- The stage follows the line you hover: hover seeks the picture.

**Content (exact):**
1. "Drop the second street wide. On her face by 0:09." −4.2 s
2. "Two ways: hold on her (+1.6 s), or cut to the window and back." `2 ways` (`.chip.a`)
   - Conflict: "**Notes 2 and 1 overlap at 00:25–00:46.** Following 2 (Feeling) over 1 (Pace) there. Flip it"
3. "Reframe to about 1.6× on Maya; sky down to a third." crop
4. "Music down 6 dB under her line, back up at the cut." −6 dB
5. "Strike line 14." −3.1 s
6. "Drop the second whiteboard shot." −2.0 s
7. "Open scene 4 on the team. The best team shot is in Launch day, which is locked; I'll look for another." (source "· Priya Shah"; the number is steel)

Foot: "About 3:31 after these changes. Target 3:00–4:00."

**States and variants:**
- Reading back (before it arrives): the block shows a shimmer skeleton of 7 rows. The pill reads "Reading back", and the primary is disabled.
- Approval not required (Settings off): the read-back appears the same, but the primary is absent, the pill reads "Cutting 0 of 7", and the head reads "Read-back · cutting now".
- Over target length: the foot text uses `--alert` and adds "4:12 is over your 4:00 target."
- Flip it: this swaps the conflict's priority and rewrites lines 1 and 2 (frame 24 behavior).
- Lines the editor can't fulfill: the right column shows a `.chip.bad` "Can't". The line explains why, and the plan text ends with a choice link.

**Interactions:**
- Hover a line to seek the stage to that note's anchor.
- Click a line to edit it (frame 24).
- `⌘↩` starts cutting. `esc` does nothing here; the read-back stays until you act.
- **Take back turnover** is in the `more` menu of the sheet head. It returns the notes to written.

**Motion:**
- When it arrives, the lines appear top to bottom, 40 ms apart, with Settle opacity. With Reduce Motion they all appear at once.
- The pill crossfades with Snap.

**Accessibility:**
- It's a list named "Read-back for Cut 4". Each line reads its number, plan and delta, then "for note: <text>".
- The conflict is a separate item with a "Flip it" button.

**Acceptance:**
- [ ] One line per turned-over note, in note order.
- [ ] Every line has concrete numbers (s, dB, ×, or a named shot).
- [ ] The conflict cites both numbers and both kinds.
- [ ] Nothing is cut until Start cutting is pressed (when approval is required).

## 24 · Read-back, adjusting a line
Frame: `screens/24-readback-adjust.html` · Render: `renders/24-readback-adjust@2x.png`

**Arrives from / leads to:**
- Arrives from clicking line 3 in frame 23.
- **Update line ↩** sends the correction. The line shows a shimmer while the editor rewrites it, then returns to frame 23 with the new plan. **Cancel** or `esc` restores it.

**Layout:**
- Line 3 becomes `.rb-line.edit`: a `--raised` background with a 1 pt `--line-2` ring, 8/6 padding, extending 6 beyond the line on each side.
- Under the source quote is a focused `.field.area` (52 min height).
- Then the caption "Say what to change and the editor rewrites this line. If it's right as it is, start cutting instead."
- Then a right-aligned row: ghost small **Cancel** and small **Update line ↩**.
- The list scrolls inside the sheet's third row, with a 28 pt fade at the bottom (`.scroll-fade`). The foot stays pinned.

**Content:**
- Line 3 plan: "Reframe to about 1.6× on Maya; sky down to a third."
- Correction: "Not that tight. Keep the horizon, just lose some of the sky", with the caret.
- Expected rewrite after Update: "Reframe to about 1.25×, horizon kept; sky down to about half." crop.

**States and variants:**
- Updating: the edit box collapses, line 3's text shows a shimmer skeleton for ≤ 3 s, and the pill reads "Reading back".
- An unclear correction: the editor replies inline in `.say`, for example "Do you mean keep the whole horizon line, or just keep it in frame?", with two choice buttons.
- Several lines can be corrected before Start cutting. Each correction is recorded in that note's thread.

**Interactions:**
- `↩` updates and `⇧↩` adds a new line.
- `esc` cancels.
- While editing, Start cutting stays enabled. Pressing it sends the correction first, then starts.

**Motion:** The edit box expands with Settle (height). The rewrite fades in with Settle.

**Accessibility:**
- The field is labeled "Correction for note 3".
- After an update, "Line 3 updated" is announced.

**Acceptance:**
- [ ] Corrections never edit the original note text. They're stored as replies on the note.
- [ ] Only one line is in edit mode at a time.
- [ ] The foot and the titlebar primary stay visible while the list scrolls.

---

# The editor's answers (frames 29–32)

Every change points to one note number. The director reads each answer under its note, plays only what moved, picks between options, and accepts or replies one answer at a time. Styles are in `css/changes.css`.

## 29 · A new cut arrived
Frame: `screens/29-changes.html` · Render: `renders/29-changes@2x.png` · Snapshot `29-changes`

**Arrives from / leads to:**
- Arrives from 25 when Cut 4 finishes. The Cut room moves to it on its own while you're watching the latest cut.
- Leads to 31 (Play changes), 30 (Pick A or B), 32 (Reply), 33 (every cut) and 34 (all accepted).

**Layout:**
- The sweep edge (`.sweep-edge`) is a 2 pt prism line at y 52, full width, directly under the titlebar.
- The notice sits at left 24, bottom 96, over the stage.
- The sheet shows "Notes on Cut 4", the status line, then Answered in Cut 4 with every answer under its note (Answers on the sheet).

**Content:**
- Pill: "Cut 4 ready" with a prism diamond. It returns to "Ready" once the director plays changes or accepts anything.
- Cut tab: 7, in the editor's color. Steel button: **Accept 6**.
- Status line: "3:31 · 9 s shorter than Cut 3".
- Rows (see `story.md`):
  1. Pace, −4.2 s.
  2. Feeling, "A / B", with the single action "Pick A or B".
  3. Picture, crop.
  4. Sound, −6 dB.
  5. Story, −3.1 s.
  6. Pace, −2.0 s.
  7. Story, 0.0 s.
- Notice: "Cut 4 is ready", sub "7 answers · 46 s of changes to watch", with **Watch through** and **Play changes**. Nothing starts playing on its own.
- The answer text wraps to four lines at most, then ends in an ellipsis. Hovering shows where the change sits.

**States and variants:**
- The editor's open questions wait in the Questions tab, counted in its color.
- Accepted rows stay done until you leave; then the answered notes fold (Answers on the sheet).
- If an answer failed partially, its delta reads "partly" in red and Reply is the default button.

**Interactions:**
- Click a row to select it and cue the picture 2 s before its change (the handle).
- Keys:
  - `A` accepts the selected answer, `R` replies, and `↑`/`↓` select.
  - `⇧⌘P` plays changes.
  - `⇧⌘A` accepts every answer that can be, and asks first.
- Double-clicking a row plays just that change (31, starting at it).

**Motion:**
- On arrival, the sweep runs one pass left to right (`--t-sweep` 900 ms, `--e-inout`). It then holds as a static 2 pt line for 2.4 s before fading out (Settle).
- The notice slides up 12 pt and fades in (Settle), and auto-dismisses after 8 s. It stays while hovered.
- With Reduce Motion, the sweep appears instantly and fades.

**Accessibility:**
- On arrival VoiceOver says "Cut 4 is ready. 7 answers."
- Each row reads as "Note 1, Cold open takes too long to get to her face, Cold open, Cut the second street wide; we're on her face by 0:09, minus 4.2 seconds", then its buttons.

**Acceptance:**
- [ ] The sweep plays exactly once per new cut and never during playback. If playback is running, it waits until pause.
- [ ] Every answer row shows its note number; no change exists without one, except Unasked rows.
- [ ] The Cut tab's count is the answers to look at plus the editor's questions.
- [ ] Deltas use a true minus sign (U+2212) and one decimal place.

## 30 · Two options
Frame: `screens/30-changes-options.html` · Render: `renders/30-changes-options@2x.png`

**Arrives from / leads to:** 29, via "Pick A or B" or by selecting answer 2. Using A or B puts that version in the cut and returns the stage to the picture, with answer 2 done ("Used B"). "Neither, reply" leads to 32.

**Layout:**
- The stage becomes two `.opt` cards side by side: 24 pt padding, 14 pt gap, 16:9 frames, steel-1 card fill.
- Each card has its letter HUD at top left (glass) and a label row: "Option A" in Archivo 14/800, the description, and the delta at right.
- The picked or recommended card isn't rings-selected until chosen. The frame shows B focused (2 pt text-1 ring) after the director clicked it.
- Options foot: the note quote and the editor's reasoning, then the buttons Use A, Use B and the ghost "Neither, reply".
- Transport: one shared playhead drives both pictures, plus a "Synced" indicator with a link icon.

**Content:**
- "Option A · Hold on her · +1.6 s".
- "Option B · Window, then back · [I'd pick this] · 0.0 s".
- Foot: "**Note 2 · Feeling.** "I want to feel how tired she was." B keeps the length and lets the silence do it. A is more direct."
- Badge: 6. Answer 1 is shown Accepted.

**States and variants:**
- Audio: only the hovered or focused option plays sound. The other is muted, and a speaker glyph shows on the active card.
- The "Synced" toggle can unlink the two pictures to scrub them separately. When unlinked, two transports appear, one under each card.
- More than two options never occur; the editor offers exactly two.
- When the director has picked, the chosen card shows a green "Using B" chip and the buttons collapse into "Change pick". Change pick brings back Use A and Use B; using the other one swaps it into the cut.
- The editor delivers the two ways as two revisions that differ only where the note is; the one committed last is in the cut. Using the other swaps those shots wherever they sit in the cut now, as a new revision, so changes for other notes stay. A music bed under them stays as it is unless the two versions differ in it.
- If the swap would recut a locked scene, or picture is locked, nothing changes and the error says to unlock first. If the cut changed around the note since, it says "Reply to ask the editor for it."
- Options that aren’t versions of the cut (looks) only record the pick.

**Interactions:**
- Click a card to make it the audible one.
- `1`/`2` switch audio between A and B. `⇧1`/`⇧2` use A or B. `Space` plays both. `Esc` returns to the picture without choosing.

**Motion:** Card focus ring with Snap. On choice, the unchosen card fades to 40% (Settle) before the stage returns to single picture (Glide).

**Accessibility:** The cards are a radio group, "Options for note 2". The editor's preference is read as "Editor recommends B". Use A and Use B have explicit labels.

**Acceptance:**
- [ ] Both pictures stay frame-locked within one frame during playback.
- [ ] The editor's preference is shown only as a chip and is never selected for the director.
- [ ] Using an option puts its version in the cut as a new revision: Watch through, Play changes and Deliver play it, and answers after it move with it.
- [ ] ⌘Z, or Change pick and the other option, puts the other version back.
- [ ] Both versions stay playable side by side here, and the unchosen one stays retrievable in its cut (33).

## 31 · Play changes
Frame: `screens/31-play-changes.html` · Render: `renders/31-play-changes@2x.png`

**Arrives from / leads to:** **Play changes** in the transport (`⇧⌘P`), **Play it** or a double-click on an answer, or the ready cut's notice. `Esc` or **Back to notes** returns to the sheet with the last-played answer selected.

**Layout:**
- Full picture like Watch through (frame 13): canvas black, 2.39:1 or native aspect fitted to width, titlebar overlay with a gradient and no room switcher. The crumb reads "Launch film / Cut 4 / Only what changed"; the right side has the editor pill and **Back to notes** (`esc`).
- Change tag HUD at left 24, top 76: a glass chip with a 14 × 2 pt prism bar and "CHANGED · NOTE 3" (mono 11, uppercase). During handles it reads "HANDLE · CUT 3 PICTURE" with no prism bar.
- Dock: glass, 1000 pt wide, bottom 24, radius 16, two rows.
  - Top row: the note chip, "**Scene.** answer", then the reel progress (`.reel-dots`, one 18 × 3 pt dash per change) and "3 of 7".
  - Bottom row: previous change, play/pause, next change, the reel timecode "01:13:02 / 0:46", the change strip, "2 s handles", Reply (ghost), and Accept (steel).
- Change strip (`.cstrip`): the current change and its handles only. The handles are hatched, and the changed span has a 2 pt prism top and brighter footage.

**Content:** Change 3 of 7: "The ridge. Reframed to 1.6× on Maya; sky is now a third of the frame." The timecode shows the position in Cut 4, and the total is the reel length.

**States and variants:**
- Options answers play A, then B, back to back, and the tag reads "OPTION A · NOTE 2". Accept is replaced by "Use A" and "Use B" (B steel only if already picked; otherwise both default).
- An accepted change shows a green "Accepted" in place of the Accept button, and the reel continues.
- End of reel: the picture holds on the last frame and the dock shows "That's every change. 5 to look at." with the buttons Back to notes (steel) and Play again.

**Interactions:**
- `←`/`→` jump to the previous or next change. `Space` plays or pauses. `A` accepts and continues to the next change. `R` pauses and opens Reply (returns to 32). `N` drops a mark. `Esc` goes back to notes. `J`/`K`/`L` shuttle.
- Handle length comes from Settings › Cutting › Handles (default 2 s).

**Motion:**
- Nothing moves during playback except the playhead.
- The dock auto-hides after 2 s idle, like Watch through, and returns on pointer move (Settle).
- The tag swaps between CHANGED and HANDLE instantly, with no animation.

**Accessibility:** "Playing changes, change 3 of 7, note 3." Accept announces "Accepted note 3". Dock controls keep their order when hidden.

**Acceptance:**
- [ ] The reel contains only changed passages plus handles, in film order, and totals the length shown on the primary button.
- [ ] Handles are visibly distinct (hatching on the strip, HANDLE tag) from changed picture.
- [ ] Accepting from the reel updates the sheet and the Cut tab's count immediately.

## 32 · Replying to an answer
Frame: `screens/32-changes-thread.html` · Render: `renders/32-changes-thread@2x.png` · Snapshot `32-changes-thread`

**Arrives from / leads to:** Reply on a row, `R`, or `R` in Play changes. Sending a reply reopens the note: the row shows "Reopened", and the note goes into the next turnover.

**Layout:**
- The thread opens in place under its row (`--panel`, inset to the row's words).
- Messages: an amber pin for the director and a prism diamond for the editor, each with a who line (11 pt text-4: "You · on Cut 3", "Editor · Cut 4").
- When the field is empty, quick replies show as chips: "Not quite", "Go further", "Too much", "Put it back". They insert text; they don't send.
- A reply field, then a line with "Goes into your next turnover", Cancel (ghost), and **Reopen 3** `⌘↩` (default button).
- The row's actions become a "Replying" chip.

**Content:**
- Thread:
  - "Tighter on her. The sky is winning."
  - "Reframed to 1.6× on Maya; sky is now a third of the frame. Going past 1.8× softens the image."
- Draft: "Not quite. Still too much sky. Try 1.8× and favour her eyes, I'll live with the softness".
- Answers 1 and 2 are done ("Accepted", "Used B").

**States and variants:**
- Empty field: the button is disabled and the placeholder reads "What's not right yet?".
- A reopened row shows an amber "Reopened" chip. The note keeps its number and its thread.

**Interactions:**
- `⌘↩` sends. `Esc` cancels and keeps the draft (restored next time).
- A reply never starts a new cut by itself; turnover is always deliberate.

**Motion:** The thread opens with Glide 360 ms. The field gets focus after it opens.

**Accessibility:** The thread is a list labelled "Conversation on note 3". The field is labelled "Reply to the editor about note 3".

**Acceptance:**
- [ ] Sending changes the note state to `reopened` and does not start cutting.
- [ ] The thread persists across cuts and shows which cut each message refers to.
- [ ] Drafts survive switching rooms.

## 33 · Every cut
Snapshots `33-history` (the cuts list) and `33b-every-answer` (Cut 4's answers opened, note 5 reverting)

**Arrives from / leads to:** the cut's name in the crumb, Cut › Every Cut… (`⌘Y`), or the scene strip's menu. Picking a cut shows it in the room (Older cuts). Compare opens the A/B layout (30) with that cut and the one before, synced.

**Content:**
- Cuts:
  - Cut 4: Oct 28 · 14:09, "Answered 7 notes · 3:31 · −9 s".
  - Cut 3: Oct 26 · 11:40, 3:40 · −12 s.
  - Cut 2: Oct 22 · 17:05, 3:52 · −20 s.
  - Assembly: Oct 20 · 09:12, "From 31 circles · 4:12".
- A picture lock or unlock appears as its own line with a lock glyph: "Picture locked · Oct 28 · 15:02".

**Acceptance:**
- [ ] Every cut since the assembly is listed; nothing is ever deleted.
- [ ] Each change's tooltip shows its range in its cut and its range in the cut before.
- [ ] Revert and Put back are reversible and logged with time and author.
- [ ] Reverting is disabled for changes in locked scenes, with the tooltip "Unlock 5 Launch day to revert".

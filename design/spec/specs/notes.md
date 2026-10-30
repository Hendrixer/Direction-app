# Notes

**Room overview.** Notes is the notes session. The director writes up marks as numbered notes, gives each a kind, triages outside notes, answers the editor's questions, and turns the whole sheet over at once. After turnover, the same room shows the editor's **read-back** for approval. The window is split into two parts: the picture **stage** on `--canvas` (left, flexible) and the **notes sheet** on `--ground` (right, 380 wide, `--sheet-w`). The titlebar's steel button is the room's single primary: **Turn over N** before turnover, and **Start cutting** while a read-back waits. Outside those two states it isn't shown.

Shared layout (frames 17–24, in pt):
- **Titlebar:** 0, 0, 1440 × 52.
  - Crumb: film and cut menus with chevrons.
  - Rooms: centered. The Notes badge (`.badge.d`, amber) counts items that need words or triage: drafts plus outside notes in the inbox.
  - Right side: editor pill, Share (ghost icon), then the primary.
- **Stage:** 0, 52, 1060 × 848.
  - Viewer padding 28/28/8. The picture fits width at its aspect: 1004 × 565 at 28, 171 for 16:9.
  - HUD timecode glass: bottom-left, 12 inset.
- **Transport:** 0, 834, 1060 × 66.
  - Play (28 icon btn), timecode, scene strip 809 wide, then a mark button (ghost icon with an amber pin glyph).
  - All note anchors show in the strip: pins for moments, `.range` bands for ranges. Outside people's marks use `.mk.pin.out` (steel).
- **Sheet:** 1060, 52, 380 × 848. It's a grid with four rows: head, tabs, list (scrolls), foot.
  - Head: `.brand-m` title and a 12 pt status line.
  - Tabs: Sheet, Questions, Outside, each with a mono count.
  - Note rows (`.nt`): 26 number column, about 69 tall for one line of text. Selected rows get a `--panel` background and a 2 pt amber left bar.
- **Composer** (`.sheet-foot`), from the top:
  - Anchor row: icon, "Note N at", anchor chip, and on the right the anchor select (Moment, Range, Region, Line, Scene, Whole cut).
  - A 64-tall text field.
  - The kinds row with **Add ↩** on the right.

Note anchors in the composer follow the playhead until you start typing. Then they're pinned, and moving the playhead doesn't change them.

Room keys:

| Key | Action |
|---|---|
| `N` | Mark at the playhead (creates a draft) |
| `↩` | Add / save the note in the composer |
| `⇧↩` | New line in the composer |
| `⇥` | Accept the editor's suggested kind |
| `1`…`5` with `⌥` | Set kind: Feeling, Story, Pace, Picture, Sound |
| `R` | Region tool on the picture |
| `I` / `O` | Set range in / out at the playhead |
| `↑` / `↓` | Previous / next note (seeks the picture) |
| `⌫` on a selected draft | Drop it. Its number is retired. |
| `⌘↩` | Turn over (opens frame 22); with a read-back showing, Start cutting |
| `⌘⌥1/2/3` | Sheet / Questions / Outside tab |

---

## 17 · Notes, drafts after a screening
Frame: `screens/17-notes-drafts.html` · Render: `renders/17-notes-drafts@2x.png`

**Arrives from / leads to:**
- Arrives from **Write notes** in frame 16, the Notes tab (`⌘4`), or clicking a pin in frame 16.
- Leads to frame 18 (start typing on a draft), frame 19 (`R`) and frame 22 (**Turn over**).

**Layout:**
- Picture: 28, 171, 1004 × 565.
- Strip: 187, 840 (809 × 44).
- Sheet tabs: 1061, 129 (379 × 49). Note rows from y 178, each about 69 tall.
- Composer: 1061, 733 (379 × 167). Anchor select: 1340, 746 (84 × 28). Add: 1361, 858 (63 × 28).
- Primary: 1304, 12 (124 × 28).

**Content:**
- Title "Notes on Cut 3". Status line "2 written · 2 from your screening, waiting for words".
- Tabs "Sheet 4 · Questions 0 · Outside 0".
- Notes 1 and 2 are written: chips "00:18:04" Pace and "00:46:00–00:58:12" Feeling, with their text from story.md.
- Notes 3 and 4 are drafts: chips "01:12:08" and "01:43:20" plus "From screening". The italic `--text-3` placeholder reads "Add a note, or press ⌫ to drop this mark."
- Composer:
  - Anchor row: "At 00:46:12" (follows the playhead) and the select "Moment".
  - Field placeholder: "What should it feel like?"
  - Kinds unselected. **Add** disabled.
- Primary: "Turn over 2". It counts written notes only.
- Note text wraps to any number of lines. Chips never wrap inside themselves; the meta row wraps between chips.

**States and variants:**
- Drawn: drafts present, note 2 selected.
- Empty sheet: the list shows the empty state, "No notes on Cut 3 yet." with "Screen it first, or press N anywhere." and a ghost **Screen Cut 3** button. The primary is disabled and reads "Turn over".
- Hover on a row: `--panel` background and a ghost `more` icon at the right. Its menu: Edit, Change kind, Copy timecode, Drop note.
- Drafts in a locked scene: an extra `.chip.ui` with a lock icon and "Locked scene", and the tooltip "The editor can't change this scene. Unlock it, or keep the note for later."
- Written notes are editable inline on double-click until turnover.

**Interactions:**
- Click a row to select it and seek the picture to its anchor (a range starts at its in point and loops while selected and playing).
- Click a strip pin to select that note. Drag a pin to move its time. Hold `⌥` while dragging to make a range.
- Type with a draft selected to fill the composer (see frame 18).
- **Turn over** opens frame 22. It's disabled while drafts are the only notes.
- Drafts don't block turnover; they stay behind as drafts.

**Motion:**
- Selection changes are instant.
- A new note row inserts with Settle (height plus opacity).
- The badge count changes with Snap.

**Accessibility:**
- The list is a table named "Notes on Cut 3". Each row reads "Note 2, Feeling, 46 seconds to 58 seconds: I want to feel how tired she was here. Let it sit."
- Drafts read "Note 3, draft from screening, 1 minute 12".
- Focus order: titlebar, picture controls, tabs, list, composer.

**Acceptance:**
- [ ] Note numbers are amber SF Mono 14 semibold and never change.
- [ ] Draft text is italic `--text-3`, written note text is `--text-1`.
- [ ] Turn over counts only written notes.
- [ ] Every anchor shows in the strip; the selected note's pin matches the playhead.
- [ ] The sheet is exactly 380 wide at every window width.

## 18 · Notes, writing a note
Frame: `screens/18-notes-writing.html` · Render: `renders/18-notes-writing@2x.png`

**Arrives from / leads to:**
- Arrives from frame 17 (select draft 3 and start typing, or double-click it).
- **Add ↩** saves and selects the next draft (note 4). `R` leads to frame 19.

**Layout:**
- As frame 17. Draft row 3 is selected and reads "Writing…".
- Composer field has `.field.focus`. The kinds row has one `.kind.sug` (Picture) carrying a small solid diamond.
- Under the kinds row is a hint line (11 pt).

**Content:**
- Anchor row: "Note 3 at 01:12:08". It's pinned, no longer following the playhead.
- Field: "Tighter on her. The sky is winning", with the caret at the end.
- The kind suggestion appears once the text is at least 3 words. Hint: "Editor suggests Picture. Press ⇥ to take it, or pick another." Only "Editor suggests Picture." is in `--agent`.
- **Add** is enabled (regular, not steel).
- Primary still reads "Turn over 2". It updates once the note is added.

**States and variants:**
- Drawn: kind suggested, not chosen.
- Kind chosen: that kind is `.kind.on`, the suggestion styling is removed, and the hint hides. See frame 19.
- No suggestion yet (under 3 words): no `.sug` and no hint.
- Kind left empty on Add: the note saves without a kind. The editor proposes one at read-back, shown as a `.chip.a` on the row ("Picture?").
- Editing an existing written note: the anchor row reads "Editing note 1". The buttons are **Cancel** (ghost) and **Save ↩**.

**Interactions:**
- `⇥` accepts the suggestion. Click any kind to set it; click again to clear.
- `esc` cancels writing and keeps the draft.
- Changing the anchor select to Region enters the region tool (frame 19). Range uses the strip: drag across scenes or press `I` / `O`.
- The kind suggestion runs on-device. It isn't a turnover; the editor doesn't see the note's text.

**Motion:** The suggestion's `.sug` border and the hint fade in with Settle, at most once per note.

**Accessibility:**
- The field is labeled "Note 3 text".
- The suggestion is announced as "Suggested kind: Picture. Press Tab to accept."
- Kinds form a radio group, "Kind", that can be empty.

**Acceptance:**
- [ ] The suggested kind uses ion blue and the diamond. It's never amber and never preselected.
- [ ] `⇥` sets it.
- [ ] The anchor stays at 01:12:08 even if the playhead moves while you type.
- [ ] Add saves and advances to the next draft.

## 19 · Notes, drawing a region
Frame: `screens/19-notes-region.html` · Render: `renders/19-notes-region@2x.png`

**Arrives from / leads to:**
- Arrives from frame 18 (`R`, or the anchor select set to Region).
- Back to frame 18 on mouse-up, with the region attached. `esc` cancels the region.

**Layout:**
- The region (`.region`) is drawn on the picture: 1.5 pt amber border, radius 2, and outside it a 35% black dim.
  - A tab label "3 · region" sits above its top-left corner.
  - Eight 7 × 7 amber handles: four corners and four edge midpoints.
- A glass hint sits centered 14 from the picture's top. A size HUD (glass) sits bottom-right.
- Composer anchor row: region icon, "Note 3, region at 01:12:08", select "Region".
- Row 3's meta shows a Region chip.
- The kind is chosen (`.kind.on` Picture).

**Content:**
- Hint: "Drag to draw what matters. esc cancels." (with an `esc` keycap).
- Size HUD: "24 × 58%" (width × height as a percentage of the frame).
- Field: "Tighter on her. The sky is winning."

**States and variants:**
- Drawing (drawn): the crosshair cursor, with handles live.
- Region set: the hint and size HUD are hidden, and the handles show only on hover.
- Multiple regions aren't allowed: one region per note. Drawing again replaces it.
- Playback pauses while drawing. The region is tied to its frame and shows for ±12 frames when the note is selected.

**Interactions:**
- Drag on the picture to draw. Drag handles to resize; `⇧` keeps the aspect.
- Drag inside to move.
- Arrow keys nudge 1%; `⇧` nudges 10%.
- `⌫` removes the region and the anchor reverts to Moment.

**Motion:**
- The outside dim fades in with Snap.
- Handles don't animate.

**Accessibility:**
- The region is announced as "Region, 24 by 58 percent, at left 31, top 20".
- Arrow keys work while the picture has focus in region mode.

**Acceptance:**
- [ ] Region color is `--director` only.
- [ ] Coordinates are stored as fractions of the frame, not points.
- [ ] `esc` restores the Moment anchor.
- [ ] The label tab reads "<note number> · region".

## 20 · Notes, the editor's questions
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
  - **Cut both ways**: "You pick in Changes"
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

## 21 · Notes, outside notes inbox
Frame: `screens/21-notes-outside.html` · Render: `renders/21-notes-outside@2x.png`

**Arrives from / leads to:**
- Arrives from someone with a screening link leaving notes (see share.md). The toast "Priya left a note on Cut 3" or the Outside tab gets here.
- **Accept** turns the item into a numbered note on the Sheet, with the next number and the person's initials. **Edit first** opens it in the composer prefilled. **Decline** removes it.

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
- Arrives from **Turn over N** in the titlebar, or `⌘↩` in Notes.
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

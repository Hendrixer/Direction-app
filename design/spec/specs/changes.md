# Changes room (frames 29–33)

When a cut is ready, the **Changes** room shows the editor's answers to the director's notes. Every change points to one note number. The director plays only what moved, picks between options, accepts or replies one answer at a time, and can look back at the history of every cut. The room badge (ion blue) counts answers still to review.

Shared layout for 29, 30 and 32 (`body.wide`, styles in `css/changes.css`):
- Titlebar: the crumb shows `Cut 4`. Primary (steel) is "Play changes" with the reel length in a `.n` chip (`0:46`).
- Stage: `minmax(0,1fr)` (880 pt at design size) × full height, canvas black, 16:9 viewer, transport with scene strip.
  - In this room the strip marks every changed scene with a 2 pt prism top edge (`.sc.chg`).
  - Answers show as prism diamonds (`.marks .mk.gem`) at their positions. No amber pins here; the director's marks belong to the Notes room.
- Answers panel: 560 pt wide. Head (title "Answers in Cut 4", History button, subline), tabs (To review · Accepted · All, with mono counts), list, foot.
- Answer row `.ans`: grid `24px 96px 1fr auto`, padding 10/14, hairline under.
  - Note number in SF Mono 13/600 amber.
  - A 96 × 54 thumbnail of the changed passage, with a 2 pt prism top edge.
  - A kind caption (11 pt text-3), then "**Scene.** Answer text" at 12.5 pt.
  - Right column: the delta (mono 11 text-3) above the actions, small Accept and an icon Reply.
  - Selected row: steel-3. Done rows: text and thumbnail at 55% and a green "Accepted" status.
- Unasked answers (latitude "Take a pass" only) show the number slot as an ion diamond and the label "Unasked".

## 29 · Changes, new cut arrived
Frame: `screens/29-changes.html` · Render: `renders/29-changes@2x.png`

**Arrives from / leads to:**
- Arrives from 25 when Cut 4 finishes, either automatically if the director is in Notes or Changes, or via the toast or notification.
- Leads to 31 (Play changes), 30 (Pick A or B), 32 (Reply), 33 (History) and 34 (all accepted).

**Layout:**
- The sweep edge (`.sweep-edge`) is a 2 pt prism line at y 52, full width, directly under the titlebar.
- Toast at left 24, bottom 96 over the stage.
- The first answer is selected and the stage is cued 2 s before it (handle).

**Content:**
- Pill: "Cut 4 ready" with a prism diamond. It returns to "Ready" once the director plays changes or accepts anything.
- Badge on Changes: 7.
- Subline: "3:31 · 9 s shorter than Cut 3 · 7 answers".
- Rows (see `story.md`):
  1. Pace, −4.2 s.
  2. Feeling, "A / B", with the single action "Pick A or B".
  3. Picture, crop.
  4. Sound, −6 dB.
  5. Story, −3.1 s.
  6. Pace, −2.0 s.
  7. Story, 0.0 s.
- Toast: "Cut 4 is ready", sub "7 answers · 46 s of changes to watch", with a ghost Dismiss.
- Foot: "Accepted answers stay in Cut 4. Anything you reply to goes into your next turnover."
- Text wraps to two lines at most, then ends in an ellipsis. Hovering shows the full text in a tooltip.

**States and variants:**
- To review empty: the list shows the empty line "Every answer is accepted. Screen it again for more notes, or lock picture when the edit is done." and leads to 34. The foot reads "Nothing left to review. Screen it again for more notes, or lock picture to start finishing."
- Accepted tab: the same rows in their done state.
- All tab: the same rows in note order.
- If an answer failed partially, its row gets a red delta "partly" and the reply action is primary.

**Interactions:**
- Click a row to select it and seek the stage to its change minus the handle.
- Shortcuts: `A` accepts the selected answer, `R` replies, `↑`/`↓` select, `⌘↩` plays changes, `⇧⌘A` (Accept all remaining) has a confirm.
- Double-clicking a row plays just that change (31, starting at it).
- Context menu on a row: Accept, Reply…, Play this change, Show in Cut 3, Revert this change.

**Motion:**
- On arrival, the sweep runs one pass left to right (`--t-sweep` 900 ms, `--e-inout`) and then holds as a static 2 pt line for 2.4 s before fading out (Settle).
- The toast slides up 12 pt and fades in (Settle) and auto-dismisses after 8 s. It stays while hovered.
- With Reduce Motion, the sweep appears instantly and fades.

**Accessibility:**
- On arrival VoiceOver says "Cut 4 is ready. 7 answers."
- Each row reads as "Note 1, Pace, Cold open. Cut the second street wide; we're on her face by 0:09. Minus 4.2 seconds. Accept button. Reply button."
- Focus moves to the first row on arrival only if the director was in Changes.

**Acceptance:**
- [ ] The sweep plays exactly once per new cut and never during playback. If playback is running, it waits until pause.
- [ ] Every answer row shows its note number; no change exists without one, except Unasked rows.
- [ ] The badge count equals the To review count.
- [ ] Deltas use a true minus sign (U+2212) and one decimal place.

## 30 · Changes, two options
Frame: `screens/30-changes-options.html` · Render: `renders/30-changes-options@2x.png`

**Arrives from / leads to:** 29, via "Pick A or B" or by selecting answer 2. Using A or B returns to 29 with answer 2 done ("Used B"). "Neither, reply" leads to 32.

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
- When the director has picked, the chosen card shows a green "Using B" chip and the buttons collapse into "Change pick".

**Interactions:**
- Click a card to make it the audible one.
- `1`/`2` switch audio between A and B. `⇧1`/`⇧2` use A or B. `Space` plays both. `Esc` returns to 29 without choosing.

**Motion:** Card focus ring with Snap. On choice, the unchosen card fades to 40% (Settle) before the stage returns to single picture (Glide).

**Accessibility:** The cards are a radio group, "Options for note 2". The editor's preference is read as "Editor recommends B". Use A and Use B have explicit labels.

**Acceptance:**
- [ ] Both pictures stay frame-locked within one frame during playback.
- [ ] The editor's preference is shown only as a chip and is never selected for the director.
- [ ] Choosing an option writes the pick to the answer, and the unchosen version stays retrievable in history (33).

## 31 · Play changes
Frame: `screens/31-play-changes.html` · Render: `renders/31-play-changes@2x.png`

**Arrives from / leads to:** 29, 30 or 32 via the primary "Play changes" (`⌘↩`). `Esc`/Stop returns to the Changes room with the last-played answer selected.

**Layout:**
- Full picture like Screening (frame 13): canvas black, 2.39:1 or native aspect fitted to width, titlebar overlay with a gradient and no room switcher.
- Change tag HUD at left 24, top 76: a glass chip with a 14 × 2 pt prism bar and "CHANGED · NOTE 3" (mono 11, uppercase). During handles it reads "HANDLE · CUT 3 PICTURE" with no prism bar.
- Dock: glass, 1000 pt wide, bottom 24, radius 16, two rows.
  - Top row: the note chip, "**Scene.** answer", then the reel progress (`.reel-dots`, one 18 × 3 pt dash per change) and "3 of 7".
  - Bottom row: previous change, play/pause, next change, the reel timecode "01:13:02 / 0:46", the change strip, "2 s handles", Reply (ghost), and Accept (steel).
- Change strip (`.cstrip`): the current change and its handles only. The handles are hatched, and the changed span has a 2 pt prism top and brighter footage.

**Content:** Change 3 of 7: "The ridge. Reframed to 1.6× on Maya; sky is now a third of the frame." The timecode shows the position in Cut 4, and the total is the reel length.

**States and variants:**
- Options answers play A, then B, back to back, and the tag reads "OPTION A · NOTE 2". Accept is replaced by "Use A" and "Use B" (B steel only if already picked; otherwise both default).
- An accepted change shows a green "Accepted" in place of the Accept button, and the reel continues.
- End of reel: the picture holds on the last frame and the dock shows "That's every change. 5 to review." with the buttons Back to answers (steel) and Play again.

**Interactions:**
- `←`/`→` jump to the previous or next change. `Space` plays or pauses. `A` accepts and continues to the next change. `R` pauses and opens Reply (returns to 32). `Esc` stops. `J`/`K`/`L` shuttle.
- Handle length comes from Settings › Cutting › Handles (default 2 s).

**Motion:**
- Nothing moves during playback except the playhead.
- The dock auto-hides after 2 s idle, like Screening, and returns on pointer move (Settle).
- The tag swaps between CHANGED and HANDLE instantly, with no animation.

**Accessibility:** "Playing changes, change 3 of 7, note 3." Accept announces "Accepted note 3". Dock controls keep their order when hidden.

**Acceptance:**
- [ ] The reel contains only changed passages plus handles, in film order, and totals the length shown on the primary button.
- [ ] Handles are visibly distinct (hatching on the strip, HANDLE tag) from changed picture.
- [ ] Accepting from the reel updates the Changes list and badge immediately.

## 32 · Changes, replying to an answer
Frame: `screens/32-changes-thread.html` · Render: `renders/32-changes-thread@2x.png`

**Arrives from / leads to:** 29, 30 or 31 via Reply or "Not quite". Sending a reply reopens the note and returns to 29 with the row marked "Reopened". The next turnover in Notes includes it.

**Layout:**
- The selected row expands in place into a `.thread` panel (steel-3, padding 4/14/14/52, aligned to the text column).
- Messages: an amber pin for the director, a prism diamond for the editor, each with a who line (11 pt text-4: "You · on Cut 3", "Editor · Cut 4").
- A reply field (`.field.area.focus`), then an actions row: a help line, Cancel (ghost), and "Reopen note 3 ⌘↩" (default button).
- The row's action column shows a "Replying" chip.

**Content:**
- Thread:
  - "Tighter on her. The sky is winning."
  - "Reframed to 1.6× on Maya; sky is now a third of the frame. Going past 1.8× softens the image."
- Draft: "Not quite. Still too much sky. Try 1.8× and favour her eyes, I'll live with the softness".
- Help: "Reopens note 3 for your next turnover".
- Badge: 5. Answers 1 and 2 are done ("Accepted", "Used B").

**States and variants:**
- Empty field: the button is disabled and the placeholder reads "What's not right yet?".
- A reopened row shows an amber "Reopened" chip instead of Accept. In Notes, the note returns to the sheet as state `reopened`, keeping number 3, with its thread visible.
- Quick replies offered as chips above the field when empty: "Not quite", "Go further", "Too much", "Put it back". These insert text; they don't send.

**Interactions:**
- `⌘↩` sends. `Esc` cancels and keeps the draft (restored next time).
- A reply never triggers a new cut by itself; turnover is always deliberate.

**Motion:** The row expands with Glide 360 ms. The field gets focus after the expansion ends.

**Accessibility:** The thread is a list labelled "Conversation on note 3". The field is labelled "Reply to the editor about note 3".

**Acceptance:**
- [ ] Sending changes the note state to `reopened` and does not start cutting.
- [ ] The thread persists across cuts and shows which cut each message refers to.
- [ ] Drafts survive switching rooms.

## 33 · Cut history and changelog
Frame: `screens/33-history.html` · Render: `renders/33-history@2x.png`

**Arrives from / leads to:** History (button in the answers panel head), Film › Cut History (`⌥⌘H`), or the cut crumb's menu › "History…". "Answers" goes back to 29. A cut in the list can be screened (primary).

**Layout:**
- A full-width view under the titlebar in the Changes room.
- Cut list: 300 pt, hairline right border, 10/8 padding.
  - Each item (`.cutit`) has a 9 pt diamond node on a 1 pt rail; the latest is prism, older ones steel-6.
  - Name in Archivo 14/700, date in mono 11 text-4, summary 12 pt text-3. The selected item is steel-4 with a hairline.
- Changelog: a head block (Archivo 24/800 "Cut 3 → Cut 4", the buttons "Compare whole cuts" and "Play changes 0:46", and the subline), a column header (mono 10.5 uppercase text-4), then rows.
- Changelog rows (`.logrow`): grid `30px 120px 1fr 160px 64px 160px`, padding 11/22.
  - Note number, a 120 × 40 thumbnail, the change and scene, the new range with "was" range below (mono 11), the delta, and the revert action right-aligned.

**Content:**
- Cuts:
  - Cut 4: Oct 28 · 14:09, 7 answers · 3:31 · −9 s.
  - Cut 3: Oct 26 · 11:40, 6 answers · 3:40 · −12 s.
  - Cut 2: Oct 22 · 17:05, 9 answers · 3:52 · −20 s.
  - Assembly: Oct 20 · 09:12, From 31 circles · 4:12.
- Subline: "7 changes from your notes on Cut 3 · built Oct 28 at 14:09 · 3:40 → 3:31. Reverting a change rebuilds only that passage."
- Row 5 is shown reverted: text at 45%, sub "Reverted by you · 14:31", action "Put back".
- The titlebar primary is "Screen Cut 4".

**States and variants:**
- Selecting Assembly shows "Built from your circles" with the circled takes it used instead of changes.
- Unasked changes show an ion diamond in the note column.
- A picture lock or unlock appears in the cut list as its own event row with a lock glyph: "Picture locked · Oct 28 · 15:02".

**Interactions:**
- "Revert this change" opens a popover, "Revert note 5's change in Cut 4? The editor rebuilds only 01:02–01:07.", with the buttons Cancel and Revert. Reverting creates no new cut name; it updates Cut 4 in place and logs it. The note returns to the sheet as reopened unless "Keep note closed" is checked.
- "Put back" reapplies the change.
- "Compare whole cuts" opens the A/B layout (30) with Cut 3 and Cut 4, synced.
- Double-clicking a row plays that change with handles.

**Motion:** Selecting a cut cross-fades the changelog (Settle). Reverting dims the row (Settle) while the rebuild runs, and the pill shows "Rebuilding 1 passage" with shimmer.

**Accessibility:** The cut list is a list, "Cuts, newest first". Rows read as "Note 3, reframed to 1.6 times on Maya, The ridge, in Cut 4 from 01:08:00 to 01:16:20, was 01:12:08 to 01:21:04, crop. Revert this change."

**Acceptance:**
- [ ] Every cut since Assembly is listed; nothing is ever deleted.
- [ ] Each change shows both its range in the new cut and its range in the cut before.
- [ ] Revert and Put back are reversible and logged with time and author.
- [ ] Reverting is disabled for changes in locked scenes, with the tooltip "Unlock 5 Launch day to revert".

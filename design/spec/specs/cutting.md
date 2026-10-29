# Cutting: the editor at work (frames 25–28)

After the director turns over a notes sheet and approves the read-back (frames 22–23), the editor builds the next cut. Cutting isn't a room. It's a state of the **Notes** room: the notes sheet becomes a progress panel titled "Cut 4 in progress", while the stage keeps playing the **current** cut (Cut 3). The director can watch, switch rooms, or quit the app. Cutting continues in the background and the titlebar pill always reports it.

Shared layout for 25–28 (styles in `css/changes.css`):
- Titlebar 52 pt. Crumb shows the cut being watched (`Cut 3`), not the one being built.
- Stage: `minmax(0,1fr)` × full height, canvas black. Viewer padding 28/28/8, 16:9 picture. Transport row (`.transport`): play 28 pt, timecode, scene strip.
- Panel `.panel`: 380 pt wide (`--sheet-w`), steel-2, hairline left border. Rows: head (16/16/12 padding), body (scrolls), foot (12/16/14).
- Progress rows `.step`: grid `26px 1fr auto`, padding 11/16/11/14, hairline under. Number in SF Mono 14/600 amber. Status at right in SF Mono 11: `Done` green with check, `Cutting` text-1 with prism diamond, `Queued`/`Waiting` text-4, `Needs you`/`Stopped` red. The working row has steel-3 background and a 2 pt prism bar at its left edge. Blocked rows have a 2 pt red bar and a 6% red wash.
- Order: done notes first, then the blocked note, then the note being cut, then the queue in the editor's order. Notes keep their numbers; the order can differ from the number order.

## 25 · Editor cutting
Frame: `screens/25-cutting.html` · Render: `renders/25-cutting@2x.png`

**Arrives from / leads to:** 23 (Approve read-back) or 22 (Turn over, when read-backs don't wait for approval). Leads to 26 (can't), 27 (conflict), 28 (failure) or 29 (Cut 4 ready).

**Layout:** As above. Panel head: "Cut 4 in progress" (Archivo 17/700, 112% width) plus a more button, and a subline in 12 pt text-3. The panel foot carries one line of reassurance.

**Content:**
- Pill: "Cutting 3 of 7" plus a 40 × 3 pt prism meter at 34%. The meter shows progress through the notes, not time.
- Subline: "Turned over 7 notes at 14:02 · started 14:03 · about 4 min left". The estimate is rounded to whole minutes, and below a minute it reads "less than a minute".
- Rows: 1 Done, 5 Done, 3 Cutting (with the plan line "Reframe to 1.6× on Maya; sky to a third of frame." from the read-back), then 2, 4, 6 and 7 Queued.
- Note text wraps to two lines at most, with an ellipsis after that. Only the working row shows its plan line.
- Foot: "You can keep watching Cut 3. Nothing changes in it."
- Titlebar primary (steel): "Screen Cut 3", which opens Screening on the current cut.

**States and variants:**
- No ETA yet: the subline reads "Turned over 7 notes at 14:02 · starting".
- Options notes show "Cutting two ways" as their working status.
- In other rooms, only the pill shows progress. Clicking the pill opens the editor popover (frame 41) with the same list in compact form.
- Quitting during cutting shows a native alert: "The editor is still cutting Cut 4. It will pick up where it left off when you reopen Launch film." with the buttons Quit and Cancel.

**Interactions:**
- Clicking a row seeks the stage to that note's anchor in Cut 3.
- Right-clicking a queued row gives "Skip this note for Cut 4", which moves it back to the sheet as reopened.
- The more button offers "Stop cutting…" (confirm: "Stop Cut 4? Finished notes are kept for the next try.") and "Show read-back".
- `Space` plays or pauses the stage. `⌘3` goes to Screening.

**Motion:**
- The pill border and meter shimmer (`--t-shimmer` 2.4 s linear loop) only while cutting.
- When a row's status changes, its background and the bar cross-fade (Settle 220 ms) and the row moves to its new position (Glide 360 ms).
- Nothing animates while the stage is playing except the playhead; the shimmer pauses during playback.

**Accessibility:**
- The pill reads as "Editor, cutting Cut 4, note 3 of 7, about 4 minutes left".
- Each row reads as "Note 3, Tighter on her. The sky is winning. Cutting."
- Progress changes are announced as polite updates (at most one every 10 s).
- Focus order: titlebar, stage transport, panel rows, foot.

**Acceptance:**
- [ ] The pill shows "Cutting N of M" with a prism shimmer border and meter. With Reduce Motion the border is a static prism.
- [ ] Cut 3 keeps playing and seeking normally while cutting runs.
- [ ] Row order follows the editor's order, and each row keeps its permanent note number.
- [ ] Only one row has the prism bar at a time.
- [ ] Quitting mid-cut shows the alert and cutting resumes on relaunch.

## 26 · Editor can't do a note
Frame: `screens/26-cutting-cant.html` · Render: `renders/26-cutting-cant@2x.png`

**Arrives from / leads to:** 25, when the editor hits a blocker: a locked scene, missing footage, or a contradiction with the brief's must-keep. Answering leads back to 25, and the note re-enters the queue.

**Layout:**
- A `.notice.cant` block sits at the top of the panel body, 16 pt side margins, 14 pt padding, radius 10, with a 1 pt red border at 45%.
- Head: a red lock icon, the bold title, and the note number chip at right.
- Choices use `.choice` rows (64 × 36 thumbnail, 8/10 padding, radius 8); the selected one has a 1.5 pt text-1 ring.
- Actions row: Answer (default button) and Show me 5A T3 (ghost).

**Content:**
- Pill: "Can't do 1" in red with a red diamond. Subline: "Cutting 4 of 7 · 1 note waiting on you".
- Title: "I can't do note 7 yet". Body: "The best team shot, 5A T3, is in Launch day, which you locked. I've left the rest of the cut moving." Source line: "Note 7 · Priya Shah · "Show the team earlier.""
- Choices:
  - "Unlock Launch day and use 5A T3", with an unlock glyph.
  - "Use 4C T2 instead" with the sub line "Team at the table, already in scene 4" and the editor chip "I'd pick this".
  - "Skip note 7 for this cut".
- The blocked row (7) has the red bar and the status "Needs you".

**States and variants:**
- Missing footage: title "I can't find the footage for note N"; choices "Locate…" and "Skip note N".
- Brief conflict: title "Note N would cut a must-keep line"; choices "Cut it anyway", "Keep it" and "Edit the brief…".
- Several blockers stack as separate notices, newest first. The pill counts them.
- Before a choice is made, Answer is disabled. The editor's recommendation is pre-selected only when Settings › Editor › "Pre-select my recommendation" is on (default off). The frame shows it selected after the director clicked it.

**Interactions:**
- Click a choice to select it. `↑`/`↓` move between choices, `↩` answers.
- "Show me 5A T3" opens a take preview popover (Dailies take component).
- Choosing "Unlock Launch day" opens a confirm sheet, "Unlock 5 Launch day? The editor may change it for note 7 only.", with the buttons Cancel and Unlock (steel). The unlock is scoped to that note and is logged in history.
- The editor never unlocks anything itself.

**Motion:** The notice slides down 8 pt and fades in (Settle). When it's answered it collapses (Glide) and the row's status returns to Queued.

**Accessibility:** The notice is announced assertively once: "The editor can't do note 7: Launch day is locked." The choices are a radio group labelled "How should the editor handle note 7?".

**Acceptance:**
- [ ] The rest of the cut keeps progressing while the notice waits.
- [ ] The editor's preference is shown as an ion "I'd pick this" chip, never pre-selected by default.
- [ ] Unlocking requires confirmation, applies to the named note only, and is logged in history (frame 33).
- [ ] The pill returns to "Cutting N of M" when no blockers remain.

## 27 · Two notes conflict
Frame: `screens/27-cutting-conflict.html` · Render: `renders/27-cutting-conflict@2x.png`

**Arrives from / leads to:** 25, when the editor detects overlapping notes it didn't flag in the read-back. Stays in 25 afterwards. This is informational: cutting continues.

**Layout:**
- A `.notice.voice` block (prism 1 pt border, steel-3 fill) at the top of the panel.
- Head: a prism diamond and the bold title.
- A segmented control (`.seg`) with two options, each carrying its note number chip.
- A help line in 12 pt text-3.
- The stage strip shows the overlapping range as an amber range box (`.strip .range`) at 00:25–00:46.

**Content:**
- Title: "Notes 2 and 1 pull against each other". Body: "Between 00:25 and 00:46, note 2 wants more time on her and note 1 wants to get there sooner. I'm following 2, because Feeling comes before Pace." Sub: "Note 1 still lands: her face by 0:09. Scene 2 runs 1.6 s longer than it would."
- Segments: "[2] Follow Feeling" (on) and "[1] Follow Pace".
- Help: "Switching re-cuts scene 2 only. You can also change it in the read-back next time."
- Pill: "Cutting 4 of 7" with the meter at 48%.

**States and variants:**
- If the director flips it, the note under the losing kind gets a reply in its thread: "Following note 1 over note 2 at 00:25–00:46, as you asked."
- Conflicts between notes of the same kind say "Both are Pace notes. I'm following the later one, note N." The segments stay.
- The notice can be dismissed with ×; the decision stays.

**Interactions:**
- Clicking a segment switches immediately (no confirm). The working row re-queues scene 2 only.
- Hovering the notice highlights the range on the strip. Clicking the range seeks there.

**Motion:** The segment thumb moves with Snap 120 ms. The notice fades in with Settle.

**Accessibility:** The segmented control is labelled "Which note wins between 00:25 and 00:46". The notice is announced politely.

**Acceptance:**
- [ ] The default resolution follows Feeling > Story > Pace > Picture > Sound.
- [ ] The notice names both note numbers and the exact overlapping range.
- [ ] Flipping re-cuts only the affected scene and records the decision on the note thread.

## 28 · Cut failed
Frame: `screens/28-cutting-error.html` · Render: `renders/28-cutting-error@2x.png`

**Arrives from / leads to:** 25, when a technical failure occurs (disk full, render crash, footage drive unplugged, lost connection to the editor). Retry leads back to 25, starting at the failed note.

**Layout:**
- A `.notice.err` block (7% red wash, red 45% border) at the top of the panel.
- Head: a warning icon, the bold title and the time (mono, right).
- The failed row is blocked with the status "Stopped". Queued rows read "Waiting".
- The panel foot reads "Retry picks up at note 6." with `⌘R` at right.

**Content:**
- Pill: "Stopped" in red.
- Titlebar primary (steel): "Retry" with the revert glyph. This replaces "Screen Cut 3" while a failure is unresolved.
- Title: "Cut 4 stopped". Body: "The disk ran out of room while I was rendering note 6. Cut 3 and your notes are safe, and the four notes I finished are kept." Sub: "Macintosh HD has 1.2 GB free. Cut 4 needs about 6 GB."
- Actions: "Free up space…" (opens Settings › Storage, frame 47) and "Use another disk…" (folder picker; moves the cache).

**States and variants (same component, different copy):**
- Drive unplugged: "The footage drive "Shoot A" was disconnected." Actions: "Reconnect and retry" and "Locate…".
- Editor unreachable (offline): pill "Offline". "I lost the connection while cutting. I'll continue when you're back online." No Retry; resumes automatically (see frame 51).
- Unknown failure: "Something went wrong rendering note 6." Actions: "Retry" and "Copy details" (copies a diagnostic to the clipboard).
- The copy never blames the director, never says "error code" up front, and always says what's safe.

**Interactions:** `⌘R` retries. Retry is disabled when the free-space check still fails, with the tooltip "Needs about 6 GB free". The more button offers "Stop and keep Cut 3".

**Motion:** None besides the notice appearing (Settle). The pill stops shimmering.

**Accessibility:** Announced assertively: "Cut 4 stopped. The disk is full." Retry is the default button, so `↩` triggers it when the panel has focus.

**Acceptance:**
- [ ] Finished notes are not redone on retry.
- [ ] The free-space requirement is computed and shown in GB to one decimal place.
- [ ] A notification is posted when the app is in the background (Settings › Notifications › "When something stops").
- [ ] Copy follows the pattern: what happened, what's safe, what to do.

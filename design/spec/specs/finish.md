# Lock and Finish (frames 34–38)

Locking protects the director's cut. Scenes can be locked one by one as they're approved, and **Lock picture** makes the whole edit final. Both locks mean the same thing at two sizes: the cut can't change (what's in it, from which take, when, how it's framed and joined), and its color and sound stay open. After picture lock the **Finish** room opens: a checklist of finishing work (color, sound, captions, titles, licenses, delivery) where the editor does what it can and the director signs off. Nothing in Finish can move a frame.

Shared:
- Locked scenes are drawn everywhere as grayscale footage at 28–30% opacity, 135° hatching (1 pt lines at 8% white every 6 pt), a lock glyph before the name, and a 1 pt line-2 border.
- After picture lock, the crumb shows a "Picture locked" chip (lock glyph, line-2 border, no fill) after the cut name. The Finish room becomes enabled. The Changes and Notes rooms stay viewable but read-only, and their primary buttons disappear.

## 34 · Locking scenes
Frame: `screens/34-lock-scenes.html` · Render: `renders/34-lock-scenes@2x.png`

**Arrives from / leads to:** 29, once every answer is accepted. The lock bar is always available in Changes; it's most prominent here. "Lock picture…" leads to 35.

**Layout:**
- Stage rows: viewer (picture at 88% width), lock head, lock bar.
- Lock head: "Scenes" (Archivo 14/700) plus a 12 pt help line, padding 14/24/10.
- Lock bar (`.lockbar`): one tile per scene, flex-proportional to scene length, 3 pt gaps, 24 pt side padding, 84 pt tall, radius 6.
  - Each tile shows footage at 60%, the name (mono 11) at top left, and the range (mono 10.5) at bottom left, with a lock glyph at bottom right when locked.
  - Hover: 1.5 pt text-1 ring and a small "Lock" button at bottom right.
- The answers panel shows the Accepted tab with all 7 rows done.

**Content:**
- Help: "3 of 5 locked. Lock a scene when its cut is right; the editor won't recut it. Color and sound stay open."
- Tiles: 1 Cold open 00:00–00:27 (locked), 2 Maya, the problem 00:27–01:12 (locked), 3 The ridge 01:12–01:51 (hover), 4 Building it 01:51–02:47, 5 Launch day 02:47–03:31 (locked).
- Foot: "Nothing left to review. Lock picture when the edit is done."
- Primary (steel): "Lock picture…" with a lock glyph.

**States and variants:**
- Lock picture is disabled while any note is open, questioned, or an outside note waits. Its tooltip names the blocker: "2 answers still to review".
- Hovering a locked tile shows "Unlock" (default button). Unlocking asks: "Unlock 1 Cold open? The editor can change it again in the next cut."
- The same lock and unlock actions exist in the scene strip context menu (`⌘L` on the current scene) in every room.

**Interactions:**
- Click Lock on a tile, or select a tile and press `⌘L`.
- `⇧`-click locks a range of tiles.
- Locking takes effect immediately, needs no confirm, and can be undone (`⌘Z`).

**Motion:** On lock, the hatching fades in and the footage desaturates over Settle 220 ms. Nothing else moves.

**Accessibility:** Each tile is a toggle button: "Scene 3, The ridge, 01:12 to 01:51, not locked. Lock." State changes are announced: "The ridge locked."

**Acceptance:**
- [ ] A locked scene is visibly hatched and grayscale in every strip in the app.
- [ ] The editor cannot recut a locked scene, and notes that need it produce frame 26. Its color and sound still change (balance, match, gain, fades, music).
- [ ] Lock and unlock events appear in history (33).

## 35 · Lock picture
Frame: `screens/35-lock-picture.html` · Render: `renders/35-lock-picture@2x.png`

**Arrives from / leads to:** 34, via "Lock picture…" (also Film › Lock Picture, `⇧⌘L`). Confirm leads to 36. Cancel or `Esc` returns to 34.

**Layout:**
- A sheet attached under the titlebar (`.modal`), 540 pt wide, over a 55% black scrim.
- Head: Archivo 24/800 title and a 13 pt explanation.
- Body: a well (`.well`) holding a checklist (`.chk` rows: 18 pt status circle, title, sub line), then a footnote.
- Foot: Cancel, then "Lock picture" (steel, with lock glyph).
- While the sheet is up, the titlebar's own primary is drawn as a default button, so the sheet's button is the only steel.

**Content:**
- Title: "Lock picture on Cut 4?"
- Explanation: "The edit becomes final, and every scene locks with it. The editor starts finishing right away: color, sound, captions and delivery. It can't move a frame."
- Checks:
  - ✓ "7 of 7 notes accepted" (Notes 1–7 on Cut 3 are answered in Cut 4)
  - ✓ "No open questions"
  - ✓ "No outside notes waiting" (Priya and Tom's notes were accepted or declined)
  - ✓ "3:31, inside your brief" (Brief asks for 3:00–4:00)
  - Lock: "2 scenes still open" (3 The ridge and 4 Building it will lock with the picture)
- Footnote: "You can unlock later from Finish or Film › Unlock Picture. It's recorded in the history."

**States and variants:**
- A failed check (red ×) disables the steel button; each failed row gets a link to resolve it ("Review 2 answers").
- Length outside the brief is a warning, not a blocker: an info circle with "3:58 is near the top of your brief (3:00–4:00)".

**Interactions:** `↩` confirms and `Esc` cancels. Confirming locks every scene, sets `pictureLocked`, logs it, and opens Finish.

**Motion:** The sheet drops from the titlebar (Glide 360 ms, `--e-out`) and the scrim fades in (Settle). On confirm, the sheet retracts and the room switches to Finish (Glide).

**Accessibility:** The sheet is a modal dialog titled "Lock picture on Cut 4?". The checks are a list, and each item reads its status first: "Done: 7 of 7 notes accepted."

**Acceptance:**
- [ ] The sheet lists every blocker, and the confirm button is disabled until there are none.
- [ ] Locking picture locks all scenes and enables the Finish room.
- [ ] Unlocking picture is possible only from the Film menu, asks for confirmation, and is logged.

## 36 · Finishing checklist
Frame: `screens/36-finish.html` · Render: `renders/36-finish@2x.png`

**Arrives from / leads to:** 35 (confirm) or `⌘6`. "Deliver…" leads to 37. Item actions open their own sheets (not drawn): Review color, Check names, Write credits, Add license.

**Layout:**
- `body.wide`. Stage: picture plus a strip with every scene locked.
- Panel (560 pt):
  - Head: "Finishing Cut 4" (Archivo 17/700), "3 of 6 done" (mono, right), and a 4 pt steel-8 progress bar.
  - List of `.fin` items: grid `34px 1fr auto`, padding 14/18. Each has a 32 pt icon tile, a title with who-labels, a description, and a right column with status and action.
- Who-labels: mono 10 uppercase. "EDITOR" in ion with a diamond, "YOU" in amber with a pin. Both can appear.

**Content (in this order):**
1. **Color** (Editor): "Matched shots across all five scenes to the window-light reference. Night exteriors lifted half a stop." Done (green) · Review.
2. **Sound mix** (Editor): "Dialogue first, music under. Mixing to −14 LUFS for web and −24 for broadcast." 62%, with a prism progress bar and "About 2 min".
3. **Captions** (Editor + You, selected): "41 English captions. Check the spelling of names: Maya Okafor, Priya Shah." "Needs you" chip (neutral) · Check 2 names.
4. **Titles and credits** (You): "Opening title off. End card: logo on black, 3 s. Credits not written yet." Write credits.
5. **Music licenses** (You): "2 tracks. "Slow Rooms" is licensed. "North Light" needs a license before you publish." "1 missing" (red chip) · Add license…
6. **Deliver** (Editor + You): "Master, web, vertical and captions. You can deliver now; open items are listed first." 4 outputs.

Also:
- Pill: "Mixing sound", shimmer, with the meter at 62%.
- Primary (steel): "Deliver…".
- Foot: "The edit is locked. Finishing changes color and sound, never a frame." with a ghost small "Unlock picture…" on the right (the same confirmation as Film › Unlock Picture).

**States and variants:**
- Each item has one of the states: To do (no status), Editor working (prism bar), Needs you (neutral chip), Done (green check), Problem (red chip).
- An editor-only item at Needs you or Problem says what the editor needs, with "Try again": once the director has done it, a new finishing run carries on with whatever isn't done. It's disabled while the editor is working.
- Delivered (frame 38) replaces this list.
- The color "Review" opens a before/after split on the stage using the options component.

**Interactions:**
- Clicking an item selects it and cues the stage to the most relevant moment (for example, the first caption with a name).
- Items the director owns open sheets that use the form components in `gate.css`.
- `⌘D` opens Deliver.

**Motion:** Progress bars update without easing jumps, interpolating over Settle per update. The shimmer applies only to items the editor is working on.

**Accessibility:** Items are a list, "Finishing, 3 of 6 done". Each reads as "Captions, editor and you, needs you: 41 English captions…, Check 2 names button."

**Acceptance:**
- [ ] Finish is unavailable until picture lock. It shows a disabled room segment with the tooltip "Lock picture first".
- [ ] No finishing action changes picture timing.
- [ ] Deliver is never blocked by open items; it warns instead (37).

## 37 · Deliver, choosing outputs
Frame: `screens/37-export.html` · Render: `renders/37-export@2x.png`

**Arrives from / leads to:** 36, via "Deliver…" (`⌘D`). Confirm leads to 38 (delivery runs, then completes). Cancel returns to 36.

**Layout:**
- A 640 pt sheet under the titlebar over the scrim.
- Head: Archivo 24/800 title and a format line.
- Body:
  - An outputs card (`.surface`) of `.out` rows: checkbox, a 40 pt thumbnail, name with spec line, and size (mono, right). Unchecked rows are at 50%.
  - A "Size" row, only when the cut's footage is bigger than the cut: a segmented control with the footage's size at the cut's shape ("3840 × 2160 · your footage", the default) and the cut's own ("1920 × 1080 · the cut"). Spec lines and estimates follow it.
  - A "Save to" row with a folder select.
  - An "Also" row with two checkboxes.
  - A red-bordered warning line.
- Foot: total size and free space at left, then Cancel and "Deliver 4 files" (steel).

**Content:**
- Title "Deliver Cut 4". Format line: "3:31 · 3840 × 2160 · 23.976 fps".
- Outputs:
  - Master: "ProRes 422 HQ · 3840 × 2160 · stereo + stems", ~38 GB (on).
  - Web: "H.264 · 1920 × 1080 · −14 LUFS", ~180 MB (on).
  - Vertical 9:16: "H.264 · 1080 × 1920 · reframed by the editor", ~120 MB (on), with the ion link "Review reframe (5 shots)".
  - Captions: "SRT and WebVTT · English · 41 lines", 8 KB (on).
  - Burned-in captions: "Adds a web copy with captions in the picture", ~180 MB (off).
- Save to: "Movies › Launch film › Delivery".
- Also: "Update the screening link to the final cut" (on), "Make a Finder alias on the Desktop" (off).
- Warning: ""North Light" still needs a music license. You can deliver, but don't publish yet."
- Foot: "4 files · about 38.3 GB · 312 GB free".

**States and variants:**
- The button label counts checked outputs ("Deliver 1 file"). It's disabled at 0 files, or when the size exceeds free space ("Not enough space on Macintosh HD").
- "Review reframe" opens the vertical crops on the stage, one per shot, with the options component for each.
- Output presets are editable in Settings › Cutting (not here).

**Interactions:**
- Clicking a row toggles it; `Space` toggles the focused row. `↩` delivers.
- The folder select offers recent folders and "Choose…".

**Motion:** The sheet appears with Glide. Totals update instantly.

**Accessibility:** Outputs are a group of checkboxes labelled "Outputs". The warning is a status message read after the title.

**Acceptance:**
- [ ] Size estimates update when outputs are toggled; the total includes only checked outputs.
- [ ] A 1920 × 1080 cut of 3840 × 2160 footage delivers at 3840 × 2160 by default: rendered at that size (titles drawn at it, effects scaled to it), not upscaled.
- [ ] Open finishing items appear as warnings but never block delivery.
- [ ] Delivery continues in the background; the pill shows "Delivering 2 of 4" with shimmer, and the Finish panel shows per-file progress.

## 38 · Delivered
Frame: `screens/38-delivered.html` · Render: `renders/38-delivered@2x.png`

**Arrives from / leads to:** 37, after every file is written. A notification is posted if the app is in the background ("Launch film is delivered"). From here: Show in Finder (primary), Copy link, or back to the checklist via the more menu.

**Layout:**
- The panel shows the hero (`.done-hero`) centered: a 48 pt green-wash circle with a check, the title in Archivo 24/800, and a meta line.
- Below: a list of files (`.file` rows, 36 pt thumbnail, name, mono meta, ghost Show), a screening-link notice, and a red notice for anything still open.
- Stage: the last frame, playhead at the end.

**Content:**
- Title: "Launch film is delivered". Meta: "Cut 4 · 3:31 · 4 files · Oct 28 at 16:40".
- Files:
  - "Launch film – Master.mov" (ProRes 422 HQ · 37.6 GB)
  - "Launch film – Web.mp4" (H.264 1080p · 176 MB)
  - "Launch film – Vertical.mp4" (H.264 1080×1920 · 118 MB)
  - "Launch film – Captions.srt" (SRT + VTT · 8 KB)
- Link notice: "Screening link updated": "Priya and Tom now see the final cut. Notes are closed on it." with a Copy link button.
- Open item: "Still open: a license for "North Light"."
- Primary: "Show in Finder".
- Foot: "Delivered files live in Movies › Launch film › Delivery."

**States and variants:**
- With no open items, the red notice is absent.
- Partial failure: the hero becomes "3 of 4 delivered" with a red row for the failed file and Retry.
- Re-delivering after changes (after unlocking picture and making a new cut) shows a "Delivered before" history line.

**Interactions:** Show reveals each file in Finder. Dragging a file row drags the file out (a file promise). `⌘C` on a row copies its path.

**Motion:** The success circle scales from 0.9 to 1 and fades in (Settle). No confetti, no sweep.

**Accessibility:** Announced: "Launch film is delivered, 4 files." Focus goes to Show in Finder.

**Acceptance:**
- [ ] File names follow "<Film title> – <Output>.<ext>".
- [ ] Sizes shown are actual, not estimates.
- [ ] The screening link is updated only if that option was on in 37.

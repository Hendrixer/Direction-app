# Dailies

**Purpose.** Every take, grouped by scene and setup, so the director can circle the ones they like, as a script supervisor would on set. Circles are the editor's first source when it assembles or recuts. The editor suggests (diamond); only the director circles (amber hand-drawn circle).

**Primary action.** "Assemble from circles" with the circle count (before the first cut). After a cut exists, the primary becomes "Use circles in next cut" with the count of circles changed since the last turnover; it adds a note "Use my new circles in scenes 2 and 4." to the sheet and opens Notes.

**Entry points.** Room switcher `⌘1`. Open Dailies from 05. "Open in Dailies" from a take anywhere. `⌘⇧1` jumps to Unsorted.

**Layout shared by 07–09.** Sidebar 240 pt (`.side`): header "SCENES" + add button; scene rows 30 pt (mono scene number 11 pt `--text-4`, title 13 pt, right-aligned count of circles in amber followed by a 7 pt amber ring; zero shows in `--text-4` without ring). Group label "NOT IN A SCENE" with Unsorted and Not usable. Footer (hairline above, 12/16 padding): "214 takes · 3 h 12 m" and "7 circled · 6 suggested" with ring and diamond.

---

## 07 · Dailies, circling takes
Frame: `screens/07-dailies.html` · Render: `renders/07-dailies@2x.png`

**Arrives from / leads to:** 05 Open Dailies, room switcher. Double-click a take or `Space` → 08. Assemble from circles → 06.

**Layout**
- Main 24/28 padding, 22 pt between blocks.
- Header: scene title Archivo 800 24 at 120% ("2 Maya, the problem"), 12 pt meta below: just "7 takes · 3:30". Right: filter segmented control "All 7 · Circled 1 · Suggested 2", and a ghost icon button for sort and display options.
- No editor note above the takes, and no help line: the suggestion lives on its take (diamond, "Suggested", the reason on hover and in 08), and the keys live in the bar at the bottom. Four kinds of text stacked above the first take (title, meta, note, hint, each its own size and colour) buried the pictures.
- Setup block: header row (mono 12 setup code, 12.5 description `--text-3`, take count right), then a 4-column grid with 14 pt gaps.
- Setup row: mono code, then the setup's description on one line (truncated, full text on hover), take count right.
- Take card: 16:9 thumbnail radius 7, take number top-left (mono 11.5 semibold, text shadow), duration bottom-right in a glass tag, suggestion diamond top-right (8 pt inset), and for a take in sync a dark pill bottom-left: link glyph, the other angles' labels in mono ("2B T2", "B1"), and a waveform glyph when the cut uses this take's sound. Under it, caption 12.5 pt, max 2 lines, then one status word 11.5 pt: "Circled" (amber), "Circled with B1" (amber at 60%, when an angle in sync is circled; the number gets the hand circle faint and broken), "Suggested" (ion), "Not usable as a take" (`--text-4`), or up to two flags.
- The bar (glass, centered, 16 pt above the bottom) is always there while the scene has takes. Nothing selected: "Select a take" and the keys, dimmed (Circle C, Watch ↩, Not Usable X). Takes selected: their label and the same actions, live.
- Labels never repeat a setup: a take coded "A1" in setup A is "A1", not "A A1".

**Content:** Story data, scene 2. Captions are the first line of dialogue in quotes, or a short description for B-roll. Status lines: "Flubbed line at 0:31", "Circled by you" (amber), "Suggested: warmest read" (ion), "Not usable as a take" (`--text-4`, card at 55% opacity), "B-roll", "Suggested: steadier", "Soft at 0:06". Editor note: "2A T3 has the warmest read of "Editing was the part nobody wanted." It fits "tired, then proud." Your circle decides; I only suggest."

**States and variants**
- Circled: amber hand-drawn circle (the `circle` path, 46 × 36 pt, 1.8 pt stroke) around the take number, plus a 1.5 pt amber ring around the thumbnail.
- Suggested: diamond top-right; status line in ion with the reason.
- Circled and suggested: both marks; status reads "Circled by you · also suggested".
- Hover (drawn on T3): the thumbnail lifts 4% and a tooltip "Circle T3 C" appears after 600 ms. Scrubbing horizontally across the thumbnail scrubs the take.
- The bar (see Layout) says what selecting is for; clicking a take was a dead end before it. The same bar shows in Unsorted and Not usable.
- Empty scene: centered "No takes in this scene yet. Drag takes here from Unsorted."

**Interactions:** Click selects; `C` or clicking the take number circles/uncircles; `X` marks Not usable; `Space` or double-click opens 08; arrows move; `⌘A` then `C` circles all selected. Drag takes between setups or onto a sidebar scene. Context menu on a take: Circle, Play, Open in Script, Move to Scene ›, Not usable, Show in Finder.

**Motion:** The circle draws itself along its path over Settle (220 ms) when added; removing fades it out over Snap. Reduce Motion: appear instantly.

**Accessibility:** Take cards are buttons: "2A Take 3, 46 seconds. Editing was the part nobody wanted. Suggested by the editor: warmest read. Not circled." Action "Circle" via VoiceOver rotor. The circle state is announced as "Circled", never only by color.

**Acceptance**
- [ ] The amber circle appears only after a director action; the editor never sets it.
- [ ] A suggested take shows the diamond and the reason text.
- [ ] Primary count equals the number of circled takes across all scenes (7).

---

## 08 · Dailies, one take open
Frame: `screens/08-dailies-take.html` · Render: `renders/08-dailies-take@2x.png`

**Arrives from / leads to:** Space or double-click on a take in 07. "All takes" or `esc` → 07. Left and right arrows move through takes in the setup; up and down change setups.

**Layout**
- Viewer region (black) + 320 pt info panel (ground, left hairline).
- Viewer: header row 14/20 padding (back button, take code semibold 15, setup and file name 12 pt `--text-3`, suggestion chip right). Picture 16:9 at full width with a glass time tag bottom-right. Transport: play/pause, timecode, a single-take strip (24 pt, one segment), volume. Reel row (hairline above): the setup's takes as 150 pt thumbnails, the open one with a 2 pt `--text-1` ring, a keyboard hint right.
- Info panel: editor's reason as a `.say` (top block with hairline), the transcript (52 pt mono time column, 13 pt lines; past lines `--text-3`, the current line `--text-1`, future `--text-2`, stage directions italic), then a footer with the circle button and secondary actions.
- Circle button: 40 pt tall, radius 10, 1.5 pt amber border at 55%, amber label "Circle this take" with the circle glyph and a `C` key cap. Circled state: amber wash fill, label "Circled", glyph solid.

**Content:** 2A T3, A011_C002_1021.mov, 0:46, playhead 00:19:02. Reason: "Warmest read of the line, and she holds the look after it for two seconds." / "Fits "tired, then proud." T2, your circle, is a little faster." Secondary: "Not usable X", "Open in Script".

**States and variants:** Playing (drawn) and paused. A take in sync with others gets an **Angles** row above the transcript; switching keeps the same moment (footage-index.md › Sync). Takes with no transcript show "No dialogue" and a waveform instead. Flubbed takes show an alert chip at the flub time in the transcript.

**Interactions:** Space play/pause; J K L shuttle; `C` circle; `X` not usable; `←`/`→` previous/next take, keeping the playhead's relative position so readings can be compared; clicking a transcript line seeks to it.

**Motion:** Switching takes cross-fades the picture over Snap. Transcript auto-scrolls to keep the current line in the upper third (Glide).

**Accessibility:** Transcript is a list; the current line has the "selected" trait. Circle button label "Circle 2A Take 3".

**Acceptance**
- [ ] Changing takes with the arrows keeps the playback position within the line.
- [ ] Only the circle button and the reel's circled take use amber in this frame.

---

## 09 · Dailies, unsorted footage
Frame: `screens/09-dailies-unsorted.html` · Render: `renders/09-dailies-unsorted@2x.png`

**Arrives from / leads to:** sidebar Unsorted, `⌘⇧1`, or the "14 unsorted" toast after logging. Moving all clips leaves the empty state.

**Layout**
- Header: "Unsorted" Archivo 24, 12 pt explanation, a default button "Accept 9 guesses" on the right.
- Grid: 5 columns, 14 pt gaps. Card = thumbnail, 12.5 pt description, guess row: diamond + ion "Probably 4" + small "Move" button right; or `--text-4` "No guess · room tone".
- Footer line 12 pt: "4 more below · Unsorted takes are never used in a cut until they're in a scene."

**States and variants**
- Dragging (drawn): the source card shows "Being dragged" at 55% opacity; a ghost thumbnail (168 pt, −3°, 92% opacity, deep shadow) follows the pointer; the target sidebar row gets `--raised` with a 1.5 pt `--text-1` ring; a tooltip "Move to 4 Building it" follows.
- Drop: the card collapses out of the grid (Settle), the scene's count in the sidebar ticks up.
- Empty: "Everything's in a scene." with the subline "The editor will put new footage here if it can't place it."
- Accept guesses: confirm-less; shows a toast "Moved 9 takes. Undo ⌘Z".

**Interactions:** Drag cards onto sidebar scenes or onto a setup in a scene view. "Move" accepts that card's guess. Multi-select with `⌘`/`⇧` click and drag together. `N` on a selection creates a new scene from it ("Untitled scene"), focus moves to its name.

**Motion:** Ghost follows the pointer with no lag. Cards reflow with Glide.

**Accessibility:** Each card offers actions "Move to scene 4 (editor's guess)", "Move to scene…", "Not usable". Drag and drop has a keyboard alternative: `M` opens a scene picker.

**Acceptance**
- [ ] Guesses use the diamond and ion text; nothing here uses amber except the sidebar circle counts.
- [ ] "Accept N guesses" counts only cards with a guess.
- [ ] Unsorted takes never appear in a cut.

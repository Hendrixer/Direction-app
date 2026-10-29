# Script

**Purpose.** Direct the words. The cut's dialogue is laid out like a screenplay with a lined-script coverage margin. The director never edits text. Each gesture creates a numbered note with a `line` anchor (see `product-model.md › Script`), which goes through turnover like any other note.

| Gesture | How | Note created | Kind |
|---|---|---|---|
| Strike | Select line(s), `⌫` or Strike | "Lose "…"." | Story |
| Hold | Select a passage, `H` or Hold | "Let this breathe." (editable) | Pace |
| Move | Drag a line or paragraph to a new place | "Move "…" after "…"." | Story |
| Readings | `R`, or click a line number | "Use 2A T3's reading." when one is chosen | Feeling |

**Primary action.** "Turn over" (same as Notes; it turns over the whole sheet, including script notes).

**Entry points.** Room switcher `⌘2`. "Open in Script" from Dailies. Clicking a line-anchored note in Notes opens Script scrolled to that line.

**Layout shared by 10–12**
- Three columns: outline 200 pt (scene list, then a "GESTURES" legend with shortcuts), script page (flexible, `--sunken`), side panel 360 pt (ground).
- Script toolbar, 44 pt, hairline below: "Find a line" field (220 × 26), "Follow playback" switch, and a legend right: on camera (solid steel-6 bar), off camera (dashed), in the cut (amber).
- Page: a 700 pt column centered, 28 pt top padding below the toolbar. Head row: "CUT 3 · AS CUT, 1:20 OF DIALOGUE" label left; coverage header right (112 pt: "2A" over 4 columns, "2B" over 3, take numbers below in mono 9).
- Row grid: 40 pt line number (mono 11, right-aligned, `--text-4`) · 14 pt gap · text · 14 pt gap · 112 pt coverage (7 columns × 16 pt). Rows are exactly 30 pt tall; text 15/30 SF Pro. The speaker name sits in a 96 pt column (mono 11 semibold, uppercase, `--text-3`) on the first line of a speech; continuation lines indent 96 pt. Stage directions are italic `--text-3` and indent 96 pt.
- Scene headings: mono 13 bold uppercase slugline + the scene title in 12 pt SF `--text-4`, scene number in the line-number column, 18 pt above.
- Coverage: a 2 pt vertical bar per take, centered in its column, running through every line that take covers. Solid steel-6 = on camera; dashed (3 on / 3 off) = off camera (the line is heard but the speaker isn't in shot); amber = the take used in this cut. Bars are continuous across rows because rows have no gaps.
- Side panel: a 16:9 picture following the playhead with a play button, timecode and "Line 12 · 2A T2", then "Script notes" with a count.

---

## 10 · Script, reading
Frame: `screens/10-script.html` · Render: `renders/10-script@2x.png`

**Arrives from / leads to:** room switcher. Select lines → toolbar (11). `R` → 12.

**Content:** Scene 1 (lines 4–6, voice-over, coverage note "Voice-over, no picture coverage"), scene 2 (lines 7–16), the start of scene 3 (line 17). Line text exactly as in the frame. Current line 12 highlighted (white 5% row fill, line number `--text-1`). Side panel empty state: "Script notes 0", "Direct the words. Strike a line to lose it, hold a passage to let it breathe, drag a line to move it, or press R to hear every reading." / "Each gesture becomes a numbered note on the sheet. Nothing changes in the cut until you turn over." / editor line "Lines 7–16 are from 2A T2, your circle. Line 12 has four other readings."

**States and variants**
- Follow playback on: the current line highlight moves with the picture and the page scrolls to keep it in the upper third. Scrolling by hand turns follow off until a line is clicked.
- No transcript yet (logging): page shows skeleton rows (sunken bars) and "Transcribing… 96 of 214 takes".
- Imported script: lines not found in any take show with no coverage and a 12 pt `--text-4` "Not shot" in the coverage column.
- Hover on a line: row fill white 3%, and a grip appears in the line-number column for dragging.

**Interactions:** Click a line to seek the picture to it. `⇧`-click extends a selection. `⌘F` find. Space plays from the current line.

**Motion:** Current line highlight moves with Snap. Auto-scroll uses Glide.

**Accessibility:** The page is a list of lines; each line reads "Line 12, Maya: Editing was the part nobody wanted. Covered by 2A takes 2, 3, 4 and 2B takes 1, 3. In the cut from take 2." Coverage is never conveyed by the bars alone.

**Acceptance**
- [ ] Rows are 30 pt and coverage bars are continuous across consecutive covered lines.
- [ ] Only the take in the cut is amber in the coverage margin.

---

## 11 · Script, struck, held and moved lines
Frame: `screens/11-script-marked.html` · Render: `renders/11-script-marked@2x.png`

**Arrives from / leads to:** gestures made in 10. Notes created here appear in Notes (17) with a script chip; the Notes badge counts unwritten or new notes (3).

**Content**
- Note 5, strike on line 14: text struck with a 2 pt amber line, text dimmed to `--text-3`. Amber number tag "5" in the left gutter (10 pt mono on amber, director-ink text).
- Note 8, hold on lines 10–11: selection wash (`--director-wash`, radius 4 on the block's outer corners) and an amber bracket 2 pt at x 46 of the row with 6 pt caps. Tag "8" in the gutter.
- Note 9, move line 16 to after line 12: line 16 dims to `--text-4` with an amber "→ after 12" suffix; an amber 2 pt insertion line with a dot at its left end sits between lines 12 and 13 and carries a tag "9 · line 16 here".
- Selection toolbar (glass, radius 10, 4 pt padding) at the right end of the selection: Strike, Hold (pressed, labeled "Held"), Move, Readings as 26 pt icon buttons; the active one shows its label.
- Side panel "Script notes 3": note rows like the notes sheet, each with an amber anchor chip with the gesture icon ("Line 14", "Lines 10–11", "Line 16 → after 12") and the kind chip. Note 8 is being edited: focused field with the default text "Let this breathe." and the hint "Edit the words or press ↩ to keep them."

**States and variants**
- Any gesture can be undone with `⌘Z`. The mark disappears and the note becomes `dropped`; its number is never reused.
- Striking a must-keep line: the strike is refused, the line shakes once, and a toast reads "That line is a must-keep in your brief. Change the brief to cut it."
- Moving across scenes is allowed; the insertion line shows the scene heading it lands under.
- Striking a line in a locked scene: toast "Scene 5 is locked. Unlock it to give notes here." with "Unlock".

**Interactions:** `⌫` strike, `H` hold, drag the grip to move, `R` readings, `↩` writes the default text, `⌘↩` turn over. Clicking a gutter tag selects the note in the side panel and vice versa. Context menu on a line: Strike, Hold, Readings, Copy Line, Show in Dailies.

**Motion:** Strike line draws left to right over Settle. Bracket grows from the first line to the last over Settle. During a drag, lines part to show the insertion point with Glide.

**Accessibility:** Struck lines read "struck, note 5". Selection toolbar buttons have labels and shortcuts. Gestures are available from the context menu and the Note menu, so nothing requires dragging.

**Acceptance**
- [ ] No text in the script is ever editable.
- [ ] Every gesture creates exactly one note with the next unused number.
- [ ] All three marks use amber plus a distinct shape (strike line, bracket, insertion line).

---

## 12 · Script, other readings of a line
Frame: `screens/12-script-readings.html` · Render: `renders/12-script-readings@2x.png`

**Arrives from / leads to:** `R` on a selected line or clicking its line number. Use this → creates note "Use 2A T3's reading." and closes. `esc` closes.

**Layout**
- Popover (`.pop`, radius 12, 620 pt wide) placed above the line so the line stays visible and highlighted (line 12 with the amber selection wash).
- Header 14/16 padding: label "LINE 12 · 5 READINGS", close button, the line in quotes at 15 pt.
- Rows (8/16 padding, hairline between): play button 22, thumbnail 64 × 36, take code (mono 12 semibold) + setup (11 pt `--text-4`), waveform of just that line (flexible), line duration mono, right column 170 pt for tags and action.
- Footer 12 pt `--text-3`: "Choosing a reading adds a note: "Use 2A T3's reading." It's cut at turnover."

**Content (line 12)**
| Take | Duration | Right column |
|---|---|---|
| 2A T2 | 2.4 s | amber chip with ring "In Cut 3" |
| 2A T3 (playing, row `--raised`) | 2.9 s | ion chip with diamond "Warmest", "Use this" |
| 2A T1 | 2.1 s | wording difference in quotes: "Editing was the part no one…" |
| 2B T2 | 2.3 s | "Off camera" |
| 2A T4 (55% opacity) | 1.2 s | "Breaks off, laughs" |

**States and variants:** Hovering a row shows its "Use this" button (only the hovered or playing row shows it). Readings are ordered: in the cut first, then editor suggestion, then others by take number, unusable last. If the line exists in only one take: popover shows that take and "This is the only reading."

**Interactions:** `↑`/`↓` move rows and play each reading from the start of the line automatically; Space toggles play; `↩` uses the focused reading; `esc` closes. Playback in the popover plays only the line plus 0.5 s either side.

**Motion:** Popover appears with Settle (scale 0.98 → 1, fade). Playing row's waveform shows a playhead; nothing else moves.

**Accessibility:** Rows are buttons: "2A Take 3, 2.9 seconds, editor suggests: warmest. Use this reading." Focus starts on the row in the cut.

**Acceptance**
- [ ] The line being compared stays visible outside the popover.
- [ ] Picking a reading creates a Feeling note with a line anchor and does not change the cut.
- [ ] The take in the cut is labeled with the amber ring chip, the suggestion with the diamond chip.

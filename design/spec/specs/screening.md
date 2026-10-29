# Screening

**Room overview.** Screening is for watching a cut straight through, the way a director watches in a dark room: no sidebar, no edit controls, nothing that invites stopping. The only act is a **mark** (`N`), which drops an amber pin at the current time without pausing. Marks become draft notes in the Notes room when the screening ends. The picture is letterboxed full-bleed on `--canvas`; all chrome is glass or overlay and hides after 2 s of no pointer movement.

Shared layout (frames 13–16):
- Window 1440 × 900. Picture at the cut's own aspect, fitted to the window width and centered vertically. At 2.39:1 that's 1440 × 602 at y 149. A 16:9 cut fits 900 tall and pillarboxes.
- **Titlebar overlay** (`.tb.over`): 52 tall, transparent with a 70% → 0% black gradient. Same content as the main titlebar, except the crumb has no chevrons and the right side shows the editor pill plus **End screening** (`esc`), a ghost button. There's no steel button in the titlebar during playback.
- **Dock** (`.dock.glass`): 960 × 54, centered, 24 from the bottom, radius 16. From the left: play/pause (ghost icon 28, 18 pt glyph), timecode, scene strip (flex), mark count chip (`.chip.d`), volume, full screen.
- Grain overlay stays on the chrome, never on the picture. In frame 14 it's off entirely.

Keys in every Screening state:

| Key | Action |
|---|---|
| `space` | Play / pause |
| `N` | Drop a mark at the playhead. Never pauses. |
| `⌘Z` | Undo the last mark (while its toast is up, or any time before the screening ends) |
| `←` / `→` | Back / forward 5 s (shows the chrome) |
| `⇧←` / `⇧→` | Previous / next scene |
| `J` `K` `L` | Shuttle |
| `F` / `⌃⌘F` | Full screen |
| `esc` | End screening. Opens frame 16 if any of the cut was watched, otherwise returns to the previous room. |
| `⌘1`…`⌘6` | Rooms (leaving ends the screening, and marks are kept) |

---

**Leaving.** Going to any other room (the switcher, ⌘1–⌘6, esc) stops the cut where it is; the playhead stays. Nothing plays in a room the picture isn't in. The same holds between every room, and for Play changes.

## 13 · Screening, playing
Frame: `screens/13-screening.html` · Render: `renders/13-screening@2x.png`

**Arrives from / leads to:**
- Arrives from the **Screening** room tab (`⌘3`), "Watch it" in the Cut ready toast, or **Watch again** in frame 16.
- Leads to frame 14 (2 s idle), frame 15 (`N`) and frame 16 (end of the cut, or `esc`).

**Layout:**
- Picture: 0, 149, 1440 × 602.
- Titlebar overlay: 0, 0, 1440 × 52. Rooms control centered at 522, 12 (396 × 28).
- Editor pill: 1192, 12. End screening: 1275, 12 (153 × 28).
- Dock: 240, 822, 960 × 54. Play at 251, 837. Timecode at 289, 845. Strip at 410, 829 (612 × 44). Mark count at 1032, 841. Volume at 1119, 837. Full screen at 1157, 837.
- Hint: centered, 112 from the bottom, 12 pt `--text-3`.

**Content:**
- Crumb: "Launch film / Cut 3".
- Timecode: "01:12:08 / 3:40". The current time is `--text-1`; "/ 3:40" is `--text-4`.
- Strip: scenes 1–5 at flex 14, 22, 18, 26, 20, with names in 10 pt mono, ellipsized. Scene 5 is hatched and grayscale, with a lock glyph before the name.
- Two pins at 8.2% and 21%. Playhead at 32.7%.
- "2 marks" chip.
- Hint "Press N to mark a moment. Playback won't stop." Show it only during a film's first two screenings, then never again.

**States and variants:**
- Drawn: playing, chrome visible.
- Paused: the play glyph replaces pause, the chrome stays visible, and the hint hides.
- Buffering: a `.spinner` replaces the play glyph. The timecode keeps running from the last frame shown.
- Zero marks: the mark chip reads "No marks" in `.chip.k`.
- Current scene: the strip's `.sc.cur` at 80% footage opacity.
- Changed scenes (when screening a new cut): a 2 pt prism top edge on each `.sc.chg`.

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

## 14 · Screening, controls hidden
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

## 15 · Screening, mark dropped
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
- Mark numbers count up within a screening. In Notes, each mark gets the next permanent note number, so mark 3 here becomes note 3 in frame 17.

**States and variants:**
- From frame 14, where the chrome is hidden: only the toast appears, top-right. The dock stays hidden. The quiet mark count updates to 3.
- Two marks within 1 s merge into one, and the toast re-times. Marks closer than 0.5 s are ignored.
- Marking inside a locked scene is allowed. The draft note will be flagged later in Notes.

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

## 16 · Screening, end of cut
Frame: `screens/16-screening-end.html` · Render: `renders/16-screening-end@2x.png`

**Arrives from / leads to:**
- Arrives from playback reaching the end of the cut, or `esc` after watching any part of it.
- **Write notes** leads to frame 17, with the drafts selected from the first mark. **Watch again** leads to frame 13 from 00:00.
- `esc` again goes to Notes with no draft selected.

**Layout:**
- The last frame is held, dimmed to brightness .32 and saturate .6.
- End card (`.glass`): 640 × 289, centered at 400, 306, radius 20, padding 32/32/26.
  - Eyebrow label.
  - `.brand-xl` title.
  - 14 pt lede in `--text-2`.
  - Strip at 56 tall with 30 pt scenes; no playhead.
  - Actions row: `lg` ghost **Watch again** on the left, `lg` steel **Write notes** on the right.

**Content:**
- Eyebrow: "End of screening · 3:40".
- Title: "That's Cut 3." (the cut name).
- Lede: "You dropped 4 marks. Write them up while it's fresh, then turn the sheet over."
- Strip: four pins at 8.2, 21, 32.7 and 47%.

**States and variants:**
- 0 marks: the lede reads "No marks this time." The primary button becomes **Back to notes**, and **Lock picture…** appears as a ghost button if every note is accepted.
- 1 mark: the lede says "1 mark".
- Ended early by `esc`: the eyebrow reads "Stopped at 02:10 of 3:40". Add a ghost **Keep watching** before **Watch again**.

**Interactions:**
- `↩` presses **Write notes**. `⌘R` presses **Watch again**.
- Clicking a pin goes to Notes with that draft selected.

**Motion:**
- The picture dims over Glide.
- The card enters with Glide: opacity plus a scale from .98.

**Accessibility:**
- Focus starts on **Write notes**.
- The card is a dialog titled "That's Cut 3."

**Acceptance:**
- [ ] Exactly one steel button.
- [ ] The title uses the actual cut name: "That's Assembly." or "That's Cut 4."
- [ ] The marks count matches the strip.
- [ ] Clicking a pin opens its draft in Notes.

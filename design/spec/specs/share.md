# Share and the Editor popover

Frames 39–41. Sharing sends a cut to people outside the room. Their notes never reach the editor unless you accept them (see `product-model.md › Outside notes`). The Editor popover is the one place that shows the editor's whole state.

Shared styles live in `css/system.css` (`.av`, `.lrow`).

---

## 39 · Share a screening link
Frame: `screens/39-share.html` · Render: `renders/39-share@2x.png`

**Arrives from / leads to:** Share button in the titlebar (icon button left of the primary, `⌘⇧S`), File › Share Cut…, or the command menu. Leads back to the room it came from. "Share a different cut…" swaps the cut picker into the sheet's title. Viewers then see frame 40, and their notes land in the Cut room › Outside (frame 21).

**Layout:**
- Sheet 580 wide, attached under the titlebar (y 52), centered on the window, with radius 0 0 14 14. A 55% black scrim covers the content below the titlebar only, and the titlebar stays live.
- Head padding 20/22/6. Body padding 14/22 with a 14 gap. Footer 14/22/18 with a hairline on top.
- Link row: a 28-tall input with flex 1 in SF Mono 12 / text-2, and a default **Copy link** button to its right.
- Options card: a `.set-card` with 4 `.set-row`s (min 44 tall).
- People: a 10.5 label, then `.lrow`s (min 40, hairline between), each with a 24 avatar, name and role, a status line, and a permission select. Last row: an "Add people by email" input plus **Invite**.
- Footer: **Stop sharing** (ghost, alert color) on the left, then a spacer, then **Share a different cut…** (ghost) and **Done** (steel, the sheet's default button, `↩`).

**Content:**
- Title "Share Cut 3" in Archivo 17/700/112%.
- Sub: "People with this link can watch Cut 3 in a browser. Their notes come to your Outside inbox. The editor never sees them until you accept one."
- URL: `direction.film/s/<film-slug>-c<cut number>-<4 random>`.
- Options, with their defaults from Settings › Sharing:
  - Viewers can leave notes: on.
  - Link expires: "In 7 days · Nov 4". Choices: Never, In 1 day, In 7 days, In 30 days, On a date….
  - Require a password: off. Turning it on reveals an input row "Password" under it.
  - Allow download: off. Sub-label: "Off: viewers can only stream, with a watermark of their name."
- People rows: name · role (text-3), then status in 11.5 text-3, e.g. "Watched all of Cut 3 · yesterday · 1 note" or "Watched to 03:31:00 · today 09:12 · 2 notes".
- Permission select: "Can leave notes", "Can watch", "Remove".
- Names truncate with an ellipsis. The status line truncates first.

**States and variants:**
- Drawn: an existing link with two viewers.
- **Not yet shared:** the URL input shows "Creating link…" with a spinner for under 1 s, the People list is empty, and the footer reads Cancel / **Create link** (steel). Nothing is shared until Create link.
- **Copied:** the Copy link label changes to "Copied" with a check for 1.6 s.
- **Expired link:** an inline `.banner` under the head: "This link expired Nov 4." with a **Renew for 7 days** button.
- **Offline:** every control is disabled, and the head adds "You're offline. Sharing waits until you're back."
- **Stop sharing** confirms with a native alert: "Stop sharing Cut 3? Priya and Tom won't be able to open the link. Their notes stay in your inbox." Buttons: Stop sharing (destructive) / Cancel.

**Interactions:**
- `⌘C` with the sheet open copies the link.
- `esc` closes, and so does Done.
- Return in the email field sends the invite. Comma-separated emails are allowed.
- An invite sends an email from Direction: "<director> shared Launch film · Cut 3 with you."

**Motion:** The sheet slides down from the titlebar in Glide (360 ms, `--e-out`) and the scrim fades in Settle. Rows that are added or removed use Settle.

**Accessibility:**
- The sheet is labeled "Share Cut 3".
- Focus order: URL, Copy link, the four options, people rows, email field, Invite, Stop sharing, Share a different cut, Done.
- Each switch is announced with its label and its sub-label as the hint.

**Acceptance:**
- [ ] The sheet is exactly 580 wide, attached at y 52, with only bottom corners rounded at 14.
- [ ] Defaults come from Settings › Sharing (frame 48), not hard-coded.
- [ ] Outside notes never appear in the editor's input until accepted (verify with a test).
- [ ] Avatars are neutral steel with initials. There is no amber anywhere in this sheet.
- [ ] Done is the only steel button.

---

## 40 · Screening link in a browser
Frame: `screens/40-share-viewer.html` · Render: `renders/40-share-viewer@2x.png`

**Arrives from / leads to:** A viewer opens the link from frame 39. Their notes appear in the director's Cut room › Outside (frame 21). This is the web viewer, a separate small web app that uses the same Gate tokens through `gate.css`.

**Layout:**
- The browser chrome (44 tall) is drawn only for context. The page starts at y 44.
- Header 56 tall with padding 0/20: the 22 app icon, the film name in Archivo 14/700, "/", the cut name in 13/500 text-2, and a chip "3:40 · shared with you until Nov 4". On the right: "Watching as", a 18 avatar and the name.
- Body grid: picture stage (flex) | a 380 notes column with a hairline left border. This is the same proportion as the director's Cut room.
- Stage: a 16:9 frame with 28 padding. The transport row holds play, timecode, the scene strip and full screen.
- Notes column: head ("Your notes" in Archivo 17), a list, and a composer at the bottom.

**Content:**
- Picture HUD, top right, glass: "TOM REYES · NOT FOR DISTRIBUTION". This watermark is always on unless the link allows download.
- Notes column sub: "The director reads every note and decides what goes to the edit. Others can't see your notes."
- Each note row: an 18 avatar instead of a number, a time chip in neutral (not amber), a "Sent today 09:10" chip in `.chip.k`, and the text.
- Composer:
  - "At" plus a neutral time chip, with the hint "Press N to pick this moment" on the right.
  - A textarea.
  - "Notes are sent as Tom Reyes" and **Send note ⌘↩** (steel).
- The scene strip shows scene names and the viewer's own notes as **neutral pins** (`.mk.pin.out`, text-2). The locked-scene hatching is not shown to viewers, and nor are other people's pins or the director's notes.

**States and variants:**
- **First visit:** a centered modal over the page: "Who's watching?" with a name field, an email field (optional) and **Start watching**. Required only when the link has no invitee identity.
- **Password:** a modal with a single password field and **Open**.
- **Notes off:** the notes column is replaced by a 380 panel with the film name, the duration and "Notes are turned off for this link."
- **Expired / stopped:** a full page empty state with the app icon: "This link has ended. Ask the director for a new one."
- **Newer cut exists:** a top banner: "The director has shared Cut 4." with an **Open Cut 4** link. Shown only if Cut 4 is shared too.
- **Sent:** after sending, the row appears at the top of the list (Settle) and the field clears.
- **Narrow (< 900 px):** the notes column moves under the picture.

**Interactions:**
- Space plays and pauses. J/K/L, ←/→ and N work as in the app.
- Clicking the strip seeks.
- Clicking a note seeks to it.
- A viewer can edit or delete their own note until the director accepts it. After that it shows "Accepted by the director" in text-3 and is read-only.

**Motion:** Only Settle and Snap are used. There's no prism sweep and no shimmer, because the editor isn't present on this page.

**Accessibility:**
- The page has `lang` and a landmark for each column.
- The player keyboard shortcuts are listed behind a "?" link in the header.
- The watermark is `aria-hidden`.

**Acceptance:**
- [ ] No amber and no diamonds anywhere on the page. The viewer is neutral.
- [ ] The watermark is burned into the stream server side when download is off, not just drawn on top.
- [ ] Sent notes arrive in the Cut room › Outside with author, cut, anchor and text.
- [ ] A viewer can't see the director's notes or other viewers' notes.

---

## 41 · Editor popover
Frame: `screens/41-agent-popover.html` · Render: `renders/41-agent-popover@2x.png`

**Arrives from / leads to:**
- Opens on a click of the editor pill in any room's titlebar, or with Film › Editor… (`⌘⇧E`).
- Leads to Settings › Editor (frame 43) via "Editor settings…".
- In other editor states the popover body changes. See the states below.

**Layout:**
- An NSPopover-style panel 360 wide, anchored below the pill: the top edge 6 below the titlebar's bottom edge minus 12 (y 46). Use the system popover arrow centered on the pill.
- Background `--panel`, radius 12, shadow per `.pop`.
- Sections are separated by hairlines, with padding 14/16:
  1. Status: a diamond, "Editor" in Archivo 14/700, and a status chip on the right. Below it, one sentence in 12 text-2.
  2. "How much freedom": three radio rows (13 label, 11.5 text-3 explanation).
  3. "Speed and quality": the film's slider, Faster · Balanced · Best, with its line under it (editor.md › Speed and quality). Disabled while the editor works, with "Applies from the next turnover."
  4. "Recent": up to 3 activity rows, each with a 14 diamond, text and an SF Mono 11 time.
  5. Footer: **Pause editor** (ghost sm, left) and **Editor settings…** (ghost sm, right).

**Content:**
- Status sentence (Ready): "Nothing in progress. Your 6 notes on Cut 3 are waiting. Turn them over when you're done."
- Latitude labels exactly as in `product-model.md`:
  - **Do what I wrote:** "Changes only what each note names. Asks when unclear."
  - **Read between the lines:** "Interprets intent. Cuts Feeling notes two ways."
  - **Take a pass:** "May suggest changes you didn't ask for, marked Unasked."
- Recent:
  - "**Cut 3 is ready.** Answered 5 notes, −12 s." Oct 26 14:20. Prism diamond: the latest event.
  - "Read back 5 notes. You approved all of them." Oct 26 13:58. Solid ion diamond.
  - "Logged and transcribed 214 takes." Oct 20 10:04.

**States and variants** (same popover, different section 1):

| Editor state | Pill | Status chip | Section 1 sentence | Extra |
|---|---|---|---|---|
| Ready | `.agent` "Ready" | `.chip.ok` Ready | as drawn | — |
| Reading back | `.agent.working` "Reading back" | `.chip.a` Reading back | "Reading your 6 notes. A plan will be ready in a moment." | — |
| Waiting on read-back | `.agent.asks` "Read-back ready" | `.chip.a` Waiting for you | "The plan for Cut 4 is ready for your OK." | **Open read-back** (default button) |
| Cutting | `.agent.working` "Cutting 3 of 6" with meter | `.chip.a` Cutting | "Cutting Cut 4. Note 3 now: reframing The ridge." | Per-note checklist (✓ done, spinner current, dim pending) and an "About 2 min left" caption |
| Questions | `.agent.asks` "2 questions" | `.chip.a` 2 questions | "I need your call on 2 things before I finish Cut 4." | **Answer** opens the Cut room's Questions tab |
| Can't | `.agent.blocked` "Can't do 1" | `.chip.bad` Can't do 1 | "I can't do note 7 without unlocking Launch day." | **Show me** opens frame 26 |
| Paused | `.agent` with a pause glyph, "Paused" | `.chip` Paused | "Paused. Nothing will change until you resume." | The footer button becomes **Resume editor** |
| Offline | `.agent` with the offline icon, "Offline" | `.chip` Offline | "You're offline. I'll pick up when you're back." | Latitude is disabled |

- Changing latitude here changes the film's default and is the same setting as Settings › Editor.
- During Cutting, latitude is disabled with the caption "Applies from the next turnover."

**Interactions:**
- Click outside or `esc` closes.
- ↑/↓ moves between the latitude radios, and Space selects.
- Clicking an activity row jumps to it: a cut opens Changes, a read-back opens Notes.
- Pause editor stops work after the current note finishes and shows "Pausing after note 3…" until then.

**Motion:** Opens in Settle with a scale from 0.98 and a fade. The pill uses Shimmer (2.4 s loop) only in the working states. Reduce Motion gives the pill a static prism border.

**Accessibility:**
- The pill is announced as "Editor, Ready, button". The popover is labeled "Editor".
- The status chip text is included in the announcement.
- The latitude radios form a radio group named "How much freedom".

**Acceptance:**
- [ ] The pill text always matches the current editor state from the table above. It must never show Ready while work is pending.
- [ ] The latitude radio is bound to `Film.latitude`.
- [ ] Pause leaves no partly-applied note in the cut.
- [ ] Diamonds: prism for the most recent event, solid ion for older ones. Never amber.

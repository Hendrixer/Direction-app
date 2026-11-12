# Settings

Frames 42–48 and 54. Opens with Direction › Settings… (`⌘,`). It's a standard macOS Settings window with toolbar-style tabs, and it is not a sheet. In SwiftUI use a `Settings { TabView { … } }` scene with `.tabViewStyle(.automatic)` and the Gate styling below.

## Window

| Part | Spec |
|---|---|
| Size | 940 wide and 760 tall, or the screen's visible height less the title bar and 48 pt on a smaller screen (at least 420). One size for every section, like System Settings: the window never resizes when the section changes, so it never runs off the screen. (It used to fit each section's height, and a tall section grew it down past the bottom of the screen.) |
| Title bar | The window's own, in the ground color, titled with the section's name, traffic lights at x 20. |
| Sidebar | 196 wide on the left, `--panel` at 50%, a hairline on its right. One item per section, top to bottom: an 18 icon and the 13 pt name, 30 tall, gap 2, padding 12/10. The chosen one: `--raised` fill, radius 7, text-1, medium weight; the rest text-2. Order: General, Editor, Engines, Cutting, Notifications, Shortcuts, Storage, Sharing. `⌘1`…`⌘8` choose a section while Settings is key. A remembered Footage or Services section opens Engines. |
| Section | The rest of the width (743). It scrolls when it's taller than the window (Engines does); it starts at the top whenever another section is chosen, and only its content fades in (160 ms, ease-out). Snapshots draw the whole section. |
| Body | Padding 4/28/22. Each group is a label (`.label`, 14 above and 7 below) plus a `.set-card` (`--panel`, radius 10, hairline). |
| Row | `.set-row`: min 44 tall, padding 10/14, hairline between rows. The label is 13/400, with an optional 11.5 text-3 sub-label under it. The control sits on the right. |
| Notes | `.set-note`: 11.5 text-3, padding 8/2/0, under a card. |
| Controls | `.switch` (32×18), `.select` (pop-up button, 28 tall), `.seg` (segmented), `.stepper`, `.input`, `.btn`. Never use checkboxes in Settings. |

Every change applies immediately. There is no Save button. Settings are app-wide unless marked **per film**. A per-film setting changes the default for new films and for the film that's open now. Its sub-label says "For this film" when the open film differs from the default.

---

## 42 · Settings, General
Frame: `screens/42-settings-general.html` · Render: `renders/42-settings-general@2x.png`

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Start | When Direction opens | Select: Reopen the last film / Show Films / Start a new film | Reopen the last film | The window shown at launch. |
| Start | Show Films when no film is open | Switch | On | When the last film window closes, the Films window opens. Off quits the app instead. |
| Playback | Start screenings full screen | Switch | Off | Watching through (`W` or Cut › Watch Through) also enters full screen. Going back to notes leaves the full screen it entered; a window that was already full screen stays so. |
| Playback | Hide controls while watching after | Select: 1 second / 2 seconds / 4 seconds / Never | 2 seconds | Idle time before watching through goes to frame 14 (picture only). |
| Playback | Audio output | Select: System default / every Core Audio output | System default | The playback device. |
| Look | Film grain | Switch | On | The 3.5% grain over UI surfaces. It's never drawn over the picture. |
| Look | Reduce motion | Select: Follow system / On / Off | Follow system | Replaces shimmer with a static prism edge, sweeps with fades, and slides with fades. |

Footer, centered 11.5 text-3: "Direction 1.0 (214) · Check for updates". The second part is a text-2 link.

**Acceptance:**
- [ ] Changing "Hide controls after" takes effect on the next idle, without restarting.
- [ ] Grain off removes the overlay from every window, including Settings.

---

## 43 · Settings, Editor

How the editor behaves: Freedom and Before cutting. Who edits (the program and its version) is in Engines (54); the compact conflict row is specified in `editor.md › 43`, and the conflict list opens in a popover from **Change…**. 720 × 585.

Frame: `screens/43-settings-editor.html` · Render: `renders/43-settings-editor@2x.png`

**Freedom card:**
- `.lat` is a 3-column grid with gap 8 and padding 12/14/14.
- Each option is a card (`--raised`, radius 10) with a 15 radio, a 13/600 title and an 11.5 text-3 description.
- Selected: a 1.5 inset ring in text-1 and a `--hover` fill.
- The whole card is the hit target.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Freedom (**per film**) | How much freedom the editor has | 3 cards: Do what I wrote / Read between the lines / Take a pass | Read between the lines | `Film.latitude`. Behavior per `product-model.md › Latitude`. It can be overridden for one turnover in frame 22. |
| Before cutting | Wait for my OK before cutting | Switch | On | "The editor reads back its plan for each note first. Off: it starts cutting right after, and you can still read it." |
| Before cutting | Cut Feeling notes two ways | Switch | On | When on, and latitude isn't "Do what I wrote", Feeling notes return as Options A/B (frame 30). |
| Before cutting | Ask before guessing | Switch | On | Off: the editor picks the likelier reading of an unclear note and says so in the read-back, instead of raising a Question. |
| Before cutting | Follow the brief | Chip "Always on" (not a control) | Always | The brief is input to every cut. Edit it with Film › Brief… (`⌘B`). |
| When notes conflict | Conflict order | Reorderable list of 5 rows (drag by grip, or `⌥↑`/`⌥↓` with a row focused) | Feeling, Story, Pace, Picture, Sound | The tiebreaker order in read-backs (frame 27). "Restore default" resets it. |

**Conflict list row:**
- 34 tall, with a grip icon (text-4), the index in SF Mono 11 text-4, the kind name in 13 text-1, and a description on the right in 11.5 text-3.
- The descriptions:
  - Feeling: "How it should feel"
  - Story: "What happens and in what order"
  - Pace: "Length and rhythm"
  - Picture: "Framing, crop, look"
  - Sound: "Music, levels, dialogue"
- While dragging, the row lifts with a `--hover` fill and the shadow from `.pop`, and the others move in Settle.

**Note under the list:** "The higher kind wins, and the editor tells you in the read-back. Drag to reorder. The default follows Walter Murch's Rule of Six. Restore default."

**Acceptance:**
- [ ] Latitude here, in the Editor popover (frame 41) and in the Turnover sheet (frame 22) all read the same value. The Turnover sheet override applies to that turnover only.
- [ ] A reordered conflict list changes the tiebreak in the next read-back.
- [ ] VoiceOver announces each conflict row as "Feeling, 1 of 5, adjustable" and supports move up and down actions.

---

## 44 · Settings, Cutting
Frame: `screens/44-settings-cutting.html` · Render: `renders/44-settings-cutting@2x.png` · 720 × 800. Color moved here from Footage.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Reviewing changes | Handles in Play changes | Stepper, 0.0–5.0 s in 0.5 s steps | 2.0 s | Untouched picture shown either side of each change in Play changes (frame 31). It also changes the reel length shown on the Play changes button. |
| Reviewing changes | Name new cuts | Seg: Cut 4 / Oct 28 / Both | Cut 4 | The cut label in the titlebar, History and exports. "Both" gives "Cut 4 · Oct 28". The Assembly is always named Assembly. |
| Picture and sound (**per film**) | Frame rate for new films | Select: Match footage / 23.976 / 24 / 25 / 29.97 / 30 / 60 | Match footage | The timeline rate the editor cuts at. It's locked after the Assembly exists. Later changes show "Set when the Assembly was built" and are disabled. |
| Picture and sound (**per film**) | Loudness target | Select: −14 LUFS · Web / −16 LUFS · Podcast / −23 LUFS · Broadcast (EBU R128) / −24 LUFS · Broadcast (ATSC A/85) | −14 LUFS · Web | The mix target for cuts and for deliveries in Finish. |
| Picture and sound (**per film**) | Music under dialogue | Select: Duck 3 dB / Duck 6 dB / Duck 9 dB / Don't duck | Duck 6 dB | The default ducking when no note says otherwise. Notes always win. |
| Picture and sound (**per film**) | Transitions | Select: Hard cuts unless a note asks / Editor's choice | Hard cuts unless a note asks | Whether the editor may add dissolves or fades on its own. "Editor's choice" is still bounded by latitude. |
| Keeping cuts | Keep earlier cuts | Select: All of them / Last 5 / Only locked and current | All of them | Older cuts beyond the limit become "Archived": the notes and changelog are kept and the renders deleted. |
| Keeping cuts | Play from proxies | Switch | On | Use smaller files for playback. Deliveries always use the originals. |
| Color | Looks folder | Path field (read-only, folder icon) with **Change…** and **Show in Finder** | `~/Movies/Direction/Looks` | LUTs here appear in the Look sheet (frame 63). Subfolders become groups. |
| Color | Convert log footage automatically | Switch | On | Sub-label: "Apple Log, S-Log3, LogC and V-Log become normal video before any look. Camera LUTs live in the Camera folder." |

**Not in the app yet**, so their rows are left out until the feature exists: Name new cuts (the editor names each cut "Cut 4" when it delivers it, in its own process; a date name needs that and every "Cutting Cut 4" to agree), Keep earlier cuts (nothing archives a cut), and Play from proxies (Direction makes no proxies and plays the originals). Music under dialogue reaches the editor with each turnover's preferences and the finishing job.

**Acceptance:**
- [ ] The Play changes duration updates when handles change, e.g. "0:46" at 2.0 s.
- [ ] The frame rate becomes read-only once the Assembly exists, with the sub-label explaining why.

---

## 45 · Settings, Notifications
Frame: `screens/45-settings-notifications.html` · Render: `renders/45-settings-notifications@2x.png`

These are macOS user notifications. On first launch, Direction asks for permission after the first turnover, not at launch. If permission is denied, a banner appears at the top of this pane: "Notifications are off for Direction in System Settings." with an **Open System Settings** button, and the switches are disabled. If Direction hasn't asked yet, the banner reads "Direction hasn't asked to send notifications yet." with **Turn On**, and the switches stay on. The pane asks macOS again whenever Direction comes to the front or the window becomes key, so turning notifications on in System Settings clears the banner when you come back.

| Group | Setting | Control | Default | Notification text |
|---|---|---|---|---|
| Tell me when | A cut is ready | Switch | On | Title "Cut 4 is ready". Body "7 answers, 1 with two options. −9 s." Action: **Play changes**. |
| Tell me when | The editor has a question | Switch | On | "The editor has a question" / "Line 12 has two good readings. Which one?" Action: **Answer**. |
| Tell me when | The editor can't do a note | Switch | On | "The editor can't do note 7" / "Launch day is locked." Action: **Show me**. |
| Tell me when | An outside note arrives | Select: Right away / Once an hour / Once a day / Never | Once an hour | "3 outside notes on Cut 3" / "From Priya Shah and Tom Reyes." Action: **Open inbox**. |
| Tell me when | A delivery finishes | Switch | On | "Launch film is delivered" / "4 files, 2.1 GB." Action: **Show in Finder**. |
| Quiet | Hold notifications during a screening | Switch | On | Notifications queue while you watch through and are delivered when you're back on your notes. Detail: "They wait until you're back on your notes." |
| Quiet | Sound | Select: Clapper / Soft / None | Clapper | The sound played with notifications. Clapper is a short bundled wood-block sound. |

Notifications never appear while the Direction window is key and showing the relevant room. In that case a toast is shown instead (see `components.md › Toast`).

---

## 46 · Settings, Shortcuts
Frame: `screens/46-settings-shortcuts.html` · Render: `renders/46-settings-shortcuts@2x.png`

**Layout:**
- Top row: a search input (flex) and **Restore defaults**.
- Groups match the shortcut overlay (frame 50): Everywhere, Playback, Watching and notes, Script, Dailies, Answers.
- The frame shows 3 groups. The full pane scrolls, with all groups in this order.

**Row:** the action label on the left, the current keys on the right as `.kbd` caps.
- Click the keys to record. The field becomes `.input.focus` showing "Press keys…" (drawn on "Draw a region").
- `esc` cancels recording and `⌫` clears the shortcut.

**Conflicts:** Keys are scoped per room.
- The same key in two rooms is allowed. A neutral note explains it, as drawn: "R also opens Other readings in Script. A key can mean one thing per room."
- The same key twice in one room is an error. The new row gets `.field.err` styling and the note "⌘L is already Lock current scene." with **Replace** and **Cancel** buttons.

The full shortcut list (defaults) is the table in `system.md › Menu bar` plus the room-only keys in frame 50. Customized shortcuts get a text-3 "Edited" caption to the left of the keys.

**Acceptance:**
- [ ] A recorded shortcut updates the menu bar key equivalent immediately.
- [ ] Restore defaults asks to confirm: "Restore all shortcuts to their defaults?"

---

## 47 · Settings, Storage
Frame: `screens/47-settings-storage.html` · Render: `renders/47-settings-storage@2x.png`

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Library | Location | Path field (read-only, SF Pro 12, folder icon) and **Change…** | `~/Movies/Direction` | Where film libraries, proxies and renders live. Change… opens a folder picker, then a confirm sheet: "Move 61.4 GB to the new location?" with Move / Use without moving / Cancel. |
| Library | When you bring footage | Seg: Link to originals / Copy into library | Link to originals | Linking leaves files in place, so footage can go missing (frame 52). Copying uses library space: each file Direction brings in is copied first, off the main thread, into the film's own `Footage/` folder in its package, and the take points at the copy. The copy keeps the original's name ("C0001 2.MP4" when that's taken; never over another file), the same file brought twice is copied once, and the copies move and go to the Trash with the film. The logging page says "Copying into the film · 3 of 12" and Dailies' sidebar shows the same with a bar. |
| Usage | Using 61.4 GB on Macintosh HD | Stacked meter: Copied footage (steel-9), Proxies (steel-8), Cuts (steel-7), Render cache (steel-6) | — | Read-only. A legend with sizes sits under the meter. Bars are proportional to the disk's capacity. |
| Cleanup | Render cache | Button "Clear 6.6 GB" | — | Deletes renders that can be rebuilt. It's disabled while the editor is cutting, with the sub-label "Available when the editor finishes." |
| Cleanup | Proxies for locked films | Select: Keep / Delete after 30 days / Delete now | Delete after 30 days | Frees proxy space once picture is locked. |

**Not in the app yet:** Proxies for locked films. Direction makes no proxies, so the row is left out until it does. Copied footage in the meter is what's in the films' `Footage/` folders.

The meter uses only steel colors, never voice or status colors. If free disk is under 10 GB, a `.banner.bad` appears above the Usage group: "Less than 10 GB free. The editor may not be able to finish a cut."

---

## 48 · Settings, Sharing
Frame: `screens/48-settings-sharing.html` · Render: `renders/48-settings-sharing@2x.png`

**Account card:**
- One row, min 64 tall: a 32 avatar with initials, the name 13/600, then email · plan · seats in 11.5 text-3.
- On the right, **Manage plan** (opens the account page in the browser) and **Sign out** (ghost).
- Signed out, it shows "Sign in to share links" with **Sign in**, and every link setting is disabled.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| New screening links | Viewers can leave notes | Switch | On | Default for frame 39. |
| New screening links | Links expire | Select: Never / After 1 day / After 7 days / After 30 days | After 7 days | Default expiry. |
| New screening links | Watermark with the viewer's name | Switch | On | Burns the viewer's name into the streamed picture. It can't be turned off while Allow download is off. |
| New screening links | Allow download | Switch | Off | Viewers can download an H.264 file. |
| New screening links | Require a password | Switch | Off | New links ask for a password, set in the Share sheet. |
| Outside notes | Show who wrote each note to the editor | Switch | On | When on, accepted outside notes keep their author in what the editor receives ("from Priya Shah, producer"). Off: they read as the director's own. |

Note under the links card: "These are defaults. Each link can be changed in its Share sheet."

## 54 · Settings, Engines
Rendered from the app (`54-settings-engines`) · 720 × 1700, scrolls on most screens. Tab icon: `cpu`.

Everything that does the thinking, in one tab: what this Mac can run and what to use on it, the editor, transcription, looking at footage, and OpenRouter for what's made (and for looking at footage elsewhere). Groups, top to bottom: This Mac, Who edits, Transcription, Looking at footage, OpenRouter, What the editor uses, Spending. The UI never says "AI" or "model" here either (made-media.md): engines, versions, things made.

**This Mac**

| Row | Shows | Control |
|---|---|---|
| The chip ("Apple M4 Max") | "64 GB memory · 521 GB free on Macintosh HD" | — |
| "mlx-vlm isn't installed" (only when the advice needs something missing) | Why: "Looking at footage on this Mac needs it." Claude Code the same way when no editor program is installed. | **Copy Command** |
| Recommended | One line a job: "Looking at footage: Best (Qwen3-VL 30B-A3B), instead of Standard", "Transcription: Apple", "Editor: Claude Code". ", instead of …" only where the choice differs. | **Use Recommended** while anything differs; a "In use" chip (ok) when it all matches |

Note: "Recommended from this Mac's chip, memory, free space and what's installed. Nothing changes until you choose."

What it recommends (`EngineAdvice`):
- **Looking at footage:** on Apple silicon, the largest local version the memory runs (Best at 32 GB or more, Standard at 16, else Quick) that's downloaded or has room for its download plus 2 GB, smaller ones in turn. Best is first because it's faster than Standard where it fits (footage-index.md › Speed). OpenRouter when nothing local fits and there's a key, and on a Mac without Apple silicon. mlx-vlm missing is a row with its install command, not a reason to send footage away.
- **Transcription:** Apple. The fastest, and it keeps false starts (footage-index.md › Transcription engines).
- **Editor:** the chosen program while it's installed, else whichever is (Claude Code first). Your own session is left alone.
- Use Recommended sets those three and nothing else. Defaults already follow it: a Mac with 32 GB or more starts on Best.

**Who edits**: as specified in `editor.md › 43` (Editor runs on, Version, Effort, Start work).

**Transcription** and **Looking at footage**

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Transcription | Transcribe with | Seg: Apple / Whisper | Apple | Apple: "Fast and built into macOS. Runs on this Mac." Whisper: "Slower, with tighter word times for cutting on a single word. Runs on this Mac." Stored in the `dev.direction.shared` defaults suite, so the editor's tools use it too. |
| Transcription | Whisper version | Select: Large v3 Turbo / Large v3 | Large v3 Turbo | Sub-label: "Fast. Nearly as accurate as Large v3. Downloaded · 1.6 GB." or "Slower, and a little more accurate. Downloads 3.1 GB the first time it's used." Disabled while Apple is chosen. |
| Transcription | mlx-whisper (only while Whisper is chosen) | Chip "Ready", or **Copy Command** | — | Ready shows the path (`~/.local/bin/mlx_whisper`). Missing: "mlx-whisper isn't installed" / "Install it in Terminal with pip install mlx-whisper. Until then, Apple transcribes." Missing ffmpeg: "Whisper needs ffmpeg" / "brew install ffmpeg". |
| Looking at footage | Look with | Seg: This Mac / OpenRouter | This Mac | This Mac: "Private and free. Footage never leaves this Mac." OpenRouter: "Sends three small frames of each shot to a vision version through OpenRouter. Needs your key under OpenRouter below." |
| Looking at footage | Detail | Select: Quick · 3.1 GB / Standard · 5.8 GB / Best · 18 GB (This Mac); or a select of OpenRouter vision versions, default Gemini 3.1 Flash Lite | Best with 32 GB of memory or more (it's faster than Standard there, footage-index.md › Speed); Standard below | Sub-label names the version and state: "Qwen3-VL 8B. Downloaded." Needs mlx-vlm: when it isn't installed, the row reads "mlx-vlm isn't installed" / "Install it in Terminal with uv tool install mlx-vlm. Until then, nothing is described; shots and sounds are still found." with **Copy Command**. |
| Looking at footage | Look at new footage automatically | Switch | On | Off: footage is indexed only when the editor asks or you choose Film › Look at Footage. |

Note under Transcription: "Takes already transcribed keep their words. New footage uses this engine."
Note under Looking at footage: "The editor reads what's found here to log takes, and you can search it in Dailies with ⌘F."

**OpenRouter** (the group was Services)


**The OpenRouter row** (`.set-row`, min 56): a 28 rounded-square monogram "O" (`--raised` fill, hairline border, radius 8, 12/700 text-2; no brand logo), "OpenRouter" (13/600) with "Music, voice, sound effects, shots and stills" under it (11.5 text-3), and on the right a chip "Ready" (ok style) with "$37.20 left" in SF Mono 11 text-3 before it, or **Add Key…** (`.btn`, key icon).

**Editing the key:** the row grows to show a secure `.input` (placeholder "Paste your OpenRouter key"), a text link "Get a key" with an arrow-up-right icon (opens openrouter.ai/keys), and Cancel (plain) / **Save** (`.btn`, not steel; the window has no steel button). After Save, Direction checks the key (`GET /key`) and shows Ready or "That key didn't work: <OpenRouter's message>". The row's context menu has Replace Key…, Remove Key, and Show Credits (opens openrouter.ai/credits).

Note under the key: "Your key is kept in your Mac's keychain, and the editor never sees it. Direction makes every request and picks the version for each from what it needs and the film's speed and quality. Frames of your takes are sent to OpenRouter, so they leave this Mac. Slow motion and sharpening happen on this Mac and cost nothing."

There are no version selects and no Made with (gone 2026-11-08): the film's speed and quality (editor.md › Speed and quality) is the only choice, and it lives with the film's editor, not in Settings.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Spending | Ask before spending more than | Select: $1.00 / $5.00 / $10.00 / $25.00 / $50.00 per turnover. Sub-label: "The editor prices each turnover's plan first, and asks only when it goes over." | $5.00 per turnover | A plan over this needs a yes to one spend question (frame 62). Under it, the editor just makes it. |
| Spending | Stop for the month at | Select: $25.00 / $50.00 / $100.00 / $250.00 / No limit | $50.00 | Nothing is made past this. |
| Spending | Spent this month | Meter (like Storage's), one segment per kind, with a legend: Music $0.36, New shots $12.40, Looking at footage $0.04, Checking $0.01 | — | Read-only. "$12.80 of $50.00" in SF Mono on the right of the row. Checking is Direction looking at what was made (decisions.md); kinds under half a cent aren't shown. |

Note under Spending: "Check each version's terms on OpenRouter before you release a film. Some don't cover film or TV."

**Acceptance:**
- [ ] A key is never written to UserDefaults, the film package, logs or the editor's tools.
- [ ] Removing a key leaves made clips playable and stops new requests at once.

---


**Acceptance:**
- [ ] Choosing Whisper here makes the next `direction_transcribe` call from the editor use Whisper, without restarting the editor.
- [ ] A download in progress shows its percent in the Detail row's sub-label and can be cancelled from the row's context menu.
- [ ] On a 16 GB Mac, Recommended says Standard; on a 64 GB Mac, Best; with no room for any download and a key, OpenRouter.
- [ ] Use Recommended changes only looking at footage, transcription and the editor, and the row then shows "In use".

---

## Accessibility (all panes)
- Each tab is a toolbar item labeled with its name.
- Each row's control has an accessibility label equal to the row label, and the sub-label as its hint.
- Focus order runs top to bottom.
- Full keyboard access: Tab moves between controls and Space toggles switches.

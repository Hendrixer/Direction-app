# Settings

Frames 42–48, 54 and 55. Opens with Direction › Settings… (`⌘,`). It's a standard macOS Settings window with toolbar-style tabs, and it is not a sheet. In SwiftUI use a `Settings { TabView { … } }` scene with `.tabViewStyle(.automatic)` and the Gate styling below.

## Window

| Part | Spec |
|---|---|
| Width | 720 pt, fixed. |
| Height | Fits the selected pane. Switching tabs resizes the window at once, with no animation; only the pane's content fades in (160 ms, ease-out). Frame heights: General 600, Editor 853, Footage 724, Cutting 650, Services 812, Notifications 530, Shortcuts 690, Storage 520, Sharing 590. The window never grows past the screen: a pane taller than the screen's visible height (less the toolbar and a 24 pt margin) scrolls under the toolbar. On a 900 pt screen, Editor and Services scroll. |
| Toolbar | `.set-tb` 76 tall: a title row 28 tall (the pane name, 13/600 text-2, centered), then a tab row. In the app the title row is the window's own title bar (titled with the pane's name, in the ground color), and the tab row sits below it. Drawing both under a transparent full-size title bar shifted the content up by the title row whenever the window resized for another tab. |
| Tabs | 74 wide each, gap 2, with an 18 icon over an 11 pt label and gap 3. Selected: `--raised` fill, radius 7, text-1. Order: General, Editor, Footage, Cutting, Services, Notifications, Shortcuts, Storage, Sharing. `⌘1`…`⌘9` switch tabs while Settings is key. |
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
| Playback | Start screenings full screen | Switch | Off | Entering Screening (`⌘3` or Start screening) also enters full screen. |
| Playback | Hide controls in Screening after | Select: 1 second / 2 seconds / 4 seconds / Never | 2 seconds | Idle time before Screening goes to frame 14 (picture only). |
| Playback | Audio output | Select: System default / every Core Audio output | System default | The playback device. |
| Look | Film grain | Switch | On | The 3.5% grain over UI surfaces. It's never drawn over the picture. |
| Look | Reduce motion | Select: Follow system / On / Off | Follow system | Replaces shimmer with a static prism edge, sweeps with fades, and slides with fades. |

Footer, centered 11.5 text-3: "Direction 1.0 (214) · Check for updates". The second part is a text-2 link.

**Acceptance:**
- [ ] Changing "Hide controls after" takes effect on the next idle, without restarting.
- [ ] Grain off removes the overlay from every window, including Settings.

---

## 43 · Settings, Editor

The **Who edits** group and the compact conflict row are specified in `editor.md › 43`. Everything below still applies to the Freedom and Before cutting groups; the conflict list moves into a popover opened by **Change…**.

Frame: `screens/43-settings-editor.html` · Render: `renders/43-settings-editor@2x.png`

**Freedom card:**
- `.lat` is a 3-column grid with gap 8 and padding 12/14/14.
- Each option is a card (`--raised`, radius 10) with a 15 radio, a 13/600 title and an 11.5 text-3 description.
- Selected: a 1.5 inset ring in text-1 and a `--hover` fill.
- The whole card is the hit target.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Freedom (**per film**) | How much freedom the editor has | 3 cards: Do what I wrote / Read between the lines / Take a pass | Read between the lines | `Film.latitude`. Behavior per `product-model.md › Latitude`. It can be overridden for one turnover in frame 22. |
| Before cutting | Wait for my OK on read-backs | Switch | On | Off: cutting starts right after the read-back, and the read-back stays readable in Notes. |
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
Frame: `screens/44-settings-cutting.html` · Render: `renders/44-settings-cutting@2x.png`

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
| Quiet | Hold notifications during a screening | Switch | On | Notifications queue while Screening is open and are delivered when it ends. |
| Quiet | Sound | Select: Clapper / Soft / None | Clapper | The sound played with notifications. Clapper is a short bundled wood-block sound. |

Notifications never appear while the Direction window is key and showing the relevant room. In that case a toast is shown instead (see `components.md › Toast`).

---

## 46 · Settings, Shortcuts
Frame: `screens/46-settings-shortcuts.html` · Render: `renders/46-settings-shortcuts@2x.png`

**Layout:**
- Top row: a search input (flex) and **Restore defaults**.
- Groups match the shortcut overlay (frame 50): Everywhere, Playback, Screening and notes, Script, Dailies, Changes.
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
| Library | When you bring footage | Seg: Link to originals / Copy into library | Link to originals | Linking leaves files in place, so footage can go missing (frame 52). Copying uses library space. |
| Usage | Using 61.4 GB on Macintosh HD | Stacked meter: Copied footage (steel-9), Proxies (steel-8), Cuts (steel-7), Render cache (steel-6) | — | Read-only. A legend with sizes sits under the meter. Bars are proportional to the disk's capacity. |
| Cleanup | Render cache | Button "Clear 6.6 GB" | — | Deletes renders that can be rebuilt. It's disabled while the editor is cutting, with the sub-label "Available when the editor finishes." |
| Cleanup | Proxies for locked films | Select: Keep / Delete after 30 days / Delete now | Delete after 30 days | Frees proxy space once picture is locked. |

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

## 54 · Settings, Footage
Frame: `screens/54-settings-footage.html` · Render: `renders/54-settings-footage@2x.png` · 720 × 724. Tab icon: `film.stack`.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Transcription | Transcribe with | Seg: Apple / Whisper | Apple | Apple: "Fast and built into macOS. Runs on this Mac." Whisper: "Slower, with tighter word times for cutting on a single word. Runs on this Mac." Stored in the `dev.direction.shared` defaults suite, so the editor's tools use it too. |
| Transcription | Whisper version | Select: Large v3 Turbo / Large v3 | Large v3 Turbo | Sub-label: "Fast. Nearly as accurate as Large v3. Downloaded · 1.6 GB." or "Slower, and a little more accurate. Downloads 3.1 GB the first time it's used." Disabled while Apple is chosen. |
| Transcription | mlx-whisper (only while Whisper is chosen) | Chip "Ready", or **Copy Command** | — | Ready shows the path (`~/.local/bin/mlx_whisper`). Missing: "mlx-whisper isn't installed" / "Install it in Terminal with pip install mlx-whisper. Until then, Apple transcribes." Missing ffmpeg: "Whisper needs ffmpeg" / "brew install ffmpeg". |
| Looking at footage | Look with | Seg: This Mac / OpenRouter | This Mac | This Mac: "Private and free. Footage never leaves this Mac." OpenRouter: "Sends three small frames of each shot to a vision version through OpenRouter. Needs your key in Services." |
| Looking at footage | Detail | Select: Quick · 3.1 GB / Standard · 5.8 GB / Best · 18 GB (This Mac); or a select of OpenRouter vision versions, default Gemini 3.1 Flash Lite | Standard | Sub-label names the version and state: "Qwen3-VL 8B. Downloaded." Needs mlx-vlm: when it isn't installed, the row reads "mlx-vlm isn't installed" / "Install it in Terminal with uv tool install mlx-vlm. Until then, nothing is described; shots and sounds are still found." with **Copy Command**. |
| Looking at footage | Look at new footage automatically | Switch | On | Off: footage is indexed only when the editor asks or you choose Film › Look at Footage. |
| Color | Looks folder | Path field (read-only, folder icon) with **Change…** and **Show in Finder** | `~/Movies/Direction/Looks` | LUTs here appear in the Look sheet (frame 63). Subfolders become groups. |
| Color | Convert log footage automatically | Switch | On | Sub-label: "Apple Log, S-Log3, LogC and V-Log become normal video before any look. Camera LUTs live in the Camera folder." |

Note under Transcription: "Takes already transcribed keep their words. New footage uses this engine."
Note under Looking at footage: "The editor reads what's found here to log takes, and you can search it in Dailies with ⌘F."

**Acceptance:**
- [ ] Choosing Whisper in Settings makes the next `direction_transcribe` call from the editor use Whisper, without restarting the editor.
- [ ] A download in progress shows its percent in the Detail row's sub-label and can be cancelled from the row's context menu.

---

## 55 · Settings, Services
Frame: `screens/55-settings-services.html` · Render: `renders/55-settings-services@2x.png` · 720 × 812. Tab icon: `key`.

**The OpenRouter row** (`.set-row`, min 56): a 28 rounded-square monogram "O" (`--raised` fill, hairline border, radius 8, 12/700 text-2; no brand logo), "OpenRouter" (13/600) with "Music, voice, sound effects, shots and stills" under it (11.5 text-3), and on the right a chip "Ready" (ok style) with "$37.20 left" in SF Mono 11 text-3 before it, or **Add Key…** (`.btn`, key icon).

**Editing the key:** the row grows to show a secure `.input` (placeholder "Paste your OpenRouter key"), a text link "Get a key" with an arrow-up-right icon (opens openrouter.ai/keys), and Cancel (plain) / **Save** (`.btn`, not steel; the window has no steel button). After Save, Direction checks the key (`GET /key`) and shows Ready or "That key didn't work: <OpenRouter's message>". The row's context menu has Replace Key…, Remove Key, and Show Credits (opens openrouter.ai/credits).

**What the editor uses** (a card under the key, one row per kind, each a select of OpenRouter versions with the default first):

| Kind | Default | Sub-label | Lists |
|---|---|---|---|
| Music | Lyria 3 Clip | "About $0.04 a 30 s clip" | Audio versions |
| Voice | (first speech version) | — | Speech versions |
| New shots | Veo 3.1 | "About $0.20 a second at 1080p" | Video versions that make shots. Extended shots and bridges use it too. |
| Changed shots | Aleph 2.0 | "About $0.28 a second" | Versions that change video (Aleph 2.0, FLUX Video Edit) |
| Stills | Nano Banana 2 | — | Image versions |

Note under the card: "Slow motion and sharpening happen on this Mac and cost nothing."

Prices in sub-labels come from OpenRouter's listing and update with it.

| Group | Setting | Control | Default | What it changes |
|---|---|---|---|---|
| Spending | Ask before spending more than | Select: $1.00 / $5.00 / $10.00 / $25.00 / $50.00 per turnover. Sub-label: "The editor prices each turnover's plan first, and asks only when it goes over." | $5.00 per turnover | A plan over this needs a yes to one spend question (frame 62). Under it, the editor just makes it. |
| Spending | Stop for the month at | Select: $25.00 / $50.00 / $100.00 / $250.00 / No limit | $50.00 | Nothing is made past this. |
| Spending | Spent this month | Meter (like Storage's), one segment per kind, with a legend: Music $0.36, New shots $12.40, Looking at footage $0.04 | — | Read-only. "$12.80 of $50.00" in SF Mono on the right of the row. |

Note under the key: "Your key is kept in your Mac's keychain. The editor never sees it; Direction makes every request."
Note under Spending: "Check each version's terms on OpenRouter before you release a film. Some don't cover film or TV."

**Acceptance:**
- [ ] A key is never written to UserDefaults, the film package, logs or the editor's tools.
- [ ] Removing a key leaves made clips playable and stops new requests at once.

---

## Accessibility (all panes)
- Each tab is a toolbar item labeled with its name.
- Each row's control has an accessibility label equal to the row label, and the sub-label as its hint.
- Focus order runs top to bottom.
- Full keyboard access: Tab moves between controls and Space toggles switches.

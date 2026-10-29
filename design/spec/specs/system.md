# System: command menu, keyboard, offline, missing footage, menus

Frames 49–53 and the macOS menu bar. Shared styles live in `css/system.css` (`.cmd*`, `.keys-grid`, `.kr`, `.kbd.s`).

---

## 49 · Command menu
Frame: `screens/49-command.html` · Render: `renders/49-command@2x.png`

**Arrives from / leads to:** `⌘K` in any room, or Help › Search. Running a row performs that action and closes the menu, returning to the room it came from or to the room the action opens.

**Layout:**
- Scrim: 45% black over the whole window, titlebar included.
- Panel: 640 wide, centered horizontally, top at y 120. `--panel` fill, radius 14, shadow 0 40 100 −16 black 95%.
- Input row 52 tall with padding 0/18: an 18 search icon (text-3), the query in 16 SF Pro, and a context chip on the right showing the room and cut, e.g. "Notes · Cut 3".
- List padding 6. Section headers use `.label` with padding 10/12/5. Rows are 36 tall with padding 0/12 and radius 8: a 15 icon (text-3), the label, and a right slot (keys or a caption in 12 text-4). The selected row is filled with `--hover`.
- Footer 36 tall with a hairline on top. Hints: ↑↓ Move, ↩ Run, ⇥ Narrow to section, and on the far right esc Close.
- At most 8 rows show before the list scrolls. The panel height fits its content.

**Content:** Sections appear in this order, and only when they have results:
1. **Actions:** every menu bar command plus room actions. They can be disabled. A disabled row shows its reason as the caption, e.g. "Lock picture · 6 notes still open".
2. **Notes:** matches note text. The row shows "Note 2 · I want to feel how tired…" with an amber number.
3. **Scenes:** "5 Launch day · locked since Cut 3" with the start timecode.
4. **Takes:** "2A T3 · suggested: warmest read".
5. **Cuts:** "Cut 2 · Oct 22 · 3:52".
6. **Settings:** "Editor › Ask before guessing". Opens Settings at that row and flashes it with a 1 s `--hover` fill.
7. **Help:** questions that open a short help popover.

Matching is a fuzzy, prefix-weighted search on the label and its synonyms. Matched characters are 600 weight in text-1 (`<mark>` in the frame) and the rest are 400.

**States and variants:**
- **Empty query:** shows Recent (the last 5 commands run), then Suggested for the room. In Notes that's Turn over, Start screening, Share Cut 3.
- **No results:** a single row "No matches for “xyz”", and below it "Ask the editor: “xyz”", which opens Notes with the composer pre-filled.
- **Note to self:** typing text that starts with `n ` (for example "n music is too loud") offers "Add note at 00:46:12: music is too loud" as the top action.

**Interactions:**
- ↑/↓ move, ↩ runs, and `⌘↩` runs without closing when the action allows it.
- ⇥ cycles the section filter, and the chip shows it ("Notes").
- `esc` clears the query first, then closes.
- Clicking the scrim closes.

**Motion:** The panel scales 0.98→1 and fades in Settle, and the scrim fades in Snap. Row selection moves instantly, with no animation.

**Accessibility:**
- The panel is a combobox ("Command menu") with a listbox.
- Each row announces its section and its disabled reason.

**Acceptance:**
- [ ] Every item in the menu bar below is reachable from the command menu.
- [ ] Disabled rows are shown with their reason. They are never hidden.
- [ ] The context chip matches the current room and cut.

---

## 50 · Keyboard shortcuts
Frame: `screens/50-shortcuts.html` · Render: `renders/50-shortcuts@2x.png`

**Arrives from / leads to:** `?` (with no text field focused), or Help › Keyboard Shortcuts (`⌘/`). esc closes it. "Settings › Shortcuts" in the sub-line is a link to frame 46.

**Layout:**
- A centered modal, 1000 wide (`.modal.center`), over a 55% scrim.
- Head: "Keyboard" in Archivo 24/800/120%, a 220 search input on the right, and the sub-line in 12 text-3.
- Body: a 3-column grid with a 36 column gap and a 24 row gap. Each group has a `.label`, then 28-tall rows: the label in 13 text-2, then the keys as 22-tall `.kbd` caps with gap 4.

**Content:** These are the defaults, and they must match the menu bar.

| Group | Action | Keys |
|---|---|---|
| Everywhere | Dailies … Finish | ⌘1–6 |
| | Command menu | ⌘K |
| | This list | ? |
| | Turn over | ⌘↩ |
| | Lock current scene | ⌘L |
| | Share | ⌘⇧S |
| | Settings | ⌘, |
| Playback | Play or pause | Space |
| | Back, stop, forward | J K L (press J or L repeatedly for 2×, 4×) |
| | One frame | ← → |
| | One second | ⇧← ⇧→ |
| | Previous or next scene | ↑ ↓ |
| | Range in and out | I O |
| | Full screen | ⌃⌘F |
| Screening and notes | Mark this moment | N |
| | Start screening | ⌘⇧↩ |
| | End screening | esc |
| | Draw a region | R |
| | Kind: Feeling … Sound | ⌥1–5 |
| | Add note | ↩ (in the composer) |
| | Drop draft | ⌫ (on a selected draft) |
| Script | Strike line | ⌫ |
| | Hold passage | H |
| | Other readings | R |
| | Move paragraph | ⌥↑ ⌥↓ |
| Dailies | Circle take | C |
| | Open take | Space |
| | Next take | → |
| | Assemble from circles | ⌘↩ |
| Changes | Play changes | ⌘⇧P |
| | Use A or B | A, B |
| | Accept answer | Y |
| | Reply | ⌘R |
| | Revert this change | ⌘⌫ |

Room-scoped keys are dimmed to text-4 when their room isn't the current one. Their row label gets a caption with the room name.

**States and variants:**
- **Search:** filters rows live. Groups with no match hide.
- **Edited:** a customized shortcut shows its edited keys and a text-3 "Edited" caption.

**Accessibility:** The modal is labeled "Keyboard shortcuts". Each row is read as "Mark this moment, N".

**Acceptance:**
- [ ] The values are generated from the same shortcut registry as the menu bar and Settings › Shortcuts. Nothing is hard-coded twice.

---

## 51 · Offline
Frame: `screens/51-offline.html` · Render: `renders/51-offline@2x.png`

**Arrives from / leads to:** Shown when there's no connection to the editor service (network loss or the service being unreachable for more than 5 s). It clears automatically on reconnect, with a toast "Back online. Turning over your 6 notes…" if a turnover was queued.

**Layout:**
- A `.banner` 36 tall directly under the titlebar, pushing the room down. The app grid rows are 52 / 36 / 1fr.
- Banner content: the offline icon, "**You're offline.**" in 600 weight, then the body in text-3. On the right, "Last connected 14:02" in 12 text-3 and **Try again** (btn sm).
- The editor pill becomes `.agent` with the offline icon and "Offline".

**What still works:** playback of cuts already on disk, screening and marks, writing and editing notes, Dailies circles, Script marks, locking scenes, and Settings.

**What waits:**
- **Turnover:** the steel button stays visible at 40% opacity. Hovering shows the tooltip "Turnover waits until you're online. Your notes are saved." Pressing it anyway queues the turnover: the button becomes "Queued" with a clock icon, and the banner adds "Turnover queued."
- **Sharing:** the Share sheet's controls are disabled.
- **New cuts and read-backs:** a cut already in progress pauses, and the pill shows Offline, not Cutting.
- **Outside notes:** they sync when you're back.

**States and variants:**
- **Reconnecting:** a spinner replaces the icon, and the copy reads "Reconnecting…".
- **Editor service down (network OK):** the same banner with the copy "**The editor isn't reachable.** Your work is saved. We'll retry every 30 seconds." and a Status page link.

**Motion:** The banner slides down in Settle and the room content moves with it. On reconnect the banner collapses in Settle.

**Accessibility:** The banner is announced once as a status update when it appears. Try again is focusable.

**Acceptance:**
- [ ] Notes written offline persist across a relaunch and turn over on reconnect only if the user queued the turnover.
- [ ] The pill never shows Cutting while offline.

---

## 52 · Footage missing
Frame: `screens/52-media-missing.html` · Render: `renders/52-media-missing@2x.png`

**Arrives from / leads to:** Linked originals (Settings › Storage › Link to originals) become unreachable, for example when a drive is unplugged. **Find footage…** in the banner, or File › Find Missing Footage…, opens the relink sheet. A successful relink clears the banner and resumes the editor.

**Layout:**
- `.banner.bad` 36 tall under the titlebar: a warning icon in alert color, "**14 takes are missing.**", then "The drive “Shoot SSD” isn't connected. The editor can't cut scenes that use them." On the right, **Find footage…**.
- Editor pill: `.agent.blocked` "Waiting for footage". Only when a turnover needs the missing takes. Otherwise it stays as it was.
- **Picture:** where a missing take would play, the frame shows a slate: a `--sunken` fill with `.hatch`, a 28 disk icon, "2A T2 is offline" in Archivo 17, and the file path in 12 text-3, all centered. The audio for that span is silent. Playback continues through the slate. It doesn't stop.
- **Relink sheet:** 620 wide, attached under the banner (y 88), over a scrim that starts below the banner.
  - A folder row: a path input and **Choose…**.
  - A progress row: spinner, "Searching Day 3… 12 of 14 found", and a 160 progress bar.
  - A file list in a `.well` with rows min 36: a status icon, the take code 500 weight, the path in SF Mono 11.5 text-3 (ellipsis in the middle), and a status chip. **Found** is `.chip.ok`, **Not in this folder** is `.chip.bad`, and "Searching" is a plain chip with a spinner.
  - Footer: a text-3 note on the left, "Unmatched takes stay offline. Notes on them are kept.", then **Cancel** and **Relink 12 takes** (steel).

**Matching rule:** filename, then duration ±1 frame, then start timecode. The sheet keeps searching the rest of the volume after the chosen folder and finds the others on its own.

**States and variants:**
- **Relinked all:** a toast "14 takes relinked." The banner collapses.
- **Partial:** the banner updates to "2 takes are missing."
- **Missing in Dailies:** affected take thumbnails show the hatched slate with a disk icon, and the take caption says "offline".
- **Editor blocked:** a turnover note that depends on missing takes gets a can't-do entry (see `cutting.md`) whose action is **Find footage…**.

**Accessibility:** The banner is a status announcement. The slate is labeled "Take 2A T2 is offline". File rows are read as "2A T2, found".

**Acceptance:**
- [ ] Missing footage never deletes notes, circles or cuts.
- [ ] Playback doesn't stop at an offline take.
- [ ] Relink only accepts a candidate whose duration matches within ±1 frame.

---

## Deleting a film

**Move to Trash** (Films, ⌘⌫), or leaving a new film you never put anything into, moves the film's `.direction` package to the Trash. Finder's Put Back brings it back.

- **In the package, so in the Trash:** the cuts and their history, notes, transcripts, Dailies, the footage index, made media, graphics, looks and the editor's folder.
- **Never touched:** the footage. Direction links to files where they are and never copies them. Deliveries in `~/Movies/<Film>/Delivery/` are the director's too.
- **Goes at once:** the film's cache in `~/Library/Caches/dev.direction.editor/<film id>/` (decoded audio, contact sheets, frames, thumbnails, sync curves), and its entry in the library. Everything in the cache can be made again; opening a put-back film registers it again.
- **At launch:** the cache of any film that isn't in the library, or whose package has been missing, goes once it hasn't been touched for a week (a film deleted in Finder). A missing film stays listed as "Can't find this film" so it can be found; only its cache goes. Library entries for trashed films that are gone are forgotten.
- **While working:** decoded audio is most of a cache (about 70 MB per three minutes of stereo). It goes each time the film is idle (nothing transcribing, listening, syncing or cutting) and is decoded again in seconds when something needs it.
- **Stays, on purpose:** spending history (the month's limit counts it) and the editor program's own session logs.
- Tests and the command-line checks never use the real cache, library or log (`DIRECTION_CACHE_DIR`, `DIRECTION_LIBRARY_PATH`, `DIRECTION_LOG_DIR`).

## 53 · Context menus
Frame: `screens/53-menus.html` · Render: `renders/53-menus@2x.png`

The frame shows three right-click menus over the Notes room at once, only for reference. In the app, one is open at a time. All three use `.pop.menu`:
- Panel: padding 5, radius 12.
- Rows 26 tall with radius 6, a 14 icon in text-3 and a 13 label. The shortcut is right-aligned in 12 text-4.
- Separators are 1 pt hairlines with a 6 inset.
- Use native `NSMenu` / SwiftUI `.contextMenu` with SF Symbols. The Gate look is the reference for the custom-drawn fallback only.

**Picture** (right-click the frame in any room with a viewer):

| Item | Key | Notes |
|---|---|---|
| Mark this frame | N | Amber pin icon. Creates a draft note at the clicked frame. |
| Draw a region | R | Enters region drawing at this frame (frame 19). |
| Note on the whole cut | — | The composer opens with the Whole cut anchor. |
| — | | |
| Copy timecode | ⌘⇧C | Copies `00:46:12`. |
| Copy frame as image | — | PNG at source resolution. |
| Show this take in Dailies | — | Opens Dailies with that take selected. |

**Scene strip** (right-click a scene). The header row is a `.label` with the scene number, name and range: "3 The ridge · 01:05:00–01:50:00".

| Item | Key | Notes |
|---|---|---|
| Play from here | Space | Seeks to the clicked point and plays. |
| Mark here | N | |
| Note on this scene | — | Composer with the Scene anchor. |
| — | | |
| Lock scene / Unlock scene | ⌘L | Toggles. For a locked scene the label is "Unlock scene" with the unlock icon. |
| Open in Dailies | — | Dailies, scrolled to this scene. |
| Open in Script | — | Script, scrolled to this scene. |
| History of this scene | — | History (frame 33) filtered to this scene. |

**Note row** (right-click a note in the sheet):

| Item | Key | Notes |
|---|---|---|
| Play from note | Space | |
| Edit note | ↩ | Only before turnover. After turnover it reads "Reply" (⌘R). |
| Change anchor… | — | Moment / Range / Region / Scene / Whole cut. Before turnover only. |
| Kind › | — | Submenu: Feeling, Story, Pace, Picture, Sound, None. The current one is checked. |
| — | | |
| Copy link to note 2 | — | `direction://film/<id>/note/2` |
| Show in history | — | |
| — | | |
| Drop note | ⌫ | Alert color. Before turnover only. The number is retired, never reused. |

Other context menus follow the same rules: takes in Dailies, script lines, answers in Changes, cuts in History.
- **Take:** Circle, Open, Play, Show in Finder.
- **Script line:** Strike, Hold, Other readings, Note on this line, Copy line.
- **Answer:** Accept, Reply, Revert this change, Play this change.
- **Cut:** Open, Compare with current, Share…, Export….

**Acceptance:**
- [ ] Every context menu item also exists in the menu bar or the command menu.
- [ ] Disabled items stay visible (`.mi.dis`) rather than being removed.

---

# Menu bar

Every command is listed with its key equivalent. Room-scoped commands are disabled outside their room and say so in the command menu. "…" means the command opens a sheet or window. Every menu also shows the standard system items macOS adds (Services, Hide, Window tiling, Enter Full Screen) that aren't listed here.

### Direction
| Item | Key |
|---|---|
| About Direction | |
| Settings… | ⌘, |
| Check for Updates… | |
| — | |
| Services ▸ | |
| — | |
| Hide Direction | ⌘H |
| Hide Others | ⌥⌘H |
| Show All | |
| — | |
| Quit Direction | ⌘Q |

### File
| Item | Key |
|---|---|
| New Film… | ⌘N |
| Open Films | ⌘O |
| Open Recent ▸ | |
| — | |
| Bring Footage… | ⌘I |
| Find Missing Footage… | |
| — | |
| Share Cut… | ⌘⇧S |
| Export… | ⌘E |
| — | |
| Show Library in Finder | |
| Close Window | ⌘W |

### Edit
| Item | Key | Notes |
|---|---|---|
| Undo | ⌘Z | Undoes the director's own acts: circles, marks, notes, locks. It never undoes the editor's cuts. Use Revert this change for that. |
| Redo | ⇧⌘Z | |
| — | | |
| Cut / Copy / Paste | ⌘X / ⌘C / ⌘V | Text fields, notes and timecode. |
| Copy Timecode | ⌘⇧C | |
| Select All | ⌘A | |
| — | | |
| Find… | ⌘F | Searches the current room: notes, takes, script. |
| Command Menu… | ⌘K | |
| — | | |
| Emoji & Symbols | ⌃⌘Space | |

### View
| Item | Key |
|---|---|
| Dailies | ⌘1 |
| Script | ⌘2 |
| Screening | ⌘3 |
| Notes | ⌘4 |
| Changes | ⌘5 |
| Finish | ⌘6 (disabled until picture lock) |
| — | |
| Show Notes Sheet | ⌥⌘S |
| Show Transcript Captions | ⌥⌘C |
| Show Safe Areas | |
| — | |
| Zoom to Fit | ⌘0 |
| Zoom In / Out | ⌘+ / ⌘− |
| — | |
| Enter Full Screen | ⌃⌘F |

### Film
| Item | Key |
|---|---|
| Brief… | ⌘B |
| Editor… | ⌘⇧E |
| — | |
| How Much Freedom ▸ (Do what I wrote / Read between the lines / Take a pass) | |
| Pause Editor / Resume Editor | |
| — | |
| Lock Current Scene / Unlock Current Scene | ⌘L |
| Lock Picture… | ⌘⇧L |
| Unlock Picture… | |
| — | |
| Rename Film… | |
| Film Settings… | |

### Cut
| Item | Key |
|---|---|
| Start Screening | ⌘⇧↩ |
| — | |
| Mark This Moment | N |
| New Note | ⌘⌥N |
| Turn Over… | ⌘↩ |
| — | |
| Play Changes | ⌘⇧P |
| Accept Answer | Y |
| Reply to Answer | ⌘R |
| Revert This Change | ⌘⌫ |
| — | |
| Assemble from Circles | ⌘↩ (Dailies) |
| — | |
| Go to Cut ▸ (Assembly, Cut 2, Cut 3, Cut 4) | |
| Compare with Previous Cut | ⌥⌘← |
| History | ⌘Y |

`⌘↩` is room-scoped: in Notes it's Turn Over, in Dailies it's Assemble from Circles.

### Playback
| Item | Key |
|---|---|
| Play / Pause | Space |
| Play Backward / Stop / Play Forward | J / K / L |
| Previous Frame / Next Frame | ← / → |
| Back One Second / Forward One Second | ⇧← / ⇧→ |
| Previous Scene / Next Scene | ↑ / ↓ |
| — | |
| Set Range In / Out | I / O |
| Clear Range | ⌥X |
| — | |
| Go to Start / End | Home / End |
| Go to Timecode… | ⌃G |
| — | |
| Loop Playback | ⌥L |
| Mute | ⌥M |

### Window
| Item | Key |
|---|---|
| Minimize | ⌘M |
| Zoom | |
| — | |
| Films | ⌘⇧0 |
| — | |
| Bring All to Front | |
| (open film windows) | |

### Help
| Item | Key |
|---|---|
| Search | (system) |
| Keyboard Shortcuts | ⌘/ or ? |
| How Direction Works | |
| What's New | |
| — | |
| Contact Support… | |
| Editor Status Page | |
| — | |
| Show Direction Log | |

**Show Direction Log** opens `~/Library/Logs/Direction/Direction.log` in Console. The app and the `direction` helper both write to it: every tool call that fails, every job that fails or whose process exits, every editor run's start and end (with the program's last error lines when it fails), and every alert. API keys and bearer tokens are masked before a line is written. It rolls over at 5 MB, keeping one older file (`Direction.1.log`).

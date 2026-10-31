# Start: films, brief, footage, assembly

**Purpose.** Get from nothing to a first cut the director can screen. Four steps, in the order a real production runs: say what the film is (brief), bring the footage, let the editor log it, let the editor assemble from your circles.

**Primary action.** One steel button per frame, at the titlebar's right (on the empty Films screen it's the hero button instead): New film → Continue → Start logging → Open Dailies → Screen the assembly.

**Entry points.** App launch with no films (01). App launch with films, `⌘⇧O`, or Window › Films (02). File › New Film `⌘N` (03). Film › Bring Footage `⌘I` from any room (04, with the stepper hidden and the crumb showing the film).

**Shared pieces.** Frames 03–05 replace the room switcher with the **stepper** (`.steps` in `css/start.css`): Brief · Footage. Each step is a 24 pt pill; done steps show a check in a filled 16 pt circle, the current step uses `--raised` with a steel-9 number dot. Steps are clickable backwards only. Once footage is logged (or Dailies is opened while it logs), the normal room switcher appears with Screening, Notes, Changes and Finish disabled (`.off`) until the assembly is ready.

---

## 01 · Films, first launch
Frame: `screens/01-films-empty.html` · Render: `renders/01-films-empty@2x.png`

**Arrives from / leads to:** first launch, or the last film deleted. New film (button, `⌘N`) → 03. Start from a folder… → system folder picker → 03 with footage pre-attached (04 is skipped later, logging starts after Continue).

**Layout**
- Window background `--canvas` with a radial glow (ellipse 50%×45% at 50% 42%, steel-1.9 to black). Titlebar transparent, no border.
- Hero column centered, 40 pt above optical center: chrome mark 168 pt wide (`assets/brand/mark-chrome.png`, drop shadow 0 34 44 black 85%), 22 pt gap, title Archivo 800 56/0.95 at 125% width, body 15/1.5 `--text-2` max 52ch, buttons row (36 pt `.btn.lg`).
- "How it works" strip: 4 × 220 pt cells, 1 pt `--line` gutters, radius 12, 44 pt from the bottom edge, centered. Each cell 16/18 pt padding: mono step number `--text-4` + 13 pt semibold label, then 12 pt `--text-3` description.

**Content**
- Title "Start a film". Body: "Tell the editor what you're making, bring your footage, and it will build a first cut for you to watch. You direct. It cuts."
- Buttons: steel "New film", default "Start from a folder…". Titlebar primary "New film ⌘N".
- Strip: 1 Brief "A few sentences on how it should feel." · 2 Footage "The editor logs and transcribes every take." · 3 First look "It assembles a cut. You see it before anyone." · 4 Notes "Watch, mark, give notes. It recuts."

**States and variants:** Only state. If the editor is unavailable (signed out or offline), the pill reads "Offline" and the body adds a 12 pt line under the buttons: "You can write the brief and bring footage now. The editor starts when you're back online." Buttons stay enabled.

**Interactions:** `⌘N` new film. Dropping a folder anywhere on the window = Start from a folder. `↩` triggers New film (default button).

**Motion:** On first launch the mark fades in and rises 8 pt over Glide (360 ms, ease-out), the text follows after 80 ms. Reduce Motion: fade only.

**The mark's light** (`ChromeMark` in the app): a light circles the letter and the chrome reacts to it.
- **The surface.** The bevel is rebuilt from the mark's silhouette: the alpha blurred wide (σ ≈ 2% of the mark) and re-ranged, so every pixel near an edge knows which way it faces. Fine relief comes from the chrome's own flecks.
- **The light.** A point light orbits just outside the letter, low. Chrome near it brightens and chrome far from it dims a little; edges turned away fall into shade.
- **The lit edge.** The stretch of bevel facing the light glows, white where it faces it squarely. Seven wavelengths, red to violet, are each aimed a step apart, so the ends of every lit edge split into a spectrum, as chrome and glass disperse light.
- **The art's rainbow** shows where the light reaches and fades to near grey where it doesn't, so it follows the light too.
- **Timing:** the light goes once around per pass, 5.6 s on `cubic-bezier(0.72, 0, 0.14, 1)` (slow out of rest, quick through the middle, a long eased stall), then rests 2.4 s up and to the left.
- It's a Metal compute shader compiled from source at first use (no build-time Metal tools), rendered at the view's pixel size. Reduce Motion, or no Metal, shows the still mark. The `zz-chrome-mark` and `zz-chrome-mark-close` snapshots render moments of one pass.

**Accessibility:** Mark is decorative (no label). Focus order: New film, Start from a folder…, titlebar New film. The strip is static text read as a list "How it works, 4 items".

**Acceptance**
- [ ] Mark is 168 pt wide and is the only chrome image in the app outside the Dock icon.
- [ ] Exactly one steel button: the hero's New film. The titlebar's New film (⌘N) is a plain button on this empty state.
- [ ] Strip cells are 220 pt and the strip sits 44 pt above the window bottom at 1440×900.

---

## 02 · Films, list
Frame: `screens/02-films.html` · Render: `renders/02-films@2x.png`

**Arrives from / leads to:** launch with films, Window › Films. Double-click or `↩` on a card → opens the film in the room it was last in (usually Notes or Screening). New film → 03.

**Layout**
- Header: 32 pt top, 40 pt sides. "Films" Archivo 800 34 at 125%, subtitle 12 pt `--text-3` 8 pt below. Right: search field 240 × 28, sort segmented control (Recent · Name).
- Grid: 4 columns, 22 pt column gap, 28 pt row gap, 40 pt side padding, 28 pt top. Card = 16:9 poster (radius 10, inner 1 pt `--line`, shadow 0 18 40 −18 black) + 10 pt gap + title (Archivo 700 15 at 112%) + status line (12 pt `--text-3`, single line, ellipsis).
- Poster overlays: top-left badge chip 8 pt inset, bottom-left duration in a glass HUD tag.

**Content (sample)**
| Film | Poster | Badge | Status line |
|---|---|---|---|
| Launch film (selected) | f-dusk | amber chip "2 notes waiting" | Cut 3 · You're giving notes · Today 14:20 |
| Night shift | f-night | — | ion text with diamond: Editor is cutting Cut 2 · 4 of 9 notes |
| Field notes | f-day, desaturated | "Picture locked" with lock | Cut 6 · Finishing · 3 of 5 done · Oct 12 |
| Ridge test | f-hands | — | Dailies · 3 circled · No cuts yet · Oct 9 |
| + New film | dashed sunken tile | — | — |

Status line rules: room/stage first, then what's waiting, then the last-opened time. An editor activity line is ion blue with a diamond and replaces the stage text. "Waiting for you" counts films with unread answers, open questions or unwritten drafts.

**States and variants**
- Selected card: 2 pt `--text-1` ring around the poster.
- Hover: poster brightens (overlay white 4%), and the right side of the status line shows "Open ↩".
- Search with no results: grid replaced by centered 13 pt `--text-3` "No films match "night"." with a ghost "Clear search" button.
- Editor pill shows the most urgent cross-film activity (here "Cutting Night shift" with a meter). Several: "Cutting 2 films".

**Interactions:** Arrow keys move selection; `↩` opens; `⌘⌫` moves to Trash after a confirm sheet ("Move Launch film to the Trash? Your footage stays where it is."). See system.md › Deleting a film for what goes with it. Context menu on a card: Open, Open in New Window, Rename, Duplicate Brief, Show Footage in Finder, Move to Trash. Drag a folder onto the grid = New film from folder.

**Motion:** Selection ring Snap (120 ms). New film card appears with Settle.

**Accessibility:** Each card is one button: "Launch film. Cut 3. You're giving notes. 2 notes waiting. Opened today 14:20." Grid is a VoiceOver list with 5 items.

**Acceptance**
- [ ] Cards are exactly 4 per row at 1440 width; posters 16:9.
- [ ] Only editor activity uses ion blue; only "notes waiting" uses amber.
- [ ] Status lines never wrap.

---

## 03 · The brief
Frame: `screens/03-brief.html` · Render: `renders/03-brief@2x.png`

**Arrives from / leads to:** New film from 01/02 → here. Continue (`⌘↩`) → 04. Also opened later via Film › Brief `⌘B` as the same layout without the stepper and with primary "Save brief".

**Layout**
- Two columns under the titlebar: form column (flexible) and an aside 380 pt wide (`--sunken`, left hairline).
- Form: a centered 640 pt column, 40 pt top padding, 26 pt gap between questions.
- Title: label "TITLE", then the title as Archivo 800 34 at 125%, 1 pt `--line-2` underline, no box.
- Questions: label 13 pt semibold + optional 12 pt `--text-4` qualifier, 8 pt gap, then the input. Logline and feeling inputs use large text (17/1.4, 12/14 padding). Feeling is a text area, minimum 88 pt.
- Length and audience sit in a 2-column row (20 pt gap). Length is two 76 pt mono fields with "to".
- Must keep: tags (26 pt pills) with a quote or film icon by type, × to remove, and a dashed "+ Add".
- References: 96 × 54 thumbnail + title + "why" line + more menu, 8 pt gap between cards.
- Aside: 40/28 padding, ion uppercase label with a diamond, Archivo 14 heading, three `.say` rows, hairline, 12 pt footnote.

**Content:** Exactly as in `specs/story.md › Brief`. Helper under feeling: "Talk the way you'd talk to an editor. Feelings are better than instructions." Aside heading: "Your brief is the first thing it reads, and the last thing it checks." Rows: "It picks takes for the assembly with this feeling in mind." / "When a note seems to fight the brief, it asks you before cutting." / "Must-keeps are never cut, by anyone but you." Footnote: "You can change the brief any time from Film › Brief (⌘B). Changes apply from the next cut."

**States and variants**
- Continue is disabled until title, logline and feeling are non-empty.
- Validation: on Continue with an empty required field, that field gets `.field.err` and a 12 pt `--alert` helper "The editor needs this to start."
- References accept drag-in of video files (thumbnail = first frame), stills, or URLs (thumbnail = page image; while fetching, a 54 pt sunken box with a spinner).
- Editing an existing brief after Cut 1 shows a banner at the top of the form: "Changes apply from the next cut. Cut 3 was made with the earlier brief." with "See earlier brief".

**Interactions:** `Tab` moves through fields in visual order. `⌘↩` Continue. In Must keep, typing and `↩` adds a tag; pasting a line from the transcript adds it as a quote tag. Dragging a clip from Dailies onto Must keep adds a film tag. References: drag to reorder.

**Motion:** None besides field focus rings (Snap).

**Accessibility:** Each question's label is the field's label; qualifiers are read as hints ("Required"). Tags are buttons "Remove Editing was the part nobody wanted".

**Acceptance**
- [ ] The form column is 640 pt wide and centered in the space left of the aside.
- [ ] Title uses Archivo; every other field uses SF Pro.
- [ ] Continue stays disabled until three required fields have text.

---

## 04 · Bring footage
Frame: `screens/04-footage-drop.html` · Render: `renders/04-footage-drop@2x.png`

**Arrives from / leads to:** Continue from 03, or Film › Bring Footage. Choose a folder or drop → files listed → Start logging → 05. When files are dropped, logging starts automatically after 1 s unless the director drops more; the primary is a fallback.

**Layout**
- 28 pt padding all round. Drop zone fills the space (radius 20, sunken radial fill, 1.5 pt dashed border at white 18%).
- Centered stack: three fanned 150 pt 16:9 cards (−8°, 0°, +7°), then the title (Archivo 800 34 at 125%), body 13.5/1.5 `--text-3` max 50ch, buttons (36 pt), and a 12 pt `--text-4` line of supported formats with icons.
- Footer row 18 pt below the zone: brief reminder with an Edit link (left), storage note (right).

**Content:** Title "Bring footage". Body: "Drop a folder, a camera card or loose files. The editor logs every take, transcribes the dialogue and sorts it into scenes. Your files stay where they are." Buttons: "Choose folder… ⌘O", ghost "From a camera card". Formats: "MOV, MP4, MXF, BRAW, R3D" · "WAV, separate sound synced by timecode" · "A script, if you have one (PDF, FDX)". Footer: "Brief saved. "Tired, then proud. Quiet, not triumphant."" and "Nothing is moved or copied. Proxies go to ~/Movies/Direction."

**States and variants**
- Drag over: border becomes 1.5 pt solid `--text-1`, the fill lifts to steel-3, and the title changes to "Drop to add 214 files" (count from the drag pasteboard).
- Unsupported drop: the zone shakes once (Snap ×2, 4 pt) and the body line becomes `--alert`: "Those aren't video, sound or script files."
- Camera card button lists mounted volumes in a menu; with none mounted it's disabled with a tooltip "No camera card connected".

**Interactions:** `⌘O` folder picker (multi-select). Drop anywhere in the window. `esc` returns to 03.

**Motion:** Fanned cards spread 6 pt on drag over (Settle).

**Accessibility:** Drop zone is a group "Drop footage here" with the two buttons as actions. Formats line is read once as a hint.

**Acceptance**
- [ ] Nothing is copied on import; the spec storage note text matches Settings › Storage path.
- [ ] Drag-over state is visibly different without color alone (solid vs dashed border).

---

## 05 · Logging footage
Frame: `screens/05-footage-logging.html` · Render: `renders/05-footage-logging@2x.png`

**Arrives from / leads to:** after files are added in 04. Open Dailies (primary, available as soon as one scene exists) → 07. When logging completes: toast "214 takes logged. 5 scenes, 14 unsorted." with "Open Dailies", and the stepper keeps Footage current until Dailies opens.

**Layout**
- Main column + 360 pt aside (sunken, left hairline).
- Summary block: 24 pt padding. Title Archivo 800 28 at 122% with a 12 pt estimate to its right, a 5 pt prism progress bar, then a row of five stats (15 pt mono value over 12.5 pt label, 28 pt gap). The "need you" stat is `--alert`.
- File table: header row 32 pt (mono uppercase labels), rows 52 pt with a hairline. Columns: status icon 22 · thumbnail 72 (40 pt tall) · file name + setup/take in mono 11 · duration 64 (mono) · scene 150 · status (flexible).
- Rows are ordered: needs you first, then in progress, then done, then queued.
- Aside: ion uppercase label, `.say` rows, scene list (52 × 30 thumbnails, title 13 pt, mono 11 meta), pending scenes at 45% opacity.

**Content:** Per `story.md`. Pill: "Logging 131 of 214" with a meter at 61%. Estimate: "About 6 minutes left. You can start circling takes now." Problem rows: "No audio. Separate sound file?" with a "Find sound…" small button; "Can't read this file. It may be damaged." with a ghost "Skip". Done rows show the first transcribed line in quotes, or "No dialogue · wind". Aside closing message: "No script found. I'll build one from the transcript for the Script room." / "Have one? Drop the PDF here."

**States and variants**
- Row status icons: alert triangle (needs you), spinner (logging/transcribing, with an 80 pt prism progress bar and the step name), green check (done), blank and 45% opacity (queued).
- All done: the summary title becomes "Footage logged", the progress bar disappears, and stats keep their values.
- With a script dropped: aside row becomes "Script matched to 92% of lines." and Script uses it.
- Paused (sleep, disk full): banner at top `.banner.bad` "Logging paused. Disk is full." with "Open Storage settings".

**Interactions:** Rows are selectable; Space previews the take (Quick Look style player sheet). Context menu: Show in Finder, Skip, Mark Not usable, Assign to Scene ›. "Find sound…" opens a file picker filtered to audio. Clicking an aside scene opens it in Dailies.

**Motion:** New rows move from queued to the in-progress group with Glide. The progress bar's prism shimmers (Shimmer 2.4 s) while working; Reduce Motion: static prism.

**Accessibility:** Table with column headers. Status cell is read as text ("Transcribing, 70 percent"). Problems are announced when they appear ("A014_C007 has no audio").

**Acceptance**
- [ ] Problem rows always sort to the top.
- [ ] The pill text, meter and the summary agree (131 of 214, 61%).
- [ ] Prism is used only on progress lines and the pill border, never as a fill on text.

---

## 06 · Building the assembly
Frames: `06-assembling`, `06-assembly-question`, `06-assembly-ready` (snapshots of Dailies; no page of its own)

**No page of its own.** The assembly is built like every later cut: the director stays in the room they asked for it in (Dailies, from Assemble from circles) and keeps circling, and the editor pill carries the work. An earlier full-window frame (a black stage, a title, scene tiles, a log and a "First look is yours" card) looked like nothing else in Direction, and everything on it has a home in the rooms.

**Arrives from / leads to:** Assemble from circles in Dailies (07). When done: one prism sweep under the titlebar, the toast, and the titlebar's steel primary becomes Screen the assembly → 13 (Screening, Assembly).

**While it builds**
- Pill "Assembling 3 of 5" with a meter. Its popover: "Building the assembly from your circled takes." and what the editor is doing now.
- Dailies' primary is "Assembling…" (disabled) with the circle count. Circles changed now apply to the next cut, with a toast saying so.
- Rooms: Dailies and Script enabled. Screening, Notes, Changes and Finish stay off until the assembly is in.

**The editor asks.** A question during the assembly appears at the top of Dailies, above the scene grid (max 620 pt wide, 28 pt in, the scene header's margin), as the same card Notes › Questions uses (`QuestionCard`, not steel: the titlebar has the steel button). The pill turns `.asks` "1 question"; its popover's Answer opens Dailies. Notes holds questions from the first cut on.

**It stops.** The full-width banner under the titlebar (`EditorRunBanner`, frame 58's copy and actions) shows wherever the director is.

**Ready.** Toast "The assembly is ready. 3:12." / "Nobody else sees it until you've screened it. Watch it once all the way through." with Screen it. The pill reads "Assembly ready"; its popover says the same and offers Screen it. In every room but Screening, the steel primary is **Screen the assembly ⌘↩** until the assembly has been screened or noted.

**Motion:** On completion, Sweep (900 ms) once across the top edge.

**Acceptance**
- [ ] Asking for the assembly never takes the director out of the room they're in.
- [ ] A question about the assembly is always answerable: in Dailies before the first cut, in Notes after.
- [ ] The Share button is absent until the assembly has been screened once.
- [ ] Only one prism sweep, on completion.

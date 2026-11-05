# Breakdown

**Purpose.** Plan the shoot, then keep track of it. The editor breaks the OK'd A/V script (specs/script.md) into shots grouped by setup: a place and its light, set up once. Each shot has a source. Once the director OKs it, the shot numbers are the slates, and the breakdown stays open through the shoot as the checklist of what's in and what's missing.

**Primary action.** OK breakdown (disabled while the editor is still breaking it down) → Bring footage (OK'd, nothing in yet) → Assemble from circles (takes are in; disabled until one is circled) → Open Dailies (once there's a cut). Turn over N wins whenever notes are waiting.

**Entry points.** Script › Open Breakdown, room switcher `⌘2` (enabled once the script is OK'd), Film › Print Shoot List….

## Shots and setups

- **Setup**: a number, a name ("Desk at night") and what it needs ("After dark · lamp off · the chat app open on the monitor"). Setups that need no camera (screen recordings, shots to make, footage you have) are marked so and listed after the rest.
- **Shot**: its code (setup number and letter: 2C), the rows it plays under, what we see, how to get it on the day (shoot, screen and sound shots: where the camera goes and whether it moves, how long to record, what to get right), what it's for (a line, when what we see doesn't say), size, move, seconds, source, its board, and for a made shot a plan and an estimate (none when it's free, like a graphic).
- **Words**: written for a director who's never been on a set: plain words, no crew shorthand (locked off, plate, cover, matte, layer, roll), every recording its own shot (never Take A and Take B; a take is another try, said on the slate), and the script's moments named by what happens there, not by row. Moves read plainly: Camera still, Moves in, Moves back, Turns side to side, Tilts up or down, Handheld, Moves alongside.
- **Sources**: Shoot · Screen (a screen recording) · Make (the editor makes it) · Have it (footage you already have) · Sound (sound only, like a narration).
- **Numbers**: before the OK, Direction numbers setups in the order they're first needed (no-camera ones last) and letters shots by their first row. After it they never change: a new shot takes the next letter in its setup and is marked as added after the OK, and a shot can't move to another setup. Numbers in the words ("the same frame as 2B") follow their shots when they're numbered again; a number that names no shot, or a shot taken out, goes back to the editor to fix.
- **What's yours**: a field the director set (what we see, size, move, source) and footage they added change only where a turned-over note on that shot asks.

## Dailies and slates

OK breakdown gives Dailies a scene per setup (its number and name) and a setup per shot (its code and what we see), so takes, circles and the assembly work as they always have. A take is filed into its shot by its slate: the shot and take said at its head ("2C, take one", "two charlie take three", "2C T1", in the first 10 seconds of its words) or its file name ("2C T1.mov", "5a_take3.mp4"). Only codes the breakdown has count. A take filed this way still goes to the editor to log; it keeps its place.

## Coverage

Each shot is one of: planned (nothing shot for its setup yet), got (its takes, circled first), missing (its setup was shot and it wasn't), needs footage (Have it, nothing added), to make. A missing shot asks what should happen: Make it (free, or about its estimate; the spend rule applies), Pick it up (it goes on the pickup list for the next shoot), Do without it (the shots around it play over its moment).

## Layout (frames 74–76)

- **Setups**, 240 wide: By setup · Script order; To shoot and No camera, each setup with its shot count (after the shoot, "3 of 4" in); Next shoot › Pickups once footage is in; Print shoot list… once OK'd; a line saying what to do now.
- **Shots**: "Breakdown" in Archivo with a line under it (shots and when it was OK'd, or takes in); the sources as chips with the estimate before the shoot, or "7 of 12 in" with a bar after. A banner when the script changed since the breakdown was made (Update the breakdown, which runs the editor; numbers and your edits stay). What the editor said when it last finished, or which shots didn't come in. Then each setup (its number in a 22 pt tile, name and count, with all of what it needs under them: it's the plan for the day) and its shots: code (with the solid diamond if added after the OK or changed in the last pass), the picture (the circled take, else the board; a waveform for sound; a dashed "Drop here" for footage to add), what we see, how to get it (two lines, before the shoot) and its size · move or its takes, then where it plays (before the shoot: the moments by name, a story beat's title or a line's words, over their times in the film, "Hold, Out" over "0:29–0:46"; never row numbers, which only the Script shows) or its first three takes with the circled one ringed in amber (after), its length, and its status chip (Shoot, Got it, Missing, Pick up, Make, Add footage). The page is centered, up to 1560 wide; rows have 13 above and below. A wide page reads bigger, as the Script page does (`PrepMeasure`): past 1240 what we see is 14 pt and may take three lines, the picture is 112 wide, Plays under 255 and rows 16 above and below; past 1440, 15 pt, 128, 300 and 19. A shot the editor asks about carries the question on one line under it (the diamond, the question, Answer…), and the head counts them ("1 question", which goes to the first); the Breakdown tab shows the count in ion. Answering is in the shot's panel.
- **The shot**, 360 wide: its code, setup and status; the picture large, with a line saying what it is; the missing shot's three choices, or the editor's question; What we see; How to shoot it (How to record it for screen and sound; both yours once you change them); What it's for; Framing; Move; Length; Source; for Make its plan and estimate; Plays under (each moment: the speaker or cue, or from a story the beat's title, and its times, then what we hear there); the director's notes on it; the composer ("Note N on 2C").
- **Have it**: the picture is a drop zone, "Drop footage here", with Choose a file… and Choose a take. What's added is brought into the film as footage and filed under the shot.

## Shoot list

Print Shoot List… prints the shots to shoot setup by setup, with what each needs, a box (✓ once a take is in), the code, what we see, size · move and length, how to get it under each, ending with how to slate. Made shots and footage you have aren't on it.

## The editor's side

`direction_breakdown` reads setups, shots with their coverage and takes, the turned-over notes, and whether the script changed (`includeScript: true` adds the A/V script). `direction_breakdown_update` adds or changes setups and shots, removes shots, answers notes and asks on shots; it returns the rows still without a shot, what it refused, and `toFix`: shot numbers in the words that name no shot. The job is `breakdown` (Resources/Editor/jobs/breakdown.md), the skill `break-down`; Direction starts it when the script is OK'd and after each Turn over. The assembly reads the breakdown when there is one: the script's rows in order, each row's picture from its shot's circled take, the narration on A1.

## Acceptance

- [ ] Setups are numbered by the row they're first needed in, no-camera setups last, and shots lettered by row.
- [ ] After the OK no shot's code changes; a new shot takes the next free letter.
- [ ] Dailies has a scene per setup and a setup per shot once OK'd.
- [ ] "2B, take 2" said in a take's first seconds, or "2B T2.mov", files it in 2B as T2.
- [ ] A shot is missing only once another shot of its setup has a take.
- [ ] A shot the editor asks about shows the question on its row, and the Breakdown tab counts it, before the shot is clicked.
- [ ] A question the director answered on the script is never asked again on the breakdown (the job's brief lists it under Already decided).
- [ ] Before the OK, a shot named in another shot's words keeps being named right when the shots are numbered again; a number no shot has comes back in `toFix`.
- [ ] The Breakdown never shows a row number: a shot plays under moments by name and time.

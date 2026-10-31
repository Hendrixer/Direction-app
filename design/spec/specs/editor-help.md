# Helping the editor (plan)

Not built. Planned 31 Oct 2026, after looking at how others have a coding agent edit video: Ajené Pinnock's Claude Code setup (HyperFrames, style skills, a review app that sends notes to a waiting session), browser-use's video-use, Tella's skills, Brooke Lacey's cut lists, ButterCut, and Palmier Pro (a Swift editor with a local MCP). The director's side of Direction is in good shape; this is about making the editor faster, better informed and harder to get wrong.

What Direction already does that they built by hand: timecoded notes that reach the editor without copy and paste, a session that continues when the director answers, its own renderer for JavaScript graphics with checks (words that overflow, title safe, contrast, small text), sync by sound, a footage index, and now layouts and a check on made shots.

## Worth building, in order

1. **Learned rules ("save this to the skill").** *Built 31 Oct 2026 as Keep as a rule, with styles restructured around rules, named layouts and moves and a house style under every film (styles.md).* The single biggest lever in Pinnock's setup: after a round of notes he says "save this to the skill", and the mistake never comes back. Direction keeps per-film NOTES.md but nothing carries between films. On an accepted answer, Changes offers **Keep as a rule** ("Text never covers my face", "No captions over full-screen graphics", "Music 25 dB under the voice"), worded by the editor and confirmed by the director, saved to the director's house rules (beside Styles) and read by every job. One-off notes stay one-off (Lacey keeps the two apart for the same reason).
2. **Direction checks every edit, like it now checks made shots.** video-use re-checks every cut after rendering and measures loudness because the agent can't listen. Direction can do it in the edit itself and return findings in the `direction_edit` result, so the editor fixes them before the director sees them: a cut inside a word or breath, a flash frame (a clip under 3 frames), a jump in loudness across a cut, black or frozen frames, a graphic or caption over a face (from the face tracks layouts already measure), a cutaway that runs past its take.
3. **A turnover packet.** Every turnover starts with the editor fetching the same things. Direction puts them in the job: for each note, its range in the cut, three frames, the words said there, the clips under it with their takes, and what's on screen. Fewer tool calls before the first edit, and the editor reads the note against the picture the director saw.
4. **Words as phrases by default.** video-use hands the agent a 12 KB "packed" transcript, one line per phrase split on pauses (`[002.52–005.36] …`), with word-level detail on demand. `direction_transcript` gives every word with its id; the phrase view becomes the default, words when an edit needs ids.
5. **Where things can go.** Placement is guesswork today ("text never covers my face", "put it where I'm pointing"). `direction_shots` and `direction_frame` add the face box per shot (from the layouts' face tracks) and the free regions left over, and `placeGraphic` warns when a graphic covers a face.
6. **You in front of things.** Pinnock's "Depth UI": he's cut out and an interface sits behind him. Apple's Vision separates a person from the background on this Mac (`VNGeneratePersonSegmentationRequest`), so a `behind` layer (a graphic or screen placed between the background and the person) is one effect, with no service or download. HyperFrames does the same with a cut-out and its inverse plate.
7. **Graphics in parallel.** Turnovers with several graphics make them one at a time. Claude Code can hand work to subagents; Direction allows its subagent tool for graphics only, each writing its own folder, and Codex gets the same through its own agents.
8. **More thinking where it counts.** Pinnock runs Opus at high effort. Settings › Engines › Effort now sets it; High is the recommendation for turnovers.

## Moves in code (built 31 Oct 2026)

The same split as layouts, for what a style does to the picture: the editor names the moment, Direction does the math. `punchIn` (framing changes on every jump cut, on the face), `emphasisPunch` (one line cut in and out) and `slowPush` (a creep across a long take), with the style's numbers (agent-timeline.md). Then the style's transitions by name with their sound under the cut, and screen zooms Screen Studio-style: `autoZoom` finds where the action is from what changes on screen four times a second (the cursor OBS records into the picture, clicks, typing; a new page ends a moment) and `zoomTo` a point or words found on screen. On the director's real 4K screen recording a minute is looked at in 17 s the first time, then read back. Next: speeding up stretches where the screen doesn't change, and techniques learned from tutorial videos (techniques.md).

## From Diffusion Studio (studied 31 Oct 2026)

Its editor gives the agent no edit tools: the agent edits the project's JSX files, and 18 inspect-and-verify tools check the work. The ideas worth taking, in order:

1. **`direction_check` after every edit, no render.** Coded issues with ranges and how bad each is: a gap, a black or frozen stretch, a clip that's never seen, a cut inside a word, a caption under a graphic, missing media, a made shot that didn't pass. `direction_turnover_complete` refuses while there are errors. (Its `check`: black-frames, no-visuals, never-visible, zero-duration, source-error.) This is item 2 above, now with a shape.
2. **Moves and graphics anchored to words.** Its keyframes run on the source's clock, so they stay on the same footage when the head is trimmed. Direction's punch-ins, zooms and graphics would hold to their word ids when removeWords or tightenPauses changes things before them.
3. **Error messages that name the fix**, from a closed set of codes: "w_481 was removed by removeWords at revision 14; the line now starts at w_482."
4. **Frames where something changes.** Its `grab auto` scans at 2 fps and keeps a frame only when the picture settles into something new, skipping transitions. Contact sheets of a take or the cut would pick their frames that way instead of every N seconds.
5. **Sheets sized for reading.** At most 2576×1456, the grid chosen so each cell is as big as it can be, labelled with its time, at most 4 images returned inline, the rest as paths.
6. **A waveform as a picture and numbers**: silences shaded and cuts marked, with the silent ranges listed.
7. **Big results as files.** Its transcribe returns a path and counts and says to search the file; Direction's transcript tool would return words by query by default.
8. **One time format everywhere**: seconds, `45f` or `MM:SS` in, seconds out.
9. **A depth ladder for watching**: stop at the first look that answers the question (the transcript, then a sheet, then frames), and let the sound choose which frames to look at.
10. **Graphics checked for determinism**: render a graphic at a later time, then an earlier one, and compare with the forward order, to catch animations that depend on what played before.

Already here: contact sheets, word-level transcripts, the footage index, jobs and the brief, house style, estimates, revisions.

## Not worth it

- **HyperFrames for graphics.** It renders HTML in headless Chrome with FFmpeg; Direction already renders JavaScript graphics itself, checked and cached, with no Chrome. Its lessons are already here (seek-based rendering, no clocks or randomness, findings with crops).
- **720p review renders.** Direction plays the cut live; nothing waits on a render to review.
- **Runway's MCP for the editor.** Its developer MCP doesn't make media, and its generation MCP bills the director's Runway app plan, needs a browser sign-in, and would go around Direction's estimates and spend limits.

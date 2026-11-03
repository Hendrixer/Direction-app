# Script

**Purpose.** Direct the picture before anything is shot. The script comes in as a file, or a story does; Direction lays it out as an A/V script, one row per beat, with what we see beside what we hear. The editor writes the picture from the film's style (and, from a story, what we hear too). The director types in any cell, leaves notes on rows, turns them over for a pass, and OKs the script for the breakdown (specs/breakdown.md).

Writing and research stay outside Direction (Takepath, a screenwriting app, any text editor). The script or story comes in once; from then on Direction's copy is the shooting script, and nothing goes back.

**Primary action.** One steel button, by state: Bring in a script… (no script) → OK script (disabled while rows have no picture, the editor has a question, or it's still writing) → Turn over N (whenever notes are waiting; it wins) → Open Breakdown (once OK'd).

**Entry points.** Films › Start from › A Script… or A Story…, and File › New Film from a Script… or New Film from a Story… (a new film named for the file). Film › Bring In a Script… or Bring In a Story…, or a script dropped on the window, in a film that has none (footage-first films can add one). With one already in, Bring In a New Draft… brings the same kind; a file dropped on the window is a new draft too. Room switcher `⌘1`.

## Bringing in a script

`ScriptImport` reads Markdown, plain text, Fountain, Final Draft (`.fdx`, through Fountain) and PDF (its text):
- Headings are sections; a level-one heading at the top with sections under it is the film's title, not a section. Front matter, comments and Fountain notes are dropped.
- Paragraphs are voice-over, a beat or two at a time: a sentence or two, about 18 words at most, never split mid-sentence.
- `NAME: words` is someone on camera (VO, V.O., Narrator are voice-over). A line on its own like `[ON CAMERA]` or `[VO]` switches what follows.
- A line that's only a picture (`[me at the desk]`, `(B-roll: hands)`, `PICTURE: …`) is the next row's hint; a `[…]` inside a paragraph belongs to the beat it's in. Hints are the writer's idea, for the editor to start from.
- A two-column table (Picture | Sound, Video | Audio) keeps both columns; its pictures count as the director's.
- Fountain: scene headings are sections, dialogue is on camera (`(V.O.)` is voice-over), action is a picture-only row in the writer's words, centered text is a title.
- Seconds come from the words at 2.5 a second (a cue without words holds 2 s), until there's a recording.

**A new draft.** Rows whose words didn't change keep their picture, their notes and their id; new words get new rows; rows whose words are gone go, and notes on only those are dropped. The breakdown is told the script moved on.

## From a story

A story is what happens, told in prose, with nobody's words written: a treatment, an outline, a beat sheet. The director says it's a story by choosing it (A Story…, the story half of the start zone); Direction never guesses, since a narrated essay is prose too.

- `ScriptImport.story` reads any of the same files as prose. Headings are sections (a title at the top as for a script); each sentence of a paragraph is a beat, a short one ("She erases it.") kept with the one before, never more than about 24 words. A line that's only a picture, or a `[…]` in a paragraph, is the beat's hint, as in a script.
- Each row keeps its part of the story (`story`). Nothing is heard yet: the sound cell says "What do we hear?". Seconds start from the beat's words, 2–8 s, until the editor gives each row its own.
- The editor writes both columns: the picture, and what we hear: someone on camera or a voice recorded on its own, a sound, music, silence. It never writes words for anyone to say. Where someone talks, the cell says who and what about ("Calling her dad: the hello") and the row is in their **own words**: the speaker finds them on the day. Words the story quotes are the writer's and are said as written.
- A new draft of a story matches beats by their part of the story: a beat whose story didn't change keeps its picture, its sound and its notes. A script brought in over a story (or a story over a script) starts the rows again.

## Layout (frames 70–73, 78)

Three columns under the titlebar, like the other rooms.

- **Outline**, 200 wide: Sections (each with its row count, or its notes in amber when it has some; click scrolls to it), Show (Every row · With notes · No picture yet · Changed by the editor · Your words) and Style (the film's style; changing it opens the brief).
- **The page**, on sunken, 820 wide: a toolbar (Find a line, what's selected or the hint "Click a cell to type in it. Notes wait for Turn over.", rows and running time: "reads in about", or "runs about" from a story). Then where the words came from ("The story, from Night walk.md · 77 words" from a story) with Bring in a new draft…, the editor's progress while it writes, and the rows under PICTURE · SOUND · TIME, grouped by section (number, title in mono caps, the section's time).
- **Row**: its number (with the editor's solid diamond when its last pass changed it); from a story, its part of the story first, 12.5 pt `--text-3`, across both columns; the picture (an 80 pt board, then the text, then chips: Note N in amber, Changed, Your words, Question, and size · move); the sound (VO, the speaker on camera, or the cue, then the words; cues, and talk in someone's own words, in italic, the label ending "· OWN WORDS"); its time. A row with notes has a 2 pt amber bar on its left. The selected rows are panel.
- **Sheet**, 360 wide: "Notes on the script" with what's waiting, with the editor, done; Notes · Questions tabs with counts; the composer at the bottom ("Note N on Row 4", What should we see?, kinds, Add ↩).

**Boards.** Every picture gets a drawn board in the board style: line drawings on near-black, one weight of grey, dark silhouettes, a single lit edge where the light falls. Kinds: title, screen, wide, medium, close, detail, on camera, action, made (with the editor's diamond), empty ("?"). A push or pull shows corner marks where it ends. Boards are free and instant and plainly not footage; a take replaces its shot's board in the breakdown when it comes in.

## States

- **No script** (70): "Start from a script or a story" with Choose a script… and Choose a story…. A brand-new film without footage shows the start screen first (start.md › 04); a script dropped there starts the script instead.
- **The editor writing** (71): the editor starts on its own when a script comes in (Start work: Ask me first holds it). Rows fill in; the first empty one says Writing… in ion with a spinner, the rest an ellipsis or the writer's idea. The pill reads "Writing pictures 6 of 11". Notes can be written; OK script is disabled.
- **Your pass** (72): type in any cell (↩ saves, esc cancels); what you type is yours and the editor keeps it. Select rows by their number (⇧-click for a range) and write a note. A row with no picture the editor can't decide on carries its question inline, with 2–3 choices and Answer.
- **After a pass** (73): changed rows carry the diamond and Changed; notes show Done and the editor's one-line reply.
- **From a story** (78): every row has its part of the story above the picture and the sound; while the editor writes, the progress reads "Laying out what we see and hear, beat by beat, from the style. 6 of 11."

## Interactions

- Click anywhere on a row to select it (⇧-click for a run of rows, ⌘-click to add or take one out); rows show a faint hover. The words in each cell are typed in where they are: the same font, size and place as the page, so nothing moves; a quiet box is drawn outside the words while the caret is in them. ↩ saves, esc puts the words back, and leaving the cell saves. Typing in a row selects it.
- Context menu on a row: Note on This Row, Edit Picture, Edit Words (Edit Sound from a story), Sound › Voice-Over · On Camera · Sound Effect · Music · Silence · Their Own Words, Move Up, Move Down, Add a Row After, Take Out Row. Choosing a sound makes it the director's: the editor keeps it. ⌥↑ ⌥↓ move the selected row, N starts a note on it, ↩ puts the caret in its picture.
- Find (⌘F): the field says "3 of 12" (or "No matches" in alert), with previous and next beside it (↩ and ⇧↩ in the field, ⌘G and ⇧⌘G anywhere). The current match's row has a 1.5 pt `--text-1` ring and is scrolled to the middle; the words that match are shaded in every matching row, and other matching rows carry a dot by their number (frame 77).
- Turn over sends every written note; the editor runs a pass. A note can be dropped (×) until it's turned over.
- OK script starts the breakdown. The script can still change after; the Breakdown room offers to bring itself up to date.

## The editor's side

`direction_script` reads the rows (picture, sound, seconds, hint, story, question), whether it's a script or a story (`kind`), and the turned-over notes. `direction_script_update` writes pictures, fixes what a row's sound is (from a story: writes it, with `ownWords` and `seconds`), answers notes (`replies`) and asks on rows (`questions`). A picture the director wrote, a sound they wrote, and the script's words, change only where a turned-over note on that row asks; anything else comes back in `refused`. Each pass is numbered, so the room can mark what the last one changed. The job is `script` (Resources/Editor/jobs/script.md), the skill `write-av-script`. It's finished when every row has a picture (from a story, and a sound), every note a reply, and no question is open; it waits for the director while one is.

## Acceptance

- [ ] A Markdown essay, a two-column table and a Fountain screenplay each come in with sections, beats and speakers as above.
- [ ] A picture the director typed survives an editor pass unless a turned-over note names its row.
- [ ] A new draft keeps the picture of every row whose words didn't change.
- [ ] OK script is disabled while a row has no picture or a question is open.
- [ ] A story comes in as beats with its part of the story on each and nothing heard; the editor writes what we hear without writing anyone's words, and a new draft keeps every beat whose story didn't change.

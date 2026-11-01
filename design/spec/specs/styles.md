# Styles

A style is how a kind of the director's videos looks, sounds and moves, kept so the editor can cut every film of that kind that way. It works the way a design system works for an app: rules in words, exact values, what Direction carries out itself, and parts that are reused as they are. The director picks one in a film's brief (optional). Under every film sits the **house style**: the director's rules for every film.

Styles are for people who know what they like before they know how to say it in an editor's words. One made once ("Desk + Screen", "Reaction") carries the pace, layouts, punch-ins, titles, captions, transitions and sound from one video to the next.

## What a film follows

The narrower one wins:

| | Covers | Set in |
|---|---|---|
| Note | one moment | Notes, and anything the director changes in the cut themselves (a layout) |
| Brief | this film | The brief, and Dailies |
| Style | this kind of video | Settings › Styles, the brief, Keep as a rule |
| House style | every film | Settings › Styles, Keep as a rule |

Where two disagree, the higher row wins. One principle is easier to predict than a list: it's how directions to a person work ("always do this, except in this kind of video").

## The split: the editor decides where, Direction does how

Rules say what and when, in words. Layouts, moves and pace say how, as numbers Direction carries out. The editor reads the rules, picks the moments, and asks for things by name ("Showing, 0:42 to 1:10", "punch in on the cuts in scene 2"); Direction tracks the face and writes the keyframes. No reasoning goes into working out how to zoom.

## A style on disk

One folder per style in the Styles folder (Settings › Styles; default `~/Movies/Direction/Styles/`, `DIRECTION_STYLES_PATH` for a process). The folder's name is the style's id. Copying the folder shares it, rules, layouts and all; dropping one in installs it. The house style is the folder `house/`, made the first time something is kept in it, and isn't listed with the styles a brief picks; no style takes its id.

```
desk-screen/
  style.json          rules, layouts, moves, pace and values (required: name)
  graphics/<name>/    Direction graphics (index.html calling direction.graphic)
  transitions/*.metal transitions (agent-timeline.md › Transitions)
  effects/*.metal     effects (agent-timeline.md › Custom effects)
  sounds/*            sound effects and stings: wav, aif, m4a, mp3, caf
  music/*             music beds
  fonts/*             ttf, otf the director owns
  look.cube           the style's look
  stills/*            what it looks like: jpg, png, heic
```

**style.json** (format 2) holds `format`, `name`, `summary` (one sentence), `updatedAt`, and:

| Key | Holds | Who reads it |
|---|---|---|
| `rules` | `[{id, area, text, kept?}]`: one sentence each in the director's words. Areas, in order: general, pace, picture, layouts, graphics, captions, transitions, sound, music, color, avoid. `kept` says which film and note a kept rule came from | Direction (Settings, Keep as a rule) and the editor |
| `layouts` | Named layouts (layouts.md › In a style): `[{name, kind, corner?, size?, shape?, screen?, edge?}]` | Direction: the picker, Dailies, `layout` by name |
| `transitions` | Named transitions for kinds of moments: `[{name, type, frames, params?, file?, sound?, soundDB?}]`, `file` (a shader) and `sound` paths inside the style; or made by a technique, `{name, technique, variant?}` with any of the rest over it (techniques.md). A style written before keeps an object of values here, read by the editor only | Direction: `transition` by name, its sound centered on the cut |
| `moves` | `punchIn {scales, keepIn?}`, `emphasisPunch {scale, everySeconds?}`, `slowPush {from, to, longerThan}`, `screenZoom {min, max, in, out, hold}` | Direction: the moves' numbers when the editor leaves theirs out |
| `pace` | `tightenPauses {longerThan, to}`, and `averageShotSeconds`, `longestShotSeconds`, `hookBySeconds` for the editor | Direction (`tightenPauses`) and the editor |
| `colors`, `fonts`, `motion`, `captions`, `transitions`, `sound`, `graphics` (which part plays which role), `look` | Exact values | The editor |
| `sources` | The videos it was learned from (From a video, below): `[{title, by?, link?, studiedAt?, measured?}]`, `measured` being what Direction counted in each (pace, words, sound, picture, words on screen). Written by Direction from the study, never by hand | Settings (Learned from) and the editor |
| `examples` | Moments that show a rule: `[{id, still, area, text, source?, at?}]`, `still` a picture in `stills/`, `source` the index in `sources`, `at` its second there | The editor (`direction_style` with `stills: true` shows them) and Settings |
| `structure` | How a video of this kind runs: `[{name, at?, length?, what}]`, from the hook to the ending | The editor, for first cuts |

Each move comes from the style, else the house style, else Direction's own (`StyleMoves.standard`: punch-ins 1× and 1.15×, emphasis 1.3×, a push from 1× to 1.05× on shots over 8 s, pauses over 0.35 s to 0.15 s, screen zooms 1.4–2× in 0.6 s, out 0.5 s, held at least 1.5 s). Layouts and transitions come from the style, else the house style.

**Older styles** (format 1) kept their words in `guide.md`. They still read: each bullet or paragraph under a heading is a rule in that heading's area, the template's placeholder lines left out. The first change writes them into style.json; guide.md is no longer read after that.

## In a film

- **The brief** has a Style question after Length (frame 03): one field showing the chosen style's name and sentence, or None ("Your house style, the brief and your notes."). It opens a list (frame 66): a search field (name, sentence and what it holds; every word must match), None first, then each style with what it holds; ↑↓ and Return choose, and Your Styles… opens Settings › Styles. Beside the field, New Style: Write One… (the same sheet as Settings › Styles, and the new style is chosen), Make One with the Editor…, Your Styles…
- **The film keeps its own copy.** Saving a brief that names a style copies its folder to `<film>.direction/Style/`, so the film doesn't change when the style does and travels with its style. Saving it with another style, or None, replaces or removes the copy. A style the editor changes for this film (`direction_save_style`), or a rule kept for it, is copied again. When the style in the Styles folder is newer than the film's copy, the brief says so under the field ("Desk + Screen has changed since this film took it.") with **Use the new version**. The house style isn't copied: every film reads it as it is.
- **The editor** sees the style by name and the house rules in full in its job text, and reads what the film follows with `direction_style`: the rules (the house style's first, then the style's, each saying where it's from), the named layouts, the moves, the values, and each part with its path. It copies graphics to `Editor/Graphics/<name>/`, transitions to `Editor/Transitions/`, effects to `Editor/Effects/`, brings sounds and music in with `direction_import`, and proposes the look with `direction_make_look fromLUT` (the look stays the director's). `direction_graphic_examples` lists the style's graphics first (`fromStyle`). It never builds by hand what a layout or a move does, even where a rule describes it.

## Keep as a rule

When a note says something the director wants every time ("never put words over my face"), the editor offers a rule with its answer (`direction_turnover_complete` › `rule`: one sentence in their words, its area, `scope` style or house, and `replaces`, the ids of rules it takes the place of). Not for one-off fixes.

Once the answer is accepted, Changes shows **Keep as a Rule…** (changes.md). The director edits the wording and picks where it goes: **`<style> films`** (into the style in the Styles folder and the film's copy; films already cut in that style keep their copy until it's picked again) or **Every film** (the house style). Rules it replaces are taken out, so a house rule that overrides a style's says so once instead of being overruled by it. The answer remembers where it went ("Kept as a rule"). A film whose style has left the Styles folder keeps rules in the house style only.

## Making a style

- **With the editor, in the app.** New Style › Make One with the Editor… in the brief: the director says what it should be like (channels, videos, what they like about them) and, when the film has a cut, whether to learn from how it's cut. Direction starts a run with job `style` (skill `make-style`, template `jobs/style.md`). It's done when a style is saved after the run began. Under Your own session, the popover says to ask that session instead.
- **With the editor, in a session of your own.** "Make me a style" with the Direction plugin: the `make-style` skill and `direction_styles`, `direction_style`, `direction_save_style`.
- **By hand.** Settings › Styles › New Style…, or New Style › Write One… in the brief: name, sentence and rules. Edit… changes them; the parts are files, so Show in Finder opens the folder. Move to Trash… asks first; films that use it keep their copy.
- `direction_save_style` writes only into the Styles folder: a new style with `name`, changes to one with `id`, the house style with `house`. `rules` adds rules, `removeRules` takes them out by id, `tokens` merge key by key into style.json (null removes one; layouts need names, moves need their numbers), a `guide` in words is read into rules, `files` copies parts from the editor's working folder to paths inside the style. Nothing else in the folder changes.

## From a video

The quickest way to a style is a video the director wishes theirs felt like. **New Style › Make One from a Video…** in the brief, or **Film › Make a Style from a Video…**: up to three videos (a YouTube, Vimeo or other link, or a file; two or three by the same person make a truer style) and what they like about them.

1. **Direction fetches and studies each, on this Mac.** A link is downloaded with yt-dlp (at most 720p, with its sound); a file is studied where it is (the study folder holds a link to it, never a copy). Each video gets its own folder in `<film>.direction/Editor/Learn/<time>-<n>/`: its words (`transcript.txt`), a frame every two seconds (`sheet-N.jpg`), and what Direction can count (`study.json`, and `study.md` in words), so the editor judges only what it can't:
   - **pace:** the shots and their lengths, cuts a minute and in each minute, when the first cut comes;
   - **words:** words a minute, the gaps left between them and how many pauses run over half a second;
   - **sound:** integrated loudness and true peak, how much of it has music and how much music under speech;
   - **music** (heard in the whole mix: macOS can't take the music apart from the voice, so these are estimates the director checks by ear, and the notes say so):
     - **cues:** each stretch of music six seconds or more. Inside continuous music a new cue starts where the chords change: the notes of the eight seconds before and after differ (1 − their cosine ≥ 0.12), at least twelve seconds apart. Each cue has the instruments Apple's sound classifier hears in a quarter of it or more ("piano", "bowed strings", "synth", "vocals"), its beat, its key, how much of it has someone talking over it, and whether it starts and ends on a cut (within the second the classifier hears in);
     - **beat:** onsets in 24 bands from 60 Hz to 6 kHz, the frames under words left out, the lag that repeats best between 50 and 200 beats a minute leaning toward 120 so it isn't read at half or double; none when nothing knocks (the loudest onset in a hundred under 8× the median: a pad, a drone, vibrato) or nothing repeats;
     - **key:** the 12 notes from G2 to C7 summed over the cue, frames under words counting a quarter, matched to Krumhansl and Kessler's major and minor profiles; named only when the best fits at 0.45 or better and leads the next by 0.05 (music under a voice fits less closely than music alone: in Matt D'Avella's "This is everything that's wrong with consumerism", scored in A minor, A minor was the best fit for most cues at 0.4–0.6). A minor key and its relative major are easy to confuse (its D minor stretch read F major). A cue's own key is named only when it runs 12 seconds or more: shorter ones there read keys the score never used. The notes of every cue together give **the film's key**, the one most of the music fits, and the cues read in another key are named beside it;
     - **breaks:** talk of four seconds or more with no music, before, between and after cues;
     - **how far under the voice:** the music's level in the pauses between words, and with nobody talking, against the words' level, in dB;
     - **stings:** music under six seconds (risers, transitions, hits), where each starts;
     - **a sound right on the cut**, on the cuts with music playing and no word starting on them: an onset four times what's usual around it and a real knock. That's a hit, or the next shot's own sound (in the D'Avella film, cut fast to b-roll, it was half the cuts against the breakdown's 23 hits and risers), and the notes say both; cuts outside the music aren't counted;
     - **risers** into the cuts with no talk in the two seconds before: the level climbing 6 dB or more through those two seconds, steadily. Under a voice a riser can't be told by its level, so this is written only when five or more cuts have no talk before them;
     - **other sounds heard:** whooshes, booms, clicks, a ticking clock, bells, a camera shutter and the like, where each starts and whether on a cut (added effects, or the footage's own);
     - **what the page credits:** the track yt-dlp names and the description's lines about music, a song or a music library, as written there;
   - **picture:** close, medium and wide by the face's size, shots with no face, how often a cut between two shots of the same face changes its size (a punch-in), brightness, contrast, saturation and warmth;
   - **words on screen:** how much of the time captions are up (text that matches what's being said), how many words at a time, where they sit, how many are in capitals, and other text;
   - **every shot** with its framing and any words on it.
2. **The editor makes the style** in one run (job `style`, skill `make-style` › From a video): the numbers become pace, moves, sound and music values, and the cues read against the transcript become music rules (what a cue changes on, where it stops); the contact sheets and frames it takes with `direction_study_frames` give the caption look, graphics, layouts, transitions, color and feeling; five to ten example stills go in `stills/` with `examples`; the run of a video goes in `structure`. What isn't the director's (the footage, the voice, music, fonts) is described, not copied. It saves with `studies`, and Direction writes each video's title, maker, link and numbers into `sources` itself.
3. **The downloads go.** Once the style is saved (the run is done), Direction removes the study folders, downloads and frames with them. A run that stops keeps them for Try Again. The style keeps the links, the numbers (the music cues among them, not every sound heard) and its stills; the link can fetch a video again.

Settings › Styles and the style's sheet show **Learned from** (each video, who made it, a link to it and what was measured), the **Examples** with their sentences, and **How one runs**.

## In the brief

A video dropped or pasted into the brief's references (a file, or a link to a video site) is studied the same way in the background, once, into `<film>.direction/Editor/References/<reference id>/`. A downloaded one keeps only what was read from it: the video goes as soon as it's studied. The card says it's studying, then shows what was measured in a line ("142 shots, 3.1 s each (19 cuts a minute) · 168 words a minute · captions most of the time · 9 music cues · −14 LUFS"), or why it couldn't, with Try Again. Taking the reference out of the brief takes its study with it.

The editor reads it as inspiration for that film: the job's brief lists the reference with what was measured and where its study is, and `direction_brief` › `studiedReferences` has the same. **Make a Style from This…** in the card's menu opens Make One from a Video with the reference and its why filled in, and saves it for every film like it.

## Settings › Styles (frame 65)

"Every film": the house style, with how many rules every film follows and Edit…. "Your styles": one row per style (name; sentence; rules, layout names and parts under it; Edit… and a folder button), New Style… under the list, and a note on what a style is. "Where they live": the Styles folder with Change… and Show in Finder.

**The edit sheet** (style-edit, style-house): name and sentence (not for the house style, which says what it is instead), then **Rules** grouped by area, each editable in place and removable, a kept rule showing the film it came from, and a line to add one (area menu, text, Add). A style shows its **Layouts** drawn by name, its **Transitions** by name with what each is ("Glint, 10 frames, whoosh under it"), and its **Moves** in a line ("Punch in 1–1.15× on jump cuts · Emphasis 1.32× · …"), changed by the editor; then its parts.

**Acceptance:**
- [x] A style is a folder with style.json; one without a readable name isn't listed; the house style isn't listed and no style takes its id.
- [x] A format 1 style's guide reads as rules, and the first change writes them into style.json.
- [x] Picking a style in the brief copies it into the film; picking None removes the copy; the film keeps working when the style is moved to the Trash.
- [x] `direction_style` returns the house rules then the style's, layouts, moves, values and parts with paths; a film without a style gets the house style.
- [x] A layout by name comes from the film's style; moves and `tightenPauses` take the style's numbers when the editor gives none.
- [x] Keep as a rule writes the style and the film's copy, or the house style, takes out what it replaces, and marks the answer.
- [x] `direction_save_style` refuses paths outside the style and files outside the film, layouts without names and moves without numbers.
- [ ] A `style` run is done once a style is saved after it began.
- [x] Snapshots and tests never read or write the director's own Styles folder.

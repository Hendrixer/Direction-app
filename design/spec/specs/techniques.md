# Techniques

Built 31 Oct 2026 (steps 1–3 below; the side-by-side check is still to come), from the director's ask: show Direction a video of an editor teaching a transition or an effect in Final Cut, Premiere or Resolve, and end up with something the editor can use on any film, in a library it reaches for when a style, the brief or a note calls for it.

## What a technique is

A named way of doing one thing, the same way every time: a transition ("Light leak"), an effect ("VHS"), a move ("Speed ramp into the cut"), a graphic ("Kinetic title"), a sound treatment ("Telephone voice"). The same split as layouts and moves: the editor decides where; the technique says how, in code and numbers.

```
Techniques/light-leak/
  technique.json   name, one sentence, when to use it, what it needs, how it's made, its settings
  transition.metal or effect.metal, graphic/, a recipe of edit operations
  assets/          overlays, sounds, LUTs, each with where it came from and its license
  preview/         the tutorial's result and Direction's, side by side
```

- **How it's made** is one of Direction's own pieces: a built-in operation with settings, a Metal transition or effect, a JavaScript graphic, or a recipe: edit operations with blanks the editor fills (`speed` ramps around `{editPoint}`, a `freeze`, a `zoomThrough`).
- **What it needs**: "motion on both sides of the cut", "a screen recording", "a person to cut out". The editor checks before using it.
- **Where it's used**: a style names techniques for its moments (a transition `{name: "Chapter", technique: "Grid flash", variant?: "Big"}`, its own settings over the technique's); the brief or a note can name one ("grid flash here"). `direction_techniques` lists them with when to use each, `direction_technique` reads one, and the edit `technique` (`name`, `editPoint` or `clipID`, `variant?`, `frames?`, `params?`) becomes the transition or effect it makes: its Metal compiled and timed, its sound under the cut. A recipe isn't run; the editor follows its steps.
- **On disk**: `Techniques/<id>/technique.json` (`name`, `summary`, `kind`, `when`, `needs`, `transition` or `effect` or `steps`, `variants`, `source`, `updatedAt`) and its files, in the Techniques folder (`~/Movies/Direction/Techniques`, `DIRECTION_TECHNIQUES_PATH` for a process; tests get their own). Settings › Styles lists them under Techniques.

## The library

**Window › Library** (also Settings › Styles › Open Library): every transition, move and effect the director can name, in one place. Direction's own come first (nine transitions, four moves: punch in, emphasis punch, slow push, screen zoom; eleven film looks: black and white, split tone, faded, halation, bloom, soften, color fringe, vignette, film grain, gate weave, letterbox), then the techniques learned from tutorials ("Learned").

- **Each has an icon of its own**: an SF Symbol, monochrome (icons.md), in a small tile, the same in the library, the @ list and anywhere else it shows. Direction's own are fixed (`LibraryCatalog.builtIns`); a technique names one (`icon`), and one that names none or one already used gets a spare.
- **Each has a preview**: three seconds at 640×360 on made-up shots drawn on this Mac (a sunset, a city at night, a figure walking, a screen with a cursor), so none of the director's footage is in it. Direction's own are made the first time the library opens, in the background, one at a time; a technique's when it's saved and again when it changes. Kept in the caches folder (`Library/v<n>/`).
- **The window**: a search field, All · Transitions · Moves · Effects · Learned, and cards (the preview's poster, playing while the pointer is on it; icon, name, one line). The chosen one shows at the side: its preview playing, what it is, when to use it and what it needs, its variants, where it was learned (a link), and "@Name". Learn a Technique… is there too while a film is open.
- **"@" in a note or the brief** (the feeling and avoid fields) opens the same list at the caret (notes.md). The editor gets each named one explained with the note (`libraryNamed` in `direction_turnovers`, a line under the note in the job) or the brief, and `direction_techniques` lists Direction's own beside the techniques.

## Learning one from a video

**Film › Learn a Technique…** (sheet `learn-technique`): paste a link or choose a file, and say what to take from it ("the light leak at 3:20").

1. **The video.** A file is copied beside what Direction reads from it. A link is downloaded when the director presses Learn under "Direction downloads the video to learn from it". Either way it stays in the film's editor folder for reference and never goes into a film.
2. **Direction reads it like footage**, into `<film>/Editor/Learn/<time>/`: `video.mp4` (yt-dlp at 720p, with `video.info.json`, its title, maker and description), `transcript.txt` (Whisper on this Mac, or Apple's), and `sheet-N.jpg` contact sheets, a frame every two seconds with its time. `direction_study_frames` gives the editor full frames at any moments, to read a settings panel.
3. **The editor builds it** (a `technique` job, template `jobs/technique.md`, skill `learn-technique`; done once a technique is saved after the run began): the steps in the tutorial's words, then the same result in Direction's: which piece makes it, its settings, the Metal or graphic when it needs one, and the recipe. Assets are made (OpenRouter's sound and image versions, inside the spend limit) or found under a license that allows it, asking before any download. It never copies the tutorial's own footage or paid packs.
4. **Checked against the tutorial**: the editor tries it on the film, looks at frames beside the tutorial's, and puts the cut back. Still to come: a decision version comparing them (as made shots are checked), and the director seeing both side by side to keep it or say what's off.

## What translates

Most transitions (light leaks, film burns, whips, glitches, zoom and spin transitions), looks and treatments (grain, VHS, halation, glow, chromatic aberration), text animation (as graphics), speed ramps, masks and reveals (with person cut-outs on this Mac), split screens, sound design. Not yet: anything needing 3D camera tracking or particle systems beyond Metal; a third-party plugin's own internals. The editor says so instead of faking it.

## The first two

Learned from two of Ryan Nangle's Final Cut Pro tutorials:

- **Grid flash** (from "Grid Transition Plugin"): a Metal transition. The frame splits into squares; each flips to the next shot at its own moment under a flash, while thin grid lines show. Settings follow the plugin's: `cols`, `order` (shuffled by `seed`, by rows, from the middle, from the top left), `flash`, `spread`, `loops` (flicker), `flashColor`, `difference` (a negative flash), `lines`. Variants Big, Large, Medium, Small, Fine (3 to 16 across), From the middle, By rows, Flicker, Negative, No lines. A run of clicks made on this Mac plays under it.
- **Pixel grid** (from "Pixel Grid Effect Tutorial"): the built-in `pixelGrid` effect. Where Final Cut uses a magnetic mask, a feather and the pixelate effect, Direction finds the subject (people and objects) with Vision fifteen times a second and keeps how much of each square it fills (`ClipEffect.data`); playback shows the clip only in those squares, with grid lines over the frame. Variants Big squares, Fine squares, No lines.

## Order

1. The technique format and library, `direction_techniques`, the `technique` operation, and styles naming techniques; today's named transitions become the first techniques.
2. Learning from a file.
3. Learning from a link (download with the director's yes).
4. The side-by-side preview and the decision-version check.

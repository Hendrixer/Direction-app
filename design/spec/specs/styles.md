# Styles

A style is how a director's videos look, sound and move, kept so the editor can cut every film that way. It works the way a design system works for an app: exact values, guidance in words, and parts that are reused as they are. The director picks one in a film's brief (optional). The brief and the notes always come first; the style decides what they leave open.

Styles are for people who know what they like before they know how to say it in an editor's words. One made once ("Desk Talk", "Long Walk") carries the pace, titles, captions, transitions and sound from one video to the next.

## A style on disk

One folder per style in the Styles folder (Settings › Styles; default `~/Movies/Direction/Styles/`, `DIRECTION_STYLES_PATH` for a process). The folder's name is the style's id. Copying the folder shares it; dropping one in installs it.

```
desk-talk/
  style.json          the values (required: name)
  guide.md            the rest, in words
  graphics/<name>/    Direction graphics (index.html calling direction.graphic)
  transitions/*.metal transitions (agent-timeline.md › Custom transitions)
  effects/*.metal     effects (agent-timeline.md › Custom effects)
  sounds/*            sound effects and stings: wav, aif, m4a, mp3, caf
  music/*             music beds
  fonts/*             ttf, otf the director owns
  look.cube           the style's look
  stills/*            what it looks like: jpg, png, heic
```

**style.json** holds `format` (1), `name`, `summary` (one sentence), `updatedAt`, and the values the editor holds to. Direction reads only the first four; everything else is for the editor. The keys the `make-style` skill uses:

| Key | Holds |
| --- | --- |
| `pace` | `averageShotSeconds`, `longestShotSeconds`, `pausesUpTo`, `hookBySeconds` |
| `picture` | `punchIn` (scale), `brollEverySeconds` |
| `colors` | hex: `text`, `accent`, `backing`, … |
| `fonts` | per role (`title`, `body`, `captions`): `family`, `weight`, `width` |
| `motion` | `in`, `out`, `hold` (seconds), `ease` |
| `captions` | `on`, `wordsAtATime`, `case`, `position` |
| `transitions` | `default` (`cut`), `use` (names), `frames` |
| `sound` | `musicUnderSpeechDB`, `effectsDB`, `whooshOnTransitions`, `popOnGraphics` |
| `graphics` | which part plays which role: `title`, `lowerThird`, `captions`, … |
| `look` | `strength` |

**guide.md** has one section for each thing an editor decides: Pace, Picture, Graphics, Captions, Transitions, Sound, Music, Color, Avoid. Instructions with numbers ("Punch in to 1.2× every two or three sentences"), not adjectives. A new style starts from this template.

## In a film

- **The brief** has a Style question after Length (frame 03): None, or one card per style (name, sentence, what it holds). The chosen card is the director's amber. "Make one with the editor…" and "Your styles…" sit under the cards.
- **The film keeps its own copy.** Saving a brief that names a style copies its folder to `<film>.direction/Style/`, so the film doesn't change when the style does and travels with its style. Saving it with another style, or None, replaces or removes the copy. A style the editor changes for this film (`direction_save_style`) is copied again.
- **The editor** sees it in `direction_brief` (`style`), in its job text (“Style: Desk Talk…”), and reads it with `direction_style`: values, guide, and each part with its path. It copies graphics to `Editor/Graphics/<name>/`, transitions to `Editor/Transitions/`, effects to `Editor/Effects/`, brings sounds and music in with `direction_import`, and proposes the look with `direction_make_look fromLUT` (the look stays the director's). `direction_graphic_examples` lists the style's graphics first (`fromStyle`).

## Making a style

- **With the editor, in the app.** "Make one with the editor…" in the brief: the director says what it should be like (channels, videos, what they like about them) and, when the film has a cut, whether to learn from how it's cut. Direction starts a run with job `style` (skill `make-style`, template `jobs/style.md`). It's done when a style is saved after the run began. Under Your own session, the popover says to ask that session instead.
- **With the editor, in a session of your own.** "Make me a style" with the Direction plugin: the `make-style` skill and `direction_styles`, `direction_style`, `direction_save_style`.
- **By hand.** Settings › Styles › New Style…: name, sentence and guide. Edit… changes them; the parts are files, so Show in Finder opens the folder. Move to Trash… asks first; films that use it keep their copy.
- `direction_save_style` writes only into the Styles folder: a new style with `name`, or changes to one with `id`. `tokens` merge key by key into style.json (null removes one), `guide` replaces guide.md, `files` copies parts from the editor's working folder to paths inside the style. Nothing else in the folder changes.

## Settings › Styles (frame 65)

"Your styles": one row per style (name; sentence and what it holds under it; Edit… and a folder button), New Style… under the list, and a note on what a style is. "Where they live": the Styles folder with Change… and Show in Finder.

**Acceptance:**
- [ ] A style is a folder with style.json and guide.md; one without a readable name isn't listed.
- [ ] Picking a style in the brief copies it into the film; picking None removes the copy; the film keeps working when the style is moved to the Trash.
- [ ] `direction_brief` names the film's style; `direction_style` returns its values, guide and parts with paths.
- [ ] `direction_save_style` refuses paths outside the style and files outside the film.
- [ ] A `style` run is done once a style is saved after it began.
- [ ] Snapshots and tests never read or write the director's own Styles folder.

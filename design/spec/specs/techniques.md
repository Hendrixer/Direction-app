# Techniques (plan)

Not built. Planned 31 Oct 2026, from the director's ask: show Direction a video of an editor teaching a transition or an effect in Final Cut, Premiere or Resolve, and end up with something the editor can use on any film, in a library it reaches for when a style, the brief or a note calls for it.

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
- **Where it's used**: a style names techniques for its moments (Chapter → Light leak) the way it names transitions now; the brief can list techniques for this film; a note can name one ("light leak here"). `direction_techniques` lists them with when to use each, and an operation `technique` runs one by name.

## Learning one from a video

**Learn a Technique…** (Settings › Styles, and in Notes): paste a link or drop a file, and say which part ("the light leak at 3:20").

1. **The video.** A file is read where it is. A link is downloaded only after the director agrees, with its name, source and size shown; the tutorial stays in the technique's folder for reference and never goes into a film.
2. **Direction reads it like footage**: words (Whisper on this Mac), shots, frames around the moment, and the editing app's panels read with Vision (effect names, keyframe values, blend modes, durations).
3. **The editor builds it** (a `technique` job, skill `learn-technique`): the steps in the tutorial's words, then the same result in Direction's: which piece makes it, its settings, the Metal or graphic when it needs one, and the recipe. Assets are made (OpenRouter's sound and image versions, inside the spend limit) or found under a license that allows it, asking before any download. It never copies the tutorial's own footage or paid packs.
4. **Checked against the tutorial**: rendered on a scratch copy of one of the director's films, and the result frames put beside the tutorial's with a decision version (as made shots are checked): "does B do what A does?"
5. **The director sees both side by side** and keeps it, or says what's off and the editor tries again.

## What translates

Most transitions (light leaks, film burns, whips, glitches, zoom and spin transitions), looks and treatments (grain, VHS, halation, glow, chromatic aberration), text animation (as graphics), speed ramps, masks and reveals (with person cut-outs on this Mac), split screens, sound design. Not yet: anything needing 3D camera tracking or particle systems beyond Metal; a third-party plugin's own internals. The editor says so instead of faking it.

## Order

1. The technique format and library, `direction_techniques`, the `technique` operation, and styles naming techniques; today's named transitions become the first techniques.
2. Learning from a file.
3. Learning from a link (download with the director's yes).
4. The side-by-side preview and the decision-version check.

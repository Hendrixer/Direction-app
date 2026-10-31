---
name: make-style
description: Make or change a style in Direction, the way a design system is made for an app: how the director's videos look, sound and move, as exact values, a guide in words and the parts (graphics, transitions, sounds, fonts, a look) the editor reuses on every film. From the director's words, their references, or a film they've made.
---

You are the editor. A style is a folder in the director's Styles folder, and the editor follows it on every film whose brief names it, wherever the brief and the notes leave a choice open. You write it only through `direction_save_style`, and only when the director asks: a style job, or a note like "Save this as my style".

A style has three layers, like a design system:
- **Values** (`tokens`, style.json): the numbers the editor holds to. Colors as hex, fonts by family, weight and width, times in seconds, levels in dB.
- **The guide** (`guide`, guide.md): the rest in words, one section each for Pace, Picture, Graphics, Captions, Transitions, Sound, Music, Color and Avoid. Write instructions an editor can follow without asking: "Punch in to 1.2× every two or three sentences on the talking head; back out on a new point." Not "dynamic, engaging".
- **Parts** (`files`): what the editor reuses as is. Graphics (Direction graphics whose colors and fonts come from the values), transitions and effects (Metal, as in the `transitions` skill and custom effects), sounds and music the director gave you, fonts they own, a look (`look.cube`), and stills that show what it looks like.

1. **Find out what they want.** Read the request, the brief and its references (`direction_brief`; Read reference stills). `direction_styles` lists the styles they have: change one only when they name it (pass its `id`), otherwise make a new one. When two directions are both plausible, ask once with `direction_ask` and show the choice in a sentence each.
2. **From a film, measure it.** `direction_timeline` gives every clip: average and longest shot on V1, how often a cutaway or graphic comes in, the punch-in scales in transform effects, transitions and their frames, music and effect levels in gain keys. `direction_transcript` gives the pauses left between words. `direction_looks` names the film's look. Put the numbers in the values and the habits in the guide. Copy the film's graphics (`Graphics/<name>`) as parts.
3. **Write the values.** Use these keys where they apply, and add others the editor should hold to:
   ```json
   {
     "pace": {"averageShotSeconds": 3.5, "longestShotSeconds": 8, "pausesUpTo": 0.25, "hookBySeconds": 8},
     "picture": {"punchIn": 1.2, "brollEverySeconds": 15},
     "colors": {"text": "#FFFFFF", "accent": "#FFC800", "backing": "#000000B3"},
     "fonts": {"title": {"family": "Archivo", "weight": 800, "width": 112}, "captions": {"family": "Archivo", "weight": 700}},
     "motion": {"in": 0.3, "out": 0.2, "ease": "out", "hold": 2.5},
     "captions": {"on": true, "wordsAtATime": 3, "case": "upper", "position": "lower third"},
     "transitions": {"default": "cut", "use": ["push", "whip"], "frames": 8},
     "sound": {"musicUnderSpeechDB": -24, "effectsDB": -14, "whooshOnTransitions": true, "popOnGraphics": true},
     "graphics": {"title": "title", "lowerThird": "lower-third", "captions": "captions"},
     "look": {"strength": 0.6}
   }
   ```
4. **Make the parts in your working folder.** Graphics in `Graphics/<name>/` from the closest example (`make-graphic` skill), with every visible word in `words`, then `direction_graphic` with note `"unasked"` until it has no problems. Transitions in `Transitions/<name>.metal` and effects in `Effects/<name>.metal`, checked by using them once on a cut you then undo with `direction_restore` if it's a real film. Sounds, music and fonts only from files the director gave you or their footage; never make them with a service in a style job, and never bundle a font they don't own.
5. **Save it once.** `direction_save_style` with `name`, a one-sentence `summary`, `tokens`, `guide` and `files` (`from` in your working folder, `to` in the style: `graphics/<name>`, `transitions/<name>.metal`, `effects/<name>.metal`, `sounds/<name>.wav`, `music/<name>.m4a`, `fonts/<name>.otf`, `look.cube`, `stills/<name>.jpg`). Read the result back and fix anything missing with one more call using its `id`.
6. **Say what it is.** Finish with the style's name and what it holds, in a sentence: "Desk Talk: 3-second shots, punch-ins every few sentences, yellow captions three words at a time, whooshes on pushes; a lower third, a title and captions."

When a film's brief names a style, every other skill reads it with `direction_style` and follows it; the notes always win over it.

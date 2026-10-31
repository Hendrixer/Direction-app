---
name: make-style
description: Make or change a style in Direction, the way a design system is made for an app: how a kind of the director's videos looks, sounds and moves, as rules in words, named layouts and moves Direction carries out, exact values, and the parts (graphics, transitions, sounds, fonts, a look) the editor reuses on every film. From the director's words, their references, or a film they've made.
---

You are the editor. A style is a folder in the director's Styles folder, and the editor follows it on every film whose brief names it, wherever the brief and the notes leave a choice open. Under every film sits the house style (id `house`): the director's rules for every film. You write a style only through `direction_save_style`, and only when the director asks: a style job, or a note like "Save this as my style".

A style is four things, like a design system:
- **Rules** (`rules`): one sentence each, in the director's words, with an area: pace, picture, layouts, graphics, captions, transitions, sound, music, color or avoid. Instructions an editor can follow without asking, with numbers: "Tighten every pause longer than 0.35 s to about 0.15 s." "Talking for the talk, Showing when the screen comes in, Detail for code and forms." Not "dynamic, engaging". Rules say what and when; they never describe by hand what Direction already does (a corner camera, a punch-in's transform).
- **What Direction carries out** (`tokens`): named `layouts` for a camera and a screen recording in sync, the `moves` (punch-ins on jump cuts, the emphasis punch, the slow push) and `pace.tightenPauses`. The editor asks for them by name and Direction does the tracking and the keyframes.
- **Values** (`tokens`): the numbers the editor holds to everywhere else. Colors as hex, fonts by family, weight and width, times in seconds, levels in dB.
- **Parts** (`files`): what the editor reuses as is. Graphics (Direction graphics whose colors and fonts come from the values), transitions and effects (Metal, as in the `transitions` skill and custom effects), sounds and music the director gave you, fonts they own, a look (`look.cube`), and stills that show what it looks like.

1. **Find out what they want.** Read the request, the brief and its references (`direction_brief`; Read reference stills). `direction_styles` lists the styles they have and how many house rules there are: change one only when they name it (pass its `id`), otherwise make a new one. Don't repeat a house rule in a style; a style rule only where this kind of video differs. When two directions are both plausible, ask once with `direction_ask` and show the choice in a sentence each.
2. **From a film, measure it.** `direction_timeline` gives every clip: average and longest shot on V1, how often a cutaway or graphic comes in, the punch-in scales in transform effects, layouts in use, transitions and their frames, music and effect levels in gain keys. `direction_transcript` gives the pauses left between words. `direction_looks` names the film's look. Put the numbers in the values and moves, the habits in rules. Copy the film's graphics (`Graphics/<name>`) as parts.
3. **Write what Direction carries out and the values.** Use these keys where they apply, and add others the editor should hold to:
   ```json
   {
     "layouts": [
       {"name": "Talking", "kind": "you"},
       {"name": "Showing", "kind": "screenAndYou", "corner": "bottomRight", "size": "medium", "shape": "rounded"},
       {"name": "Detail", "kind": "screen"}
     ],
     "moves": {"punchIn": {"scales": [1, 1.15], "keepIn": "thirds"}, "emphasisPunch": {"scale": 1.32, "everySeconds": 45}, "slowPush": {"from": 1, "to": 1.05, "longerThan": 8}},
     "pace": {"tightenPauses": {"longerThan": 0.35, "to": 0.15}, "averageShotSeconds": 3.5, "longestShotSeconds": 8, "hookBySeconds": 8},
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
   Layouts are only for films with a camera and a screen recording in sync: name each for what it's for, and give the bubble an `edge` color (#RRGGBB) when it should stand apart from what's on screen. Leave out a move the style never makes.
4. **Write the rules.** One sentence each, grouped by area, from what they asked for and what you measured. Ten to forty is usual.
5. **Make the parts in your working folder.** Graphics in `Graphics/<name>/` from the closest example (`make-graphic` skill), with every visible word in `words`, then `direction_graphic` with note `"unasked"` until it has no problems. Transitions in `Transitions/<name>.metal` and effects in `Effects/<name>.metal`, checked by using them once on a cut you then undo with `direction_restore` if it's a real film. Sounds, music and fonts only from files the director gave you or their footage; never make them with a service in a style job, and never bundle a font they don't own.
6. **Save it once.** `direction_save_style` with `name`, a one-sentence `summary`, `rules`, `tokens` and `files` (`from` in your working folder, `to` in the style: `graphics/<name>`, `transitions/<name>.metal`, `effects/<name>.metal`, `sounds/<name>.wav`, `music/<name>.m4a`, `fonts/<name>.otf`, `look.cube`, `stills/<name>.jpg`). Read the result back and fix anything missing with one more call using its `id` (`removeRules` takes rules out by id).
7. **Say what it is.** Finish with the style's name and what it holds, in a sentence: "Desk Talk: 3-second shots, punch-ins on every jump cut, yellow captions three words at a time, whooshes on pushes; a lower third, a title and captions."

When a film's brief names a style, every other skill reads it with `direction_style` (the house rules first, then the style's) and follows it; the notes always win over it, and the style wins over the house style.

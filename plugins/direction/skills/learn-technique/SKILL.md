---
name: learn-technique
description: Learn a transition, effect or editing move from a tutorial video (Final Cut Pro, Premiere, Resolve, After Effects, CapCut) and make it a technique in Direction's library, rebuilt from Direction's own pieces, so every film can use it by name.
---

You are the editor, learning something the director liked so you can do it on any film. A technique is a folder in the director's Techniques folder; you write it only through `direction_save_technique`, and only in a technique job or when the director asks. You learn the method, never copy the tutorial: no footage, stills, sounds or paid packs from it go into the technique.

1. **Find the result.** Most tutorials show it in the first 10 seconds, then build it. Look at the contact sheets (`sheet-1.jpg`…) and `direction_study_frames` around those moments until you can say exactly what happens on screen, frame by frame: what moves, what appears where, how long, what's on top of what. Write that down in two or three sentences before anything else.
2. **Find how it's built.** Read `transcript.txt` and look at the settings panels (`direction_study_frames` at the moments the transcript names a setting): the effects used, their order, masks, blend modes, keyframes, durations, the plugin's options and their defaults. A paid plugin's options are a list of what the effect can vary; you rebuild the look, not the plugin.
3. **Choose Direction's piece:**
   - **A transition** (two shots, a cut between them): a Metal transition (`transitions` skill: `[[ stitchable ]] float4 name(coreimage::sampler from, coreimage::sampler to, float progress, …, coreimage::destination dest)`, `direction::uv`, `direction::at`, `direction::ratio`, settings declared as `// direction: param name min max default` or `// direction: param name color #RRGGBB`). Turn the plugin's options into settings with the same meaning and sensible ranges.
   - **An effect** (one clip): a built-in effect when one does it (`direction_edit_catalog`: transform keys, mask, blur, blend, filters, `pixelGrid` for a subject shown square by square, `place`, `card`), else a Metal effect.
   - **A recipe** (several edit operations): `steps`, each an edit operation in words with its arguments: speed ramps, freezes, `zoomThrough`, cutaways, layers.
   Masks a tutorial draws by hand (magnetic masks, rotoscoping) are found by Direction: people and objects with `pixelGrid`, faces with `reframe`/`punchIn`, screens with `pin`. Say what Direction can't do yet (3D tracking, particles) instead of faking it.
4. **Make it in your working folder** (`Techniques/<name>/`): the Metal, and any sounds it needs, made on this Mac (short clicks, whooshes) or from files the director gave you. Ask (`direction_ask`) before downloading anything, and record where each asset came from.
5. **Try it on this film.** Use it once with `direction_edit` (`validateOnly` first; for a transition that isn't saved yet, a `transition` with type `shader` and `params.file` in your working folder's Transitions), look at `direction_frame` at three points through it beside the tutorial's frames at the same points, adjust, and put the cut back with `direction_restore`.
6. **Save it** with `direction_save_technique`: a short `name` the director would say ("Grid flash"), a one-sentence `summary`, `when` it belongs, what it `needs` from the footage, `kind` and its `transition`/`effect`/`steps`, `variants` named after the tutorial's presets or the looks it showed ("Big", "From the middle", "Negative"), `source` ({title, url, author, at: where the result and the steps are}), and `files` from your working folder.
7. **Say what it is**, in a sentence, and which variants it has.

When a style, the brief or a note names a technique, every other skill uses it with `direction_edit` `{op: "technique", name, editPoint | clipID, variant?}`; `direction_techniques` lists them with when to use each.

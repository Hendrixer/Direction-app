---
name: make-style
description: Make or change a style in Direction, the way a design system is made for an app: how a kind of the director's videos looks, sounds and moves, as rules in words, named layouts and moves Direction carries out, exact values, and the parts (graphics, transitions, sounds, fonts, a look) the editor reuses on every film. From the director's words, their references, a film they've made, or videos they like that Direction has studied.
---

You are the editor. A style is a folder in the director's Styles folder, and the editor follows it on every film whose brief names it, wherever the brief and the notes leave a choice open. Under every film sits the house style (id `house`): the director's rules for every film. You write a style only through `direction_save_style`, and only when the director asks: a style job, or a note like "Save this as my style".

A style is four things, like a design system:
- **Rules** (`rules`): one sentence each, in the director's words, with an area: pace, picture, layouts, graphics, captions, transitions, sound, music, color or avoid. Instructions an editor can follow without asking, with numbers: "Tighten every pause longer than 0.35 s to about 0.15 s." "Talking for the talk, Showing when the screen comes in, Detail for code and forms." Not "dynamic, engaging". Rules say what and when; they never describe by hand what Direction already does (a corner camera, a punch-in's transform).
- **What Direction carries out** (`tokens`): named `layouts` for a camera and a screen recording in sync, named `transitions` for kinds of moments (each with its sound), the `moves` (punch-ins on jump cuts, the emphasis punch, the slow push, zooms on screen recordings) and `pace.tightenPauses`. The editor asks for them by name and Direction does the tracking and the keyframes.
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
     "transitions": [
       {"name": "New section", "type": "slide", "frames": 8, "params": {"x": -1}, "sound": "sounds/whoosh.wav", "soundDB": -20},
       {"name": "Chapter", "type": "shader", "file": "transitions/glint.metal", "frames": 10, "sound": "sounds/whoosh.wav", "soundDB": -20}
     ],
     "moves": {"punchIn": {"scales": [1, 1.15], "keepIn": "thirds"}, "emphasisPunch": {"scale": 1.32, "everySeconds": 45}, "slowPush": {"from": 1, "to": 1.05, "longerThan": 8}, "screenZoom": {"min": 1.4, "max": 2, "in": 0.6, "out": 0.5, "hold": 1.5}},
     "pace": {"tightenPauses": {"longerThan": 0.35, "to": 0.15}, "averageShotSeconds": 3.5, "longestShotSeconds": 8, "hookBySeconds": 8},
     "colors": {"text": "#FFFFFF", "accent": "#FFC800", "backing": "#000000B3"},
     "fonts": {"title": {"family": "Archivo", "weight": 800, "width": 112}, "captions": {"family": "Archivo", "weight": 700}},
     "motion": {"in": 0.3, "out": 0.2, "ease": "out", "hold": 2.5},
     "captions": {"on": true, "wordsAtATime": 3, "case": "upper", "position": "lower third"},
     "sound": {"musicUnderSpeechDB": -24, "musicAloneDB": -8, "effectsDB": -14, "whooshOnTransitions": true, "popOnGraphics": true},
     "music": {"cueSeconds": [60, 120], "changesOn": "a new beat of the story", "breaks": "before a line that has to land", "instruments": ["piano", "bowed strings"], "beatsPerMinute": [80, 100], "key": "minor, one key across the film", "stings": "a riser into each new section"},
     "graphics": {"title": "title", "lowerThird": "lower-third", "captions": "captions"},
     "look": {"strength": 0.6}
   }
   ```
   Layouts are only for films with a camera and a screen recording in sync: name each for what it's for, and give the bubble an `edge` color (#RRGGBB) when it should stand apart from what's on screen. Name each transition for the moment it marks ("Chapter", "Skip ahead"); its `file` and `sound` are paths in the style. Leave out a move the style never makes.
4. **Write the rules.** One sentence each, grouped by area, from what they asked for and what you measured. Ten to forty is usual.
5. **Make the parts in your working folder.** Graphics in `Graphics/<name>/` from the closest example (`make-graphic` skill), with every visible word in `words`, then `direction_graphic` with note `"unasked"` until it has no problems. Transitions in `Transitions/<name>.metal` and effects in `Effects/<name>.metal`, checked by using them once on a cut you then undo with `direction_restore` if it's a real film. Sounds, music and fonts only from files the director gave you or their footage; never make them with a service in a style job, and never bundle a font they don't own.
6. **Save it once.** `direction_save_style` with `name`, a one-sentence `summary`, `rules`, `tokens` and `files` (`from` in your working folder, `to` in the style: `graphics/<name>`, `transitions/<name>.metal`, `effects/<name>.metal`, `sounds/<name>.wav`, `music/<name>.m4a`, `fonts/<name>.otf`, `look.cube`, `stills/<name>.jpg`). Read the result back and fix anything missing with one more call using its `id` (`removeRules` takes rules out by id).
7. **Say what it is.** Finish with the style's name and what it holds, in a sentence: "Desk Talk: 3-second shots, punch-ins on every jump cut, yellow captions three words at a time, whooshes on pushes; a lower third, a title and captions."

## From a video

When the job gives you videos the director likes, each one is studied in its own folder: `study.md` (what Direction measured: shots and their lengths, cuts in each minute, words a minute and the pauses left, loudness, the music (each cue with what plays in it, its beat and key, how much of it is under the voice and whether it starts and ends on a cut; the stretches of talk with no music; how far under the voice it sits; short bursts like risers and hits; the other sounds heard and the hits and risers on cuts; what the page credits), how close the framing is and how often a cut changes the face's size, how much of the time captions are on screen and where, and every shot with any words on it), `transcript.txt` (the words with their times) and `sheet-N.jpg` (a frame every two seconds, each with its time). The video is beside them; `direction_study_frames` gives you full frames at any seconds you name.

1. **Read the numbers, then look.** Take pace, pauses, loudness and the captions' rhythm from `study.md` as they are; they're counted, not guessed. Turn them into the style's numbers: `pace` (averageShotSeconds, longestShotSeconds, hookBySeconds, tightenPauses from the pauses), `moves` (punch-ins when cuts often change the face's size; their scale from two frames either side of such a cut), `sound` (dialogue level from the loudness; `musicUnderSpeechDB` and `musicAloneDB` from how far under the voice the music sits, in the pauses and with nobody talking) and `music` (how long cues run and what they change on, where the music stops, the instruments, the beat, the film's key and the cues that leave it, the stings). Read the cues against the transcript: where each starts and stops in what's being said tells you why it changes, and that's the rule ("A new cue for each new question; none under the sponsor read"). Then go through the contact sheets for what only you can judge: the caption look (font family and weight, color, outline or box, how many words, where), lower thirds and titles, how the screen and the camera share the frame, b-roll, transitions and what you hear under them, color and contrast, and the feeling. Look at a moment up close with `direction_study_frames` before you write a rule from it.
2. **Keep what the director said they like first.** The request says what to take; the rest of the video only fills in. Where two videos disagree, say which one each rule follows, or ask with `direction_ask` if it matters.
3. **Examples.** For the rules that are easiest to get wrong (the caption look, a punch-in, a layout, a transition), take one frame each with `direction_study_frames`, copy it in with `files` (`to: stills/<name>.jpg`), and list it in `tokens.examples` as `{still, area, text, source, at}`: what it shows in a sentence, which video (its index in the job's list, from 0) and the second. Five to ten is plenty.
4. **Structure.** From the transcript and the cuts in each minute, write `tokens.structure`: the parts a video like this has, in order, each `{name, at?, length?, what}` ("Hook", 0, 8, "The result first, then the question it answers"). Only what holds across the video, not this video's topic.
5. **What can't be copied, describe.** Their footage, voice, music and fonts aren't the director's. Name a font close to theirs that the director has (or say which to get), describe the music as rules from the cues (instruments, beat, key, how long a cue holds, where it drops out, what's credited on the page; name a genre from those, as a guess), never as a claim that you heard it, and build graphics from the closest example with your own colors and that font.
6. **A move or transition Direction doesn't have** (a signature wipe, a glitch on every cut): if the library (`direction_techniques`) has one close, name it in `transitions` with `technique`; otherwise describe it as a rule and say in your summary that it could be learned as a technique.
7. **Save once**, with `studies` naming the study folders from your job, so the style keeps each video's title, maker, link and Direction's numbers as its sources. Don't copy the numbers into `sources` yourself. The folders, videos and all, are removed once the style is saved, so take every frame you want first.

A video in the brief's references is studied the same way (its folder is in `direction_brief` › `studiedReferences`). In a film job it's inspiration for that film, read as you would read the brief; make a style from it only when the director asks.

When a film's brief names a style, every other skill reads it with `direction_style` (the house rules first, then the style's) and follows it; the notes always win over it, and the style wins over the house style.

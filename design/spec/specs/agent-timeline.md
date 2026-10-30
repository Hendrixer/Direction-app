# The editor's timeline

No frames. This is the contract between the editor and Direction's renderer. Read `product-model.md` first.

The director never sees a timeline: they see scenes on a strip, answers and choices. The editor sees everything: every layer, effect, keyframe, graphic and made clip. Direction doesn't hand off to another editing app; it renders everything itself.

**The editor reads the timeline as data and changes it only through Direction's edit functions.** It never writes the timeline itself. Each function is one editorial act ("trim", "swap the take", "duck the music"), carried out by Direction's own code: the frame math, keeping picture and sound in sync, locks, and which note the change answers. The editor decides what to do; Direction does it exactly.

Why functions and not a writable document:
- **Intent survives.** Changes can say "Trimmed scene 1, −4.2 s, for note 1" because the call said so, rather than guessing from a diff.
- **Nothing gets lost by accident.** Rewriting a whole document can drop or shift things the editor never meant to touch. A function touches only what it names.
- **Direction does the exact work.** Agents are poor at frame-accurate time arithmetic and sync. Functions take plain inputs ("this edit point, 12 frames later") and Direction computes the rest.
- **Checked one act at a time.** Each operation is checked against locks, media and the catalog, and errors point at the operation that failed.
- **Readable activity.** The pill and History show verbs, because every change is a verb.

Where data isn't enough, the editor still writes code, but code that **makes things**, not code that edits the timeline: graphics in JavaScript (`graphics.md`) and effects as Metal shaders (below). Placing them is an edit function like any other.

---

## Reading: OpenTimelineIO, read-only

`direction_timeline` returns the cut as **OpenTimelineIO** JSON (OTIO, the Academy Software Foundation's open timeline format), which agents and their tools already understand, plus a compact outline. Every item carries its id in `metadata.direction.id`; operations refer to those ids.

| Tool | Arguments | Returns |
|---|---|---|
| `direction_timeline` | `cut?`, `revision?`, `range?` | The OTIO document (only items overlapping `range`, if given) and `outline` |
| `direction_edit_catalog` | — | Every operation below with its arguments, and every effect and transition with its parameters' ranges and defaults |

| OTIO | Direction meaning |
|---|---|
| `Timeline` | One cut. `metadata.direction`: `cut`, `editRevision`, `width`, `height`, `rate`, `look` (the director's) |
| `Stack` → `Track` (kind `Video`) | Video layers, bottom first: V1 is the story track (footage), V2+ are overlays (graphics, cutaways, made shots). |
| `Track` (kind `Audio`) | A1 dialogue, A2 music, A3 sound effects, A4+ more. |
| `Clip` + `ExternalReference` | A take or a made clip. `metadata.direction.assetID` names the footage; `source_range` is the trim. |
| `Clip` + `GeneratorReference` | Something Direction draws: `direction.graphic` (`parameters.graphicID`) or `direction.solid` (`parameters.color`) |
| `Gap`, `Transition`, `Effect`, `LinearTimeWarp`, `FreezeFrame` | As OTIO defines them; effect parameters in `metadata.direction.params`, keyframes in `metadata.direction.keys` |
| `Marker` | Scenes (`metadata.direction.scene: {number, title, locked}`) and notes (`metadata.direction.note: {number, kind}`) |

The **outline** reads like this:

```
Cut 3 · 3:40:00 · 1920×1080 · 23.976 · look "Window light" (film)
V2  00:02:00–00:06:00  clip-91  graphic "Title · Two years."  above look
V1  00:00:00–00:09:12  clip-12  1A T2  src 00:04:10–00:13:22  reframe(1.1)
V1  00:09:12–00:25:00  clip-13  1B T4  src 00:00:20–00:16:08  ‹scene 1›
A2  00:00:00–00:25:00  clip-40  music "Felt piano" (made)  ducked −6 dB under A1
```

The editor may export the document to its working folder and analyze it in a script (Python with `opentimelineio`, or JavaScript). The analysis can decide which operations to send; it can't send a document back.

## Writing: edit functions

`direction_edit` takes a batch of operations and applies all of them as one new revision, or none.

```json
{ "baseEditRevision": 41, "idempotencyKey": "t3-note1", "summary": "Get to her face sooner",
  "notes": [1], "validateOnly": false,
  "operations": [
    { "op": "removeRange", "range": { "start": 4.2, "end": 8.4 }, "ripple": true },
    { "op": "roll", "editPoint": "clip-12|clip-13", "frames": -6 } ] }
```

- `notes` says which notes the batch answers; any operation may override it with its own `note`. A batch with no note is allowed only with latitude "free" and is labeled Unasked.
- Times are cut seconds unless an argument says source; `frames` arguments count frames at the cut's rate. Direction snaps every result to whole frames.
- Clips are named by id from `direction_timeline`. An edit point is `"<left clip>|<right clip>"`.
- `validateOnly` checks everything and returns the predicted result (changed ranges, new length, warnings) without committing.
- The result lists, per operation, what changed: the ranges in the new cut and the old cut, the scenes, and the delta. Changes and Play changes are built from this list.
- Errors are `{index, code, message}`, pointing at the operation that failed.

### Operations

**Story** (V1, keeping every layer in sync unless the operation says otherwise)

| Op | Arguments | What Direction does |
|---|---|---|
| `insert` | `assetID`, `sourceRange`, `at`, `track?` | Inserts and ripples everything after it |
| `overwrite` | `assetID`, `sourceRange`, `at`, `track?` | Places over what's there, without moving anything |
| `removeRange` | `range`, `ripple` | Removes the range on every track; ripple closes the gap |
| `remove` | `clipID`, `ripple` | |
| `move` | `clipID`, `to` (`at`, or `before`/`after` a clip) | Moves a clip and its linked sound |
| `split` | `clipID`, `at` | |
| `trim` | `clipID`, `edge` (`head`/`tail`), `frames`, `ripple` | Extends or shortens one end |
| `roll` | `editPoint`, `frames` | Moves a cut point; the total length doesn't change |
| `slip` | `clipID`, `frames` | Changes which part of the take plays, without moving the clip |
| `slide` | `clipID`, `frames` | Moves a clip between its neighbors, trimming them to fit |
| `splitEdit` | `editPoint`, `lead` (`sound`/`picture`), `frames` | J- and L-cuts: sound starts before the picture changes, or carries after |
| `replaceTake` | `clipID`, `withAssetID`, `alignOn` (`words`/`head`/`tail`) | Swaps in another take. With `words`, Direction finds the same line in the new take's transcript and lines it up word for word: "use T5's reading". |
| `removeWords` | `wordIDs` | Cuts the words and their picture on every layer (today's transcript edit) |
| `tightenPauses` | `range`, `longerThan` (s), `to` (s) | Finds pauses in that range from the words and sounds, and shortens each one |
| `speed` | `clipID`, `rate`, `ripple` | |
| `freeze` | `clipID`, `at`, `seconds` | Holds a frame |

**Picture**

| Op | Arguments | What Direction does |
|---|---|---|
| `reframe` | `clipID`, `scale`, `x?`, `y?`, `follow?` (`face`/`subject`), `keepIn?` (thirds/center) | With `follow`, Direction tracks the face or subject with Vision and writes the keyframes that keep it placed |
| `balance` | `clipID`, `exposure?`, `contrast?`, `saturation?`, `temperature?`, `tint?` | Shot matching (today's `color`) |
| `matchBalance` | `clipID`, `toClipID` | Direction measures both shots and sets the balance that matches the reference |
| `cameraLUT` | `assetID`, `lut` (`auto`, a file, or `none`) | Per take, not per clip |
| `addEffect` | `target` (clip id or track), `effect`, `params`, `keys?` | Returns the effect's id |
| `setEffect` | `effectID`, `params?`, `keys?` | |
| `removeEffect` | `effectID` | |
| `transition` | `editPoint`, `type`, `frames` | |
| `removeTransition` | `editPoint` | |

**Layers**

| Op | Arguments | What Direction does |
|---|---|---|
| `cutaway` | `assetID`, `sourceRange?`, `seconds?`, `at`, `cover?` (a clip id or edit point) | Puts picture on V2 over the story; the sound underneath keeps playing. With `cover`, Direction centers it over a jump cut. Without `sourceRange`, `seconds` long: a take in sync with V1 there plays the same moment, lined up to the frame (switching angles, a screen recording under the words about it, picture-in-picture with `reframe`). It stays lined up as the cut changes (footage-index.md › Sync). |
| `placeGraphic` | `graphic`, `at`, `seconds?`, `aboveLook` (default true) | Places a checked graphic (`graphics.md`) on the first free layer at V2 or above |
| `placeMade` | `madeID`, `at`, `track`, `sourceRange?` | Places a made clip like footage |

**Sound**

| Op | Arguments | What Direction does |
|---|---|---|
| `gain` | `target` (clip id or track), `dB`, `keys?` | |
| `fade` | `clipID`, `in?`, `out?` (frames) | |
| `duck` | `track` (usually A2), `under` (usually A1), `dB`, `attack?`, `release?` | Direction finds every line of dialogue from the words and writes the gain keys |
| `syncSound` | `clipID`, `assetID?` | A take in sync with a V1 clip plays its sound under it, in place of the clip's own: the group's sound take by default. Naming the clip's own take puts its sound back. Stays lined up like a synced cutaway. |
| `placeMusic` | `madeID` or `assetID`, `at`, `endOn` (`cut`, `word`, or a time) | Lines the music's end up with a cut or a word, trimming from the head |
| `audio` | as today | EQ, compression and per-track settings |

**Film**: `format` and `duplicateSequence` as today.

Every operation is checked before anything commits:

| Code | When |
|---|---|
| `scene_locked` | It would change anything overlapping a locked scene, on any track |
| `picture_locked` | Any picture change after picture lock |
| `stale_revision` | `baseEditRevision` isn't current |
| `overlap` | It would make two clips overlap on one track |
| `unknown_op`, `bad_argument` | Not in the catalog, or a value out of range |
| `missing_media` | An asset, graphic or made clip that doesn't exist |
| `no_words` | `replaceTake` with `words`, or `tightenPauses`, on a take with no transcript |
| `not_in_sync` | A `cutaway` without `sourceRange` from a take that isn't in sync with the story clip under it |
| `look_is_yours` | Anything that would change the director's look |
| `words_are_yours` | Changing a graphic's words the director set, without a note that names it |

### Effects catalog

Used by `addEffect` and `setEffect`.

| Effect | Parameters (range, default) | Keys | Notes |
|---|---|---|---|
| `transform` | `scale` (0.1–8, 1), `x`, `y` (−1–1, 0; fraction of frame), `rotation` (−180–180, 0), `opacity` (0–1, 1), `crop` (`l r t b`, 0–0.5, 0) | yes | `reframe` writes this |
| `blend` | `mode`: normal, screen, multiply, overlay, add | no | On V2+ clips |
| `mask` | `shape`: rect, ellipse; `x y w h` (0–1); `feather` (0–0.5, 0.05); `invert` (false) | yes | Limits the clip's other effects to the shape: "brighten her face" |
| `blur` | `radius` (0–100 px, 0) | yes | |
| `sharpen` | `amount` (0–1, 0) | no | |
| `stabilize` | `amount` (0–1, 0.5) | no | Vision homographic registration, cached per clip |
| `filter.<kind>` | Every filter in `looks.md` | yes | Per-clip texture, apart from the director's look |
| `shader` | `file` (`Effects/<name>.metal`) and the parameters it declares | yes | Custom; see below |

Balance and camera LUTs have their own operations. Transitions: `dissolve`, `dipToBlack`, `dipToWhite` (shown in OTIO as `SMPTE_Dissolve` and Direction-named types). Settings › Cutting › Transitions still decides whether the editor may add them without a note.

### Custom effects (shaders)

When no catalog effect does what a note needs, the editor may write a Metal fragment function in `Effects/<name>.metal`, then use it with `addEffect` (`effect: "shader"`):

```metal
// direction: param amount 0 1 0.5
// direction: param tint color #F2A33A
[[ stitchable ]] half4 effect(coreimage::sample_h s, float amount, float3 tint, coreimage::destination dest) { … }
```

- The header comments declare parameters; `direction_edit_catalog` lists custom effects once they compile.
- Direction compiles it with `MTLDevice.makeLibrary(source:)` and wraps it as a Core Image kernel. Compile errors come back with line numbers.
- Before use, Direction renders 3 frames with it; a kernel slower than 40 ms a frame at 1080p, or one that produces NaN, is refused (`shader_too_slow`, `shader_invalid`).
- Shaders can't read files or the network; they only see pixels and their parameters.

## What Direction renders

Order, per frame: each clip's effects in order → its track's effects → layers composited bottom to top with their blend modes → **the director's look** (`looks.md`) → tracks marked above the look (graphics by default) → output. Audio: clip gain and keys → track effects → ducking → the mix to the loudness target.

## What we took from open source

We looked at how other editors expose their work to code, without handing anything off to them:
- **EffectCraft** (Rust, MIT/Apache): every action goes through one command registry behind its CLI and MCP server, and every effect has fixed parameter names and defaults. Direction takes the same stance: one catalog of operations and effects, fixed arguments.
- **MLT** (the engine under Kdenlive and Shotcut): filters and transitions attached to clips and tracks. It's the model for per-clip and per-track effects here.
- **OpenTimelineIO**: the shared vocabulary the editor reads.
- **Premation** (AGPL; study only, don't copy code): a deterministic WebGL/WebGPU renderer for motion graphics. It's why graphics render in a browser engine on a clock Direction controls.

**Acceptance:**
- [ ] There's no tool that accepts a timeline document. The only way to change a cut is `direction_edit`.
- [ ] `replaceTake` with `words` keeps the line's first word within one frame of where the old take's first word was.
- [ ] `tightenPauses` never cuts inside a word.
- [ ] Any operation inside Launch day (locked) fails with `scene_locked` and its index, and nothing in the batch commits.
- [ ] Every catalog effect renders the same frame in preview, `direction_frame` and export.
- [ ] Each change in Changes names the operation and note that made it.

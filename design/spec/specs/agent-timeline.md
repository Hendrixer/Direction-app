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
| `punchIn` | `range`, `scales?` (`[1, 1.15]`), `keepIn?` | Moves. On every jump cut over `range` (a take cut to itself) the framing changes to the next of `scales`, framed on the face (eyes on the upper third with `thirds`); a cut to another take starts from the first again; it carries on from the shot before `range`. Shots that already move are left alone, with a warning. Numbers default to the film's style (styles.md › Moves) |
| `emphasisPunch` | `range`, `scale?`, `keepIn?` | Moves. Cuts in to `scale` on the face for `range` (one line, inside one shot on V1) and back out: two cuts on the same take, nothing else moves |
| `slowPush` | `range`, `scales?` (`[from, to]`), `longerThan?`, `keepIn?` | Moves. On each still shot over `range` at least `longerThan` long, scale keys from the first to the second across the shot, toward the face. A punched-in shot is left alone |
| `autoZoom` | `range`, `clipID?`, `scale?` | Moves. Screen Studio-style zooms over `range` on the screen recording showing there (a layout's screen, or the take on V1). Direction looks at what changes four times a second (`ScreenActivity`: the cursor, clicks landing, typing; a new page ends a moment), keeps moments where the action stays in one area for about ¾ s, zooms so it fills about half the view (the style's `screenZoom` min to max), pans between moments close together, and eases out after. Keys go on the clip's transform (scale, x, y), never past the picture's edges |
| `zoomTo` | `range`, `focus?` (`"action"`, `{x, y}`, `{text}`), `clipID?`, `scale?` | Moves. One zoom: in at `range`'s start, out by its end, to the action there, a point, or words found on screen with Vision at the start |
| `technique` | `name`, `variant?`, `editPoint?` (a transition), `clipID?` (an effect), `frames?`, `params?` | Uses a technique from the director's Techniques folder (techniques.md): Direction turns it into the `transition` or `addEffect` it makes, its Metal checked and its sound placed. A recipe is followed by the editor, not run |
| `balance` | `clipID`, `exposure?`, `contrast?`, `saturation?`, `temperature?`, `tint?` | Shot matching (today's `color`) |
| `matchBalance` | `clipID`, `toClipID` | Direction measures both shots and sets the balance that matches the reference |
| `cameraLUT` | `assetID`, `lut` (`auto`, a file, or `none`) | Per take, not per clip |
| `addEffect` | `target` (clip id or track), `effect`, `params`, `keys?` | Returns the effect's id |
| `setEffect` | `effectID`, `params?`, `keys?` | |
| `removeEffect` | `effectID` | |
| `transition` | `editPoint`, `type`, `frames`, `params?` | See Transitions below. With `name`, one of the style's transitions: its kind, length, settings and Metal from the style, and its sound centered on the cut on the first free sound track from A3 |
| `removeTransition` | `editPoint` | |

**Layers**

| Op | Arguments | What Direction does |
|---|---|---|
| `layout` | `range`, `layout`: the name of one of the style's layouts (`"Showing"`), or `{kind: screenAndYou\|you\|screen\|sideBySide, corner?, size?, shape?, screen?: full\|framed, edge?: #RRGGBB}` | How a camera and a screen recording in sync share the frame over `range` (layouts.md): the screen on V2, the camera on V3 (or the one take on V2), synced and silent. A bubble is framed by its `transform`, a smaller screen by `place`; both get a `card`. Direction looks a name up in the film's style and measures which take is the camera and where the face is (Vision, cached per take). Pieces of a take still shown keep the editor's zoom, masks, blurs and freeze; earlier layouts and other synced cutaways over `range` make way; anything else on V2–V3 moves up. Where a director's layout sits is theirs: `layout_is_yours` unless a note asks. |
| `cutaway` | `assetID`, `sourceRange?`, `seconds?`, `at`, `cover?` (a clip id or edit point) | Puts picture on V2 over the story; the sound underneath keeps playing. With `cover`, Direction centers it over a jump cut. Without `sourceRange`, `seconds` long: a take in sync with V1 there plays the same moment, lined up to the frame (switching angles, a screen recording under the words about it, picture-in-picture with `reframe`). It stays lined up as the cut changes (footage-index.md › Sync). |
| `pin` | `clipID` (V2+), `corners?`, `follow?` (`screen`) | Puts the clip into a screen, window or sign in the shot under it, in perspective. Without corners Direction finds the biggest rectangle in that shot with Vision and follows it; with corners it stays, or follows from them with `follow: screen`. Writes the clip's `pin` effect |
| `zoomThrough` | `editPoint` (V1), `seconds?` (0.2–5, default 1), `corners?` | Pushes into a screen in the left shot until it fills the frame at the cut, with the right shot's first frame held in the screen and opening out to the whole frame by the cut (see Zoom through) |
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
| `scene_locked` | It would recut a locked scene: its takes, timing, framing, joins, or any picture over it. Its color and sound stay open. |
| `picture_locked` | Any change to the cut after picture lock. The graphics over the picture (captions, titles, credits: `placeGraphic` and `title` on V2 and up, moved or removed) stay open, as its color and sound do. |
| `stale_revision` | `baseEditRevision` isn't current |
| `overlap` | It would make two clips overlap on one track |
| `unknown_op`, `bad_argument` | Not in the catalog, or a value out of range |
| `missing_media` | An asset, graphic or made clip that doesn't exist |
| `no_words` | `replaceTake` with `words`, or `tightenPauses`, on a take with no transcript |
| `not_in_sync` | A `cutaway` without `sourceRange` from a take that isn't in sync with the story clip under it |
| `look_is_yours` | Anything that would change the director's look |
| `words_are_yours` | Changing a graphic's words the director set, without a note that names it |
| `shader_invalid`, `shader_too_slow` | An effect or transition shader that doesn't compile, makes NaN, or takes over 40 ms a frame at 1080p |
| `no_screen` | `pin` or `zoomThrough` without corners, in a shot where Vision finds no screen, window or sign |

### Effects catalog

Used by `addEffect` and `setEffect`.

| Effect | Parameters (range, default) | Keys | Notes |
|---|---|---|---|
| `transform` | `scale` (0.1–8, 1), `x`, `y` (−8–8, 0; fraction of frame), `rotation` (−180–180, 0), `opacity` (0–1, 1), `crop` (`l r t b`, 0–0.5, 0) | yes | `reframe` writes this |
| `blend` | `mode`: normal, screen, multiply, overlay, add | no | On V2+ clips |
| `mask` | `shape`: rect, ellipse; `x y w h` (0–1); `feather` (0–0.5, 0.05); `invert` (false) | yes | Limits the clip's other effects to the shape: "brighten her face" |
| `card` | `radius` (0–0.5 of the shorter side, 0.2), `edge` (0–1, 0.3), `shadow` (0–1, 0.5), `background` (#RRGGBB), `edgeColor` (#RRGGBB) | no | The placed picture with rounded corners or as a circle, a thin light edge (solid and a little bolder in `edgeColor`) and a soft shadow, over a background that fills the frame when given. `layout` writes it |
| `place` | `x`, `y`, `w`, `h` (the rectangle in the frame), `fromX`, `fromY`, `fromW`, `fromH` (the part of the clip's finished picture), fractions of the frame from its top left | yes | After the clip's transform and its other effects, so a zoom or a blur plays inside the rectangle. `layout` writes it for a smaller screen and owns it |
| `pixelGrid` | `cells` (4–64, 16), `lines` (0–1, 0.6), `lineWidth` (0.5–8 px at 1080, 1.5), `lineColor` (#RRGGBB), `threshold` (0.05–1, 0.35) | no | On a clip over another: it shows only in the squares of a `cells`-wide grid its subject fills, with grid lines over the frame. Direction finds the subject with Vision when it's added (and when `cells` changes) and keeps it with the effect |
| `blur` | `radius` (0–100 px, 0) | yes | |
| `sharpen` | `amount` (0–1, 0) | no | |
| `stabilize` | `amount` (0–1, 0.5) | no | Vision homographic registration, cached per clip |
| `pin` | `tl.x tl.y tr.x tr.y br.x br.y bl.x bl.y` (−1–2; the frame's corners) | yes | The whole picture into four corners of the frame, in perspective, in place of its framing and transform; crop and opacity still apply. `pin` and `zoomThrough` write it |
| `filter.<kind>` | Every filter in `looks.md` | yes | Per-clip texture, apart from the director's look |
| `shader` | `file` (`Effects/<name>.metal`) and the parameters it declares | yes | Custom; see below |

Balance and camera LUTs have their own operations. Keys on a held frame (a freeze) play over the hold, so a freeze can push in; `freeze` keeps the values the clip had at that frame, so a follow stays put.

### Transitions

Settings › Cutting › Transitions still decides whether the editor may add them without a note, and the film's style (`styles.md`) says which.

- `dissolve`, `dipToBlack`, `dipToWhite`: as before (OTIO `SMPTE_Dissolve` and Direction-named types). Dips need no handles.
- **Direction's own**, drawn from both shots at once by Metal functions that ship with it: `push` and `slide` (`x`, `y` −1–1: the way they travel), `whip` (the same, plus `blur` 0–1), `zoom` (`amount` 1.2–6), `wipe` (`angle` −180–180, `softness` 0–0.5), `iris` (`x`, `y` 0–1 from the top left, `softness`). Like a dissolve they need handle on both sides.
- **The editor's own**: `type: shader`, `params.file` `Transitions/<name>.metal` in its working folder, and the parameters its header declares. One stitchable function of both pictures and how far through it is:

```metal
// direction: param softness 0 0.5 0.1
[[ stitchable ]] float4 wipe(coreimage::sampler from, coreimage::sampler to, float progress, float softness, coreimage::destination dest) { … }
```

  `direction::uv`, `direction::at` and `direction::ratio` count 0–1 from the bottom left, as GLSL transitions do, so gl-transitions.com's port line for line. Each is compiled and checked like a custom effect (3 frames at 1080p, a quarter, half and three quarters through) before it touches the cut, and kept with the cut (`source`, `params`, `file`) so every revision draws the same. The compositor draws the incoming clip and the outgoing one through the function instead of laying one over the other.

### Zoom through

`zoomThrough` is the push into a laptop that becomes the park someone walks into. Vision finds the biggest rectangle near the cut in the left shot (or takes `corners`) and follows it to the cut. The left clip gets transform keys, one a frame: scale grows evenly to the point where the screen's box covers the frame (refused past 8×), and the screen's middle travels to the frame's middle. The right shot's first frame goes on the first free layer above V1 for the length of the push, held, with its pin keyed to the screen's corners under the push; over the last 40% the corners open out to the frame's, so at the cut it is the whole frame and the right shot carries on from it. The left clip can't already have a transform.

**Acceptance:**
- [ ] A push halfway through shows the old shot on one side and the new on the other; a wipe and an iris bring the new one in from where they say.
- [ ] A transition whose shader doesn't compile is refused with its line, and the cut keeps the one it had.
- [ ] A pinned clip sits in its corners; zoomThrough shows the new shot in the screen as the push begins and fills the frame by the cut, with no jump at it.

### Custom effects (shaders)

When no catalog effect does what a note needs, the editor may write a Metal fragment function in `Effects/<name>.metal` in its working folder (`<film>.direction/Editor/`; films from before it had one keep theirs in `<film>.direction/Effects/`), then use it with `addEffect` (`effect: "shader"`):

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

# The editor's timeline

How the editor (Claude Code or Codex over MCP) reads a cut and changes it. The design is `design/spec/specs/agent-timeline.md`; this page is what's built.

The editor reads the cut as **OpenTimelineIO** and changes it only through **edit functions** in a `direction_edit` batch. Each function is one editorial act ("trim", "swap the take", "duck the music") that Direction carries out exactly: the frame math, keeping picture and sound in sync, locks, and which note the change answers. No tool accepts a timeline document.

Code: `Sources/DirectionCore/Editing.swift` (the operations), `Sources/DirectionCore/Phase2/Timeline/` (catalog, locks, the store transaction, OTIO export), `Sources/DirectionMedia/Timeline/` (per-clip rendering, shaders, Vision and audio measurements), `Sources/DirectionMedia/{GPUCompositor,SequenceRenderer}.swift`, `Sources/DirectionTools/Phase2/TimelineTools.swift`.

## Reading

`direction_timeline` takes `cut?` (a saved cut's name, "Cut 3", or its id), `revision?`, `range?` (`{start, end}` seconds; only items overlapping it) and `outlineOnly?`. It returns `{cut, editRevision, sequenceID, outline, otio}`.

| OTIO | Direction |
|---|---|
| `Timeline.1` | One cut. `metadata.direction`: `cut`, `editRevision`, `sequenceID`, `width`, `height`, `rate`, `look` (the director's film look, or null) |
| `Stack.1` → `Track.1` kind `Video` | V1 (the story) first, then V2, V3… A track whose clips overlap (a title and a picture on one layer) is split into lanes with the same name and `metadata.direction.lane`. Track effects are in the track's `effects`; `metadata.direction` has `aboveLook`, `gainDB`, `gainKeys`, `ducked`. |
| `Track.1` kind `Audio` | A1 is V1's own sound (clips with `metadata.direction.linked: "picture"`, the same id as the picture, placed where the sound plays, so J- and L-cuts show) plus sound-only clips on A1; A2, A3… are sound-only clips. Overlays with sound that plays get a "V2 sound" track. |
| `Clip.2` + `ExternalReference.1` | A take or a made clip. `source_range` starts in the take and lasts as long as the clip plays in the cut. `metadata.direction`: `id`, `assetID`, `kind` (take, made, graphic, title, sound), `take` ("1A T2"), `scene`, `track`, `balance`, `framing`, `blend`, `aboveLook`, `cameraLUT`, `gainDB`, `gainKeys`, `duckKeys`, `fadeIn`, `fadeOut`, `soundLead`, `soundTail`, `madeID`. |
| `Clip.2` + `GeneratorReference.1` | `direction.graphic` (`parameters.graphicID`, the graphic's name, and its `assetID`) or `direction.title` (`parameters.text`). There is no `direction.solid` yet: the model has no solids. |
| `Gap.1`, `Transition.1` | Transitions sit before the clip they lead into: `SMPTE_Dissolve`, `Direction_dipToBlack`, `Direction_dipToWhite`, with `in_offset` (before the cut) and `out_offset` (after it). |
| `Effect.1`, `LinearTimeWarp.1`, `FreezeFrame.1` | Effects in render order; `metadata.direction` has `id`, `params` and `keys` (cut seconds). Speed is a `LinearTimeWarp`; a freeze is a `FreezeFrame`. |
| `Marker.2` | Scenes on V1 (`metadata.direction.scene: {number, title, locked}`), notes on the stack (`metadata.direction.note: {number, kind, id}`, the text in `comment`). |

Times are `RationalTime.1` at the cut's rate. The outline is one row per clip, top layer first, then sound:

```
Cut 3 · 0:13:00 · 1920×1080 · 30 · no look
V2  00:02:00–00:06:00  clip-91  graphic "Title · Two years."  above look
V1  00:00:00–00:04:00  c1  1A T1  src 00:02:00–00:06:00  reframe(1.1)
V1  00:04:00–00:09:00  c2  1B T2  src 00:03:00–00:08:00  dissolve 12f in  ‹scene 1›
A2  00:00:00–00:13:00  m1  music "Felt piano"  src 00:00:00–00:13:00  ducked −6 dB under A1
```

`‹scene N›` marks the last clip of a scene (`· locked` when it is). The editor may save the OTIO and analyze it with `opentimelineio`; it can't send it back.

## Writing

```json
{ "baseEditRevision": 41, "idempotencyKey": "t3-note1", "summary": "Get to her face sooner",
  "notes": [1], "validateOnly": false,
  "operations": [
    { "op": "removeRange", "range": { "start": 4.2, "end": 8.4 }, "ripple": true },
    { "op": "roll", "editPoint": "clip-12|clip-13", "frames": -6, "note": 2 } ] }
```

- Times are cut seconds unless the argument says source (`sourceRange` is in the take's seconds). `frames` count frames at the cut's rate: positive lengthens a trim or moves later, negative shortens or moves earlier. Every result snaps to whole frames.
- `notes` lists note numbers the batch answers; an operation's `note` overrides it. Unknown or hidden note numbers fail. While a notes turnover is open, a batch with no note is refused unless the turnover's latitude is free; then the change is recorded `unasked`. Outside a turnover (an assembly, or your own session) no note is needed.
- `validateOnly` runs everything, including Direction's measurements and shader checks, and returns the predicted result without committing.
- One batch is one revision, or nothing. Errors are `{index, code, message}`.

The result:

```json
{ "committed": true, "editRevision": 42, "baseEditRevision": 41, "summary": "Get to her face sooner", "notes": [1, 2],
  "oldLength": 220.0, "newLength": 215.8, "delta": -4.2, "warnings": [],
  "operations": [
    { "index": 0, "op": "removeRange", "notes": [1], "unasked": false, "summary": "Removed 00:04:06–00:08:12",
      "delta": -4.2, "deltaText": "−4.2 s",
      "changes": [ { "new": {"start": 4.2, "end": 4.2}, "old": {"start": 4.2, "end": 8.4}, "tracks": ["A1", "A2", "V1"], "scenes": [1] } ] } ] }
```

Each change is placed in the new cut (through every later operation in the batch) and the old cut (back through every earlier one). The revision keeps the whole result: `ProjectStore.editRecord(revision:)` and `editRecords(after:through:)` give Changes and History each operation with its note.

| Code | When |
|---|---|
| `scene_locked` | Anything that would change what plays over a locked scene, on any track: its clips, overlays and sound over it, transitions and J/L cuts reaching into it, its takes' camera LUTs and stream settings. Changes earlier in the cut may move it whole. |
| `picture_locked` | After picture lock, anything but `balance`, `matchBalance`, `cameraLUT`, `color`, `gain`, `fade`, `duck`, `audio`, `placeMusic`, `placeMade` on an A track and removing a sound clip. |
| `stale_revision` | `baseEditRevision` isn't current. |
| `overlap` | Two clips on one track would overlap. |
| `unknown_op` / `bad_argument` | Not in the catalog / a value out of range, a missing argument, an unknown argument, an id that isn't in the cut, not enough handle. |
| `missing_media` | An asset, graphic, made clip or LUT file that doesn't exist. |
| `no_words` | `replaceTake` with words, `removeWords`, `tightenPauses` or `duck` with no transcript. |
| `look_is_yours` | `look`, `setLook`, `applyLook`, or an effect named `look`/`lut`. |
| `words_are_yours` | Raised by the graphics tools, not by edit functions, which never change a graphic's words. |
| `shader_invalid` / `shader_too_slow` | A shader that doesn't compile or makes NaN or infinity / is slower than 40 ms a frame at 1080p. |

## Operations

Story operations keep every layer in sync; overlays and sound-only clips move on their own track.

| Op | Arguments | Notes |
|---|---|---|
| `insert` | `assetID, sourceRange, at, track?` | Opens a gap on every track (clips across `at` split) and places the clip. |
| `overwrite` | `assetID, sourceRange, at, track?` | Replaces what's on that track, nothing moves. |
| `removeRange` | `range, ripple?` (default true) | Every track. |
| `remove` | `clipID, ripple?` (default false) | Ripple closes the gap on every track for V1, on its own track otherwise. |
| `move` | `clipID, to: {at} \| {before} \| {after}, to.track?` | A V1 clip takes everything over it; the story closes behind it and opens where it lands. Overlays just move. |
| `split` | `clipID, at` | The right half is a new clip with new effect ids. |
| `trim` | `clipID, edge, frames, ripple?` (default true) | Shortening V1 with ripple removes the frames on every track; lengthening moves everything after. Errors say how much handle there is. |
| `roll` | `editPoint, frames` | Length unchanged. |
| `slip` | `clipID, frames` | Keys stay with the footage (they're in source seconds). |
| `slide` | `clipID, frames` | Neighbors trim to fit. |
| `splitEdit` | `editPoint, lead: sound\|picture, frames` | J-cut: the right clip's sound starts early and the left's ends as early. L-cut: the reverse. 0 frames straightens it. |
| `replaceTake` | `clipID, withAssetID, alignOn: words\|head\|tail, ripple?` | With words, a local alignment finds the line in the new take; its first matched word lands where the old one was, and the tail keeps the same room after the last. Keys and stream overrides carry over. |
| `removeWords` | `wordIDs` | Word ids from `direction_transcript`; whole frames around each word. |
| `tightenPauses` | `range, longerThan, to` | Pauses between words longer than `longerThan` become `to`. Direction measures the sound first and takes only quiet, so a breath or a laugh stays; cuts snap inward, never into a word. |
| `speed` | `clipID, rate, ripple?` (default true) | 0.1–8, whole frames. |
| `freeze` | `clipID, at, seconds` | A held frame, rippled in; no sound. |
| `reframe` | `clipID, scale, x?, y?, follow?, keepIn?` | Writes the clip's `transform`. `follow: face` (Vision face rectangles) or `subject` (attention saliency) writes x/y keys that keep it at `keepIn` (center, thirds) or where it first appears. |
| `balance` | `clipID, exposure?, contrast?, saturation?, temperature?, tint?` | Partial: only what's named changes. |
| `matchBalance` | `clipID, toClipID` | Direction measures the middle frame of both, the reference as it's balanced now, and solves exposure, temperature, tint, saturation and contrast. |
| `cameraLUT` | `assetID, lut: auto\|none\|file` | A file is absolute or relative to the film's `Looks/Camera/`. |
| `addEffect` | `target (clip or V track), effect, params, keys?` | Returns `effectID`. |
| `setEffect` / `removeEffect` | `effectID, params?, keys?` / `effectID` | A clip's blend has the id `<clipID>:blend`. |
| `transition` | `editPoint, type, frames` | Centered on the cut. `"|<clip>"` dips in at a clip's head. A dissolve needs handles; an edit that later takes them away drops it with a warning. |
| `removeTransition` | `editPoint` | |
| `cutaway` | `assetID, sourceRange, at \| cover` | First free layer at V2 or above; its own sound is muted. `cover` (a clip or edit point) centers it over that cut. |
| `placeGraphic` | `graphic, at, seconds?, aboveLook?` (default true) | First free layer at V2 or above. |
| `placeMade` | `madeID, at, track, sourceRange?` | Places a made clip like footage; the track must be free. |
| `gain` | `target (clip or A track), dB, keys?: {dB: [{t, v}]}` | |
| `fade` | `clipID, in?, out?` (frames) | |
| `duck` | `track, under? (A1), dB, attack? (0.25), release? (0.5)` | Words less than 0.6 s apart are one line; keys go on every clip of `track`, and redoing it replaces them. |
| `placeMusic` | `madeID \| assetID, at, endOn: {cut} \| {word} \| seconds, track?` | Ends on the cut or the word's start, trimmed from the head; if it's shorter, it starts later and says so. |
| `audio`, `format`, `duplicateSequence` | as before | |

Older shapes still decode: `{"batch": {…}}` with `type` per operation and `{value,timescale}` times; `title`, `color`, `frame` and `rename` keep working.

## Effects

| Effect | Parameters (range, default) | Keys |
|---|---|---|
| `transform` | `scale` (0.1–8, 1), `x`, `y` (−1–1, 0; fractions of the frame, y down), `rotation` (−180–180, 0; clockwise), `opacity` (0–1, 1), `crop` `{l,r,t,b}` (0–0.5) | yes; crop as `crop.l`… |
| `blend` | `mode`: normal, screen, multiply, overlay, add | no; V2+ only |
| `mask` | `shape` rect/ellipse, `x y w h` (0–1, from the top left), `feather` (0–0.5, 0.05), `invert` | yes |
| `blur` | `radius` (0–100 px at the cut's size) | yes |
| `sharpen` | `amount` (0–1) | no |
| `stabilize` | `amount` (0–1, 0.5) | measured |
| `filter.<kind>` | `amount` (0–1, 0.5), `option` where the filter has one | yes |
| `shader` | `file` and its declared parameters | yes |

Keys are `{param: [{t, v, ease?}]}` with `t` in cut seconds and `ease` linear, hold or smooth. Clip keys are stored in source seconds so they follow the footage through trims and ripples; track keys are cut seconds and move with ripples.

### Shaders

A Metal function in the film's `Effects/<name>.metal`:

```metal
// direction: param amount 0 1 0.5
// direction: param tint color #F2A33A
[[ stitchable ]] half4 effect(coreimage::sample_h s, float amount, float3 tint, coreimage::destination dest) { … }
```

The first argument is `coreimage::sample_h` (one pixel, premultiplied) or `coreimage::sampler` (`sample(p)`, `coord()`, `extent()` in Core Image's bottom-left pixel space); then one `float` per number parameter and one `float3` per color, in the header's order; then optionally `coreimage::destination`. Direction compiles it with `MTLDevice.makeLibrary(source:)` behind a small prelude, wraps it in a `CIImageProcessorKernel`, and refuses `#include`, `#import`, `#pragma` and `#line`. Before an `addEffect` or `setEffect` uses it, Direction renders 3 frames of a 1080p test picture: a median over 40 ms a frame is `shader_too_slow`, any NaN or infinity is `shader_invalid`. Compile errors carry the file's own line numbers. The source is kept in the effect, so a revision renders the same even if the file changes. `direction_edit_catalog` lists the shaders that compile, and the ones that don't with their errors.

## What Direction renders

Per frame: each clip's camera LUT and balance, crop and placement (framing, then the transform), its other effects in order (blur, sharpen, `filter.<kind>` through `LookPipeline.filter`, shaders), limited to the union of its masks, then opacity and its transitions → its track's effects → tracks composited bottom to top with their blend modes → the director's look (`LookPipeline.apply`, with the V1 take at that frame) → clips marked above the look (graphics by default; a track's `aboveLook` applies to clips that don't say) → output. Stabilize corrects the take's own pixels first. A dissolve draws both clips from their handles; dips mix the clip toward black or white where it has alpha. ProRes 4444 alpha composites as alpha. Frame, preview and export all render through the same compositor.

Sound: stream gain and fades, clip gain and gain keys, track gain and keys, duck keys and clip fades, as volume ramps in the mix (dB keys are linear in dB, so long changes get more points). J- and L-cuts move where each clip's sound starts and ends. A freeze has no sound. The mix isn't normalized to a loudness target yet.

## For the other areas

- **Looks.** `SequenceRenderer.compile(project:sequenceID:cacheDirectory:previewMaxDimension:looks: LookContext? = nil)`. Callers pass `try? store.lookContext()`; the frame, preview, export and feedback-context call sites in `ToolRuntime` and both app players do. The compositor calls `LookPipeline.apply(_:context:storyAssetID:frameIndex:)` once per frame over everything below the look, and `LookPipeline.filter(_:kind:amount:option:frameIndex:)` for each `filter.<kind>` effect. `frameIndex` is frames from the cut's start. Camera LUT `.cube` files set with `cameraLUT` are applied by the renderer; `auto` (detecting log footage) is left to the looks area.
- **Graphics.** A checked graphic is a `MediaAsset` in `project.assets`: its ProRes 4444 render with alpha, with `asset.graphic` set to the graphic's name. `placeGraphic` asks `store.graphicAssetID(name)` first and falls back to the newest asset whose `graphic` matches. Placed graphics are clips with `aboveLook: true` unless the editor says otherwise.
- **Made media.** A made clip is a `MediaAsset` (probed like footage, file in `Made/`). `placeMade` and `placeMusic` accept the asset's id or `asset.madeID`, the made record's id. OTIO marks it `kind: "made"` with `madeID`.
- **Changes.** Each committed `direction_edit` revision has an `EditResult`: per operation its notes (or `unasked`), summary, delta and changed ranges in the new and old cut with scenes.

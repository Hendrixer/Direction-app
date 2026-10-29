# The editor's timeline

No frames. This is the contract between the editor and Direction's renderer. Read `product-model.md` first.

The director never sees a timeline: they see scenes on a strip, answers and choices. The editor sees everything: every layer, every effect, every keyframe, every graphic and made clip. Direction doesn't hand off to another editing app; it renders everything itself. Where data isn't enough, the editor writes code: graphics in JavaScript (`graphics.md`), effects as Metal shaders (below), and scripts that transform the timeline.

---

## Format: OpenTimelineIO, with Direction's fields

The editor reads and writes the timeline as **OpenTimelineIO** JSON (OTIO, the Academy Software Foundation's open timeline format). Agents and their tools already know it, and the `opentimelineio` Python library can read and write it in a script. OTIO describes the edit but not how effects render, so Direction fills that part in under `metadata.direction`.

| OTIO | Direction meaning |
|---|---|
| `Timeline` | One cut. `metadata.direction`: `cut`, `editRevision`, `width`, `height`, `rate`, `look` (the director's, read-only) |
| `Stack` → `Track` (kind `Video`) | Video layers, bottom first: V1 is the story track (footage), V2+ are overlays (graphics, picture-in-picture, made shots). |
| `Track` (kind `Audio`) | A1 dialogue, A2 music, A3 sound effects, A4+ more. Names are fixed; extra tracks are named by the editor. |
| `Clip` + `ExternalReference` | A take or a made clip. `metadata.direction.id` is the clip's stable id; `assetID` names the footage. `source_range` is the trim. |
| `Clip` + `GeneratorReference` | Something Direction draws: `generator_kind` `direction.graphic` (`parameters.graphicID`), `direction.solid` (`parameters.color`) |
| `Gap` | Empty time on a track |
| `Transition` | `transition_type` from the catalog below; `in_offset`, `out_offset` |
| `Effect` on a clip or track | `effect_name` from the catalog; parameters in `metadata.direction.params`; keyframes in `metadata.direction.keys` |
| `LinearTimeWarp`, `FreezeFrame` | Speed and holds, as OTIO defines them |
| `Marker` on the timeline | Scenes (`metadata.direction.scene: {number, title, locked}`) and notes (`metadata.direction.note: {number, kind}`). Read-only; changing them is an error. |

Keyframes are `{"param": [[seconds, value, "linear" | "ease" | "hold"], …]}` in the clip's own time. A parameter with keys ignores its static value.

```json
{ "OTIO_SCHEMA": "Clip.2", "name": "3B T2",
  "source_range": { "OTIO_SCHEMA": "TimeRange.1",
    "start_time": { "OTIO_SCHEMA": "RationalTime.1", "rate": 23.976, "value": 1022 },
    "duration":   { "OTIO_SCHEMA": "RationalTime.1", "rate": 23.976, "value": 96 } },
  "media_references": { "DEFAULT_MEDIA": { "OTIO_SCHEMA": "ExternalReference.1", "target_url": "direction://asset/asset-3b-t2" } },
  "active_media_reference_key": "DEFAULT_MEDIA",
  "effects": [ { "OTIO_SCHEMA": "Effect.1", "effect_name": "direction.transform",
                 "metadata": { "direction": { "params": { "scale": 1.6, "y": -0.08 } } } } ],
  "metadata": { "direction": { "id": "clip-5d1c", "assetID": "asset-3b-t2", "note": 3 } } }
```

## Reading and writing

| Tool | Arguments | Returns |
|---|---|---|
| `direction_timeline` | `cut?`, `revision?`, `range?` | The OTIO document, plus `outline`: a compact text view, one line per item (below). Pass `range` to get only items overlapping it. |
| `direction_timeline_apply` | `baseEditRevision`, `document` or `path` (an `.otio` file in the working folder), `summary`, `notes` (note numbers this change answers), `idempotencyKey`, `validateOnly?` | The new `editRevision` and a list of what changed, or errors |
| `direction_effects` | — | The effects and transitions catalog below, with every parameter's range and default |
| `direction_edit` | unchanged | Small operations still work and are often simpler |

**Apply** diffs the submitted document against `baseEditRevision` by `metadata.direction.id`: items without an id are new; ids that are gone are removed; changed fields become operations. All of it commits as one new revision, or nothing does. Errors are a list of `{path, code, message}` with a JSON pointer into the document:

| Code | When |
|---|---|
| `scene_locked` | Any change overlapping a locked scene's range, on any track |
| `picture_locked` | Any picture change after picture lock |
| `stale_revision` | `baseEditRevision` isn't current |
| `overlap` | Two clips overlap on one track |
| `unknown_effect`, `bad_param` | Not in the catalog, or a value out of range |
| `missing_media` | An asset or graphic that doesn't exist |
| `marker_changed` | A scene or note marker was edited |

**Outline** lines look like this, so the editor can read a cut without parsing JSON:

```
Cut 3 · 3:40:00 · 1920×1080 · 23.976 · look "Window light" (film)
V2  00:02:00–00:06:00  graphic "Title · Two years."  above look
V1  00:00:00–00:09:12  1A T2  src 00:04:10–00:13:22  transform(scale 1.1)
V1  00:09:12–00:25:00  1B T4  src 00:00:20–00:16:08  ‹scene 1›
A2  00:00:00–00:25:00  music "Felt piano" (made)  gain −6 dB under A1
```

**Scripting.** The editor may export the timeline to its working folder, transform it with a script (Python with `opentimelineio`, or JavaScript), and apply the file. Direction never runs the editor's scripts; the editor's program does, inside its sandbox. Apply checks the result like any other change.

## What Direction renders

Order, per frame: each clip's effects in list order → its track's effects → layers composited bottom to top with their blend modes → **the director's look** (`looks.md`) → tracks marked `aboveLook` (graphics by default) → output. Audio: clip gain and keys → track effects → dialogue ducking → the mix to the loudness target.

### Effects catalog

| `effect_name` | Parameters (range, default) | Keys | Notes |
|---|---|---|---|
| `direction.transform` | `scale` (0.1–8, 1), `x`, `y` (−1–1, 0; fraction of frame), `rotation` (−180–180, 0), `opacity` (0–1, 1), `crop` (`l r t b`, 0–0.5, 0) | yes | Reframing for notes like "tighter on her" |
| `direction.balance` | `exposure` (−3–3 stops, 0), `contrast` (0.5–1.5, 1), `saturation` (0–2, 1), `temperature` (−1–1, 0), `tint` (−1–1, 0) | no | Shot matching. The existing `ColorGrade`. |
| `direction.cameraLUT` | `file` (a LUT with use `.camera`) | no | Usually set automatically for log footage |
| `direction.blend` | `mode`: normal, screen, multiply, overlay, add | no | On V2+ clips |
| `direction.mask` | `shape`: rect, ellipse; `x y w h` (0–1); `feather` (0–0.5, 0.05); `invert` (false) | yes | Limits the clip's other effects to the shape: "brighten her face" |
| `direction.blur` | `radius` (0–100 px, 0) | yes | |
| `direction.sharpen` | `amount` (0–1, 0) | no | |
| `direction.stabilize` | `amount` (0–1, 0.5) | no | Vision homographic registration, cached per clip |
| `direction.filter.<kind>` | Every filter in `looks.md` | yes | Per-clip texture, apart from the director's look |
| `direction.shader` | `file` (`Effects/<name>.metal`) and the parameters it declares | yes | Custom; see below |
| Audio: `direction.gain` (−60–12 dB), `direction.eq`, `direction.compress` | As today's `AudioSettings` | gain only | |

### Transitions

`Cut` (no transition), `SMPTE_Dissolve` (the OTIO name), `direction.dipToBlack`, `direction.dipToWhite`. Settings › Cutting › Transitions still decides whether the editor may add them without a note.

### Custom effects (shaders)

When no catalog effect does what a note needs, the editor may write a Metal fragment function in `Effects/<name>.metal`:

```metal
// direction: param amount 0 1 0.5
// direction: param tint color #F2A33A
[[ stitchable ]] half4 effect(coreimage::sample_h s, float amount, float3 tint, coreimage::destination dest) { … }
```

- The header comments declare parameters; `direction_effects` validates them.
- Direction compiles it with `MTLDevice.makeLibrary(source:)` and wraps it as a Core Image kernel. Compile errors return to the editor with line numbers.
- Before use, Direction renders 3 frames with it; a kernel that takes longer than 40 ms a frame at 1080p, or produces NaN, is refused (`shader_too_slow`, `shader_invalid`).
- Shaders can't read files or the network; they only see pixels and their parameters.

## Rules the renderer enforces

- The look is the director's: the timeline document shows it under `metadata.direction.look` and refuses changes to it.
- Graphics' words that the director changed are locked against the editor unless a note asks (`graphics.md`).
- Made clips are files in `<film>.direction/Made/`, referenced like footage.
- Every apply records `summary` and `notes`, so Changes can show which note each change answers.

## What we took from open source

We looked at how other editors expose their work to code, without handing anything off to them:
- **EffectCraft** (Rust, MIT/Apache): every action goes through one command registry behind its CLI and MCP server, projects are versioned JSON, every effect has fixed parameter names and defaults, and expressions are JavaScript. Direction takes the same stance: one catalog, fixed parameters, every action a tool.
- **MLT** (the engine under Kdenlive and Shotcut): filters and transitions attached to producers and tracks in a scriptable XML graph. It's the model for per-clip and per-track effects here.
- **OpenTimelineIO**: the shared vocabulary for tracks, clips, gaps, transitions and markers.
- **Premation** (AGPL; study only, don't copy code): a deterministic WebGL/WebGPU renderer for motion graphics. It's the reason graphics here render in a browser engine on a clock Direction controls.

**Acceptance:**
- [ ] `direction_timeline` then `direction_timeline_apply` with the document unchanged makes no new revision.
- [ ] A script that round-trips the document through `opentimelineio` and back applies cleanly.
- [ ] Any change inside Launch day (locked) fails with `scene_locked` and a pointer to the item.
- [ ] Every catalog effect renders the same frame in preview, `direction_frame` and export.

# Looks

How Direction handles the film's color and texture, for editors working over MCP and for code that renders. The product spec is `design/spec/specs/looks.md`; this is what's built.

A **look** is a LUT at a strength plus filters. The director chooses it in the Look sheet (Film › Look…, ⌥⌘L). The editor balances shots and proposes looks with `direction_make_look`; nothing it can call sets one. Any path that would returns `look_is_yours`.

## Where color happens, per frame

1. **Camera LUT**, per take: log footage becomes normal video.
2. **Balance**, per clip: the editor's shot matching.
3. **The editor's effects**, per clip, including `filter.<kind>`.
4. **The look**: the scene's own look if it has one, otherwise the film's. The LUT at its strength, then the filters in their fixed order.
5. **Graphics** above the look.

Looks work on Rec. 709 values: the LUT runs through `CIColorCubeWithColorSpace` with `CGColorSpace.itur_709`, the space the compositor writes, so a LUT sees the same code values Resolve or Final Cut would give it.

## Tools

### `direction_looks`

Read only. Returns:

- `current.film`: the film's look (`name`, `lut`, `strength`, `filters` as kind → amount, `options` as kind → option, `by`, `note`). `{"name": "None"}` when there's none.
- `current.scenes`: `[{sceneID, scene: "3 The ridge", look}]` for scenes with their own.
- `available`: `[{group, byEditor, looks: [{name, path, look, problem}]}]`. "Made by the editor" first, then "Your looks folder" (loose files), then one group per subfolder. A `problem` means the LUT doesn't validate; it's never applied.
- `filters`: the eleven filters in render order, with `options`.
- `camera`: `convertLogAutomatically`, the `Camera` folder, the camera LUTs `installed`, and per take its `log` (from metadata), `chosen` (`auto`, `none` or a file) and the `cameraLUT` it gets.

### `direction_make_look`

```json
{
  "name": "Window light",
  "fromStill": "/Users/me/Refs/window.jpg",
  "strength": 1,
  "filters": [{"kind": "halation", "amount": 0.3}, {"kind": "vignette", "amount": 0.2}, {"kind": "grain", "amount": 0.4, "option": "fine"}],
  "note": "Warm, one source, a lot of shadow.",
  "noteID": "feedback-…"
}
```

- At most one of `cube` (the text of a `.cube` file), `fromStill` (a reference still's path) or `fromLUT` (a name or path in the Looks folder). None means filters only.
- `fromStill` measures the film's frames and the still in CIELAB and builds a 33-point LUT that moves the film's mean and spread per channel onto the still's (Reinhard-style color transfer). Lightness spread is held to 0.6–1.6×.
- Saved in the film as `Editor/Looks/<slug>.json` (the look) and `<slug>.cube` (its LUT). The same name replaces your earlier version.
- Returns `look`, `path`, `lut` (`kind`, `size`) and `stills`: before (the picture as the director sees it now) and after (with this look) on three frames from different scenes, as PNG paths and as images. A film with no cut yet returns no stills.
- `apply: true` is refused with `look_is_yours`. Offer looks as Options in `direction_turnover_complete` or as a question with `direction_ask`; the director's pick sets the look.

Errors: `lut_invalid` (with the reason), `lut_not_found`, `still_not_found`, `no_frames` (`fromStill` before there's a cut), `bad_argument`, `look_is_yours`.

## LUT files

`.cube` as Resolve, Premiere and Final Cut write it:

- `LUT_3D_SIZE` or `LUT_1D_SIZE`, 17–65. Exactly size³ (3D) or size (1D) rows of three numbers, red changing fastest.
- `TITLE`, `DOMAIN_MIN`/`DOMAIN_MAX` (or Resolve's `LUT_3D_INPUT_RANGE`), `#` comments. Keywords come before the table; other keywords are ignored.
- Every value inside 0–1 (float noise within 0.0001 is clamped). `DOMAIN_MIN` below `DOMAIN_MAX`.

1D LUTs and non-unit domains are resampled into a plain 3D cube. Parsed cubes are cached per file and read again when the file changes.

## Filters

One amount each (0–1), in this fixed order. Sizes are at 1080p and scale with the frame.

| Kind | Option | What it does |
|---|---|---|
| `blackAndWhite` | | Desaturates with a red-weighted mix (0.50 R, 0.40 G, 0.10 B) |
| `splitTone` | `warmTeal` (default), `coolAmber` | Warm highlights and teal shadows, or the reverse; black and white stay put |
| `fade` | | Lifts blacks up to 16% |
| `halation` | | Red-orange glow around highlights |
| `bloom` | | Neutral glow from bright areas |
| `soften` | | Highlights spread into what's around them, like a mist filter |
| `chromaticAberration` | | Red and blue split at the edges, up to 4 px |
| `vignette` | | Darkens the corners |
| `grain` | `fine` (default), `medium`, `coarse` | Luminance-weighted grain; the average brightness stays put |
| `gateWeave` | | Projector-gate drift, under 0.6 px |
| `letterbox` | `2.39` (default), `2.00`, `1.85` | Black bars to a wider frame; no amount |

Grain and gate weave depend only on the frame index (frames from the cut's start), so preview, `direction_frame` and export match frame for frame.

## Folders

- **The Looks folder**: Settings › Footage › Color, default `~/Movies/Direction/Looks`, created by the app when first used. Stored as `looksFolder` in the `dev.direction.shared` defaults suite, so every process reads the same one. Subfolders are groups. `Camera/` holds camera LUTs and isn't listed as looks.
- **Looks chosen from the folder** are copied into `<film>.direction/Looks/` so the film keeps working if the folder changes.
- **The editor's looks**: `<film>.direction/Editor/Looks/`.

## Camera LUTs

Direction reads each take's log curve from its video track: Apple Log from the format description's log transfer function, otherwise S-Log3, LogC or V-Log from the transfer function, color metadata, or a Sony `M01.XML` sidecar. When Settings › Footage › "Convert log footage automatically" is on (`convertLogFootage`, default on) and `Looks/Camera/<log name>.cube` exists (`Apple Log.cube`, `S-Log3.cube`, `LogC.cube`, `V-Log.cube`), that take gets it. Direction ships no camera LUTs. The editor sets or clears one per take with `cameraLUT` (`auto`, `none`, or a file), stored by `ProjectStore.setCameraLUT`.

## For renderers

`DirectionCore`:

- `store.lookContext() -> LookContext?`: nil when there's nothing to apply. `look` (`FilmLook`: `film` plus `scenes` by scene id), `sceneForAsset` (take → scene, from the dailies) and `cameraLUTs` (take → absolute `.cube` path).
- `store.setLook(_:sceneID:asDirector:)`: the only way to change the look. Without `asDirector` it throws `look_is_yours`; `LookRules.refuse()` is that error, for edit functions that would touch the look.

`DirectionMedia`:

- `LookPipeline.camera(image, context:, assetID:)`: on each layer's source frame, before balance.
- `LookPipeline.apply(image, context:, storyAssetID:, frameIndex:)`: after every layer below the look, with the take on V1 at that frame.
- `LookPipeline.filter(image, kind:, amount:, option:, frameIndex:)`: one filter, for `filter.<kind>` effects (`kind` may carry the `filter.` prefix).
- `LookPipeline.apply(look, to:, frameIndex:)` and `LookPipeline.lut(image, path:, strength:)` for one look or one LUT.

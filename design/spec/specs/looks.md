# Looks

Frames 54 (Settings › Footage › Color) and 63 (the Look sheet). Read `product-model.md › Look, Filter, LUT` first.

A **look** is the film's color and texture: a LUT at a strength, plus filters such as Grain and Halation. The director chooses it, the way a director and a cinematographer set a look before the colorist matches shots. The editor balances shots so they match each other (`direction.balance`), and may propose looks, but never applies one.

---

## Where color happens, per frame

1. **Camera LUT.** Log footage (Apple Log, S-Log3, LogC, V-Log) becomes normal video. Direction detects log from the file's metadata and applies the matching LUT from `Looks/Camera/` automatically when Settings › Footage › "Convert log footage automatically" is on. The editor can set or clear it per take.
2. **Balance.** The editor's shot matching: exposure, contrast, saturation, temperature, tint.
3. **The editor's effects.** Transform, masks, per-clip filters (`agent-timeline.md`).
4. **The look.** The film's look, or the scene's own if it has one: the LUT at its strength, then the filters in the fixed order below.
5. **Graphics** above the look.

Working space is Rec. 709 (gamma 2.4). LUTs apply with Core Image `CIColorCubeWithColorSpace` in that space.

## LUT files

- Format: `.cube` (1D and 3D, sizes 17–65), the format Resolve, Premiere and Final Cut all read. Direction validates each file: size, `DOMAIN_MIN/MAX`, and no values outside 0–1 after the domain. Invalid files show in the Look sheet as "Can't read this LUT" and are never applied.
- **The Looks folder** (Settings › Footage › Color): default `~/Movies/Direction/Looks`, watched for changes. Subfolders become groups in the Look sheet. `Camera/` holds camera LUTs and isn't shown as looks.
- **Looks in a film** are copied into `<film>.direction/Looks/` when chosen, so the film keeps working if the folder changes.
- **Looks the editor makes** live in the film's `Editor/Looks/` and show under "Made by the editor".

## Filters

One control each, so the director never tunes a dozen sliders. The order is fixed.

| Order | Filter | Control | What it does |
|---|---|---|---|
| 1 | Black and white | Amount | Desaturates with a red-weighted channel mix |
| 2 | Split tone | Amount, and Warm·Teal / Cool·Amber | Tints shadows and highlights apart |
| 3 | Fade | Amount | Lifts blacks |
| 4 | Halation | Amount | Red-orange glow around highlights, like film |
| 5 | Bloom | Amount | Soft glow from bright areas |
| 6 | Soften | Amount | Diffuses highlights, like a mist filter |
| 7 | Chromatic aberration | Amount | Splits color at the frame's edges, up to 4 px |
| 8 | Vignette | Amount | Darkens the corners |
| 9 | Grain | Amount, and Fine / Medium / Coarse | Luminance-weighted grain, new every frame, seeded by frame number so renders match |
| 10 | Gate weave | Amount | The slight drift of film in a projector gate, up to 0.6 px |
| 11 | Letterbox | 2.39 / 2.00 / 1.85 | Black bars to a wider frame (no amount) |

Filters render on the GPU in the existing compositor (Core Image built-ins where they exist; the rest as Metal kernels shipped with the app). Grain and Gate weave are seeded by frame, so preview, `direction_frame` and export match exactly.

## How the editor proposes a look

A note like "It should feel like a still of window light" (Picture) goes to the editor like any other note. The editor:
1. Makes two or three looks with `direction_make_look`: `{name, cube?: text, fromStill?: path, filters, note}`. It can write a `.cube` file itself (a list of colors), derive one from a reference still by matching its color, or start from a LUT in the Looks folder.
2. Direction validates the LUT and returns before and after stills on three frames from different scenes.
3. The editor answers the note with Options (A/B) or a question with up to four looks as stills. Picking one sets the film's look (or the scene's, if the note was on a scene).

The editor never sets the look itself; `direction_timeline_apply` refuses it.

---

## 63 · The Look sheet
Frame: `screens/63-look.html` · 1440 × 900, sheet 1120 × 720.

Opens with Film › Look… (`⇧⌘L`), from the picture's context menu (Look…), and from a look answer in Changes. Here it's over Screening's paused picture at 01:20:00 (scene 3, The ridge, dusk).

- **Left: the picture** (720 wide, 16:9), the current frame with the selected look. `\` holds to show the picture without the look; a small text-3 hint under the picture says "Hold \ to compare". Under it, a strip of 5 stills, one from each scene, all with the selected look, so the director sees it across the film; click a still to show that frame large.
- **Right: the panel** (360 wide, padding 20):
  - Section "LOOKS": a grid of tiles, 3 across, each the current frame with that look (tile 104 wide, radius 8), name under it in 12 text-2. Groups with section labels:
    - "MADE BY THE EDITOR" (a diamond before the label): "Window light", "Window light, warmer" (each tile has a small diamond at its corner).
    - "YOUR LOOKS FOLDER": "Print film", "Soft stock", "Bleach bypass", "Teal & amber", "Muted".
    - "None" as the first tile of the first group.
  - Selected tile: a 1.5 pt text-1 ring. The film's current look has a small "Current" chip.
  - **Strength** slider (0–100%, default 100%) for the LUT.
  - Section "FILTERS": rows for every filter in order, each with a switch and, when on, an amount slider on the same row (Grain shows its size seg under the row). In the frame: Halation on at 30%, Grain on at 40% Fine, Vignette on at 20%, the rest off.
  - **Apply to**: a select "Whole film" / "Scene 3 The ridge" (the scene under the playhead) / each scene. A scene with its own look shows "Scene 3 has its own look · Use the film's look" under it as a text link.
- **Buttons:** Cancel (plain) · **Use This Look** (steel).
- Changing anything previews instantly on the large picture and the 5 stills (under 100 ms at 1080p); nothing changes the film until Use This Look.
- Use This Look records an undoable director act ("Changed the look of the film") in History. It doesn't make a new cut; looks apply to every cut.

**Acceptance:**
- [ ] A LUT dropped into the Looks folder appears in an open Look sheet within 2 s.
- [ ] Grain looks identical in two exports of the same cut.
- [ ] The editor can't change the look; `direction_timeline_apply` returns an error if it tries.
- [ ] VoiceOver reads each tile as "Print film, look" and each filter row as "Grain, on, 40 percent".

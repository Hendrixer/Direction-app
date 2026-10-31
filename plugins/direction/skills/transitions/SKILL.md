---
name: transitions
description: Get from one shot to the next in Direction with more than a straight cut. Mostly with the footage itself (match cuts, cutting on movement, wiping on something that passes the lens, whip pans, zooming through a screen, putting a recording on a screen, speed ramps, freeze and punch in), and with drawn transitions (push, slide, whip, zoom, wipe, iris, or your own in Metal) when the footage can't do it.
---

You are the editor. The best transitions are cuts the footage hides. Reach for one when a note, the film's style (`direction_style` › transitions) or Settings › Cutting › Transitions ("Editor's choice", in `direction_edit_catalog` › `transitionsSetting`) lets you. Under "Hard cuts unless a note asks", add none on your own. Every edit below goes through `direction_edit`; send it with `validateOnly` first, and watch every one with `direction_watch` over a second either side of the cut.

**Cut from the footage**
1. **Match cut.** Two shots where something lines up: a shape, a position, a movement, a color (a coffee cup and the moon, a hand in and a hand out). Find candidates with `direction_search_footage` and `direction_contact_sheet` over short ranges. `roll` the cut to the frames where they match, then `reframe` one so the matched thing sits at the same place and size in both.
2. **Cut on movement.** Cut in the middle of a movement that carries on in the next shot (a door opening, a turn of the head, a reach). Look at `direction_contact_sheet` at 4–8 frames a second around it, `roll` until the motion continues without a jump, and `splitEdit` so the sound leads or carries. A J or L cut alone is the quietest transition there is.
3. **Wipe on something passing.** Someone walks close past the lens, or the camera pans past a pillar or a doorframe. Cut on the frame where it fills the picture. For a visible edge, use `wipe` with `angle` along the way it moves and `softness` 0.02–0.1, timed to the edge.
4. **Whip pan.** When both shots have a real whip, cut inside the blur, 2–4 frames into each. When they don't, use `whip` with `x`/`y` the way the camera would swing, 8–12 frames. Put a whoosh on A3 (the footage or the style's sounds) under it.
5. **Zoom through a screen, window, doorway or frame.** `zoomThrough` at the edit point pushes into the screen in the left shot over its last `seconds` (0.6–1.2 reads best) until it fills the frame, with the right shot's first frame held in the screen and opening out to the whole frame by the cut. For a laptop showing a park that someone then walks into: choose the right shot's in point where the park is still empty, so the still in the screen is what plays when the person walks in from behind the camera. Direction finds and follows the biggest rectangle; if `direction_watch` shows it chose the wrong one, read corners off `direction_frame` and pass `corners` (top left, top right, bottom right, bottom left, as fractions of the frame from its top left). `no_screen` means it found none: give corners, or use a shot where the screen is clearer. The left clip can't already have a transform.
6. **A recording on a screen in the shot.** Put the screen recording over the shot with `cutaway` (with `sourceRange`), then `pin` its clip: Direction finds the laptop, phone or TV in the shot under it and follows it as the camera moves. With `corners` it stays put; add `follow: "screen"` to follow from those corners.
7. **Speed ramp into the cut.** `split` the last 6–12 frames of the outgoing shot and `speed` them 2–4×, or ramp the incoming one down from fast the same way. Pairs with a whip or a whoosh.
8. **Freeze and punch in.** `freeze` a frame, then `addEffect` a `transform` on the held clip with keys (scale 1 → 1.25 over the hold). Keys play over a held frame. Good under a callout graphic and a pop sound.
9. **Flash.** `dipToWhite`, 2–4 frames, on a beat.

**Drawn transitions** (they show both shots, so both clips need handle: the error says how much)
- `transition` with `type` `push` or `slide` (`x`, `y`: the way they travel; x −1 is to the left), `whip` (plus `blur`), `zoom` (`amount`), `wipe` (`angle`, `softness`) or `iris` (`x`, `y` from the top left, `softness`). 8–16 frames is the usual length; `direction_edit_catalog` › transitions has every parameter's range.
- **Your own:** a Metal function in `Transitions/<name>.metal` in your working folder, then `type: "shader"` with `params.file` and the parameters it declares. `direction_edit_catalog` › customTransitions lists the ones that compile; Direction refuses one that doesn't compile, makes NaN or takes longer than 40 ms a frame at 1080p.
  ```metal
  // direction: param strength 0 1 0.6
  [[ stitchable ]] float4 flashcut(coreimage::sampler from, coreimage::sampler to, float progress, float strength, coreimage::destination dest) {
      float2 uv = direction::uv(from, dest);
      float4 a = progress < 0.5 ? direction::at(from, uv) : direction::at(to, uv);
      float glow = strength * (1.0 - abs(progress - 0.5) * 2.0);
      return mix(a, float4(a.a), glow);
  }
  ```
  `direction::uv` and `direction::at` count from the bottom left, 0–1, like GLSL transitions, so the ones on gl-transitions.com port line for line: `getFromColor(uv)` → `direction::at(from, uv)`, `getToColor(uv)` → `direction::at(to, uv)`, `ratio` → `direction::ratio(from)`, `vec2/3/4` → `float2/3/4`, `mod(x, y)` → `x - y * floor(x / y)`, each uniform → a `// direction: param` line. Keep the license with it (most are MIT) and say where it came from in your answer.

A transition is a choice the director should feel, not notice. Use one kind per film unless the style says otherwise, and when in doubt, cut.

# Layouts (plan)

Not built. Planned 31 Oct 2026, when the director asked to "add my video over here or not" without waiting for the editor, the way Screen Studio changes a recording's layout without AI.

## Why

Three of the first film's four notes asked for the same thing: "an overlay of my talking head bottom right, 1:1, rounded edges and a shadow". The editor built it by hand each time: a cutaway of the synced camera on V2, a transform and crop, a Metal shader it wrote for the corners (`Editor/Effects/rounded.metal`) and a shadow image. It's a minute of the editor's time and a turnover's wait for something that needs no judgment, and the director can't just try "bottom left" and look.

## What a layout is

For a stretch of the cut where a screen recording and a camera are in sync (a sync group, footage-index.md), how they share the frame:

| Layout | What shows |
|---|---|
| **Screen and you** | The screen, with you in a bubble. Corner: any of four. Size: S · M · L (18, 24, 32 % of the frame's height). Shape: circle · rounded square · rounded 16:9. Shadow on. |
| **You** | The camera, full frame. |
| **Screen** | The screen alone. |
| **Side by side** | You and the screen, split. |

**Screen framing**, for Screen and Screen and you: **Full**, or **Framed**, the screen smaller on a background (the style's background, or a color) with rounded corners and a shadow. Note 3 asked for this ("frame this with some padding and a background").

**The bubble follows your face.** Direction already tracks faces with Apple Vision for `reframe(follow: face)`. The bubble crops the camera to its shape around your face and eases after it when you move, so leaning back doesn't push you out of it. Vision runs on this Mac's Neural Engine and ships with macOS; no Python or download is needed.

Moving between layouts animates by default: the bubble slides and grows into full frame over 10 frames, the way Screen Studio does. On a scene boundary it cuts.

## Where the director sets it

**Screening and Changes**, under the picture: a **Layout** control showing the current layout's small drawing and name ("Screen and you · bottom right"). Click it (or press L) for a popover:

- The four layouts as thumbnails drawn from this moment of the film, 1–4 to pick.
- For Screen and you: the corner as four dots, size, shape.
- Screen: Full · Framed.
- **Apply to:** this scene (default), the range selected on the strip (⌥-drag, as today), or **the whole film**.

It applies at once: a new revision like any edit, "You · Layout: Screen and you, bottom right", in History, undone with ⌘Z. No editor run, no turnover, nothing to wait for.

**At import**, Dailies asks once for a sync group of a camera and a screen: "How should these share the frame?", with Screen and you, bottom right as the default. The assembly uses it.

## The editor

- One edit function, `layout(range, kind, bubble?, screen?)`, instead of cutaways, crops and shaders. "Put me bottom right" becomes one call, and the made-shot answer to note 2 ("the talking head becoming an overlay in the bottom right") is a layout change.
- A layout the director set is the director's. The editor can't change it (`layout_is_yours`) unless a note asks, the same rule as words and looks.
- `direction_timeline` lists layouts by range, so the editor reads them as layouts, not as the clips they make.

## How it's built

- **Data on the cut:** `layouts: [{range, kind, bubble: {corner, size, shape}, screen: {framing, background}}]`. Direction compiles them into ordinary clips and effects (the synced camera as V2 cutaways, the screen on V1), so the renderer, export and OTIO need nothing new.
- **Two built-in effects:** `bubble` (shape, corner radius, a thin edge, a soft shadow, its crop keyed to the face track) and `frame` (padding, background, corner radius, shadow), replacing the editor's shader.
- **Face track per camera take**, measured once in the footage index at 5 fps and smoothed, so the bubble never waits on Vision while you scrub.

## Phases

1. `bubble` and `frame` effects, the face-tracked bubble, the `layout` edit function, and the editor's skills using it.
2. The Layout control in Screening and Changes, with its lock.
3. The question at import.

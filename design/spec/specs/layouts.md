# Layouts

Built 31 Oct 2026, the day the director asked to "add my video over here or not" without waiting for the editor, the way Screen Studio changes a recording's layout without AI.

## Why

Three of the first film's four notes asked for the same thing: "an overlay of my talking head bottom right, 1:1, rounded edges and a shadow". The editor built it by hand each time: a cutaway of the synced camera on V2, a transform and crop, a Metal shader it wrote for the corners (`Editor/Effects/rounded.metal`) and a shadow image. It's a minute of the editor's time and a turnover's wait for something that needs no judgment, and the director can't just try "bottom left" and look.

## What a layout is

For a stretch of the cut where a screen recording and a camera are in sync (a sync group, footage-index.md), how they share the frame:

| Layout | What shows |
|---|---|
| **Screen and you** | The screen, with you in a bubble. Corner: any of four, 4 % of the frame's height in from both edges. Size: S · M · L (22, 28, 36 % of the frame's height). Shape: Circle · Rounded (a square) · Wide (16:9). A thin light edge and a soft shadow. |
| **You** | The camera, full frame. |
| **Screen** | The screen alone. |
| **Side by side** | You and the screen, split. |

**Screen framing**, for Screen and Screen and you: **Full**, or **Framed**, the screen smaller on a background (the style's background, or a color) with rounded corners and a shadow. Note 3 asked for this ("frame this with some padding and a background").

**The bubble follows your face.** Apple's Vision finds the face in each camera take about once a second (`LayoutAnalysis.faceTrack`), once, kept in the film's cache. The bubble crops the camera to its shape around the face (about two fifths of its height, a little above the middle), one size for each stretch, and its middle eases after the face with a key at most every two seconds, only when it moved, so leaning back carries the bubble with you without it twitching. Vision runs on this Mac and ships with macOS; no Python or download is needed. On the director's 17-minute 4K camera take the first search took 41 s; every change after it, 0.1 s. The search starts when the Layout button first shows, so it's usually done before the first change.

**Which take is which.** A take named for a camera ("camera-…", "webcam") is the camera. Otherwise the camera is the take with the biggest face over five frames, and the rest are screens: a screen recording often shows the person too (a camera preview, a video of them). With no face anywhere, a name or shape that looks like a screen recording decides.

Layouts cut from one to the next. Animating between them (the bubble sliding and growing into full frame over 10 frames) is still to come.

## Where the director sets it

**Under the picture** in Notes, Changes and Finish (the transport's last button, after Mark), when the film has a camera and a screen recording in sync: a drawing of the layout at the playhead. Click it for the picker:

- The four layouts, drawn from the same geometry the renderer uses.
- For Screen and you: Corner (four dots), Size (S · M · L), Shape (Circle · Rounded · Wide).
- Screen: Full · Framed.
- **Apply to:** Scene (the scene at the playhead, the default), Selection (the range ⌥-dragged on the strip, offered when there is one), or Film.
- Under them: "Changes the cut at once. ⌘Z undoes.", or why it can't now ("The editor is making the next cut.", "Picture is locked.", "Layouts change Cut 3. Watch it to change them.").

Every choice applies at once: the director's own revision of the latest cut (`TimelineStore.directorEdit`), which the cut then plays, recorded as theirs (`EditResult.byDirector`). No editor run, no turnover. ⌘Z puts the cut back while nothing else has changed since (`undoDirectorEdit`); ⌘⇧Z lays it out again. While the editor is making the next cut, the latest cut can't change.

**In Dailies**, a take in sync with others shows **In the cut** under Angles: the film's layout (Screen and you in each corner, Side by side, You, Screen; Screen and you · bottom right until chosen). The editor's job says it, and the assembly lays out the cut with it.

## The editor

- One edit function, `layout(range, kind, bubble?, screen?)`, instead of cutaways, crops and shaders. "Put me bottom right" becomes one call, and the made-shot answer to note 2 ("the talking head becoming an overlay in the bottom right") is a layout change.
- A layout the director set is the director's. The editor can't change it (`layout_is_yours`) unless a note asks, the same rule as words and looks.
- `direction_timeline` lists layouts by range, so the editor reads them as layouts, not as the clips they make.

## How it's built

- **Clips, not a new kind of data:** a layout is the screen on V2 and the camera on V3 (or the one take a layout needs, on V2), synced cutaways like any other, each carrying `Clip.layout` (the layout, its role, whether the director set it). Direction keeps them in sync through every edit; the renderer, export and OTIO need nothing new. `Sequence.layout(at:)` and `layoutSpans` read them back; the timeline outline lists them as "Layout 00:00:00–01:00:00 Screen and you · bottom right (the director's)".
- **What a layout replaces:** over its range, an earlier layout and any synced picture from the story's own takes (the editor's hand-made bubbles). Layouts sit just over the story: anything else on V2–V3 there moves up, with everything above it.
- **One built-in effect, `card`:** rounded corners or a circle, a thin edge, a soft shadow and an optional background, replacing the editor's shader. The framing is an ordinary `transform` (crop, scale, x, y), keyed where the face moves.
- **The editor's way in:** `direction_edit` with `layout`; Direction measures before it runs (`LayoutMeasure`: cameras, screens, faces).

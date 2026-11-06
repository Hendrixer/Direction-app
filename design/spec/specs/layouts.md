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
| **Side by side** | You and the screen, split: the screen on the left 64 %. In a frame taller than it's wide (9:16, 4:5) it's **Stacked**: the screen across the top, as tall as a 16:9 screen needs (at most 64 %), and you under it. The picker draws its tiles in the cut's shape. |

**Screen framing**, for Screen and Screen and you: **Full**, or **Framed**, the screen smaller on a background (the style's background, or a color) with rounded corners and a shadow. Note 3 asked for this ("frame this with some padding and a background").

**The bubble follows your face.** Apple's Vision finds the face in each camera take about once a second (`LayoutAnalysis.faceTrack`), once, kept in the film's cache. The bubble crops the camera to its shape around the face (about two fifths of its height, a little above the middle), one size for each stretch, and its middle eases after the face with a key at most every two seconds, only when it moved, so leaning back carries the bubble with you without it twitching. Vision runs on this Mac and ships with macOS; no Python or download is needed. On the director's 17-minute 4K camera take the first search took 41 s; every change after it, 0.1 s. The search runs the first time the editor lays out a cut with a camera in it.

**Which take is which.** A take named for a camera ("camera-…", "webcam") is the camera. Otherwise the camera is the take with the biggest face over five frames, and the rest are screens: a screen recording often shows the person too (a camera preview, a video of them). With no face anywhere, a name or shape that looks like a screen recording decides.

Layouts cut from one to the next. Animating between them (the bubble sliding and growing into full frame over 10 frames) is still to come.

## In a style

A style names its own layouts (styles.md › A style on disk): each one a layout above plus a name and, for the bubble, an `edge` color drawn solid so it reads as you, not as part of the screen. Desk + Screen has Talking (You), Showing (Screen and you, bottom right, M, rounded) and Detail (Screen); Reaction has Reacting and Corner clear (L, yellow edge). Its rules say when each is used. A style without layouts takes the house style's; with none anywhere, the four above.

- A style's page draws its layouts, by name.
- The editor names them (`layout: "Showing"`); Direction looks the name up in the film's style before it runs.

## The director's part

The director doesn't pick layouts. On 2026-11-05 the user took out the Layout button under the picture, its picker, and Dailies' **In the cut**: they were there for one way of shooting (a desk and a screen) and nobody used them. A layout changes the way everything else in the cut does: with a note ("put me bottom right here", "show only the screen while I type"), which the editor answers with a layout and the director watches. The style says which layouts a film uses and when, and its rules hold.

Layouts the director set before then stay theirs (`layout_is_yours` below), and the director's own revisions with them still undo.

## The editor

- One edit function, `layout(range, layout)`, with the style's name for one or its parts, instead of cutaways, crops and shaders, even where a style's rule describes a corner camera. "Put me bottom right" becomes one call, and the made-shot answer to note 2 ("the talking head becoming an overlay in the bottom right") is a layout change.
- **A layout owns only where its clips sit.** The editor's own work on them stays when the layout changes: a zoom on the screen (its transform), masks and blurs over something private, filters, a freeze. What placed them goes: an earlier layout's place and card, and a bubble made by hand (a camera scaled under 1×, its shader).
- A layout the director set (before 2026-11-05) is the director's. Where its clips sit can't change (`layout_is_yours`: a new layout over it, their place or card, a bubble's transform, moving or cutting them) unless a note asks, the same rule as words and looks. The editor can still zoom the screen, blur or mask what's private, and freeze it, as the style asks.
- `direction_timeline` lists layouts by range, so the editor reads them as layouts, not as the clips they make.

## How it's built

- **Clips, not a new kind of data:** a layout is the screen on V2 and the camera on V3 (or the one take a layout needs, on V2), synced cutaways like any other, each carrying `Clip.layout` (the layout, its role, whether the director set it). Direction keeps them in sync through every edit; the renderer, export and OTIO need nothing new. `Sequence.layout(at:)` and `layoutSpans` read them back; the timeline outline lists them as "Layout 00:00:00–01:00:00 Screen and you · bottom right (the director's)".
- **What a layout replaces:** over its range, an earlier layout and any synced picture from the story's own takes. Pieces of a take the new layout still shows carry on (trimmed to the range, new ids where they're split), moved into it; the rest give way. Layouts sit just over the story: anything else on V2–V3 there moves up, with everything above it.
- **Two built-in effects.** `card`: rounded corners or a circle, a thin edge (or a solid one in `edgeColor`), a soft shadow and an optional background, replacing the editor's shader. `place`: part of the clip's finished picture into a rectangle of the frame, after its transform and other effects, so a zoom or a blur plays inside a framed screen. A smaller screen is placed with `place`; a bubble is framed on the face with its `transform` (crop, scale, x, y, keyed where the face moves), read from the take itself so it stays sharp.
- **The editor's way in:** `direction_edit` with `layout`; Direction measures before it runs (`LayoutMeasure`: cameras, screens, faces).

# Graphics

Frame 64. Read `product-model.md › Graphic, GraphicWord` first.

Titles, lower thirds, end cards, chapter cards, quotes, counters, maps, charts: the editor writes them as small web pages in JavaScript, and Direction renders them frame by frame on a clock it controls. No template app, no Remotion, no hand-off. Agents write this kind of code well, especially with examples, so Direction ships examples and a strict contract.

---

## The contract

A graphic is a folder in the film: `Editor/Graphics/<name>/` with `index.html` and any files it uses (images, fonts, data). Direction injects its runtime as the first script.

```html
<!doctype html>
<html><head><meta charset="utf-8">
<link rel="stylesheet" href="style.css">
</head><body>
<h1 id="title"></h1>
<script>
direction.graphic({
  duration: 4,                                        // seconds
  words: { title: { label: "Title", text: "Two years.", max: 40 } },
  render(t, words) {                                   // a pure function of t (seconds) and words
    title.textContent = words.title;
    title.style.opacity = direction.ease.inOut(direction.clamp((t - 0.3) / 0.6));
  }
});
</script>
</body></html>
```

- `render(t, words)` must draw the whole frame for time `t`. It may be async (return a promise).
- CSS animations, CSS transitions and the Web Animations API also work. Direction pauses the document timeline and sets every animation's `currentTime` to `t` before each frame.
- Canvas 2D, SVG, WebGL and WebGPU work.
- `direction.ease` (linear, in, out, inOut, spring), `direction.clamp`, `direction.lerp`, `direction.random(seed)` are provided.
- **Words** are the fields the director may change (frame 64). Every visible word in a graphic should come from `words`, not be hard-coded.
- Libraries bundled with the app, offline: GSAP, anime.js, d3, three.js, lottie-web. Load them as `direction:lib/gsap.js`. Nothing loads from the internet.
- Fonts: system fonts, Archivo (bundled), and font files in the graphic's folder.

## How Direction renders a graphic

- An offscreen `WKWebView` at the sequence's pixel size (device pixel ratio 1), with a transparent background.
- Time is Direction's: `Date.now`, `performance.now` and `requestAnimationFrame` are replaced by the runtime and advance only when Direction asks for the next frame. `Math.random` is seeded per graphic.
- For each frame: set `t`, await `render`, await `document.fonts.ready`, take a snapshot with alpha.
- Frames are cached as a ProRes 4444 file in `Renders/Graphics/<name>-<hash>.mov`, where the hash covers the folder's files and the words. Playback uses the cache; until it's ready, the picture shows "Preparing picture".
- The page is served through a private URL scheme that only returns its own folder, the runtime and the bundled libraries. Network requests are blocked with a content rule list.
- A frame that takes longer than 2 s, or a page that throws, fails the render with the error and line.
- A graphic's track is above the look by default (`aboveLook`), so the director's look doesn't tint titles. The editor can turn that off for graphics that should feel in the world.

## Tools

| Tool | Arguments | Returns |
|---|---|---|
| `direction_graphic_examples` | `name?` | The list of examples, or one example's full source |
| `direction_graphic` | `name`, `note`, `check?` | Checks and renders the graphic in `Editor/Graphics/<name>/`. Returns stills at 0, 25, 50, 75 and 100%, console errors, render time per frame, and problems: words that overflow their box, anything outside title safe (90%), text under 24 px at 1080p, contrast under 4.5:1 against the picture behind it. |
| `direction_edit` | `placeGraphic` | Places it on V2 or above (shown in the timeline as a `GeneratorReference`, `direction.graphic`) |

The editor's `make-graphic` skill says: start from the closest example, keep every visible word in `words`, run `direction_graphic` and look at the stills before placing it, and fix every problem it reports.

### Examples shipped with the app

Title card · Lower third · Chapter card · End card · Quote · Kinetic words · Counter · Map line · Simple chart · Logo sting · Credits roll · Captions style. Each is plain, well-commented source that uses Gate's restraint by default: one typeface, generous space, short, calm motion.

## The director's side

Graphics arrive as answers to notes, with a diamond like every other change. A graphic answer on the Cut room's sheet has a **Words** button. Words are the director's to fix directly, without a turnover: a typo in a title shouldn't cost a round trip.

### 64 · Changes, a title's words
Frame: `screens/64-changes-graphic.html` · 1440 × 900.

The Cut room on Cut 4 with note 8's answer selected. Note 8 (Story, on Scene 1): "Put a title over the cold open: two years." Answer: "Added a title over the street wide: “Two years.” In at 00:02, out at 00:06." Delta: "title".

- The picture shows the title rendered over the street wide (`f-night`): "Two years." centered low, Archivo 700 at 64 px, white at 92%.
- The answer card has, beside Accept and Not quite, a **Words** button (`.btn`, text-cursor icon).
- Clicking Words opens a popover (300 wide, `.pop`) anchored to the button:
  - Section label "WORDS".
  - One `.input` row per word field with its label above it in 11.5 text-3: "Title" with "Two years, alone." being typed (the caret visible).
  - A counter under the field, right-aligned, SF Mono 11 text-4: "17 / 40".
  - Note, 11.5 text-3: "The editor won't change these unless a note asks."
  - Buttons: Cancel (plain) · **Change Words** (steel).
- Change Words re-renders the graphic (about 1 s for a 4 s title on this Mac; the picture shows "Preparing picture" until then), records "You changed the words of the title" in History, and is undoable with `⌘Z`. It doesn't make a new cut.

**Acceptance:**
- [ ] Two renders of the same graphic and words are byte-identical.
- [ ] A graphic that requests the internet fails its check with "Graphics can't use the internet" and the URL.
- [ ] Words longer than `max` can't be typed.
- [ ] After the director changes words, `direction_edit` refuses to change them (`words_are_yours`) unless the batch lists a note that names the graphic.

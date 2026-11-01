# Graphics

Titles, lower thirds, chapter cards, end cards, quotes, counters, maps, charts, logo stings, credits and captions are small web pages the editor writes in JavaScript. Direction renders them frame by frame on a clock it controls, caches the result as ProRes 4444 with alpha, and registers it as an asset the timeline places like footage. The director can fix the words directly. Product spec: `design/spec/specs/graphics.md` (frame 64).

## The contract

A graphic is a folder in the film: `<film>.direction/Editor/Graphics/<name>/`. The name is the folder's: lowercase letters, digits, dashes and underscores (`title`, `lower-third-maya`). The folder holds `index.html` and any files it uses (CSS, images, fonts, JSON).

```html
<!doctype html>
<html><head><meta charset="utf-8"><link rel="stylesheet" href="style.css"></head>
<body>
<h1 id="title"></h1>
<script>
direction.graphic({
  duration: 4,                                              // seconds, up to 120
  words: { title: { label: "Title", text: "Two years.", max: 40 } },
  render(t, words) {                                        // a pure function of t (seconds) and words
    title.textContent = words.title;
    title.style.opacity = direction.ease.inOut(direction.clamp((t - 0.3) / 0.6));
  }
});
</script>
</body></html>
```

- `render(t, words)` draws the whole frame for time `t`. It may be async. Frames can be asked for in any order.
- `words` maps a key to `{ label, text, max }`. `label` is what the director sees, `max` is how many characters the layout holds. `render` receives `{ key: text }` with the director's words in place of yours where they set them.
- Every visible word comes from `words`. When an element shows a word in another form (a counting number, quote marks the layout adds, a split sentence), put `data-word="<key>"` on it or an ancestor.
- Helpers: `direction.ease.linear | in | out | inOut | spring` (0–1 in, 0–1 out; spring overshoots about 9% and settles at 1), `direction.clamp(x, lo = 0, hi = 1)`, `direction.lerp(a, b, t)`, `direction.random(seed)` (returns a seeded generator), `direction.width`, `direction.height`, `direction.words`.
- Canvas 2D, SVG, WebGL and WebGPU work. CSS animations, CSS transitions and the Web Animations API work: Direction pauses each animation and sets its `currentTime` from `t` (relative to the frame it first appeared, so a transition a render starts plays from 0).
- Watch for globals: element ids become window properties only when nothing else owns the name. `id="name"` is `window.name`, a string; `const top` is a syntax error. The examples use other names.

### The clock

Direction injects its runtime (`Sources/DirectionMedia/Graphics/Web/runtime.js`) before any page script. Time is Direction's:

- `Date.now()`, `new Date()` and `performance.now()` return the frame's time (dates start at 2026-01-01 00:00 UTC + `t`).
- `requestAnimationFrame` callbacks run once per frame, with the frame's time in milliseconds, before `render`.
- `Math.random` is seeded from the graphic's name.
- Timers (`setTimeout`, `setInterval`) keep real time. Don't animate with them; they're not part of the frame.

With that, two renders of the same files and words are byte-identical (the movie's creation stamps are zeroed too).

### Libraries and fonts

Bundled, offline, at exact versions (licenses in `THIRD_PARTY_NOTICES.md`):

| Load | Library | Global |
|---|---|---|
| `<script src="direction:lib/anime.js">` | anime.js 4.5.0 (UMD) | `anime` (`anime.animate`, `anime.createTimeline` …) |
| `<script src="direction:lib/d3.js">` | d3 7.9.0 | `d3` |
| `<script src="direction:lib/three.js">` | three.js 0.186.1 (r186), one classic script | `THREE` |
| `import * as THREE from "direction:lib/three.module.js"` | the same three.js as one ES module | — |
| `<script src="direction:lib/lottie.js">` | lottie-web 5.13.0 | `lottie` |

Run every library on Direction's clock: build animations paused and seek them in `render` (anime.js `animate(target, { …, autoplay: false })` then `.seek(t * 1000)`; lottie `loadAnimation({ autoplay: false, animationData })` then `goToAndStop(t * 1000)`; three.js `renderer.render(scene, camera)` once per `render`, with `preserveDrawingBuffer: true`). GSAP isn't bundled (its license question in `open-questions.md` is open); use anime.js.

Fonts: Archivo is bundled (`font-family: 'Archivo'`, weights 100–900, widths 62–125% via `font-stretch`), system fonts work, and font files in the folder load with `@font-face`. Direction waits for `document.fonts.ready` before each frame.

Scripts from `direction:lib/` are a different origin than the page, so an error inside a library reads "Script error." Add `crossorigin` to the script tag to see the library's own message.

## How Direction renders it

- An offscreen `WKWebView` at the main sequence's pixel size, device pixel ratio 1, transparent background, no window. It runs in whichever process calls the tool: the app, or the `direction` command-line helper that serves MCP (its async main runs the main run loop, which is all WebKit needs, so no helper app process is involved).
- The page is served from `direction://graphic/` by a private URL scheme that returns only the graphic's folder, Direction's runtime, the bundled libraries (`direction:lib/…`) and fonts (`direction:fonts/…`). Everything else is a 404 (reported as a console error).
- Network requests are blocked by a content rule list (`^https?://`, `^wss?://`, `^ftp://`) and by a Content-Security-Policy on every page (`default-src 'self' direction: data: blob: 'unsafe-inline' 'unsafe-eval'`). Navigations away are refused. Any of them fails the check: "Graphics can't use the internet: <url>".
- Per frame: set `t`, run animation-frame callbacks, await `render`, seek animations, await fonts, snapshot with alpha. A frame whose page takes longer than 2 s to draw fails ("The frame at 2.40 s took longer than 2 s to draw."). The snapshot after it is Direction's and has 10 s of its own, so a busy Mac doesn't fail a page that's fine. A page that throws fails with the file and line ("index.html:24: …").
- Frames are written as ProRes 4444 with alpha (premultiplied BGRA in, tagged Rec. 709) to `<film>.direction/Renders/Graphics/<name>-<hash>.mov`. The hash covers every file in the folder, the words, the picture size and rate, and the runtime and libraries, so a cached file is reused only when nothing that changes a pixel changed.
- About 5 ms a frame at 1080p on an M-series Mac: a 4 s title at 30 fps renders in about a second.

## Tools

### `direction_graphic_examples` `{ name? }`

Without `name`: the list of examples (`name`, `title`, `summary`, `libraries`), the film's graphics folder, the contract in a paragraph, the libraries and the fonts. With `name` (`title-card` or `Title card`): every file of that example with its source. Copy the files into `Editor/Graphics/<name>/` and change them.

Examples: Title card · Lower third · Chapter card · End card · Quote · Kinetic words · Counter (anime.js) · Map line (d3) · Simple chart (d3) · Logo sting (three.js) · Credits roll · Captions style. They live in `Sources/DirectionMedia/Graphics/Web/examples/` and each one checks clean.

### `direction_graphic` `{ name, note, check? }`

Checks and renders `Editor/Graphics/<name>/`. `note` is the note it answers: an id, a number, or `"unasked"`. `check: true` makes the stills and runs the checks without rendering the movie.

Returns:

- `words`: `key`, `label`, `text` (what renders), `max`, `setByDirector`.
- `stills`: PNGs at 0, 25, 50, 75 and 100% (also sent as images over MCP), composited over the picture behind the graphic, or dark steel when Direction doesn't know where it plays.
- `problems`: `{ code, message, word?, at? }`, each reported once:
  - `overflow`: words don't fit their own box (the nearest block around them is too narrow to wrap them, or holds fewer lines), or run off the picture. Text hidden by a clipping ancestor (a reveal mask, a credits window) isn't checked; only what shows is.
  - `outside_title_safe`: visible text outside the middle 90% of the picture.
  - `small_text`: text under 24 px at 1080p (font size × transforms, scaled to a 1080-line picture).
  - `low_contrast`: under 4.5:1 (WCAG) against what's right behind it: its own backing colors, composited over the picture behind the graphic when the backing isn't opaque. The picture comes from where the graphic is placed, else from the note's moment; `picture` in the result says which, or why contrast against the picture wasn't checked. Text over a gradient or image backing isn't checked. Only text at 50% opacity or more is checked.
  - `too_long`: a word longer than its `max`.
  - `not_in_words`: visible text with letters that isn't one of the words (or inside `data-word`). Numbers alone are data, not words.
  - Text drawn into a canvas or WebGL can't be measured; draw words as HTML or SVG text.
- `consoleErrors`: `console.error` calls, files that didn't load, missing files.
- `frameTimes`: `milliseconds` per frame drawn (render plus snapshot), `slowest`, `average`.
- `movie` (unless `check`): `path`, `cached`, `frames`, `width`, `height`, `frameRate`, `codec`; `assetID` and `editRevision`.
- `next`: what to do now.

Errors: `invalid_name`, `graphic_not_found`, `note_not_found`, `graphic_internet`, `graphic_threw`, `graphic_frame_timeout`, `graphic_not_declared`, `invalid_graphic`, `words_are_yours`.

## Assets and placement

The first render adds an asset to the film (a new edit revision, "Added the graphic title"): a ProRes 4444 movie with alpha whose `name` is the graphic's name. `ProjectStore.graphicAssetID(name)` returns its id; `placeGraphic` places it like footage on V2 or above. `ProjectStore.graphic(assetID:)` goes the other way, for the timeline's `GeneratorReference` (`direction.graphic`, `parameters.graphicID` = the name) and its outline (`graphic.displayName`, "Title · Two years.").

The asset keeps its id for the life of the graphic. A re-render updates the asset in a new revision only when its length or picture size changed. Otherwise, and always for the director's words, nothing in the timeline changes: every read of the film (`ProjectStore.read`, any revision) swaps in the graphic's current render (path, size, date; bookmark cleared). So a cut pinned to an older revision plays the new words without a new cut, and export, frames and playback agree.

## The director's words

Graphic answers in Changes have a **Words** button (frame 64). The popover has a field per word with its label and a counter ("17 / 40"); words longer than `max` can't be typed. **Change Words** re-renders (the picture shows "Preparing picture" until it's ready), saves the words as the director's, records "You changed the words of the title" in History and is undoable with ⌘Z. It doesn't make a new cut.

After that, the editor can't change those words:

- The editor changes words by changing what its page declares. A director-set word whose declared text changes (or that disappears) needs a note, passed as `note`, that the director wrote or replied on **after** changing the words and that names the graphic (its name, a word's label, or the director's words).
- Without one, `direction_graphic` fails with `words_are_yours` and says which words to keep. With one, the editor's words stand and that word is no longer the director's.
- Running the page unchanged keeps the director's words: they're passed in over the page's own.
- `ProjectStore.checkGraphicWords(name, declared:, noteID:)` is the same check, for `direction_edit`.

## Where it lives

| Path | What |
|---|---|
| `Sources/DirectionCore/Phase2/Graphics/` | The `graphics` table (name, folder, words, director_words, asset_id, note_id), `Graphic`, `GraphicWord`, the words lock, `graphicAssetID`, current renders in every revision |
| `Sources/DirectionMedia/Graphics/` | `GraphicPage` (WebKit, the scheme, the rule list), `GraphicMovieWriter` (ProRes 4444), `GraphicChecks`, `GraphicMaker` (check, render, cache, register), `GraphicResources` |
| `Sources/DirectionMedia/Graphics/Web/` | `runtime.js`, `lib/` (and `lib/licenses/`), `fonts/`, `examples/` |
| `Sources/DirectionTools/Phase2/GraphicsTools.swift` | The two tools |
| `Sources/DirectionApp/Phase2/Graphics/` | `GraphicsModel`, the graphic answer stage, the Words popover, frame 64's fixture |
| `plugins/direction/skills/make-graphic/SKILL.md` | The editor's routine |

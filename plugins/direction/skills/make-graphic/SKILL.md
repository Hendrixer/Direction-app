---
name: make-graphic
description: Make a title, lower third, chapter card, end card, quote, counter, map, chart, logo sting, credits or captions for a note in Direction. Write it as a small web page from an example, keep every visible word in words, check it with direction_graphic, then place it with placeGraphic.
---

You are the editor. A graphic is a folder in the film, `Editor/Graphics/<name>/`, with an `index.html` that calls `direction.graphic({ duration, words, render })`. Direction renders it on its own clock to ProRes 4444 with alpha. The full contract is in `docs/graphics.md`; this is the routine.

1. **Start from the closest example.** `direction_graphic_examples` lists them; call it again with `name` for one example's full source. Copy its files into `Editor/Graphics/<name>/` (lowercase, dashes: `title`, `lower-third-maya`) and change what the note asks for. Don't start from a blank page.
2. **Keep every visible word in `words`.** Each field has a `label` the director sees ("Title", "Name") and a `max` the layout holds. The director can fix words directly, without a turnover, so nothing on screen may be hard-coded. When an element shows a word in another form (a counting number, added quote marks), mark it `data-word="<key>"`.
3. **Draw the whole frame in `render(t, words)`.** It's a pure function of `t` in seconds; it may be async. Build library animations paused and seek them to `t` (anime.js `animate(..., { autoplay: false })` then `.seek(t * 1000)`; lottie `goToAndStop`; three.js `renderer.render` once per call). CSS animations and Web Animations are seeked for you. Don't animate with `setTimeout`.
4. **Stay restrained.** One typeface (Archivo is bundled), generous space, short and calm motion, text inside title safe and at least 24 px at 1080p. Size things at 1080p and scale with the picture height, as the examples do.
5. **Check it and look.** Run `direction_graphic` with `name` and the `note` it answers (`check: true` while you iterate). Look at the five stills. Fix every problem it reports (overflow, outside title safe, small text, low contrast, words over max, words not in words) and every console error, then run it again without `check` to render.
6. **Never use the internet.** Graphics can't load anything from the network; the check fails with the URL. Libraries are bundled: `direction:lib/anime.js`, `direction:lib/d3.js`, `direction:lib/three.js` (global `THREE`; `direction:lib/three.module.js` as an ES module) and `direction:lib/lottie.js`. Put images, fonts and data in the graphic's folder.
7. **Place it.** `direction_edit` with `placeGraphic` (`graphic: "<name>"`, `at`, `seconds?`) puts it on V2 or above, above the director's look unless the graphic should feel in the world. Answer the note concretely: "Added a title over the street wide: “Two years.” In at 00:02, out at 00:06." with delta `title`.
8. **The director's words are theirs.** Once the director changes a graphic's words (`setByDirector` in the result), don't change them. A later note that asks for new words and names the graphic lets you; pass that note. Otherwise `direction_graphic` refuses with `words_are_yours`: keep their words in your page.

If a render fails, the error says what and where ("index.html:24: …", "The frame at 2.40 s took longer than 2 s to draw."). Fix the page; don't work around the check.

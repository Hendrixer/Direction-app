# Direction marketing site

Live at https://givedirection.ai (and www). It's a static site with no build step: everything that ships is in `public/` (`index.html`, `css/site.css`, `js/site.js` for the nav, rooms and notes player, and `js/mark.js` for the lit chrome D, ported from `Sources/DirectionApp/Gate/ChromeMark.swift` to WebGL2).

## Preview and publish

```sh
python3 -m http.server 4321 --directory site/public   # or the "site" entry in .claude/launch.json
cd site && npm install                                 # once: cf and wrangler
cd site && npx cf deploy                               # publishes to givedirection.ai
```

- **Deploying.** It's a Cloudflare Worker that only serves static assets: `cloudflare.config.ts` names the Worker (`direction-site`) and its domains, and `wrangler.config.ts` points the assets at `public/`. `public/_headers` sets the security headers, plus long caching for the font.
- **The changelog** (`/changelog/`) is built from `changelog/<version>.md`, one file per version.
  - Each file has frontmatter (`version`, `date`, `build`, `title`, and an optional `hero` naming a picture in `changelog/heroes/`), then Markdown.
  - Everything before the first `## ` is the write-up. Each `## Improvements` or `## Fixes` after it becomes a row that opens.
  - `node tools/changelog.mjs` writes `public/changelog/index.html` and `feed.xml`. `notes <version>` prints the GitHub release notes, and `sparkle <version>` prints the update's "What's new".
  - `scripts/release.sh` and `scripts/publish-release.sh` use it, so a release gets its tag, GitHub release and changelog entry from that one file (`docs/releasing.md`).
  - Write it in plain words: no crew shorthand.
- **Sharing and search.**
  - The head of `index.html` has the canonical URL, Open Graph and X card tags, and JSON-LD (WebSite, SoftwareApplication, FAQPage). The FAQ answers in the JSON-LD must match the FAQ on the page.
  - `public/robots.txt` and `public/sitemap.xml` sit beside the page. Update the sitemap's `lastmod` when the page changes.
- **The share image and icons** (`og.jpg`, `apple-touch-icon.png`, `favicon-32.png`) are drawn from `tools/og.html`. To redraw them, run `sh site/tools/render-og.sh` (it needs Google Chrome).
- **The pictures are stand-ins.** `tools/scenes.mjs` draws them as SVG (`node site/tools/scenes.mjs` rewrites `public/img/*.svg`). Replace them with frames and short loops from a real film made in Direction.
- **Grain** is the app's own tile (`img/grain.png`, the same xorshift noise as `Gate/Primitives.swift`). It sits behind UI surfaces at about 4% and on steel buttons at 18%, and never covers a picture.
- **Download** links go to `https://updates.givedirection.ai/Direction.dmg`, the release Sparkle publishes (see `docs/releasing.md`).
- **The font** is `fonts/archivo.woff2`: Archivo cut down to weights 400–800, widths 100–125% and Latin characters, about 47 KB.
- **Colors carry meaning, as in Gate.** Amber is the director (notes, pins, circled takes, @mentions). The prism and ion blue are the editor.
- **With Reduce Motion on**, nothing animates: the rooms and notes show their finished state, and the mark is a still image.

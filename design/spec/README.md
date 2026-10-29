# Direction: implementation spec

This folder is the complete design for Direction, built on the Gate design language. It replaces `design/gate/` as the source to implement from. It is not based on the current app's layout. Build these screens; don't adapt the existing ones.

## What's here

| Path | What it is | Use it for |
|---|---|---|
| `product-model.md` | Objects, lifecycles, vocabulary, agent rules | What the app **does**. Read first. |
| `tokens.json` | Every color, type, space, radius, motion value | Generate `GateTokens.swift` from it. Don't hand-copy values. |
| `gate.css` | The same tokens plus every shared component, in CSS | The exact recipe for each component (padding, radius, shadows, states). |
| `css/*.css` | Room-specific components (start, notes, changes, system) | Recipes for components that appear in one room group. |
| `specs/story.md` | The sample film every frame shows | Preview data and test fixtures. |
| `specs/open-questions.md` | Cross-room decisions | Wins over room specs when they disagree. |
| `specs/editor.md`, `footage-index.md`, `agent-timeline.md`, `looks.md`, `graphics.md`, `made-media.md` | Phase 2: Direction starts the editor; how it sees footage; its timeline; looks, graphics and made media | Frames 54–64 and the editor's tools. `agent-timeline.md` has no frames: it's the editor's side. |
| `specs/mac.md` | Mac conventions: windows, Settings (⌘,), titlebar double-click, menus, undo, keyboard, Dock, notifications, accessibility | Applies to every room. |
| `screens/NN-*.html` | One frame per screen or state, 1440×900 pt unless noted | The exact picture to match. |
| `renders/NN-*@1x.png`, `@2x.png` | Renders of each frame. Only 1x is committed; run `./render.sh` to make the 2x set (needs Google Chrome). | Visual comparison against your build. |
| `renders/NN-*.layout.json` | Boxes of every `data-c` element: x, y, w, h, color, radius, font | Measurements. No guessing from pixels. |
| `specs/*.md` | Per-room specs: flow, copy, interactions, keys, motion, accessibility, acceptance checks | Behavior that a picture can't show. |
| `specs/components.md` | Component inventory mapped to SwiftUI | Build these once, reuse everywhere. |
| `specs/icons.md` | Each icon id mapped to an SF Symbol | Use SF Symbols in the app, not the SVGs. |
| `index.html` | Gallery of every frame | Open in a browser to browse. |
| `render.sh` | Re-renders frames | `./render.sh` or `./render.sh 17-notes-drafts` |

## How to implement (for the implementing agent)

1. Read `product-model.md` and `specs/components.md` completely.
2. Generate tokens from `tokens.json`. CSS px equal macOS points. OKLCH values convert to sRGB with the formula in `tokens.json › meta.oklch`; the precomputed `srgb` hex is included for every color.
3. Build the components in `specs/components.md`, each with all of its states, before any screen.
4. Build screens in frame order. For each frame:
   - Open the HTML. It is the source of truth for structure; the CSS gives exact values.
   - Read the frame's section in its spec file (each frame lists its spec in `frames.js`).
   - Build it in SwiftUI with real data models from `product-model.md`. Put any copy you see in the frame in the app exactly as written.
   - Screenshot the app window at 1440×900 pt with the same state and compare it with `renders/<id>@2x.png`. Check every box in `renders/<id>.layout.json` within ±2 pt and every color as an exact token. Fix and repeat until it matches.
   - Tick the acceptance checks in the spec.
5. Anything not drawn (hover on every row, every error) follows the component's states in `specs/components.md`. Don't invent new components, colors or copy. If something is missing, add it to `specs/open-questions.md` and use the closest documented pattern.

## Ground rules that apply everywhere

- **Picture is brightest.** UI surfaces stay in steel-0 to steel-5. Nothing beside the frame glows.
- **Two voices.** Amber (`--director`) and the pin, ring and hand-drawn circle shapes belong only to the director's acts: marks, notes, circles, ranges, regions, note numbers. The diamond plus prism (fine lines ≤2 pt) or ion blue (text) belong only to the editor (agent). Outside people are neutral steel with a person icon.
- **One steel button per window state.** It's the primary action of the room, at the right of the titlebar.
- **Rooms** are a titlebar segmented control: Dailies, Script, Screening, Notes, Changes, Finish. `⌘1`…`⌘6`.
- **The editor pill** at the titlebar's right is always present and always truthful: Ready, Reading back, Cutting 3 of 6 (shimmer), 2 questions, Can't do 1, Offline.
- **Nothing moves during playback** except the playhead and time.
- **Reduce Motion:** replace shimmer with a static prism edge, the sweep with an instant edge that fades over 220 ms, and slides with fades.
- **Fonts:** SF Pro for UI (13 pt body), SF Mono for every timecode and count, Archivo (bundled, width 112–125%, weight 700–800) only for room headings, film and cut names, and empty-state titles.
- **Grain:** a 180 pt noise tile at 3.5% opacity, screen blend, over the whole window. It's not drawn over the picture inside the frame.

## Frame conventions

- The body of each HTML is the window's content view at 1×. The titlebar is part of the content (full-size content view, transparent titlebar, traffic lights at x 20). The traffic lights are drawn only as placeholders.
- Footage is drawn with CSS gradients (`.f-dusk`, `.f-room` …). In the app these are real video frames.
- Sheets are drawn attached under the titlebar over a 55% black scrim.
- `data-c` attributes name the component each element is, matching `specs/components.md`.

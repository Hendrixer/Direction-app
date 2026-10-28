# Direction's visual system and review comments

The app uses the approved icon export from Scott's Documents/Direction Icon folder. Resources/AppIcon.icns is the unmodified app icon; Sources/DirectionApp/Resources/DirectionBrand.png is the unmodified transparent 1024px export used by the interface.

## Interface

- Neutral black and gray surfaces, plain comment rows, and a metallic playback control connect the editor to the icon without extending its colors across the interface.
- A deterministic, cached 192px noise tile provides subtle grain on the transport and composer. It is generated once, without a per-frame noise pass.
- Video stays on a clean black canvas. Grain and chromatic accents never alter the footage or its export.
- Selected tabs and notes use neutral fills. Timecodes and range handles are silver or gray. Primary actions use a flat light fill; only the playback control uses the metallic gradient.
- The header exposes import, export, and a project-actions menu for the existing agent tools, activity, and saved-cut functions.

## Leaving a comment

1. Click the seek bar to select a moment. Playback pauses and the comment composer opens with that time.
2. Drag the small range grip beneath the playhead left or right to draw a range on the same bar. Its two endpoints can then be dragged independently.
3. The **Range** button provides a keyboard-accessible alternative, and range endpoints expose accessibility increment/decrement actions.
4. Select **Whole video** in the composer when the note applies to the entire cut. Clearing it returns to the current moment or range.
5. Saved comments retain their existing revision, source, transcript, and frame-region context.

The scope chips and raw numeric start/end fields have been removed. Changing the reviewed revision or sequence clears stale temporal and frame-region anchors while preserving an unfinished draft.

## Verification

The full scripts/test.sh run passed: 48 Swift tests, 20 CLI/JSON API/MCP checks, and 15 plugin/project lifecycle checks. Nine Swift tests cover the new comment-anchor behavior, including reverse dragging, out-of-bounds and non-finite input, scope restoration, saved-cut cleanup, focus requests, and revision changes.

Native UI verification used a separate project and library under build/ui-verification. A seek click created a moment comment; dragging and resizing a range created a range comment; the checkbox created a whole-video comment. Reading the saved comments through the CLI confirmed all three scopes and their anchors. The editor and media panel were visually inspected at both large and smaller window sizes.

The release app is packaged at build/Direction.app. The icon declaration, exact source copies, and ad-hoc code signature were verified.

The later monochrome refinement is documented in [the research record](../design/ui-refinement/research.md). It reviewed twelve product screens, Apple's materials, color, and typography guidance, Frame.io's comment workflow, and Scott's five supplied examples. The selected comment-anchor regression suite passed again after the visual changes, and seeking, range selection, and the whole-video checkbox were checked in the running release.

After unlocking the Mac, the final release was relaunched and seeking from both Transcript and Media was verified to open Comments with the text editor focused. Compact range endpoints were visually checked for separate handles and adjusted through their accessibility actions. The previous JetBlack project was reopened after the isolated verification session.

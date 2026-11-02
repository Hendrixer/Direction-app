# Direction's visual system and review comments

The app uses the approved icon export from Scott's Documents/Direction Icon folder. Resources/AppIcon.icns is the unmodified app icon; Sources/DirectionApp/Resources/DirectionBrand.png is the unmodified transparent 1024px export used by the interface.

## Interface

The current system follows [Gate 2.0](https://claude.ai/artifact/KBjd5vAbxK1p5fJFhFTG23), Scott's supplied design guide. Its extracted source and implementation mapping are in [design/gate](../design/gate/README.md). The previous monochrome app is preserved in commit `e81ec17`.

- The semantic Gate tokens define the exact OKLCH steel ramp, text hierarchy, spacing, radii, type, and motion. Compatibility Palette names bind to these roles.
- Work surfaces are black and near-neutral steel. A cached 192px noise tile supplies the guide's 3.5% window grain and 18% steel grain. Video remains clean black with no grain or tint over the picture or export: every picture (players, thumbnails, stills, looks) is marked `clearOfGrain()` and cuts itself out of the window's grain.
- Popovers are the system's, with its animation off: `gatePopover` fades the popover's window itself and scales it from 0.98 about the arrow's tip (a plain fade under Reduce Motion). The system animation steps at half the display's rate, 30 fps on a 60 Hz screen; Direction's runs at the full rate.
- Amber identifies the director's numbered notes, pins, ranges, and frame regions. Agent replies/status use a diamond and ion blue. Ordinary timecodes stay neutral.
- The titlebar separates Dailies, Screening, and Notes. Screening hides the note sheet; selecting a moment or range opens it. The strip shows actual video-clip intervals at their true proportions.
- Primary actions use steel with a bright top lip; secondary actions use raised neutral surfaces and quiet actions use ghost buttons. Native translucent material is reserved for floating HUDs.
- Archivo at its actual expanded width is bundled for room headings. Work text uses the native SF scale; paused timecodes use sequence-rate non-drop frame counts, with frames hidden during playback.
- Import, transcript editing, saved cuts, activity, agent tools, and export remain connected to existing behavior. The guide's future assembly, turnover, A/B, and lock workflows are not represented as working controls.

## Leaving a comment

1. Click the clip strip to select a moment. Playback pauses and the comment composer opens with that time.
2. Drag the small range grip beneath the playhead left or right to draw a range on the same bar. Its two endpoints can then be dragged independently.
3. The **Range** button provides a keyboard-accessible alternative, and range endpoints expose accessibility increment/decrement actions.
4. Select **Whole video** in the composer when the note applies to the entire cut. Clearing it returns to the current moment or range.
5. Saved comments retain their existing revision, source, transcript, and frame-region context.

The scope chips and raw numeric start/end fields have been removed. Changing the reviewed revision or sequence clears stale temporal and frame-region anchors while preserving an unfinished draft.

## Earlier verification

The Gate pass has completed native verification, including direct seeking and composer focus, independent pointer resizing of both range ends, range creation from Screening, saved-note navigation, Whole cut restoration, and seeking from Dailies. The release app is rebuilt and open. See [the Gate verification record](../design/gate/README.md) for the current checks and screenshots.

The full scripts/test.sh run passed: 48 Swift tests, 20 CLI/JSON API/MCP checks, and 15 plugin/project lifecycle checks. Nine Swift tests cover the new comment-anchor behavior, including reverse dragging, out-of-bounds and non-finite input, scope restoration, saved-cut cleanup, focus requests, and revision changes.

Native UI verification used a separate project and library under build/ui-verification. A seek click created a moment comment; dragging and resizing a range created a range comment; the checkbox created a whole-video comment. Reading the saved comments through the CLI confirmed all three scopes and their anchors. The editor and media panel were visually inspected at both large and smaller window sizes.

The release app is packaged at build/Direction.app. The icon declaration, exact source copies, and ad-hoc code signature were verified.

The later monochrome refinement is documented in [the research record](../design/ui-refinement/research.md). It reviewed twelve product screens, Apple's materials, color, and typography guidance, Frame.io's comment workflow, and Scott's five supplied examples. The selected comment-anchor regression suite passed again after the visual changes, and seeking, range selection, and the whole-video checkbox were checked in the running release.

After unlocking the Mac, the final release was relaunched and seeking from both Transcript and Media was verified to open Comments with the text editor focused. Compact range endpoints were visually checked for separate handles and adjusted through their accessibility actions. The previous JetBlack project was reopened after the isolated verification session.

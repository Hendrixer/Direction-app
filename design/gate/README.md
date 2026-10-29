# Gate in Direction

Source: [Gate design language 2.0](https://claude.ai/artifact/KBjd5vAbxK1p5fJFhFTG23), reviewed in Yab on 28 October 2026. `reference.txt` and `reference.css` preserve the supplied guide. The app before this pass is saved in commit `e81ec17` and `before.png`.

The implementation uses the live CSS values where the illustrative Swift snippet differs: the ten explicit OKLCH steel stops and the four individual prism stops. Gate has three layers: primitives, semantic roles, and reusable component materials. The existing Palette names adapt to those semantics so utility screens share the system.

Black surrounds the picture. The titlebar and notes sheet use the steel ramp, with a cached 192-pixel grain tile. Amber belongs to director pins, note numbers, selected ranges, and frame regions. Agent replies and working status use a diamond and solid ion blue; the prism gradient is reserved for fine attributable edges. Steel buttons have a bright top lip, a restrained vertical gradient, and the specified grain. Floating HUDs use native translucent material. Ordinary timecodes remain neutral.

The titlebar separates Dailies, Screening, and Notes. Screening hides the notes sheet; choosing a moment or range brings it back. The strip draws real video-clip intervals at their actual proportions. It does not invent scene divisions, changed-scene flags, or locks. Notes retain their project-wide index across cuts and sequence filtering. Existing moment, range, region, whole-video, transcript, media, saved-cut, and export operations remain connected to their real implementations.

This pass applies the design system to the current app. The guide's circled-take assembly, turnover/read-back approvals, synced A/B comparison, screening mark queue, and picture-lock workflows require separate product work. The interface does not present controls for those unimplemented operations.

The large chrome icon stays on the welcome screen and in the macOS app icon. Work surfaces prioritize the picture and use the native type scale, with Archivo for room headings. Reduced Motion removes room movement.

## Verification

The full Swift run passed 69 tests. After the final navigation, cut-label, and region-scope fixes, all 33 app tests passed, including three added regressions (72 unique Swift tests across the runs). Tests cover color conversion against known primaries, exact token colors, the bundled Archivo axes, frame timecodes, proportional clip intervals and overlays, pointer mapping, and note anchors. The release app built and was signed successfully; `git diff --check` is clean.

The final release was inspected in the native app after unlocking. Direct strip clicks seek and focus the note field; dragging the playhead grip creates a range, and both endpoints resize independently. A range drag begun in Screening finishes before Notes opens. Selecting a saved note also exits Screening, Whole cut restores its previous range when cleared, and endpoint accessibility adjustment remains available. Seeking from Dailies opens Notes with the text field focused. No test notes were posted to the user's project.

Native testing caught macOS gesture arbitration that pure coordinate tests cannot cover. The seek target recognizes its pointer gesture alongside editable keyboard focus; range grips use high-priority drags. Room navigation uses explicit navigation/focus signals, so changing scope during a drag does not destroy the timeline before mouse-up. All 33 app tests passed again after these fixes, and the signed release was rebuilt and relaunched.

Final captures: [Notes](after.jpg), [Screening](screening.jpg). Direction is left open in Notes on the existing First cut project.

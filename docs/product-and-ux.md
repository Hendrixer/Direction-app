# Direction · v0.2

The director reviews, leaves comments, edits through the transcript, and supplies media. The agent arranges clips, mixes audio, grades, changes output format, saves cuts, and exports. All work is local.

The native window uses a true black canvas with neutral surfaces and a narrow comments/transcript/media sidebar. One small project menu handles new/open/recent projects. Add media is the only persistent header action. There are no promotional headings, eyebrows, layer lanes, finishing panels, or agent configuration panels.

- **Comments:** moment, range, or whole-video notes. Range start/end accept seconds and can be set from the playhead using their adjacent buttons or I/O shortcuts. The scrubber highlights the selected interval. A saved note appears as a clickable marker. Nearby markers group into a count menu so overlapping comments remain reachable. Clicking it selects the card, seeks, and opens the original revision; Back to latest returns to the working cut. Existing accepted/addressed notes remain reviewable.
- **Transcript:** delete text and apply to cut the corresponding footage, or select exact timed words. Words seek the viewer. The empty state selects a source/audio track for local transcription. Only deletions are supported; inserted/replaced words are not synthesized.
- **Media:** linked source thumbnails and search. The first source can initialize an empty sequence; subsequent imports remain in the library for the agent to arrange. Source paths stay available through tools.

Markers for older edits follow source anchors. Removed or ambiguous material gets no fabricated location; its comment remains in the list. Whole-video comments also live in the list. Comments do not wake the agent; it reads them on the next requested revision.

Paused playback follows external edits. Playing footage stays stable until the director loads the available update. Errors and in-progress work appear only when relevant. Keyboard and accessibility names remain even where visual labels were removed.

## Native design tokens

The implementation source is `Sources/DirectionApp/Theme.swift`.

| Role | Value |
| --- | --- |
| Canvas | #000000 |
| Sidebar surface | 3.5% neutral white |
| Raised controls | 8.5% neutral white |
| Primary text / action | 94% neutral white |
| Secondary text | 56% neutral white |
| Separator | White at 9% opacity |
| Review marker | Warm amber, approximately #F0B86B |
| Panel inset | 20 pt |
| Sidebar | 360 pt |
| Control height | 34 pt |
| Surface radius | 10 pt |
| Control radius | 8 pt |

SF system type is 12–15 pt for controls/content, with monospaced 10–11 pt time values. Shared controls define primary, secondary, disabled, pressed, and selected treatments. Video keeps its own color; surrounding surfaces remain neutral.

[Somae Design](https://somae-design.fine-gull-3581.chatgpt.site) informed the spacing discipline and semantic token approach. HeroUI's component/theming guidance was considered; the implementation stays in SwiftUI/AppKit to preserve native playback, accessibility, and Metal compositing.

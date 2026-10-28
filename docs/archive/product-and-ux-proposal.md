> Historical architecture proposal, superseded by the current documentation one directory above. This describes intended scope, not shipped capabilities.

# Product and review experience

## Confirmed intent

Direction serves creators who have a vision and taste without requiring editing expertise. It should support polished YouTube content and small productions, with editing, color, and sound in the first release.

Direction runs natively on the Mac and uses Apple Silicon hardware. An external agent, such as Claude Code or Codex, operates it through MCP. The native UI updates as committed changes arrive. Human interaction centers on reviewing footage and leaving useful comments, with minimal manual editing.

Generative B-roll, video-to-video transformations, and new AI-generated video belong to later releases. The architecture should accommodate generated assets without making a generation service a prerequisite for editing.

The editing model is workflow-neutral: supplied single-camera or multicamera footage, screen recordings, B-roll, graphics, and audio can be arranged as the director intends. Landscape, portrait, square, and custom canvases are first-class sequence settings. Externally generated media enters through normal import; Direction does not generate footage in this release.

Review happens locally in the Mac app in version one.

## Proposed defaults awaiting product decisions

- Apple Silicon, macOS 26 or later. Confirm the OS floor before implementation; lowering it changes transcription and framework choices.
- Bring your own external agent. Direction provides media intelligence and editing tools; the agent provides reasoning and conversation.
- Multiple named output sequences can share project media, including landscape/portrait variants. Each supports multiple camera, B-roll, title, dialogue, and music layers. Nested sequences can wait.

## The main workspace

The player owns most of the window. Surrounding controls should feel closer to a screening room than a traditional editing console.

```text
┌──────────────────────────────────────────────────────────────────┐
│ Direction / Project        Cut 03 ▾       Agent status     Export │
├───────────────────────────────────────────┬──────────────────────┤
│                                           │ Feedback             │
│                                           │                      │
│              Video player                 │ 00:18–00:23          │
│                                           │ Tighten this pause.  │
│                                           │                      │
│                                           │ 00:42                │
│                                           │ Warm up this shot.   │
├───────────────────────────────────────────┤                      │
│ Playback / timecode / audio / full screen  │                      │
│ Filmstrip + waveform + feedback ranges    ├──────────────────────┤
│ [selected review range]                   │ Comment composer     │
├───────────────────────────────────────────┤ Frame / Range / Cut  │
│ Latest change summary · View changes      │ [Leave feedback…]    │
└───────────────────────────────────────────┴──────────────────────┘
```

### Window chrome

Show the project name, review-cut picker, compact connection/activity status, and export. Put media, project brief, transcript, and activity in secondary panels. Avoid a permanent asset browser and an embedded chat occupying the player area.

Connection status distinguishes an attached MCP client, an active job, idle, disconnected, and failed. A connected process alone does not mean an AI agent is currently thinking.

### Player and review timeline

- Play, pause, frame step, scrub, speed, audio level, and full screen.
- A thin filmstrip with an optional waveform and feedback markers.
- Drag a time range or mark in/out to scope feedback. These handles select feedback coverage; they do not trim the edit.
- Click a comment to seek and highlight its range. Offer loop playback of that range.
- Optional rectangle/pin annotation on a paused frame, using normalized output-frame coordinates.
- Compare two cuts at corresponding content anchors, with before/after audio available for sound feedback. A simple A/B switch precedes more elaborate split-screen comparisons.

No track headers, razor tools, clip dragging, node graphs, grading wheels, or audio mixing desk in the default workspace. Keep media import, relinking, restoring a cut, accepting feedback, and export accessible.

### Feedback panel

Use plain language as the main input. Capture context automatically, so the person does not have to write an editing command.

Feedback can apply to:

| Scope | Example | Captured context |
| --- | --- | --- |
| Moment | “The title covers my face.” | Cut, exact time, contributing clips, optional frame region |
| Range | “Remove the pause but keep the breath before the next sentence.” | Cut interval, source spans, nearby transcript |
| Whole cut | “The music should feel quieter throughout.” | Cut ID and project brief |

An optional category such as pacing, picture, sound, or graphics can help organization. Do not require it, force technical terminology, or infer an edit without preserving the original text.

Each feedback thread displays its time/range, author, plain-text request, status, and linked revision when addressed. Replies stay in the same thread. Open and addressed comments remain visible as distinct states.

The agent can mark a request as addressed and explain the change. The director accepts it or reopens it. “Agent finished” and “director approved” are different facts.

### Activity and updates

The main screen should report concrete changes: “Removed a 1.2-second pause,” “Adjusted dialogue level,” or “New cut ready.” Detailed operation logs belong in the activity panel.

When paused on the live working cut, refresh after each valid committed batch, preserving the content under the playhead where possible. During playback, finish against the pinned snapshot and show “Updated cut available” rather than jumping the viewer to different footage. A named review cut never mutates while being reviewed. Users can explicitly choose to follow the live working cut.

The review UI should remain responsive while analysis, proxy generation, and export run. Long jobs show progress where measurable, cancellation, and errors. Do not show fabricated percentage completion for work whose total is unknown.

## Review loop

1. Import media and provide a project brief: intended audience, target duration, format, style, and reference notes.
2. Connect the external agent. The app provides executable/configuration details and a connection check.
3. The agent inspects media, transcript, scene samples, and audio measurements, then edits through typed operations.
4. The director sees the live working cut and activity. The agent checkpoints an immutable cut when it is ready for review.
5. The director watches and leaves moment, range, or whole-cut comments.
6. The agent reads new feedback, applies a versioned revision, and links its changes to the requests it addressed.
7. The director compares, accepts or reopens feedback, then exports the chosen cut.

Feedback is durable even if the agent disconnects. Immediate agent reaction while it is idle depends on host support; do not imply that saving a comment automatically wakes Claude Code or Codex. See the [agent contract](agent-contract.md).

## First-release capability boundary

| Area | Include in first release | Later expansion |
| --- | --- | --- |
| Editing | Insert, trim, split, remove, move, ripple, linked audio, gaps, multiple camera angles with synchronization offsets, B-roll overlays, crop/scale/reframe, constant speed, simple transitions | Manual multicam switching UI, advanced retiming and optical flow |
| Output formats | Landscape, portrait, square, custom canvas and per-sequence frame rate; safe framing and title placement for each variant | Automated subject tracking across reframes |
| Color | Exposure, white balance, contrast, saturation, basic curves, supported LUTs, explicit input/output color transforms, before/after | Tracked secondaries, complex node graphs, comprehensive HDR mastering |
| Sound | Separate dialogue/music, gain envelopes, fades, EQ, compression, limiter, measured loudness and peaks, ducking | Broad plugin hosting, spatial audio, advanced restoration |
| Speech cleanup | Silence detection and conservative cleanup; assess local denoise quality before committing to a model/provider | Voice replacement, generative repair, broad separation models |
| Graphics | Titles, captions, image/logo overlays, a small set of parameterized motion templates | Arbitrary compositing, generative graphics and video |
| Review | Point/range/global comments, frame regions, replies, addressed/accepted states, cut history and A/B | Shared web links, multiuser collaboration |
| Export | Tested H.264, HEVC, and ProRes presets, resolution/aspect controls, cancellation, output validation | Broad interchange, delivery packages and specialist codecs |

Color and sound are first-release subsystems. The first engineering slice can be narrower than the first release, but the release is not complete until their agreed capabilities work through both MCP and playback/export.

## Acceptance experience

A director supplies a real recording and says: “Make a concise walkthrough. Remove dead air, put the screen recording over the explanation, make the dialogue clear, keep music underneath, and give the image a warmer look.”

The agent builds a playable cut without GUI scripting. The director selects a five-second interval and says “Keep this explanation; just remove the pause.” The agent sees the exact cut and source spans, revises it, and links the result to that comment. The director compares the versions and exports the selected one. Original media and earlier cuts remain recoverable.

## Visual reference evidence

These are inspected web references for review interaction, not native Mac specifications:

- [Frame.io: player with side comments and a pinned frame comment](https://mobbin.com/screens/2b1d64ba-d37a-450a-ae9e-4735ef5b21df). Useful for placing feedback alongside the footage and keeping it attached to a visual location.
- [Vimeo: player with a comment sidebar](https://mobbin.com/screens/0b804d5e-14cc-4929-bf2b-efa3d0388435). Useful for the separation of viewing and feedback.

Direction adds structured source anchoring, agent activity, and a revision-to-feedback relationship to this review pattern. It should not inherit unrelated navigation or publishing controls from those references.

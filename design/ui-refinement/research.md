# Direction UI refinement: research and decisions

October 28, 2026

## Scope and preserve list

This pass refines Direction’s native Mac review workspace: application header, player framing, playback transport, comment inspector, and their shared visual tokens. The job remains watching footage, choosing a moment or range, and leaving feedback for the next edit.

Scott asked for a simpler, more sophisticated aesthetic. He likes the grainy surfaces and metallic play button, but dislikes the yellow text. His later clarification sets a strict grayscale interface: black and gray in the dark appearance, or white and gray in a light appearance. Blue and green surface tints are excluded. Color belongs to the icon and media content. The later light reference informs grouping and hierarchy; it does not request a theme switch.

Preserve the approved icon, real project data, existing editing and review actions, native seeking, click-to-comment focus, draggable range endpoints, whole-video checkbox, revision anchoring, and accessibility actions. Keep tactile grain on a small number of utility surfaces and retain the metallic playback control. Add no dependencies, fictional waveforms, sample controls, or replacement interaction model.

## What the supplied references establish

The Echo Mirage examples place a large media image inside a mostly black workspace. Raised controls share a small family of gray surfaces; rows inside a panel do not each need their own surrounding card. White range brackets and neutral timecodes remain visible without a colored metadata system.

The Creativesplaylist example uses type scale, alignment, empty space, and fine rules to distinguish regions. Its artwork supplies color. It is a music interface, so the useful transfer is its visual grouping, not its library structure, playlists, social details, or oversized display heading.

These observations come from Scott’s screenshots. They establish his requested direction, not a general rule about all creative tools.

## Visual reference review

Twelve Mobbin web screens were visually inspected. They provide structure examples for a pointer-driven desktop workspace, not native macOS behavior specifications. Three screens anchor the chosen direction; a pool supports individual decisions. Dropped screens remain recorded so the search does not silently become a collection of attractive fragments.

| Screen | Role | Decision carried or reason dropped |
|---|---|---|
| [Artlist](https://mobbin.com/screens/5421842e-bb3f-436b-87a4-4e4e963684db) | Anchor | Black creative workspace, compact toolbar, and broad media area. Carry the hierarchy, not its media catalog. |
| [YouTube Music](https://mobbin.com/screens/ab67a36b-6a30-4fa0-b5d4-77d50f88ca28) | Anchor | Flat queue rows and compact bottom transport. Carry grouping, not music navigation. |
| [[untitled]](https://mobbin.com/screens/a58d7560-8cad-490f-a3ec-acd736c41735) | Anchor | Minimal rows, restrained type hierarchy, and a small floating transport. Carry the limited surface hierarchy. |
| [Sora](https://mobbin.com/screens/cec75b4a-a09e-45e7-9668-12e3363280e1) | Pool | One comments plane with plain rows supports the inspector treatment. |
| [Vimeo](https://mobbin.com/screens/a0e413d9-735c-4c11-9717-3de66d3eb960) | Pool, structure only | Plain feedback rows are relevant; its light appearance is not adopted. |
| [Frame.io](https://mobbin.com/screens/39416f38-9246-4a6d-bc30-79874a268b5e) | Dropped visual treatment | Boxed comments and yellow timestamps repeat the specific treatment Scott rejected. |
| [Riverside](https://mobbin.com/screens/75720d35-877e-4aca-9f8c-3f4586d13621) | Dropped | Dense multitrack controls and purple emphasis do not fit this review-focused pass. |
| [ClassDojo](https://mobbin.com/screens/225128f0-1acf-49e8-a5e7-86532d8c7dfb) | Dropped | Domain and screen structure do not answer the review-workspace problems. |
| [Suno](https://mobbin.com/screens/4dfa86af-b0d2-432d-9b4f-d2b1d7f33344) | Dropped | Dense colored promotional content competes with the restrained workspace direction. |
| [Open](https://mobbin.com/screens/52fbd644-07a0-4c4f-9aad-05c42f17f5ba) | Dropped | Minimal fullscreen presentation supplies too little evidence for a working review interface. |
| [Spotify](https://mobbin.com/screens/bafdbaa7-6118-48e0-90a2-92c0d339dce6) | Dropped | Colored panels and dense home content do not support the selected hierarchy. |
| [SoundCloud](https://mobbin.com/screens/301a21e9-d189-4959-9e06-efe024cc9c2b) | Dropped | Orange waveform and social emphasis are outside the requested treatment. |

## Primary-source checks

[Apple’s Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) describes materials as a way to establish depth and hierarchy. It distinguishes the controls/navigation layer from content and recommends sparse custom glass effects. This supports limiting repeated material treatments; Apple does not prescribe grain, metallic controls, or this exact palette.

[Apple’s Color guidance](https://developer.apple.com/design/human-interface-guidelines/color) recommends consistent color meanings, sufficient contrast, and alternatives to color-only signals. The strict grayscale choice comes from Scott. Selected fills, brackets, labels, and endpoint shapes must still communicate state.

[Apple’s Typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography) lists 13-point default text and a 10-point minimum for macOS. It recommends readable weights, few typefaces, and hierarchy through size, weight, and color. Direction retains the system font; ordinary body copy and secondary metadata receive distinct roles.

[Frame.io’s commenting documentation](https://help.frame.io/en/articles/9105251-commenting-on-your-media), updated September 9, 2026, documents a nearby composer, time-anchored comments, draggable range brackets beneath playback, and a timestamp control beside Send. That is functional evidence for preserving Direction’s new comment workflow, independent of Frame.io’s visual treatment.

## Applied move table

| Problem | Applied decision | Evidence and judgment |
|---|---|---|
| Yellow metadata draws emphasis away from notes and footage. | Neutral timestamps, markers, range fills, and endpoints; no tinted workspace surfaces. | Scott’s request and monochrome range reference. Exact gray values are local judgment. |
| Material effects repeat across too many nested elements. | Reserve grain for transport/composer and chrome for playback; remove repeated prism borders. | Three anchor screens’ limited surface hierarchy; Apple’s separation guidance. Grain strength is judgment. |
| Header branding and utility details compete. | Flatten and compact the header; establish a clear project title around 16 points. | Artlist’s compact toolbar and supplied black headers. Exact spacing is judgment. |
| Every comment becomes a separate decorative object. | Plain comment rows, fine separators, quiet selected fill, and simple tabs. | Sora and Vimeo examples, supported by the anchors’ row structure. Native state handling stays intact. |
| Transport occupies more visual space than its functions require. | Slim the transport to approximately 126 points while preserving seeking, handles, and metallic play. | YouTube Music and [untitled] grouping. Exact dimensions and metal finish are judgment. |

## Limits and checks

The references do not justify adding playlists, dense editing tracks, social controls, avatars, fabricated waveforms, or automatic content colors. The single direction is a matte grayscale review workspace with selective tactile controls.

The implementation is checked against the existing build/tests and native rendered states. Compare the before/after captures for hierarchy and surface count, then exercise moment comments, range adjustment, whole-video selection, narrow windows, and disabled controls. Research establishes examples and constraints; it does not claim measured improvements in speed, trust, or engagement.

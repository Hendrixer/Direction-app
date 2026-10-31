# Engines (plan)

Not built. Planned 31 Oct 2026, from the director's ask: the editor stays the editor (the hands), and the tool it edits in is pluggable: Direction's own, or another editing app, chosen per film, as long as Direction supports it.

## What Direction needs from any tool

The director's side stays the same whatever the editor edits in: watch a cut, note it, read the answers, play only what changed. For that, a tool has to give Direction:

1. **A way in**: the current cut and the footage, opened in the tool.
2. **A way to work**: an MCP server or CLI the editor uses, and a skill that says how (`edit-in-<tool>`); computer use only as a last resort.
3. **A way back**: a review movie of the new cut, and its timeline when the tool can hand one over (OTIO or FCPXML), so the answers can point at clips. Without a timeline, the director reviews the movie, and answers point at times.

Direction keeps the brief, the notes, the turnovers, the answers and the review loop in every case. What only Direction's own engine gives: the director's instant changes (layouts, ⌘Z), moves and techniques by name, live playback of every revision, checks on every edit.

## What the tools are (researched 31 Oct 2026)

| Tool | What it is | How the editor drives it | Fit |
|---|---|---|---|
| Direction | Its own timeline, edit functions and Metal renderer | `direction_edit` and the rest | The default |
| DaVinci Resolve Studio 21.1 | A full editor; $295 once | Blackmagic's own MCP; the scripting API (no transitions or keyframes on the edit page; some calls report success and do nothing); Resolve must be running | The best "real editor" to support first; reads and writes OTIO since 18.5 |
| Final Cut Pro | A full editor | FCPXML in (Workflow Extensions, fcpxml MCP servers); no way to export a timeline without a person | In only; review by movie |
| Premiere Pro | A full editor; subscription | UXP plug-in API (no razor, no time remapping yet); community MCP bridges | Later |
| Diffusion Studio (editor) | An agent-first desktop editor (Electron), projects as JSX files | Its local MCP, `diffusion` CLI and skills; free, MPL-2.0 | Possible "edits in" option; a competing editor with its own renderer |
| Eddie | A cloud assistant editor for interviews (rough cuts, multicam, logging) | Hosted MCP (118 tools), CLI, REST; credits | A rough-cut service: its OTIO comes into Direction's timeline |
| HyperFrames | HTML/GSAP compositions rendered headless in Chrome | CLI and skills; Apache-2.0 | A graphics renderer beside Direction's JavaScript graphics |
| Wireflow | Hosted generation graphs (Veo, Kling, Sora, ElevenLabs) | Each graph is a REST endpoint and MCP tool | A made-media service, not an editing tool |

**Round trips keep only the edit decisions.** Through OTIO and FCPXML, clips, tracks, gaps and markers survive; transitions, effects, keyframes and speed ramps mostly don't. Anything else is baked into the media or done again.

## Order

1. **The seam.** An engine setting per film (Settings › Editor › Edits in), the review movie as a cut Direction can play and note when no timeline comes back, and OTIO in and out of Direction's timeline.
2. **Services into Direction's timeline**: a rough cut from Eddie (its OTIO opened as the assembly), graphics from HyperFrames as clips.
3. **Resolve Studio** as the first other editor: in through OTIO and the project, the editor on Blackmagic's MCP with an `edit-in-resolve` skill, back as a rendered movie plus OTIO.
4. Then Final Cut (in only), Diffusion Studio, Premiere, as each one's API allows.

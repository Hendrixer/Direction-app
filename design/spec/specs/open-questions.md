# Decisions and open questions

The four room specs were drawn in parallel. These are the cross-room decisions made when they were joined. When a room spec and this file disagree, this file wins.

## Decided

1. **One steel button.** It's the primary action at the titlebar's right. While a sheet is open, that button becomes a plain, inactive button under the scrim, so the sheet's confirm is the only steel button. On the empty Films screen (01), the hero's New film is the steel button and the titlebar's is plain.
2. **Cutting is a state of Notes, not a room.** While the editor cuts (25–28), the Notes sheet becomes "Cut 4 in progress", the picture keeps playing the previous cut, and the primary is "Screen Cut 3" (or "Retry" after a failure).
3. **The turnover covers notes 1–7.** Note 7 is Priya's accepted outside note. Script frame 11 shows notes 8 and 9 being written against Cut 3 *after* that frame's moment; they aren't part of the turnover drawn in 22. In the app, notes written after a turnover wait for the next one.
4. **Question takes.** Frame 20 asks about line 12 with "T2" and "T5". Treat T5 as `2A T5`, a fifth take of setup 2A that frame 07 doesn't show. Sample data is illustrative; the app shows whatever takes exist.
5. **"Needs you" is neutral.** Amber is only for the director's own acts. Things waiting on the director use neutral steel chips; hard blockers (can't do, stopped, missing license) use alert red.
6. **The Changes room** shows answers as diamonds on the strip. Director pins are hidden there; they live in Notes.
7. **Room-scoped keys.** `⌘↩` runs the room's primary (Turn over, Assemble from circles, Play changes…). `R` is Region in Notes and Other readings in Script.
8. **Strip proportions** in the frames are approximate. The app sizes scenes from real durations.
9. **Account name** in frame 48 is sample data ("Dana Moreau"). The director is never named elsewhere; the UI says "you".
10. **Class names `.agent` and `.side`** in `gate.css` are reserved for the titlebar pill and the sidebar. Don't reuse them inside other components.

11. **No timeline for the director, and no raw timeline for the editor.** The editor reads the cut as OpenTimelineIO and changes it only through Direction's edit functions (`direction_edit`): named operations that Direction carries out exactly (`agent-timeline.md`). The director sees scenes, answers and choices only.
12. **No hand-off to other editing apps.** Direction renders everything: effects, graphics, made clips, looks. No FCPXML, OTIO or EDL export for finishing elsewhere. (OTIO is the editor's format, not an export.)
13. **The look is the director's.** The editor balances shots and may propose looks; it never applies one.
14. **Graphic words are the director's to fix** directly, without a turnover. Everything else about a graphic goes through notes.
15. **Direction makes every service request.** Keys stay in the Keychain; the editor asks Direction with `direction_make`.
16. **Direction starts the editor** (Claude Code or Codex) by default. Your own session over MCP stays supported with activity but no control.
17. **Graphics are JavaScript Direction renders**, not Remotion. Examples ship with the app.
18. **Local first for looking at footage.** mlx-vlm in a helper process (Qwen3-VL 8B by default); OpenRouter is optional with a key.
21. **One service: OpenRouter.** Music, voice, sound effects, new shots, stills and (optionally) looking at footage all go through OpenRouter with one key, replacing separate ElevenLabs, Runway, Higgsfield and Gemini keys.

19. **Phase 2 frames vary the sample.** Frame 61 shows note 4 answered two ways, B with made music, where story.md has a single −6 dB answer. Frame 64 adds an eighth answer to Cut 4, a title for the cold open numbered 8, although Script's note 8 is "Let this breathe" and the Cut 4 turnover covers notes 1–7. Treat 61 and 64 as alternate samples that each show one feature, not one continuous state.
20. **The Look sheet's layout** (frame 63): Strength sits on the Looks header row, Apply to sits in the sheet's foot left of the buttons, and filter rows are 22 tall, so everything fits a 720-tall sheet without scrolling. This wins over looks.md where they differ.
22. **The editor plans the shot; Direction gives it steps.** No separate planning agent: the editor chains `direction_make` kinds (stills, new shots from frames, extended shots, bridges, changed shots) with the `make-shot` skill's recipes. Stills before motion; frames of the film as references.
23. **One amount decides when the director is asked.** The editor prices each turnover's plan with `direction_estimate`. Under Settings › Services › Ask before spending more than, it makes it without asking; over it, one spend question covers the whole plan (its estimate plus 10%). There's no separate approval of stills.
24. **A changed shot changes the take itself** (Aleph 2.0 or FLUX Video Edit through OpenRouter), not a new shot from its frame. Runway and Higgsfield directly would add keys without adding versions: OpenRouter carries Runway's Aleph 2.0 and Gen-4.5 at Runway's prices, and Higgsfield's API resells the same versions.
25. **Slow motion and sharpening are local.** Apple's frame interpolation and super resolution (VideoToolbox) run on this Mac at no cost; made shots are sharpened to the cut's size before they come in.
26. **People in made shots.** For now the only person in the films is the director, so pickups that show someone from the footage need no extra consent step.

## Needs product decisions (not blockers for building the UI)

- **Hosted sharing (39, 40, 48).** Screening links need a hosted service ("direction.film") and server-side watermarking. Today Direction is local only. Build the Share sheet and the Outside inbox; until a service exists, Share shows a disabled state ("Sharing isn't set up on this Mac"), and outside notes can come in through the editor's tools.
- **Credit for outside notes.** Should an accepted outside note keep its author's name when the editor sees it? The default is yes (Settings › Sharing).
- **Region dim strength.** While drawing, the area outside the region is dimmed 35%. That may be too subtle over bright footage; 50% while drawing, 35% at rest is the fallback.
- **Codex versions.** The list of versions to offer for Codex. Until decided, "The program's default" and Other….
- **Cost with plan sign-ins.** Claude Code and Codex may report no cost when signed in with a plan. The popover hides spend then; decide whether to show tokens instead.
- **Music for release.** Each music version on OpenRouter has its own terms. Decide whether Direction warns at delivery when a film contains made music.
- **Vision downloads.** Standard is 5.8 GB and Best 17 GB. This Mac has 13 GB free today; decide whether Quick should be the default on Macs with less than 50 GB free.
- **GSAP's license** is free for commercial use but excludes tools that compete with Webflow. Direction isn't one; confirm before bundling, or drop it from the bundled libraries.

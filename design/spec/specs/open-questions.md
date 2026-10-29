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

## Needs product decisions (not blockers for building the UI)

- **Hosted sharing (39, 40, 48).** Screening links need a hosted service ("direction.film") and server-side watermarking. Today Direction is local only. Build the Share sheet and the Outside inbox; until a service exists, Share shows a disabled state ("Sharing isn't set up on this Mac"), and outside notes can come in through the editor's tools.
- **Credit for outside notes.** Should an accepted outside note keep its author's name when the editor sees it? The default is yes (Settings › Sharing).
- **Region dim strength.** While drawing, the area outside the region is dimmed 35%. That may be too subtle over bright footage; 50% while drawing, 35% at rest is the fallback.

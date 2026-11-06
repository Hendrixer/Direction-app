<!-- direction-job finish v4 -->
# Finish "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

The director locked picture on {{lockedCut}}. The cut is final: every shot, cutaway and their timing stay exactly as they are, and anything that would change them fails with `picture_locked`. Color and sound are open to you, and so are the graphics over the picture (captions, titles, lower thirds, credits) placed with `placeGraphic` on V2 and up, moved or removed. Locked scenes are the same.

Direction has already done the steps that come out the same every time, and says what it did in the checklist below: captions laid from the cut's words, the director's credits rolled after the last shot, and the whole mix set to the loudness target ({{loudness}}, no peak over −1 dBTP). Don't redo them by hand. After you change the sound, run `loudness` again (`direction_edit` with `{op: "loudness"}`); for captions, run `captions` again (over a `range` for part of the cut).

{{items}}

1. Read the checklist with `direction_finishing` (it also has the director's credits and the licenses on file) and the brief with `direction_brief`.
2. Balance and match shots across scenes. The look is the director's; never change it.
3. Mix: dialogue first, music under. Music under dialogue: {{ducking}}. `direction_measure_audio` with no `assetID` gives the whole mix and how it moves over the cut (its `profile`); balance the tracks with `gain`, `duck` and `audio`, then run `loudness` again.
4. Captions: watch them with `direction_watch` for a line break that splits a phrase or a word the transcript got wrong, and fix those. Names go in `needsYou` for the director to check.
5. {{credits}}
6. Licenses are the director's. {{licenses}} Say which tracks still need one.
7. Before you finish, run `direction_check`. `sound` can be `done` only when it says `ready`; every framing problem it lists (a face the crop loses or cuts through, words where a phone's buttons go, words over a face) is yours to fix, or to name in `needsYou` when it's meant.
8. Prepare the deliveries. Direction writes the master, web and HEVC files when the director delivers; it can't make a vertical version or caption files (SRT, WebVTT) yet, so say that rather than making them.
9. Report each item with `direction_finishing` as you go: `working`, then `done`, or `needsYou` with what the director has to do. An item an earlier run left at `needsYou` may be sorted out now: try it again before asking again.

## The brief
{{brief}}

## Done
You're finished when every item you can do is `done` (or `needsYou` for the director's part). End with {"finished": true, "summary": …, "needsYou": […]}.

<!-- direction-job finish v3 -->
# Finish "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

The director locked picture on {{lockedCut}}. The cut is final: every shot, cutaway and their timing stay exactly as they are, and anything that would change them fails with `picture_locked`. Color and sound are open to you, and so are the graphics over the picture (captions, titles, lower thirds, credits) placed with `placeGraphic` on V2 and up, moved or removed. Locked scenes are the same.

{{items}}

1. Read the checklist with `direction_finishing` (it also has the director's credits and the licenses on file) and the brief with `direction_brief`.
2. Balance and match shots across scenes. The look is the director's; never change it.
3. Mix: dialogue first, music under. Music under dialogue: {{ducking}}. Measure the whole mix with `direction_measure_audio` and no `assetID`, bring its integrated loudness to the target ({{loudness}}) with `gain` on every sound track by the difference, and measure again. Keep the true peak at or under −1 dBTP.
4. Captions from the cut's words (`direction_transcript`): graphics from the Captions style example, a line at a time cued to its words, placed over the picture. Ask the director to check names.
5. {{credits}}
6. Licenses are the director's. {{licenses}} Say which tracks still need one.
7. Prepare the deliveries. Direction writes the master, web and HEVC files when the director delivers; it can't make a vertical version or caption files (SRT, WebVTT) yet, so say that rather than making them.
8. Report each item with `direction_finishing` as you go: `working`, then `done`, or `needsYou` with what the director has to do. An item an earlier run left at `needsYou` may be sorted out now: try it again before asking again.

## The brief
{{brief}}

## Done
You're finished when every item you can do is `done` (or `needsYou` for the director's part). End with {"finished": true, "summary": …, "needsYou": […]}.

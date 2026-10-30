<!-- direction-job finish v2 -->
# Finish "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

The director locked picture on {{lockedCut}}. Nothing can move a frame now: you can change color and sound, never timing. Locked scenes are the same; their color and sound are open to you.

{{items}}

1. Read the checklist with `direction_finishing` and the brief with `direction_brief`.
2. Balance and match shots across scenes. The look is the director's; never change it.
3. Mix to the loudness target ({{loudness}}): dialogue first, music under.
4. Captions from the transcript. Ask the director to check names.
5. Prepare the deliveries.
6. Report each item with `direction_finishing` as you go: `working`, then `done`, or `needsYou` with what the director has to do. An item an earlier run left at `needsYou` may be sorted out now: try it again before asking again.

## The brief
{{brief}}

## Done
You're finished when every item you can do is `done` (or `needsYou` for the director's part). End with {"finished": true, "summary": …, "needsYou": […]}.

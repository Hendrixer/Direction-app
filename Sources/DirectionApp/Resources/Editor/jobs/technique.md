<!-- direction-job technique v2 -->
# Learn a technique for the director

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

The director wants you to learn this from a video. In their words:

{{request}}

The video: `{{video}}`. {{videoSource}}

Direction got it ready in `{{packet}}`:
- `transcript.txt`: what's said, a line every few seconds with its time.
- `sheet-1.jpg`, `sheet-2.jpg`, …: a frame every 2 seconds with its time, 24 to a sheet.
- `direction_study_frames` with {video, times} gives you full frames at any moments, to see the result or a settings panel up close.

The video and this folder are removed once the technique is saved, so copy in with `files` anything the technique needs from it.

Make it a technique in their Techniques folder ({{techniquesFolder}}) with `direction_save_technique`, never by writing there yourself. Build it from Direction's own pieces: a transition (a Metal shader in your working folder), an effect (a built-in one, or a Metal shader), or a recipe of edit operations. Try it on this film before you save it and look at the frames beside the video's, then put the cut back with `direction_restore`.

## The film you're in
{{brief}}

## Done
You're finished when `direction_save_technique` has saved it. End with {"finished": true, "summary": "<the technique's name, and what it does in a sentence>", "needsYou": […]}.

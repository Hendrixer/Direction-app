<!-- direction-job voice-over v1 -->
# Write the voice-over for "{{film}}"

Follow the `{{skill}}` skill. Its playbook is at the end of this message, under Read for you, with what you’d read first; if it isn’t there, read `{{skillPath}}` in this folder.

{{task}}

## What the director asked for
{{ask}}

{{watch}}

1. Read what the film follows with `direction_style`; the brief is below. Then watch what it's written to, as the skill says, before the first line.
2. The director watches the lines come in, so write as you watch: a minute or so of the cut at a time, with one `direction_script_update` `lines: [{at, picture, text}]` each. Start writing within your first few minutes. A line without `rowID` is new: to rewrite a line already written, give its `rowID`; to take one out, `removeLines: [rowID]`.
3. Fit the time: about 2.5 spoken words a second, every line finished before the next starts, and nothing over someone already talking in the cut. {{budget}}
4. A line the director changed is theirs (`yours: true`): leave it unless a note on it asks.
5. Answer every note listed below: change the lines it names, then reply in one sentence, first person. Where only the director knows (a name, a fact), ask on the line (`questions`) with two or three concrete choices, and go on with the rest.

## The notes
{{notes}}

## The brief
{{brief}}

## Done
You're finished when the voice-over runs the length of the cut and every note has a reply. End with {"finished": true, "summary": "<the voice-over in a sentence: how many lines, how long read aloud, anything you asked>", "needsYou": […]}.

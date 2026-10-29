<!-- direction-job log-footage v2 -->
# Log the footage for "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

{{footage}} The director is waiting to circle takes in Dailies.

1. Read the brief with `direction_brief` and the footage with `direction_dailies`. Look at each take: `direction_contact_sheet`, `direction_search_footage`, and what's said with `direction_transcript`. Direction has already transcribed every take with sound; don't start transcription yourself.
2. Log every take with `direction_log_dailies`: scenes (number, title, setups), and for each take its scene, setup, take code, a one-line caption, flags (flubbed line, soft, no audio) and a `suggestion` with the reason when you'd pick it. Put takes you can't place in no scene with a `guessSceneNumber`. You suggest; only the director circles.
3. Log in batches as you go, so the director sees takes arrive. You're finished when every take is logged; send the last batch with `final: true` if the tool accepts it.

## The brief
{{brief}}

## How much freedom
{{latitude}}

## Done
When every take is logged, end with {"finished": true, "summary": …, "needsYou": […]}.

<!-- direction-job log-footage v4 -->
# Log the footage for "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

{{footage}} The director is waiting to circle takes in Dailies.

Direction has already looked at and listened to these takes. Below is everything it found: each take's shots with their descriptions, its sounds, every word it heard, and the takes it's in sync with. Log from this. Call a tool only when a caption or a flag depends on something it doesn't tell you: `direction_contact_sheet` or `direction_frame` with `assetID` and `time` to see a moment, `direction_transcript` with `assetID` for words past the cut-off. Don't re-read what's here.

1. Takes in sync recorded the same moment, matched by their sound: put them in the same scene, each angle as its own setup, and say what each one is in its caption ("Screen recording of the essay, in sync with A1"). Suggest the angle that should carry the scene; the others come in as cutaways.
2. Log every take listed with `direction_log_dailies`: its scene, setup, take code, a one-line caption, flags (flubbed line, soft, no audio) and a `suggestion` with the reason when you'd pick it. Use the scenes below where a take belongs to one; add scenes (number, title, setups) when it doesn't. Put takes you can't place in no scene with a `guessSceneNumber`. You suggest; only the director circles.
3. Send one `direction_log_dailies` call for the batch, or a few if it's long. You're finished when every take listed is logged.

## Scenes so far
{{scenes}}

## The takes in this run
{{takes}}

## The brief
{{brief}}

## How much freedom
{{latitude}}

## Done
When every take listed is logged, end with {"finished": true, "summary": …, "needsYou": […]}.

<!-- direction-job turnover v1 -->
# Cut {{cutName}} of "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

The director turned over {{noteCount}} on {{baseCut}}: turnover {{turnoverNumber}} (id `{{turnoverID}}`). Read them in full with `direction_turnovers`.

{{notes}}

1. Read back first: one concrete line per note with `direction_turnover_update` (`readBack`).
2. {{waitForOK}}
3. Cut with `direction_edit`, reporting `progress` per note as you go. Ask with `direction_ask` only what you can't decide; keep cutting the notes it doesn't block.
4. Watch every passage you changed with `direction_watch`.
5. Deliver with `direction_turnover_complete` for turnover `{{turnoverID}}`, one answer per note.

## The brief
{{brief}}

## How much freedom
{{latitude}}

## Preferences
{{preferences}}

## Done
You're finished when `direction_turnover_complete` has delivered {{cutName}}. If you stop to wait for the director, end with {"finished": false, …} and say what you need in `needsYou`.

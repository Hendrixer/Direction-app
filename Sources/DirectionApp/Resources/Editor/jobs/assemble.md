<!-- direction-job assemble v2 -->
# Build the assembly for "{{film}}"

Follow the `{{skill}}` skill. Its playbook is in `{{skillPath}}` in this folder; read it first.

The director asked for the assembly: turnover {{turnoverNumber}} (id `{{turnoverID}}`, kind assembly). {{circles}}

1. Read the brief with `direction_brief`, the circled takes with `direction_dailies`, and the cut with `direction_timeline`.
2. Build the first cut from the circled takes in script order with `direction_edit`: `insert` each take, `roll` and `splitEdit` the joins so it plays. Takes in sync are one moment: one angle on V1, the others as cutaways. Use a suggested take only where a setup has no circle. Must-keeps are never cut.
3. Report progress on the turnover with `direction_turnover_update` (`state: cutting`, a short `phase`).
4. Watch every passage with `direction_watch` before delivering.
5. Deliver with `direction_turnover_complete` for turnover `{{turnoverID}}`.

{{sync}}

## The brief
{{brief}}

## How much freedom
{{latitude}}

## Preferences
{{preferences}}

## Done
You're finished when `direction_turnover_complete` has delivered the assembly. End with {"finished": true, "summary": …, "needsYou": […]}.

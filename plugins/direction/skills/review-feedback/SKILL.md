---
name: review-feedback
description: Read director comments with their original frames, audio, transcript, and source anchors, then revise a Direction edit and report which notes were addressed.
---

Comments do not wake an agent. Read them when the user next asks you to revise or check feedback. Resolve the intended project and pass `projectPath` on every call.

Read `direction_feedback`, paginating by its cursor when necessary. Fetch `direction_feedback_context` for actionable comments. It returns the original edit revision, moment/range, source anchors, audio-track context, captured transcript, and sampled PNG/WAV content. Inspect the media when available; do not infer the note's meaning from timestamps alone.

A comment belongs to the footage the director saw. Its original time is not necessarily its position in the latest edit. Inspect current anchor projections: exact, split, removed, or ambiguous. Use projected ranges only when they identify the intended material. If removed, explain that state; if ambiguous, inspect the candidate footage or ask a focused question. Do not apply an old timestamp blindly to a newer cut.

Commit changes using the current `baseEditRevision`, then verify the affected range with actual frames/audio. Reply through `direction_feedback_reply` with the resulting revision, a concrete explanation, and status `addressed` when the requested change is ready. Only the director can accept a note; never mark it accepted on their behalf.

Retain the feedback cursor per project for subsequent requests, while checking any still-open notes. A reply is an authorized update inside the user's local video project; it is not a message to an external service. If a note cannot be completed, leave it open and explain the specific limitation.

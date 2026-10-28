---
name: edit-video
description: Assemble, trim, reframe, color-grade, mix audio, transcribe, or export supplied footage in a local Direction project.
---

Resolve the intended project from the user's request or `direction_projects`; pass its `projectPath` on every call. Read `direction_inspect` before edits and `direction_feedback` at the beginning of each requested revision. Inspect current schemas for operations rather than inventing fields.

Edits are non-destructive, atomic batches. `direction_edit` takes `batch` with `baseEditRevision`, `idempotencyKey`, `summary`, `operations`, and optional `sequenceID`. Rational time is `{value,timescale}`; a range is `{start,duration}`, half-open. Convenience tools use seconds. Use `validateOnly` for substantial assembly changes; submit the same batch to commit. On conflict inspect again. Reuse a key only for an identical retry.

Use higher video layers for B-roll; same-kind/same-layer clips cannot overlap. Ripple removal affects synchronized layers. Transcript edits delete existing timed words and the matching footage; they do not synthesize speech or support arbitrary word replacement. Prefer exact word IDs when repeated wording is ambiguous.

Inspect each source's audio track IDs and labels. Track indices are not track IDs. Mute unused embedded tracks explicitly and retain intended dialogue, music, or game audio. Source settings affect that source's uses; clip overrides affect only the addressed clip. Native gain, fades, EQ, compression, and limiting are available. Measurements are RMS/sample peak, not LUFS/true peak.

Color and framing changes use the shared Metal rendering graph. Current output is SDR Rec.709; HDR input is rejected. There are no LUTs, advanced transitions, automatic multicam sync, or automatic pause removal. Report a concrete unsupported request rather than simulating success.

Verify with `direction_frame` and `direction_preview` on the committed revision; inspect actual images/audio with available multimodal capabilities. Preview/export/transcription return job IDs: poll `direction_job` using the same project path and keep the server alive until terminal. Export to a new path; existing files are protected. Save a named review cut when useful and open it with `direction_open_project(showInApp: true)`. If an edit needs undoing, `direction_restore` creates a new revision rather than deleting history.

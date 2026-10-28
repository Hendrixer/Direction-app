> Historical architecture proposal, superseded by the current documentation one directory above. This describes intended scope, not shipped capabilities.

# MCP and review contract

Status: proposed API surface. Names, schemas, and examples below are design artifacts, not implemented tools.

## Operating model

Direction owns media, the editable sequence, processing, review state, and output. The external agent interprets prompts and feedback, chooses an edit, inspects the result, and explains its decisions.

Use typed, deterministic commands instead of a single `edit_video(prompt)` endpoint or arbitrary script execution. Optional MCP prompts may teach workflows, but do not replace the tool schemas. All operations have capability/version checks and machine-readable errors.

## Tool families

| Family | Proposed tools | Purpose |
| --- | --- | --- |
| Discovery | `direction.capabilities`, `project.list`, `project.open`, `project.inspect` | Discover actual engine/effect/codec support and project state |
| Media | `media.import`, `media.list`, `media.inspect`, `media.relink` | Bring in sources, inspect streams and repair access |
| Perception | `analysis.start`, `transcript.read`, `frames.sample`, `audio.measure` | Ground editorial decisions in actual media |
| Editing | `edit.validate`, `edit.apply`, `edit.diff`, `edit.restore` | Preview and atomically apply typed operations |
| Review | `review.create_cut`, `review.list_cuts`, `feedback.list`, `feedback.reply`, `feedback.mark_addressed` | Read director feedback and link revisions back to it |
| Inspection | `preview.render_frame`, `preview.render_range` | Verify the actual edited image/audio |
| Jobs | `jobs.get`, `jobs.list`, `jobs.cancel` | Manage bounded asynchronous work |
| Output | `export.presets`, `export.start`, `export.inspect` | Render a pinned cut and inspect the result |
| Updates | `events.read` | Replay ordered events from a cursor |

The native review UI uses the same service to add feedback and accept/reopen it. The external editing agent does not accept its own work on the director's behalf.

Avoid returning full projects or transcripts by default. Use stable IDs, bounded pages, ranges, fields, and cursors. Return image content or resources for sampled frames, with timestamps and render revision. Large previews/exports remain local artifacts; do not embed video bytes in ordinary tool responses.

## Edit batch

An edit submission contains:

- `projectId` and `sequenceId`.
- `baseEditRevision` identifying the inspected state.
- `idempotencyKey`, scoped to the project and canonical payload.
- Ordered typed `operations`, with documented ripple/link/speed semantics.
- Optional feedback IDs and a human-readable change summary.

`edit.validate` produces a proposed diff, timing effects, capability failures, and relevant warnings without committing. Validation is a tool, not a mandatory human approval dialog for each edit. `edit.apply` revalidates atomically against the base revision and publishes one committed result.

An idempotency retry with the same payload returns the existing outcome. Reusing a key for another payload is an error. A stale base revision returns `revision_conflict` and the current revision/diff reference. Rejected operation N cannot leave operations 1 through N−1 committed.

Expensive derived work runs as jobs after the edit is persisted. A pending render/audio cache is distinct from the committed sequence. Operations that require an external result first use a separate preparation job, then an explicit edit referring to the completed artifact.

Initial operation vocabulary:

```text
insert_clip       trim_clip         split_clip        remove_clip
move_clip         remove_range      set_speed         set_transform
set_transition    set_color         set_audio         set_gain_envelope
set_title         set_captions      insert_image      set_sync_group
create_sequence   set_sequence_format
```

Each operation schema defines whether times are source-relative or sequence-relative, how linked media behaves, whether gaps/ripple are allowed, legal parameter ranges, and which assets/instances it may affect. Define constant speed first; complex variable retiming waits for an explicit mapping implementation.

## Feedback example

This example represents 18–23 seconds of cut 03 on a 30 fps sequence. Canonical intervals are half-open; the frame at the end is excluded. Human-readable seconds are a display convenience.

```json
{
  "id": "feedback-17",
  "projectId": "project-1",
  "sequenceId": "sequence-main",
  "reviewCutId": "cut-03",
  "editRevision": 42,
  "scope": "range",
  "interval": {
    "start": { "value": 540, "timescale": 30 },
    "duration": { "value": 150, "timescale": 30 }
  },
  "text": "Keep the explanation, but remove the pause before the next sentence.",
  "status": "open",
  "anchors": [
    {
      "clipInstanceId": "clip-a12",
      "assetId": "asset-camera-a",
      "sourceStreamId": "video-0",
      "sourceInterval": {
        "start": { "value": 2460, "timescale": 30 },
        "duration": { "value": 150, "timescale": 30 }
      },
      "sequenceInterval": {
        "start": { "value": 540, "timescale": 30 },
        "duration": { "value": 150, "timescale": 30 }
      }
    }
  ],
  "context": {
    "transcriptSegmentIds": ["transcript-segment-24", "transcript-segment-25"],
    "frameResource": "direction://cuts/cut-03/frames/540-30",
    "region": null
  }
}
```

For moments, record one exact rational time rather than a zero-length interval with ambiguous selection semantics. For global feedback, omit the interval. A spatial region uses normalized output-frame coordinates with an explicit origin and is pinned to the original rendered frame. It must not be treated as source-space geometry after a crop or reframe.

Anchor extraction covers every contributing video/audio/title layer, not just the topmost visible clip. Transcript context uses source token/segment IDs. A comment about background music should retain the relevant audio source identity even when a different video layer is showing.

## Remapping across edits

Keep the original comment and its original cut immutable. Produce a separate projection onto the current edit using clip lineage and source-to-sequence maps.

Projection results are `exact`, `split`, `removed`, or `ambiguous`, with intervals, candidate instance IDs, and a reason. Moving a clip remaps the interval; splitting a clip may create several intervals; duplicated footage may need disambiguation. Deleting the referenced footage produces `removed`, not an invented nearby timestamp. A removed interval is evidence that the content disappeared, not proof that the director's intent was satisfied.

Store split/trim/duplicate lineage and speed mappings with each revision. When remapping fails, the agent can still inspect the original cut, source spans, and frame. Never silently attach a comment to whatever now occupies the old clock position.

## Feedback lifecycle

```text
open → addressed by agent → accepted by director
                    ↘ reopened by director → open
```

An agent response includes feedback IDs, the committed revision, affected operation IDs, a change summary, and an optional preview artifact. The director can accept one comment independently of accepting a whole cut. Historical feedback remains attached to its original cut.

## Long operations and recovery

Import analysis, transcription, proxies, audio processing, and exports return a `jobId`. Jobs pin their input revision and contain phase, status, measurable progress when available, cancellation state, errors, and result artifacts.

Do not hold an MCP call open for an entire export. A client can poll or subscribe where supported, disconnect, then inspect a durable job record. Engine/application interruption and resumability are explicit job properties. A completed export belongs to its pinned cut even if the working sequence changed while it rendered.

## Events and agent wakeup

Use events such as `edit.committed`, `feedback.created`, `feedback.updated`, `cut.created`, and `job.updated`. Durable cursors support replay and reconnect. The UI consumes events immediately through the local service.

MCP resource notifications are hints for compatible clients. They do not guarantee that a particular host will run its AI model or deliver an unsolicited editing turn. The baseline workflow reads `feedback.list` and `events.read` at agent checkpoints and on a user request to revise.

A later supported host hook or persistent agent runner can provide autonomous revision while the user is leaving comments. This is a separate integration with cancellation and session ownership; it is not implied by having an MCP connection.

## Access and observability

Project access and export destinations are explicit capabilities. Do not add arbitrary shell execution or arbitrary filesystem browsing as editor tools. Keep diagnostics, render timings, hardware-path information, and actionable errors available through bounded inspection. Logs include project/revision/job/operation IDs and avoid recording full private transcripts by default.

The bundled helper communicates with the running app. Same-user local IPC is a practical integration boundary, not a claim to protect files from other processes with the same macOS user privileges.

## Contract acceptance tests for implementation

- A stale agent cannot overwrite a newer edit.
- A retried edit cannot duplicate a clip or export.
- A rejected batch cannot leave a partial sequence.
- Fractional frame rates and sample-accurate audio retain sync over long durations.
- The UI and agent inspect the same committed revision.
- A feedback range follows moved/split source content, and reports ambiguity for duplicates.
- A deleted source interval remains reviewable in the original cut.
- The agent can inspect frames and audio before and after its operation.
- An agent-addressed comment stays unapproved until the director accepts it.
- A disconnected client can recover feedback cursors and job outcomes.
- Playback/export use the same color and audio decisions.

---
name: start-project
description: Create or open a local Direction video project, import supplied footage, and prepare an initial edit for the director to review.
---

Use Direction's MCP tools for the local Mac app. The server starts without a project.

For an existing project, call `direction_projects` to find known project paths, or `direction_open_project` with the user's path. For a new project, call `direction_create_project` with `path` (an absolute `.direction` package path) and `name`. Choose a descriptive folder in the user's requested location; otherwise use `~/Movies/Direction/<name>.direction`. Existing paths are never overwritten. If a creation response was lost, open that exact path before trying another creation.

Keep the returned `projectPath` and supply it on **every** project tool call. Opening a project registers it and optionally shows it in the app; it does not change an implicit editing target. Call `direction_open_project` with `showInApp: true` when the director should review it.

Inspect the project, then import each user-supplied file with `direction_import`. `append: false` only adds to the library; `append: true` places it at the end of the sequence. Separate media ingestion from the intended assembly. Inspect returned asset IDs and every embedded audio track before choosing dialogue/music sources. Don't generate or download footage unless the user requests it.

Use `direction_edit` for the requested sequence format and initial assembly. There is no baked-in interview, multicam, or social workflow. Let the user's brief determine the cut. Landscape, portrait, and square are sequence dimensions. Multiple camera angles can be layered manually; automatic synchronization is not implemented.

Inspect exact revision and tool schemas before editing. Use `baseEditRevision` and a distinct `idempotencyKey` for each intended mutation, retaining that key for identical retries. If another edit changed the revision, inspect again and revise the batch. Originals remain linked, so tell the user where their `.direction` project is stored and keep source files available.

Log the footage for the director's Dailies with `direction_log_dailies`: scenes (number, title, setups), and for each take its scene, setup, take code, a one-line caption, flags (flubbed line, soft focus, no audio) and, when you'd recommend it, a `suggestion` with the reason. Put takes you can't place in no scene with a `guessSceneNumber`. You can suggest; only the director circles. If the director has written a brief (`direction_brief`), read it first.

Use `direction_transcribe` with the chosen asset/audio track when dialogue editing is useful. Speech runs locally; first use may download Apple's model. Poll the returned job while the MCP process stays alive. Finally sample actual edited frames/audio, save a review cut, and open the project for the director. Report what is ready and any missing media or unsupported format.

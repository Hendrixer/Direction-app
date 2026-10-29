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

You can't watch video, so Direction looks at the footage for you, the way an assistant editor does when it comes in: it finds every shot, makes a contact sheet for every take, writes a line about each shot, notes the sounds, and makes it all searchable. It starts by itself when footage arrives (if Settings › Footage says so); otherwise call `direction_index`, which returns a job. How shots are described is the director's choice in Settings, never yours. `direction_dailies` gives each take an `index` state: `waiting`, `looking`, `done` or `failed`. A take can be logged as soon as its shots exist, before its descriptions do.

Log the footage for the director's Dailies with `direction_log_dailies`, working from the index rather than raw files:

1. Read the shots with `direction_shots` (by `assetID`, or all of them page by page): each has a source range, a description, size, movement, people, setting, flags and the sounds in it. People are described, never named ("woman, dark hair"); map them to names yourself from the dialogue and the brief.
2. Look at each take's `direction_contact_sheet` (16 frames with source timecodes) to see it whole. When a moment matters (a flub, focus, an eyeline), look at a real frame with `direction_frame` and `assetID` plus `time` in source seconds.
3. Use `direction_search_footage` to find what the brief or a scene needs ("Maya laughing", "wide of the ridge at dusk"), and `similarTo` a shotID to find matching coverage across takes. Results come best shot per take first, with why they matched (`picture`, `words`, `both`).
4. Log scenes (number, title, setups), and for each take its scene, setup, take code, a one-line caption, flags (flubbed line, soft focus, no audio) and, when you'd recommend it, a `suggestion` with the reason. Put takes you can't place in no scene with a `guessSceneNumber`. You can suggest; only the director circles. If the director has written a brief (`direction_brief`), read it first.

When Direction starts you to log footage, it has already transcribed every take with sound: read the words with `direction_transcript`. Otherwise use `direction_transcribe` with the chosen asset/audio track when dialogue editing is useful. Speech runs locally; first use may download the model. The job runs inside this MCP process, so poll it with `direction_job` until it finishes before you end your turn; if you end first, the job stops with you. Finally watch what you assembled with `direction_watch` (a filmstrip of a passage of the cut with its words, sounds and cuts), save a review cut, and open the project for the director. Report what is ready and any missing media or unsupported format.

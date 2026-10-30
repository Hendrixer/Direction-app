# Looking at footage · the editor's contract

A coding agent can't watch video. Direction does what an assistant editor does when footage comes in: it finds every shot, makes a contact sheet for every take, writes a line about each shot, notes the sounds, reads any text on screen, and makes the footage searchable. You read that index, and look at real frames when you need to. The design is `design/spec/specs/footage-index.md`; this page is what the tools promise.

Direction runs the index itself, the same way every time. You don't choose how footage is looked at or which engine describes it; the director does, in Settings › Footage. You read the result.

## When it runs

- **By itself**, when footage arrives and Settings › Footage › "Look at new footage automatically" is on (the default). The app starts it as footage comes in; the MCP server starts it the first time you read `direction_dailies`, `direction_shots` or `direction_search_footage` with takes waiting.
- **On request**, with `direction_index`.
- One index job runs per film at a time, in whichever process started it (the app or an MCP server). Asking again returns the running job. It works take by take in footage order, at background priority, and picks up footage that arrives while it runs.
- Poll it like any job with `direction_job`. Its phase reads "Finding shots · 3 of 12", "Looking at footage · 7 of 12", or "Downloading Qwen3-VL 8B · 42%".
- Stop it with `direction_index` `{"cancel": true}` from the process that runs it (`direction_cancel_job` doesn't reach it).

## What it makes, per take

| Step | How | You get |
|---|---|---|
| Shots | Vision feature prints on frames sampled 4 times a second. A boundary is a local peak in the distance between neighbors above 0.35, or a fade through 4% black; shots are at least 0.5 s; each boundary is placed on the exact frame. | Shots with source ranges, and three small keyframes each (10%, 50%, 90%) in the film's `Index/Keyframes/` |
| Contact sheet | 16 frames evenly across the take, 4 × 4, 1600 px wide, each labeled with its source timecode | One JPEG per take in the film's `Index/` |
| Sounds | Apple's sound classifier in 1 s windows; runs of the same kind merge | Runs of `speech`, `laughter`, `music`, `applause`, `wind`, `traffic`, `silence` |
| Descriptions | Three 672 px keyframes per shot and the take's words for that range, read greedily (temperature 0, 160 tokens) into a fixed shape, checked, with one retry | `description` (≤ 18 words, present tense), `size`, `movement`, `people`, `setting`, `flags` |
| Text on screen | Apple's text recognition on each shot's middle frame; a shot with 12 words or more (a screen recording, slides) is read every 2 s, skipping frames that haven't changed. Lines come largest text first. | Stretches of text with source ranges: `onScreen` in `direction_shots`, all of it in `direction_screen_text` |
| Search | Apple's sentence embeddings for each description, line of dialogue and stretch of text on screen, and SQLite FTS5 for exact words | `direction_search_footage` |

Descriptions come from the engine the director chose:

- **This Mac** (default): mlx-vlm in a helper process. Quick is Qwen2.5-VL 3B (`mlx-community/Qwen2.5-VL-3B-Instruct-4bit`), Standard is Qwen3-VL 8B (`mlx-community/Qwen3-VL-8B-Instruct-4bit`), Best is Qwen3-VL 30B-A3B (`mlx-community/Qwen3-VL-30B-A3B-Instruct-4bit`). Weights download to the Hugging Face cache the first time. Nothing leaves the Mac.
- **OpenRouter**: the three keyframes of each shot go to the chosen vision version with the director's key, four shots at a time. Nothing else leaves the Mac.

If the chosen engine isn't ready (mlx-vlm isn't installed, no room for the download, no OpenRouter key), shots, sheets, sounds and words still run; descriptions are skipped, the take says why in `descriptionsSkipped`, and search uses words only. Nothing falls back to another engine.

## Index states

Every take has one, in `direction_dailies` (`assets[].index`) and `direction_shots` (`takes[].index`):

- `waiting`: not looked at yet (or its job stopped; it'll be picked up again).
- `looking`: in progress. Its shots may already be there; a take can be logged once its shots exist, before it's described.
- `done`: everything that can run has run.
- `failed`: Direction couldn't read it. The director sees "Couldn't look at this take" with Try Again; you can retry with `direction_index` `{"assetIDs": [...]}`.

## Tools

### `direction_index`
`assetIDs?` (only those takes, and retry failed ones), `force?` (look again from scratch), `cancel?`.
Returns `{job, states: {waiting, looking, done, failed}, engine, descriptionsSkipped}`.

### `direction_shots`
`assetID?`, `sceneID?`, `offset`, `limit` (default 100, at most 500).
Returns `{shots, takes, total, nextOffset}`. Each shot:

```json
{ "id": "shot-…", "assetID": "asset-…", "number": 2,
  "start": 9.5, "end": 22.833, "range": "00:09:12–00:22:20",
  "description": "Push in to a medium. Window light on her face.",
  "size": "medium", "movement": "push", "people": ["woman, dark hair"], "setting": "office, dusk",
  "flags": [], "sounds": [{"kind": "speech", "start": 12.0, "end": 16.0}],
  "keyframes": ["…/Index/Keyframes/asset-…/2-1.jpg", "…/2-2.jpg", "…/2-3.jpg"],
  "describedWith": "mlx-vlm · mlx-community/Qwen3-VL-8B-Instruct-4bit",
  "onScreen": null }
```

`description` is null until the shot is described. `onScreen` is the gist of the shot's text on screen, largest text first (up to 24 words), or null when there's none. People are what's visible, never names: map them to names yourself from the dialogue and the brief when you log.

### `direction_contact_sheet`
`assetID`, `range?` `{start, end}` in source seconds, `frames` 4–36 (default 16).
Returns the image inline plus `{columns, rows, cells: [{cell, time, timecode}], path}`. Cells read left to right, top to bottom; each is centered in an equal part of the range. The default sheet is the one made when the take was looked at.

### `direction_frame` with `assetID`
`assetID`, `time` (source seconds), `maxDimension?`. A real frame of the take itself, not of the cut, as an inline PNG with `{time, timecode, width, height, source: true}`. Without `assetID` it renders the cut as before.

### `direction_watch`
`start`, `end` (cut seconds), `revision?`, `sequenceID?`, `frames` 8–24 (default 12).
The closest thing to watching: a filmstrip image of the passage labeled with cut timecodes, with each frame that follows a cut marked "CUT" and the words spoken written under it. Returns `{revision, range, cells: [{cell, time, timecode, afterCut}], cuts: [{time, timecode}], words, sounds: [{start, end, kind}], path}`. Every call is recorded with its revision and range (`ProjectStore.watchedRanges`) for the turnover's delivery check, so watch every passage you changed before delivering a cut.

### `direction_screen_text`
`assetID`, `range?` `{start, end}` in source seconds (keeps the stretches that overlap it).
Returns `{assetID, take, read, stretches: [{shotID, start, end, range, lines}], note}`. `read` is false until Direction has read the take. A stretch spanning its whole shot is text that stayed on screen throughout (a window title, a slide's heading); the others are what came and went, each from about when it appeared to about when it left. Lines come largest text first, then top to bottom. Use it to cut to a screen recording while it shows what's being said, and to caption screen recordings by what they show rather than "a computer screen".

### `direction_search_footage`
`query`, `sceneID?`, `circledOnly?`, `wordsOnly?` (transcripts alone), `similarTo?` (a shotID), `limit` (default 12).
Ranks shots by the meaning of their descriptions and lines (Apple's sentence embeddings) blended with exact words (FTS5, stemmed, so "laughing" finds "laughs"): 0.6 meaning, 0.4 words. Each take's best shot comes first, then other shots. `similarTo` ranks by how alike the pictures are (Vision feature prints) instead.
Returns `{results, stillLooking}`; each result has `shotID, assetID, take, sceneID, circled, score (0–1), why (picture | words | both | screen), text, matched, start, end, range, keyframes`. `text` is the description, the quoted line when it matched on words, or the lines on screen that matched. For `screen`, `start`–`end` is when that text is on screen; otherwise it's the shot. Search runs on this Mac; the query never leaves it.

## Where things live

- Shots, sounds, text on screen, vectors, FTS5 and watched ranges: tables in the film's `project.sqlite` (`index_*`). They're Direction's own working state, never part of an edit revision, and are rebuilt from the footage at any time.
- Contact sheets and keyframes: the film package's `Index/` folder.
- The 672 px frames read by the describer are temporary and deleted after each take.
- Settings: the `dev.direction.shared` defaults suite (`lookEngine`, `lookDetail`, `lookOpenRouterVersion`, `lookAutomatically`).
- The helper: `describe.py` in the app's resources, run with the Python from `uv tool install mlx-vlm` (`~/.local/share/uv/tools/mlx-vlm/bin/python`), or any `python3` that can `import mlx_vlm`. It loads one version and answers JSON lines, `{"id", "images", "prompt", "max_tokens"}` → `{"id", "text"}` or `{"id", "error"}`, after a first `{"ready": true}`. It stops 60 s after its last shot.

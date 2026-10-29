# Made picture and sound

Sometimes a note needs something the footage doesn't have: music under the drive, the sound of rain, a sky at dusk, an establishing shot nobody filmed. You can make it through OpenRouter with the director's key. Direction makes every request: you never see the key, and you never call OpenRouter yourself. Everything you make says where it came from and what it cost, and nothing is spent past the director's limits.

The director's UI never says "generate", "AI", "prompt" or "model". Things are **made**, you **asked for** something, and services have **versions**. Use the same words in read-backs, answers and questions.

## Footage first

1. Search the footage (`direction_search_footage`) before making anything. Make something only when a note asks for what the footage doesn't have, or with latitude `free` (then the answer is Unasked).
2. Say it in the read-back, with the version and about what it costs: "Note 4: make a sparser piano bed with Lyria 3 Clip, about $0.04."
3. When you use a sound effect, say in the read-back that quality varies.

## Tools

### `direction_services` (no arguments)

Returns:

- `services[0]`: `{name: "OpenRouter", state: "ready" | "notSet", kinds: [{kind, version, versionName, price?, durations?}]}`. Each kind shows the version Settings › Services chose, or the default.
- `limits`: `{askAbovePerTurnover, stopAtPerMonth}`. `stopAtPerMonth` is null for no limit.
- `turnover`: `{id, spent, left}` for the open turnover, or null.
- `month`: `{spent, left}`.

Defaults:

| Kind | Default version | Price |
|---|---|---|
| Music | Lyria 3 Clip | About $0.04 per 30 s clip |
| Sound effects | Lyria 3 Clip | Same as music |
| Voice | The first speech version OpenRouter lists | Per character |
| New shots | Veo 3.1 | About $0.40 a second at 1080p, with sound |
| Stills | Nano Banana 2 | Per image |

Versions and prices come from OpenRouter's model lists, cached for a day in `~/Library/Application Support/Direction/openrouter-models.json`.

### `direction_make`

| Argument | Required | Meaning |
|---|---|---|
| `kind` | yes | `music`, `soundEffect`, `voice`, `shot`, `changedShot` (a shot from one you have) or `still`. |
| `ask` | yes | What to make, in plain words. For `voice`, the words to say. This is what the director reads as "What the editor asked for", so write it for them. |
| `note` | yes | The note ID it's for (a note number also works), or `"unasked"`. |
| `turnover` | yes | The turnover ID. |
| `seconds` | for music, sound effects and shots | The length. Music and effects go up to 600 s; shots up to 60 s, rounded up to a length the version offers (Veo 3.1 offers 4, 6 or 8 s). |
| `from` | for `changedShot` | `{assetID, start, end?}` in source seconds. The take's frame at `start` becomes the shot's first frame. OpenRouter's video API takes images, not video, so "change the sky" makes a new shot that starts on that frame. |
| `references` | no | Asset ids of stills or takes, as visual references for shots and stills. |
| `ways` | no | 1 (default) or 2. With 2 it makes it twice, for options A and B, at twice the cost. |
| `version` | no | A version id from `direction_services`. |
| `estimateOnly` | no | Returns `{spend, seconds, version, versionName, requests, priced}` and spends nothing. |
| `spendQuestionID` | no | A spend question the director answered yes to (below). |

Otherwise it returns a job. Poll `direction_job` until its status is `completed`. Its `result` is:

```json
{"assetID": "asset-…", "made": [{"assetID": "asset-…", "file": "Made/music-sparse-felt-piano-1a2b.wav", "provenance": {"kind": "music", "version": "google/lyria-3-clip-preview", "versionName": "Lyria 3 Clip", "asked": "…", "seconds": 24, "spend": 0.04, "noteID": "…", "turnoverID": "…"}}], "spend": 0.04, "estimate": 0.04}
```

What happens to the result:

- Made clips are ordinary footage. They're copied into `<film>.direction/Made/`, brought in with `direction_import`, and placed like any other asset (`placeMade`, `placeMusic`, or `direction_edit`).
- Their provenance is kept by asset id, so Changes, Dailies and History show it.
- A made clip used in an option's version shows a Made chip on that option.

Music longer than a clip is made in 30 s clips, joined with a short crossfade and cut to `seconds`. Clips aren't joined on a beat. Shorter music is cut to `seconds`, with a short fade at the end.

## Spend

Every request reserves its estimate before it goes out. It's settled at what OpenRouter reports (`usage.cost`), or at the estimate when OpenRouter doesn't report a cost. A failed request gives its hold back, unless something was already made and charged.

The record is per Mac and per month, and the month resets on the 1st. The app and the editor's tools share it in `~/Library/Application Support/Direction/spend.json`, under a file lock.

### Over the turnover's limit

When a make would push the turnover past the director's limit, `direction_make` returns this, not a job:

```json
{"status": "spend_over_limit", "estimate": 3.2, "turnoverSpent": 2.9, "turnoverLimit": 5, "left": 2.1, "message": "…"}
```

Nothing has been sent. To go ahead:

1. Ask a spend question. Direction writes the money line ("About $3.20. This turnover would reach $6.10 of your $5.00 limit.") from its own record:

   ```json
   {"kind": "spend", "turnoverID": "…", "noteIDs": ["…"],
    "text": "Note 3 wants less sky. Reframing to 1.6× gets the sky to a third of the frame. To change the sky itself to dusk cloud, I'd make a new shot from this frame with Veo 3.1.",
    "choices": [{"id": "reframe", "label": "Reframe only", "detail": "No spend", "recommended": true, "assetID": "…"},
                {"id": "make", "label": "Make a new shot from this frame", "detail": "About $3.20", "assetID": "…"},
                {"id": "find", "label": "Find another take", "detail": "I'll search the ridge footage first"}],
    "spend": {"estimate": 3.2, "choiceID": "make", "kind": "changedShot"}}
   ```

2. Wait for the director's answer in `direction_questions`.
3. If they picked the `choiceID` choice, call `direction_make` again with `spendQuestionID`.

Rules for that approval:

- One yes lets exactly one request past the turnover's limit (`spend_question_used` after that).
- It covers up to 10% more than the question's estimate (`spend_over_question` past that).
- It never gets past the monthly cap.
- Other answers return `spend_not_agreed`. Then do what the director chose instead.

### Past the monthly cap

```json
{"status": "spend_cap", "estimate": 3.2, "monthSpent": 48, "monthLimit": 50, "left": 2, "message": "…"}
```

There's no override from your side. Tell the director in your answer or a can't-do. Only they can raise the limit in Settings › Services.

## Errors

| Code | Meaning |
|---|---|
| `no_openrouter_key` | There's no key in Settings › Services. Nothing was sent. |
| `openrouter_key_rejected`, `openrouter_credits`, `openrouter_error` | OpenRouter refused. The message is OpenRouter's own. |
| `shot_failed`, `shot_timeout` | The video job failed or ran past 30 minutes. |
| `unknown_version`, `invalid_arguments`, `feedback_not_found`, `turnover_not_found` | Fix the call. |

## The key

The director pastes the key once, in Settings › Services. Direction checks it with `GET /key`, which is free.

The key is kept in the login keychain. There's one copy for the app and one for the bundled `direction` tool that runs your MCP calls. The app hands the tool its copy on standard input (`direction key save`).

There are two copies because of how macOS protects keychain items. Since macOS 10.12, an item's partition list makes a second unsigned or ad-hoc-signed binary prompt for the keychain password, even when the item's access list trusts it. So each binary reads only its own copy, with keychain dialogs turned off. A rebuilt tool that can't read its copy fails instead of asking, and the app gives it the key again the next time Settings › Services opens.

The key never appears in tool arguments, results, job records, logs or the film. Removing it in Settings stops new requests at once, and made clips stay playable.

Frames sent for a shot from one you have leave the Mac. OpenRouter's video generation isn't eligible for zero data retention.

## For other areas

`OpenRouter.chat(_:spend:)` is the plain chat call. Pass `spend: .looking` to count a footage-description request's `usage.cost` in this Mac's record, where Settings shows it as "Looking at footage". Tests stub every call with `OpenRouter.$overrides.withValue(.init(transport:key:service:ledger:catalog:limits:pollInterval:))`. It's task-local, so parallel test suites never share a transport, key, ledger or cache.

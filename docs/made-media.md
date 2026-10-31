# Made picture and sound

Sometimes a note needs something the footage doesn't have: music under the drive, the sound of rain, a sky at dusk, an establishing shot nobody filmed. You can make it through OpenRouter with the director's key. Direction makes every request: you never see the key, and you never call OpenRouter yourself. Everything you make says where it came from and what it cost, and nothing is spent past the director's limits.

The director's UI never says "generate", "AI", "prompt" or "model". Things are **made**, you **asked for** something, and services have **versions**. Use the same words in read-backs, answers and questions.

## Footage first, then a plan

1. Search the footage (`direction_search_footage`) before making anything. Make something only when a note asks for what the footage doesn't have, or with latitude `free` (then the answer is Unasked).
2. For picture, plan in steps with the `make-shot` skill: frames of the film as references, stills before motion, short shots with small motion, and change a take rather than replace it.
3. Price the whole plan with one `direction_estimate` call. Under the director's limit, make it. Over it, ask one spend question for the plan.
4. Say it in the read-back, with what Direction will use and about what it costs: "Note 3: change the sky to dusk cloud with Aleph 2.0, about $1.40." When you use a sound effect, say that quality varies.

## You don't choose versions

Direction picks the version for every request from what it needs and the director's **Made with** setting (Best, Balanced or Cheapest): the frames it sends, its length, and whether a frame shows a person (ByteDance's Seedance and Seedream refuse those). If a version turns a request down, Direction moves to the next one and the result's `note` says so; say that in your answer. There is no `version` argument. `direction_services` and `direction_estimate` tell you what will be used.

## Tools

### `direction_services` (no arguments)

Returns:

- `services`: OpenRouter (`state: "ready" | "notSet"`) and This Mac (`kinds: ["slowMotion", "upscale"]`, `sharpening: "ready" | "downloadsOnFirstUse" | "downloading" | "unavailable"`).
- `kinds`: `[{kind, label, version, versionName, service, price?, durations?, lastFrame?, withAPerson?}]`. The version Direction would use now for a typical request of the kind (shots from a first frame); `withAPerson` is the one it would use when a frame shows a person, if different.
- `madeWith`: `best`, `balanced` or `cheapest`, the director's choice.
- `limits`: `{askAbovePerTurnover, stopAtPerMonth}`. `stopAtPerMonth` is null for no limit.
- `turnover`: `{id, spent, left}` for the open turnover, or null.
- `month`: `{spent, left}`.

What's used:

| Kind | Version | Price |
|---|---|---|
| `music`, `soundEffect` | Lyria 3 Clip | About $0.04 per 30 s clip |
| `voice` | The first speech version OpenRouter lists | Per character |
| `still` | Chosen: GPT Image 2.5, Nano Banana 2.1 and others, by Made with | A few cents to about 20 cents per image |
| `shot`, `extension`, `bridge` | Chosen: Seedance 2.5, MiniMax H3, Wan 3.0 and others, by Made with and whether a frame shows a person | About $0.08 to $0.25 a second |
| `changedShot` | Chosen: Aleph 2.0, or FLUX Video Edit on Cheapest | About $0.28 a second ($0.56 at least); FLUX Video Edit about $0.03 |
| `slowMotion` | This Mac (Apple frame interpolation) | Nothing |
| `upscale` | This Mac (Apple super resolution) up to 1920 × 1080; FLUX Video Upscale above | Nothing on this Mac |

Versions and prices come from OpenRouter's model lists, cached for a day in `~/Library/Application Support/Direction/openrouter-models.json`.

### `direction_estimate`

`{turnover, steps: [<direction_make arguments>, …]}` (up to 24 steps; `note` may be left out). Spends nothing. Returns each step's `{kind, version, versionName, spend, seconds, requests, note?}`, the plan's `total`, `turnoverSpent`, `limit`, `needsQuestion`, `monthSpent`, `monthLeft`, `overMonthlyCap` and a `message` saying what to do.

### `direction_make`

| Argument | Required | Meaning |
|---|---|---|
| `kind` | yes | `music`, `soundEffect`, `voice`, `still`, `shot`, `extension`, `bridge`, `changedShot`, `slowMotion` or `upscale`. |
| `ask` | except slow motion and sharpening | What to make, or for a changed shot what to change, in plain words. For `voice`, the words to say. The director reads it as "What the editor asked for", so write it for them. |
| `note` | yes | The note ID it's for (a note number also works), or `"unasked"`. |
| `turnover` | yes | The turnover ID. |
| `seconds` | music, sound effects, shots, extensions, bridges | The length. Music and effects up to 600 s; shots up to 60 s, rounded up to a length the version offers. Keep shots 4–6 s. |
| `from` | changed shots, slow motion, sharpening, extensions | `{assetID, start, end}` in source seconds: the range to change (up to 10 s), slow down (up to 20 s) or sharpen (up to 60 s). For an extension, `{assetID, end, side: "tail"}` continues from `end`. |
| `first`, `last` | bridges need both | `{assetID, at?}`: the frame a shot starts or ends on, from a still (no `at`) or a take at `at` seconds. A `last` always needs a `first`: OpenRouter turns it down otherwise, so to land on a take, make a still for the first frame and a bridge from it. |
| `references` | no | Up to 4 stills or takes (`assetID`, or `{assetID, at}`) that ground a still or shot in the film. |
| `sound` | no | Shots, extensions and bridges are silent unless true. |
| `factor` | slow motion | 2 (default), 3 or 4. |
| `ways` | no | 1 (default) or 2; up to 4 for stills. Each way costs the same again. |
| `estimateOnly` | no | Returns `{spend, seconds, version, versionName, requests, priced}` and spends nothing. |
| `spendQuestionID` | no | A spend question the director answered yes to (below). |

Otherwise it returns a job. Poll `direction_job` until its status is `completed`. Its `result` is:

```json
{"assetID": "asset-…", "made": [{"assetID": "asset-…", "file": "Made/changedShot-replace-the-overcast-sky-1a2b.mov", "check": {"verdict": "broken", "findings": ["Something looks broken at 0:03."], "frames": [{"at": 0, "verdict": "clean"}, …], "shadow": true}, "provenance": {"kind": "changedShot", "version": "runway/aleph-2", "versionName": "Aleph 2.0", "asked": "…", "seconds": 5, "spend": 1.4, "from": {"assetID": "…", "start": 12, "end": 17}, "sharpenedFrom": "1280 × 720", "noteID": "…", "turnoverID": "…", "check": {…}}}], "spend": 1.4, "estimate": 1.4}
```

`check` is Direction's own look at each way of a new shot, extension, bridge, changed shot or still, before you see it, by a fast decision version that sees pictures (GPT-6 Luna decisions; Jev 1.14 when Luna can't answer). Five frames (start, ¼, ½, ¾, end; a still is one) are each asked whether anything in them is broken, the first and last whether the people and the place stayed the same, all five whether things move or morph, and the whole whether it shows what was asked. `verdict` is the worst it found: `clean`, `minor` or `broken`, with `findings` in words and each frame's verdict at its time in seconds. `{"verdict": "unchecked", "why": …}` when it couldn't look (the shot is still made and paid for). `shadow: true`: the check is new and still being tuned against what the director keeps, so it decides nothing. Use it to know where to look, not instead of looking (make-shot › Judge every frame). Each check costs well under a cent, in Settings › Spent this month under Checking.

How each kind is made:

- **Still:** `POST /images` with references as image parts.
- **Shot, extension, bridge:** `POST /videos` with `frame_images` (`first_frame`, `last_frame`), references as image parts, `generate_audio` from `sound`. An extension's first frame is the take's frame at `end` (tail), or its last frame is the frame at `start` (head).
- **Changed shot:** the range is sent itself, as an H.264 file (1280 wide at most, under 16 MB) in `input_references` as a `video_url`. What comes back is the same length, without sound. Place it on V2 over the same range so the take's sound keeps playing.
- **Slow motion** and **sharpening on this Mac** use Apple's frame interpolation and super resolution. Nothing leaves the Mac and nothing is spent. Apple's sharpening takes inputs up to 1920 × 1080 and downloads its files on first use.

Finishing: every shot that comes back from OpenRouter is sharpened on this Mac to the cut's size when the cut is at least 1.5× taller and this Mac can (the result's provenance has `sharpenedFrom`; `sharpened: false` says it couldn't). An extension's repeated join frame is dropped. Finished files are HEVC 10-bit.

What happens to the result:

- Made clips are ordinary footage. They're copied into `<film>.direction/Made/`, brought in with `direction_import`, and placed like any other asset (`placeMade`, `placeMusic`, or `direction_edit`).
- Their provenance is kept by asset id, so Changes, Dailies and History show it.
- A made clip used in an option's version shows a Made chip on that option.

Music longer than a clip is made in 30 s clips, joined with a short crossfade and cut to `seconds`. Clips aren't joined on a beat. Shorter music is cut to `seconds`, with a short fade at the end.

## Spend

Every request reserves its estimate before it goes out. It's settled at what OpenRouter reports (`usage.cost`), or at the estimate when OpenRouter doesn't report a cost. A failed request gives its hold back, unless something was already made and charged.

The record is per Mac and per month, and the month resets on the 1st. The app and the editor's tools share it in `~/Library/Application Support/Direction/spend.json`, under a file lock.

### Over the turnover's limit

Price the plan first with `direction_estimate`. When `needsQuestion` is true, or a make returns `spend_over_limit`, nothing has been sent:

```json
{"status": "spend_over_limit", "estimate": 1.4, "turnoverSpent": 4.1, "turnoverLimit": 5, "left": 0.9, "message": "…"}
```

To go ahead:

1. Ask one spend question for the whole plan, with its total. Direction writes the money line ("About $2.75. This turnover would reach $5.65 of your $5.00 limit.") from its own record:

   ```json
   {"kind": "spend", "turnoverID": "…", "noteIDs": ["…"],
    "text": "Note 3 wants less sky. Reframing to 1.6× gets the sky to a third of the frame. To make the sky itself dusk cloud, I'd change those 5 seconds of the take with Aleph 2.0, and make an establishing shot of the ridge at dusk to lead in.",
    "choices": [{"id": "reframe", "label": "Reframe only", "detail": "No spend", "recommended": true, "assetID": "…"},
                {"id": "make", "label": "Change the sky and add the dusk shot", "detail": "About $2.75", "assetID": "…"},
                {"id": "find", "label": "Find another take", "detail": "I'll search the ridge footage first"}],
    "spend": {"estimate": 2.75, "choiceID": "make", "kind": "changedShot"}}
   ```

2. Wait for the director's answer in `direction_questions`.
3. If they picked the `choiceID` choice, make each step with `spendQuestionID`.

Rules for that approval:

- A yes covers the plan it priced: every request that names it may go past the turnover's limit until together they've used the estimate plus 10% (`spend_over_question` past that).
- It never gets past the monthly cap.
- Other answers return `spend_not_agreed`. Then do what the director chose instead.

### Past the monthly cap

```json
{"status": "spend_cap", "estimate": 3.2, "monthSpent": 48, "monthLimit": 50, "left": 2, "message": "…"}
```

There's no override from your side. Tell the director in your answer or a can't-do. Only they can raise the limit in Settings › Engines.

## Errors

| Code | Meaning |
|---|---|
| `no_openrouter_key` | There's no key in Settings › Engines. Nothing was sent. |
| `openrouter_key_rejected`, `openrouter_credits`, `openrouter_error` | OpenRouter refused. The message is OpenRouter's own. |
| `shot_failed`, `shot_timeout` | The video job failed or ran past 30 minutes. |
| `spend_over_question` | The plan's yes is used up. Ask again for the rest. |
| `nothing_to_sharpen`, `cant_sharpen` | The take is already the cut's size, or bigger than Apple's sharpening takes (use FLUX Video Upscale). |
| `invalid_arguments`, `feedback_not_found`, `turnover_not_found` | Fix the call. |
| `unknown_version` | No version on OpenRouter can make it as asked (too long, or a frame no version takes). Make it shorter, or plan it another way. |

## The key

The director pastes the key once, in Settings › Engines. Direction checks it with `GET /key`, which is free.

The key is kept in the login keychain. There's one copy for the app and one for the bundled `direction` tool that runs your MCP calls. The app hands the tool its copy on standard input (`direction key save`).

There are two copies because of how macOS protects keychain items. Since macOS 10.12, an item's partition list makes a second unsigned or ad-hoc-signed binary prompt for the keychain password, even when the item's access list trusts it. So each binary reads only its own copy, with keychain dialogs turned off. A rebuilt tool that can't read its copy fails instead of asking, and the app gives it the key again the next time Settings › Engines opens.

The key never appears in tool arguments, results, job records, logs or the film. Removing it in Settings stops new requests at once, and made clips stay playable.

Frames and ranges sent for a shot leave the Mac. OpenRouter's video services aren't covered by zero data retention.

## For other areas

`OpenRouter.chat(_:spend:)` is the plain chat call. Pass `spend: .looking` to count a footage-description request's `usage.cost` in this Mac's record, where Settings shows it as "Looking at footage". Tests stub every call with `OpenRouter.$overrides.withValue(.init(transport:key:service:ledger:catalog:limits:pollInterval:))`. It's task-local, so parallel test suites never share a transport, key, ledger or cache.

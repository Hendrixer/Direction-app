# Made picture and sound

Frames 55 (Settings › Services), 61 (a made answer in Changes), 62 (a spend question). Read `product-model.md › Made, Service, Spending` first.

Sometimes a note needs something the footage doesn't have: music under the drive, the sound of rain, a sky at dusk, an establishing shot nobody filmed. The editor can make it through OpenRouter, using the director's key. Direction makes every request, so keys never reach the editor; every made thing says where it came from and what it cost; and nothing is spent past the director's limits.

The UI never says "generate", "AI", "prompt" or "model". Things are **made**; the editor **asked for** something; services have **versions**.

---

## Services

Every service goes through **OpenRouter**: one key, one bill, many versions. Direction calls OpenRouter's API at `https://openrouter.ai/api/v1` with `Authorization: Bearer <key>`.

| Use | Kinds | OpenRouter call | Default version | Notes |
|---|---|---|---|---|
| Music | music | `POST /chat/completions` with `modalities: ["text","audio"]`, `stream: true`; audio arrives in `delta.audio` chunks | Lyria 3 Clip (30 s clips) | Longer beds are made in clips and joined on a beat by Direction. |
| Voice | voice | `POST /audio/speech` | The first speech version listed | Temp voiceover and scratch narration. |
| Sound effects | soundEffect | `POST /chat/completions` with audio output | The music version | Quality varies; the editor says so in the read-back when it uses one. |
| New shots | shot | `POST /videos` (async: `pending` → `in_progress` → `completed`), poll `GET /videos/{id}`, download `GET /videos/{id}/content` | Veo 3.1 | Text to video, or from a frame (`frame_images` with `first_frame`/`last_frame`) and `input_references`. |
| A shot from one you have | changedShot | `POST /videos` with a frame of the take as `first_frame` and the ask | Veo 3.1 | OpenRouter's video API takes images, not video, so "change the sky" makes a new shot that starts on that take's frame. |
| Stills | still | `POST /images`, or chat completions with image output | Nano Banana 2 | Backgrounds and plates for graphics. |
| Looking at footage | — | `POST /chat/completions` with keyframes as `image_url` parts and `response_format: {type: "json_schema"}` | Gemini 3.1 Flash | Only when Settings › Footage › Look with is OpenRouter. |

- Versions come from OpenRouter's model lists (`GET /models?output_modalities=audio|image|video`, `GET /videos/models`), cached for a day. Settings › Services shows the version used for each kind, with the defaults above.
- **Estimates** come from each version's listed pricing (per second of video, per clip, per token). **Spend** is what OpenRouter reports for the request: `usage.cost` on video jobs and chat responses. The month's total is Direction's own record of those.
- OpenRouter's video generation isn't eligible for zero data retention; the Services note says footage frames sent for a shot leave this Mac.

- Other services can be added later behind the same tools.
- The key is stored in the macOS Keychain as Direction's own item, readable by the Direction app and its bundled `direction` tool, which handles the editor's tool calls. It never appears in the film, the logs, or any tool's arguments or results.
- Saving the key tests it with `GET /key` (credits and limits) and shows Ready with the credits left, or the error.

## Spending

| Setting | Default | Behavior |
|---|---|---|
| Ask before spending more than | $5.00 per turnover | The editor may spend up to this much in one turnover without asking. More needs a spend question. |
| Stop for the month at | $50.00 | Nothing is made past this. The editor is told `spend_cap`, and the run's banner offers Change limit… (frame 58's table). |

The month resets on the 1st. "Spent this month" sums Direction's own record of every made thing, per service. It doesn't read the service's own bill.

## Tools

| Tool | Arguments | Returns |
|---|---|---|
| `direction_services` | — | Ready services, their kinds and versions, the limits, what's left in this turnover and this month |
| `direction_make` | `kind`, `service?`, `version?`, `ask` (what to make, in plain words), `seconds`, `from?` (`{assetID, range}`, for a changed shot), `references?` (asset ids or stills), `ways` (1 or 2), `note`, `turnover`, `estimateOnly?` | With `estimateOnly`: `{spend, seconds}`. Otherwise a job; when done, the made clip's `assetID` and its provenance. |

- Over the turnover's limit, `direction_make` returns `spend_over_limit` with the estimate and what's left. The editor then asks a spend question (`direction_ask` kind `spend`, below) and calls again with the question's id once the director agrees.
- Over the monthly cap, it returns `spend_cap`. There's no override from the editor's side.
- Made files are saved in `<film>.direction/Made/` (copied in, never linked), probed like footage, and placed with the `placeMade` or `placeMusic` edit functions (`agent-timeline.md`).
- Footage first: the `take-turnover` skill tells the editor to search the footage (`direction_search_footage`) before making anything, and to say in the read-back when it plans to make something: "Note 4: make a sparser piano bed with Lyria 3 Clip, about $0.04."

## Where made things show

- **Read-back:** the plan line says what will be made and about how much it costs.
- **Changes:** an answer that uses made picture or sound has a **Made** chip after its delta: a neutral steel `.chip` with the editor's 7 pt diamond before the word. Clicking it opens the provenance popover (frame 61).
- **Dailies:** a "Made" group after Unsorted lists every made clip with its provenance, so it can be watched and reused like footage.
- **History:** each made clip's provenance stays with the cut that introduced it.

---

## 55 · Settings, Services
Frame: `screens/55-settings-services.html` · 720 × 682. See `settings.md › 55`.

## 61 · Changes, made music
Frame: `screens/61-changes-made.html` · 1440 × 900.

The Changes room on Cut 4 with note 4 selected ("Music is too sure of itself here.", Sound, 01:43:20). In this frame the answer is two ways:
- Answer text: "Two ways. A: the same track, down 6 dB under her line. B: a sparser piano bed I made, with no resolve."
- Options stage as in frame 30: A and B tiles. B's tile carries the **Made** chip.
- The provenance popover is open from B's chip (320 wide, `.pop`):
  - Header: diamond + "Made with Lyria 3 Clip" (13/600). Sub: "Music · OpenRouter · Oct 28 14:02" (11.5 text-3).
  - Section "WHAT THE EDITOR ASKED FOR" and the text in 12.5 text-2, in quotes: "Sparse felt piano, unresolved, around 70 bpm. No swell. 24 seconds, ending on a held note."
  - Rows (label text-3, value SF Mono text-2, right): Version · "google/lyria-3-clip"; Length · "0:24"; Spent · "$0.04"; For · "Note 4".
  - Footer: "Play it alone" (text link, plays only the made audio from its start) and "Show in Dailies".

## 62 · Notes, a spend question
Frame: `screens/62-notes-spend.html` · 1440 × 900.

The Notes room during the read-back of Cut 4's turnover, the questions panel open (frame 20's layout), with a spend question.

- Question card text: "Note 3 wants less sky. Reframing to 1.6× gets the sky to a third of the frame. To change the sky itself to dusk cloud, I'd make a new shot from this frame with Veo 3.1."
- A spend line under the text: "About $3.20. This turnover would reach $6.10 of your $5.00 limit." Money in SF Mono; the limit sentence in text-3.
- Choices (2–4, the existing question choice rows):
  - "Reframe only" · "No spend" · with the editor's recommendation diamond.
  - "Make a new shot from this frame" · "About $3.20".
  - "Find another take" · "I'll search the ridge footage first".
- Free text field as in frame 20.
- The pill shows "1 question".

Picking "Make a new shot" allows that one request to go over the turnover's limit. It never allows going past the monthly cap.

**Acceptance:**
- [ ] No request reaches a service without a key saved in Settings and a spend under both limits or a yes to a spend question.
- [ ] Every made clip shows its service, what the editor asked for, the version and the spend, from Changes, Dailies and History.
- [ ] Removing a service's key stops new requests and leaves made clips playable.

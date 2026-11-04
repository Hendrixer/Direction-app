# Made picture and sound

Frames 55 (Settings › Services), 61 (a made answer in the Cut room), 62 (a spend question). Read `product-model.md › Made, Service, Spending` first.

Sometimes a note needs something the footage doesn't have: music under the drive, the sound of rain, a sky at dusk, a beat more of her face, an establishing shot nobody filmed. The editor can make it through OpenRouter, using the director's key, or on this Mac. Direction makes every request, so keys never reach the editor; every made thing says where it came from and what it cost; and nothing is spent past the director's limits.

The UI never says "generate", "AI", "prompt" or "model". Things are **made**; the editor **asked for** something; services have **versions**.

---

## How good shots get made

The way people get good results from video services (2026) is the same everywhere, from Higgsfield's Supercomputer to research systems like ViMax: **a planner breaks the job into steps, works out the picture as stills first, and spends on motion last.** Direction's editor is that planner. Direction gives it the steps as `direction_make` kinds, the recipes in the `make-shot` skill, and one money rule.

1. **Footage first.** Search the footage before making anything (`direction_search_footage`).
2. **Ground it in the film.** References are frames of the film's own takes (the location, the light, the wardrobe, the lens), so what's made matches what's around it.
3. **Stills before motion.** A still costs cents, a second of video 10–40 cents. Make stills (two to four ways), look at them, fix the best one with another still if it's 80% right, then animate it.
4. **Short, small motion.** 4–6 seconds, one action, one camera move. Long clips drift.
5. **Frames hold continuity.** An extension starts on the take's last frame; a bridge starts on one take and ends on another.
6. **Change the take, don't replace it.** "Lose the boom", "dusk sky", "change the sign": the take itself is changed over the smallest range that holds the problem.
7. **Watch before using.** The editor looks at every made clip before it places one, and makes it once more at most.
8. **Finish it like footage.** Direction sharpens made shots to the cut's size on this Mac; the editor balances them to their neighbors (`matchBalance`); the director's look and grain sit over everything.

## What the editor can make

| Kind | Label | For | Made with | Version |
|---|---|---|---|---|
| `music` | Music | Beds and stings | OpenRouter | Lyria 3 Clip |
| `soundEffect` | Sound effect | Rain on glass, a door | OpenRouter | Lyria 3 Clip |
| `voice` | Voice | Scratch narration, temp lines | OpenRouter | The first speech version listed |
| `still` | Still | Plates, backgrounds, a shot's first frame | OpenRouter | Chosen (below) |
| `shot` | New shot | Inserts, B-roll, establishing shots, a pickup | OpenRouter | Chosen |
| `extension` | Extended shot | "Hold on her a beat longer" | OpenRouter | Chosen |
| `bridge` | Bridge | "Get us from the car to the door" | OpenRouter | Chosen, from those that take a last frame |
| `changedShot` | Changed shot | Remove, replace, relight or restyle something in a take | OpenRouter | Chosen: Aleph 2.0 or FLUX Video Edit |
| `slowMotion` | Slow motion | "Slow that down" | This Mac | Apple frame interpolation |
| `upscale` | Sharpened | A soft take, a small made shot | This Mac, or OpenRouter | This Mac up to 1920 × 1080; FLUX Video Upscale above |

### Choosing a version

Nobody picks versions: there are dozens, they change monthly, and what's best depends on the request. The director chooses one thing, **Made with** (Settings › Engines): **Best** (the best-rated version that can make it, whatever it costs), **Balanced** (the default: the cheapest of the versions rated within 50 of the best one that can make it) or **Cheapest** (the cheapest rated at least 1000). Direction then picks each request's version (`MadeCatalog.route`):

1. **What can make it.** From OpenRouter's list, the versions for the kind that take the frames it sends (`supported_frame_images`; a last frame always comes with a first), offer its length, and take a person if a frame shows one.
2. **A person in a frame.** Direction looks at every frame and reference it will send, on this Mac (Vision's faces and bodies; the back of a head counts). ByteDance's service (Seedance, Seedream) refuses input images that may show a real person unless that person was registered with ByteDance, so those are left out. A version that turned down a frame with a person is skipped for a week (`made-refusals.json` beside the spend ledger).
3. **How good.** Ratings are the Artificial Analysis arenas, read 31 Oct 2026 (image to video for shots, image editing for stills), in `MadeRanking.ratings`. Versions without a rating come after every rated one, and versions OpenRouter lists no price for come after every priced one.
4. **If it's turned down.** A request a version refuses for what's in it (a person, a policy) goes to the next one, up to two more, and the result's `note` says so: "Seedance 2.5 wouldn't take a frame with a person in it, so this used MiniMax H3." A refusal costs nothing. The next version is checked against both limits and the spend question's yes again; if it would pass one, the job ends with `spend_over_limit` or `spend_cap` and nothing more is sent.

The editor never names a version; `direction_services` tells it what Direction would use. Music and voice keep the defaults in the table.

- **New shot** starts from words, from a `first` frame, or from `first` and `last` frames. A frame is a still or a moment of a take. With references, the version sees up to four frames of the film.
- **Extended shot** continues a take from its out point (`side: tail`: the take's frame at `end` is the first frame). Direction drops the one frame that would repeat, so the join is seamless. Leading into a take (`side: head`) isn't possible: OpenRouter turns down a last frame without a first one, so the editor makes a still for the first frame and a bridge from it.
- **Bridge** needs first and last frames; Direction picks from the versions that take a last frame.
- **Changed shot** sends the range itself (up to 10 seconds; `from: {assetID, start, end}`) to a version that changes video (Aleph 2.0 or FLUX Video Edit). The made clip is the same length as the range, with no sound; it goes on V2 over the original, and the take's own sound keeps playing.
- **Slow motion** makes the in-between frames for a range of a take (`factor` 2, 3 or 4) with Apple's frame interpolation. It costs nothing.
- **Sharpened** enlarges a range up to the cut's size. On this Mac it uses Apple's super resolution (4×, then fitted to the cut); the first use downloads Apple's sharpening files once. FLUX Video Upscale is the paid alternative.
- **Sound:** shots are made silent unless `sound: true` (cheaper on most versions). Ambience is usually better from the footage or a sound effect.
- **Two ways:** `ways` is 1 or 2, and up to 4 for stills.

### Finishing a made shot

After a new shot, extended shot, bridge or changed shot downloads, and before it enters the film:
1. **Sharpen** on this Mac when the cut is at least 1.5× taller than the clip and this Mac can (`VTSuperResolutionScaler`, 4×, inputs up to 1920 × 1080), then fit it to the cut. Written as HEVC 10-bit. If the sharpening files can't be had, the clip comes in as made and the result says "not sharpened".
2. **Join** an extended shot: drop its first frame (tail) or last frame (head).
3. The provenance records both: "Sharpened from 1280 × 720 on this Mac".

## Services

Every paid service goes through **OpenRouter**: one key, one bill, many versions. Direction calls `https://openrouter.ai/api/v1` with `Authorization: Bearer <key>`.

| Kinds | OpenRouter call | Notes |
|---|---|---|
| music, soundEffect | `POST /chat/completions` with `modalities: ["text","audio"]`, `stream: true`; audio arrives in `delta.audio` chunks | Lyria makes 30 s clips; longer beds are clips joined by Direction. |
| voice | `POST /audio/speech` | |
| still | `POST /images` | References as `input_references` image parts. |
| shot, extension, bridge | `POST /videos`, poll `GET /videos/{id}`, download `GET /videos/{id}/content` | Frames as `frame_images` (`first_frame`, `last_frame`); references as `input_references` image parts; `generate_audio` from `sound`. |
| changedShot | `POST /videos` with the range as `input_references: [{type: "video_url", video_url: {url}}]` | The range is sent as an H.264 data URL, 1280 wide at most, under 16 MB. |
| upscale (OpenRouter) | `POST /videos` with the range as a `video_url` reference and `upscale_factor` | FLUX Video Upscale. |
| looking at footage | `POST /chat/completions` with keyframes and `response_format: {type: "json_schema"}` | Only when Settings › Footage › Look with is OpenRouter. |

- Versions come from OpenRouter's lists (`GET /models?output_modalities=audio|speech|image`, `GET /videos/models`), cached for a day. From `/videos/models` Direction keeps each version's durations, resolutions, aspect ratios, `supported_frame_images`, `upscale_factor` and pricing SKUs.
- **Which versions change video:** versions whose listing has no durations and no frame images, or a SKU priced "with video input" (Aleph 2.0, FLUX Video Edit, Seedance). Changed shots go to those that return the range changed (Aleph, FLUX Video Edit).
- **Estimates** come from each version's listed price: per second of video at the chosen resolution and sound, with any per-generation minimum; per clip; per image; per token. **Spend** is what OpenRouter reports (`usage.cost`). The month's total is Direction's own record.
- OpenRouter's video services aren't covered by zero data retention; the Services note says frames and ranges sent for a shot leave this Mac.
- The key is stored in the macOS Keychain as Direction's own item, readable by the Direction app and its bundled `direction` tool. It never appears in the film, the logs, or any tool's arguments or results.
- Saving the key tests it with `GET /key` and shows Ready with the credits left, or the error.

## Spending

**One amount decides when the director is asked.** The editor prices everything it plans to make for a turnover before it makes any of it. Under the amount, it just makes it. Over the amount, it asks one spend question for the whole plan, and a yes covers every step of that plan.

| Setting | Default | Behavior |
|---|---|---|
| Ask before spending more than | $5.00 per turnover | Choices $1, $5, $10, $25, $50. A plan that would take the turnover past this needs a yes to a spend question. |
| Stop for the month at | $50.00 | Nothing is made past this. The editor is told `spend_cap`. |

- A yes covers the plan it priced: requests that name the question (`spendQuestionID`) may go past the turnover's limit until they've used the question's estimate plus 10%. More than that needs another question.
- A version OpenRouter lists no price for needs a yes to a spend question whatever the turnover has spent, and nothing goes to one once the month's cap is reached.
- A shot is paid for once it's sent: stopping it, or losing it while it's made, keeps its charge. Only OpenRouter saying it couldn't make the shot gives the hold back, unless it reports a charge.
- Nothing made on this Mac costs anything or counts toward either limit.
- The month resets on the 1st. "Spent this month" sums Direction's own record of every made thing, per kind.

## Tools

| Tool | Arguments | Returns |
|---|---|---|
| `direction_services` | — | Ready services, the version Direction would use for each kind (and `withAPerson` when that differs) with its price, `madeWith`, the limits, what's left in the open turnover and this month |
| `direction_estimate` | `turnover`, `steps` (each a `direction_make` call's arguments) | Each step's version, seconds and spend; the plan's `total`; `turnoverSpent`, `limit`, `needsQuestion`; `monthLeft`. Spends nothing. |
| `direction_make` | `kind`, `ask`, `seconds?`, `from?` (`{assetID, start?, end?, side?}`), `first?` / `last?` (`{assetID, at?}`), `references?` (asset ids, or `{assetID, at}`), `sound?`, `factor?`, `ways?`, `note`, `turnover`, `estimateOnly?`, `spendQuestionID?` | With `estimateOnly`: `{spend, seconds}`. Otherwise a job; when done, each made clip's `assetID` and provenance. |

- `from` is the take range a changed shot, slow motion or sharpening works on, and the take an extended shot continues (`side`).
- Over the turnover's limit, `direction_make` returns `spend_over_limit` with the estimate. The editor should have priced the plan first with `direction_estimate`; it asks one spend question (`direction_ask` kind `spend`, with `spend: {estimate: <plan total>, choiceID}`) and passes `spendQuestionID` on every step.
- Over the monthly cap, it returns `spend_cap`. Only the director can change that.
- Made files are saved in `<film>.direction/Made/` (copied in, never linked), probed like footage, and placed with `placeMade` or `placeMusic` (`agent-timeline.md`).
- The `make-shot` skill holds the recipes: fix a take, hold longer, bridge, insert or establishing shot, a pickup, slow motion, a soft shot.

## Where made things show

- **Read-back:** the plan line says what will be made and about how much: "Note 3: change the sky to dusk cloud with Aleph 2.0, about $1.40."
- **Changes:** an answer that uses made picture or sound has a **Made** chip after its delta: a neutral steel `.chip` with the editor's 7 pt diamond before the word. Clicking it opens the provenance popover (frame 61).
- **Dailies:** a "Made" group after Unsorted lists every made clip with its provenance.
- **History:** each made clip's provenance stays with the cut that introduced it.

### The provenance popover

Header: diamond + "Made with <version>" (or "Made on this Mac"). Sub: "<Label> · <OpenRouter | This Mac> · <date>". Section "WHAT THE EDITOR ASKED FOR" with the words (omitted for slow motion and sharpening). Rows, each only when it applies:

| Row | Value |
|---|---|
| Version | `runway/aleph-2` (SF Mono) |
| From | "A012 · 0:12–0:17" (changed shot, slow motion, sharpened); "End of A012" or "Start of A012" (extended shot); "A012 to A015" (bridge); "Still: diner exterior" (a new shot from a still) |
| Length | "0:05" |
| Sharpened | "From 1280 × 720 on this Mac" |
| Checked | "Looks clean", "Slightly off" or "Looks broken at 0:03" (SF Mono): Direction's own look when it arrived (decisions.md › Judging made shots). The tooltip has what it found. Only for new shots, extensions, bridges, changed shots and stills. |
| Spent | "$1.40", or "Nothing" |
| For | "Note 3" |

Footer: "Play it alone" and "Show in Dailies".

---

## 55 · Settings, Services
Frame: `screens/55-settings-services.html` · 720 × 812. See `settings.md › 55`.

## 61 · Changes, made music
Frame: `screens/61-changes-made.html` · 1440 × 900.

The Cut room on Cut 4 with note 4's answer selected ("Music is too sure of itself here.", Sound, 01:43:20). In this frame the answer is two ways:
- Answer text: "Two ways. A: the same track, down 6 dB under her line. B: a sparser piano bed I made, with no resolve."
- Options stage as in frame 30: A and B tiles. B's tile carries the **Made** chip.
- The provenance popover is open from B's chip (320 wide, `.pop`):
  - Header: diamond + "Made with Lyria 3 Clip" (13/600). Sub: "Music · OpenRouter · Oct 28 14:02" (11.5 text-3).
  - Section "WHAT THE EDITOR ASKED FOR" and the text in 12.5 text-2, in quotes: "Sparse felt piano, unresolved, around 70 bpm. No swell. 24 seconds, ending on a held note."
  - Rows (label text-3, value SF Mono text-2, right): Version · "google/lyria-3-clip"; Length · "0:24"; Spent · "$0.04"; For · "Note 4".
  - Footer: "Play it alone" (text link, plays only the made audio from its start) and "Show in Dailies".

## 62 · Notes, a spend question
Frame: `screens/62-notes-spend.html` · 1440 × 900.

The Cut room during the read-back of Cut 4's turnover, the questions panel open (frame 20's layout), with a spend question for a plan.

- Question card text: "Note 3 wants less sky. Reframing to 1.6× gets the sky to a third of the frame. To make the sky itself dusk cloud, I'd change those 5 seconds of the take with Aleph 2.0, and make an establishing shot of the ridge at dusk to lead in."
- A spend line under the text: "About $2.75. This turnover would reach $5.65 of your $5.00 limit." Money in SF Mono; the limit sentence in text-3.
- Choices (2–4, the existing question choice rows):
  - "Reframe only" · "No spend" · with the editor's recommendation diamond.
  - "Change the sky and add the dusk shot" · "About $2.75".
  - "Find another take" · "I'll search the ridge footage first".
- Free text field as in frame 20.
- The pill shows "1 question".

Picking "Change the sky and add the dusk shot" lets that plan's requests go over the turnover's limit, up to $3.03 (the estimate plus 10%). It never allows going past the monthly cap.

**Acceptance:**
- [ ] No request reaches a service without a key saved in Settings and a spend under both limits or a yes to a spend question.
- [ ] A plan under the limit is never asked about; a plan over it is asked about once.
- [ ] A changed shot sends the take's range itself, not a frame of it.
- [ ] Slow motion and sharpening on this Mac spend nothing and send nothing anywhere.
- [ ] Every made clip shows its service, what the editor asked for, the version, where it came from and the spend, from Changes, Dailies and History.
- [ ] Removing a service's key stops new requests and leaves made clips playable.

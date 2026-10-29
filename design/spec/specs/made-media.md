# Made picture and sound

Frames 55 (Settings › Services), 61 (a made answer in Changes), 62 (a spend question). Read `product-model.md › Made, Service, Spending` first.

Sometimes a note needs something the footage doesn't have: music under the drive, the sound of rain, a sky at dusk, an establishing shot nobody filmed. The editor can make it with a service, using the director's key. Direction makes every request, so keys never reach the editor; every made thing says where it came from and what it cost; and nothing is spent past the director's limits.

The UI never says "generate", "AI", "prompt" or "model". Things are **made**; the editor **asked for** something; services have **versions**.

---

## Services

| Service | The editor uses it for | Kinds | Billing | Notes |
|---|---|---|---|---|
| ElevenLabs | Music, sound effects, voice | music, soundEffect, voice | Your ElevenLabs plan | Music needs a paid plan. Self-serve music terms exclude film and TV; Settings links the terms. |
| Runway | Changing a shot you have: sky, weather, time of day, removing things. Extending a shot. | changedShot, shot | Runway API credits | Changes work on clips up to about 30 s at 1080p. |
| Higgsfield | New shots, with many video versions (Kling, Seedance, Wan …) | shot | A prepaid dollar balance, separate from Higgsfield's app plan | |
| Gemini | Looking at footage, when chosen in Settings › Footage | — | Gemini API key from Google AI Studio | A Gemini app subscription isn't an API key. |

- More services can be added later behind the same tools.
- Keys are stored in the macOS Keychain, in Direction's own item per service. They're read only by Direction's process when it makes a request.
- Each service row in Settings tests its key once when saved, with the service's cheapest read call (account or balance), and shows Ready or the error.

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
- Made files are saved in `<film>.direction/Made/` (copied in, never linked), probed like footage, and placed with `direction_timeline_apply` like any clip.
- Footage first: the `take-turnover` skill tells the editor to search the footage (`direction_search_footage`) before making anything, and to say in the read-back when it plans to make something: "Note 4: make a sparser piano bed with ElevenLabs, about $0.40."

## Where made things show

- **Read-back:** the plan line says what will be made and about how much it costs.
- **Changes:** an answer that uses made picture or sound has a **Made** chip after its delta: a neutral steel `.chip` with the editor's 7 pt diamond before the word. Clicking it opens the provenance popover (frame 61).
- **Dailies:** a "Made" group after Unsorted lists every made clip with its provenance, so it can be watched and reused like footage.
- **History:** each made clip's provenance stays with the cut that introduced it.

---

## 55 · Settings, Services
Frame: `screens/55-settings-services.html` · 720 × 700. See `settings.md › 55`.

## 61 · Changes, made music
Frame: `screens/61-changes-made.html` · 1440 × 900.

The Changes room on Cut 4 with note 4 selected ("Music is too sure of itself here.", Sound, 01:43:20). In this frame the answer is two ways:
- Answer text: "Two ways. A: the same track, down 6 dB under her line. B: a sparser piano bed I made, with no resolve."
- Options stage as in frame 30: A and B tiles. B's tile carries the **Made** chip.
- The provenance popover is open from B's chip (320 wide, `.pop`):
  - Header: diamond + "Made with ElevenLabs" (13/600). Sub: "Music · Oct 28 14:02" (11.5 text-3).
  - Section "WHAT THE EDITOR ASKED FOR" and the text in 12.5 text-2, in quotes: "Sparse felt piano, unresolved, around 70 bpm. No swell. 24 seconds, ending on a held note."
  - Rows (label text-3, value SF Mono text-2, right): Version · "music v2"; Length · "0:24"; Spent · "$0.40"; For · "Note 4".
  - Footer: "Play it alone" (text link, plays only the made audio from its start) and "Show in Dailies".

## 62 · Notes, a spend question
Frame: `screens/62-notes-spend.html` · 1440 × 900.

The Notes room during the read-back of Cut 4's turnover, the questions panel open (frame 20's layout), with a spend question.

- Question card text: "Note 3 wants less sky. Reframing to 1.6× gets the sky to a third of the frame. To change the sky itself to dusk cloud, I'd change the shot with Runway."
- A spend line under the text: "About $3.20. This turnover would reach $6.10 of your $5.00 limit." Money in SF Mono; the limit sentence in text-3.
- Choices (2–4, the existing question choice rows):
  - "Reframe only" · "No spend" · with the editor's recommendation diamond.
  - "Change the shot with Runway" · "About $3.20".
  - "Find another take" · "I'll search the ridge footage first".
- Free text field as in frame 20.
- The pill shows "1 question".

Picking "Change the shot" allows that one request to go over the turnover's limit. It never allows going past the monthly cap.

**Acceptance:**
- [ ] No request reaches a service without a key saved in Settings and a spend under both limits or a yes to a spend question.
- [ ] Every made clip shows its service, what the editor asked for, the version and the spend, from Changes, Dailies and History.
- [ ] Removing a service's key stops new requests and leaves made clips playable.

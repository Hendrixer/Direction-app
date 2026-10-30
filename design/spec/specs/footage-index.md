# Looking at footage

Frames 05 (logging, updated copy), 54 (Settings › Footage), 59 (a take's shots), 60 (search). Read `product-model.md › Shot, Sound, Index` first.

A coding agent can't watch video. Instead of handing it raw files, Direction does what an assistant editor does when footage comes in: it finds every shot, makes a contact sheet for every take, writes a line about each shot, notes the sounds, and makes the footage searchable. The editor reads that index, and looks at real frames when it needs to. The director gets search too.

Direction runs the index itself, the same way every time. The editor doesn't decide how footage gets indexed; it reads the result.

---

## What runs when footage comes in

All steps run at background priority, in parallel with transcription, take by take, in the order the takes will be logged. The editor's logging job starts once shots exist for a take.

| Step | How | Output |
|---|---|---|
| 1. Proxies and keyframes | AVFoundation, 4 frames per second at 512 px from the proxy | Cached frames (deleted after step 4) |
| 2. Shots | Vision `VNGenerateImageFeaturePrintRequest` on each sampled frame. A boundary is a local peak in the distance between neighbors above 0.35, or a fade (mean luminance crossing 4% black). Shots are at least 0.5 s. | `Shot` rows with source ranges |
| 3. Contact sheet | 16 frames evenly across the take, a 4 × 4 grid, 1600 px wide, each cell labeled with its source timecode in SF Mono | One JPEG per take in `Index/` |
| 4. Descriptions | A vision engine (below) looks at 3 keyframes per shot (10%, 50%, 90%) at 672 px, with the take's words for that range, and fills a fixed shape | `description`, `size`, `movement`, `people`, `flags` per shot |
| 5. Sounds | SoundAnalysis `SNClassifySoundRequest(classifierIdentifier: .version1)` in 1 s windows. Runs merge; the top label maps to the seven kinds in `Sound`. Loudness per second is kept for the strip. | `Sound` rows |
| 6. Text on screen | Vision `RecognizeTextRequest` (accurate, no language correction) on each shot's middle frame at 1920 px; a shot with 12 words or more is read every 2 s (below) | `ScreenText` stretches per shot |
| 7. Search | Apple's NaturalLanguage sentence embeddings (`NLEmbedding.sentenceEmbedding(for: .english)`, built into macOS) make a vector for each shot's description, each line of dialogue and each stretch of text on screen. All three also go into SQLite FTS5. Vision feature prints from step 2 are kept per keyframe for "more like this shot". | Vectors in `project.sqlite`; the FTS index |

Steps 1–3 and 5–7 are built into macOS or bundled and always run on this Mac. Step 4 is the one with a choice of engine.

### The shape a description fills

```json
{ "description": "Medium on Maya at the window. She looks down, then out.",   // ≤ 18 words, present tense, no guessing names
  "size": "medium",                   // wide | medium | close | insert
  "movement": "static",               // static | pan | tilt | push | pull | handheld
  "people": ["woman, dark hair"],     // what's visible; the editor maps these to names when it logs
  "setting": "kitchen, dusk",
  "flags": ["soft"] }                 // soft | shaky | overexposed | underexposed
```

Both engines decode greedily (temperature 0) into this JSON with a 160-token limit, validated against the shape, with one retry. Because nothing is sampled creatively, the sampler differences between local engines (min-p versus top-n-sigma) don't matter here.

### Engines for descriptions

| Engine | Detail | Runs | Size | Speed target (M4 Max) | Notes |
|---|---|---|---|---|---|
| This Mac | Quick | Qwen2.5-VL 3B, 4-bit, through `mlx-vlm` | 3.1 GB | ~0.4 s a shot | Shorter, plainer lines |
| This Mac | **Standard** (default) | Qwen3-VL 8B, 4-bit, through `mlx-vlm` | 5.8 GB | ~1 s a shot | Best balance |
| This Mac | Best | Qwen3-VL 30B-A3B, 4-bit, through `mlx-vlm` | 18 GB | ~1.5 s a shot | Needs 32 GB of memory or more |
| OpenRouter | a vision version (default Gemini 3.1 Flash Lite) | OpenRouter chat completions with your key | — | ~1 s a shot, in parallel | Three 672 px keyframes per shot leave this Mac; nothing else does |

- **On this Mac**, Direction runs a small Python helper shipped in the app (`Resources/Vision/describe.py`) with the Python from `uv tool install mlx-vlm` (found like mlx-whisper: `~/.local/share/uv/tools/mlx-vlm/bin/python`, or any `python3` that can `import mlx_vlm`). The helper loads the version once and answers JSON lines on stdin/stdout: `{"images": [paths], "prompt": "…"}` → `{"text": "…"}`. It's stopped 60 s after the last shot. Apple's MLX library for Swift isn't used because `swift build` can't compile its GPU code.
- Weights download on first use to the Hugging Face cache (`~/.cache/huggingface/hub`), with progress in Settings › Footage, and show in Settings › Storage.
- If free disk space is less than the download plus 2 GB, the download doesn't start, and Settings says so with Quick offered instead.
- **Through OpenRouter**, each shot's three keyframes go as `image_url` parts (JPEG data URLs) with `response_format` set to the description's JSON schema. Requests run 4 at a time. Spend counts toward Settings › Services limits.
- Without mlx-vlm and without an OpenRouter key, steps 1–3 and 5–7 still run; descriptions are skipped and search uses words and text on screen only.

Speed targets are for the sample film (214 takes, 3 h 12 min, about 1,900 shots): Standard finishes in about 35 minutes, and circling can start as soon as the first scene is logged.

### The pill while footage is looked at

Looking at footage is Direction's own work, done on the editor's behalf. Until the editor's logging run starts, the pill reads "Looking at footage · 88 of 214" (no shimmer: that means the editor itself is working). Once logging starts, the pill shows the run ("Logging 42 of 214") and the index carries on underneath.

### Listening

Transcription is Direction's work too. When footage arrives, the app transcribes every take with sound, one at a time, with the engine in Settings › Footage, alongside looking at it. A take is logged only once its words are in (see Logging in batches), so the editor logs from them. While Direction is still transcribing after the index finishes, the pill reads "Listening · 3 of 12".

- The app owns these jobs, never the editor's helper, so they outlive an editor run. A transcription job that was cancelled or whose process exited (an editor run that ended, a crash) is started again by the app, twice at most.
- Logging waits from the moment footage arrives: a take with no index yet counts as still being looked at, so the editor never starts before Direction has begun.
- Showing a film that's already open (the editor's `direction_open_project` with `showInApp`, a notification, Open Recent) brings its window forward. It never closes and reopens the film, which would cancel its running jobs.
- A transcript where Whisper got stuck repeating itself (a run of 60 words using fewer than 18 different ones) counts as missing and is made again.
- A take whose transcription failed (no speech on it, say) doesn't hold up logging. Its transcript section in Dailies says why and offers **Transcribe Again**.
- Whisper runs through its library rather than its command line, with fallback temperatures, each window started fresh (`condition_on_previous_text` off) and silences skipped where it would make words up (`hallucination_silence_threshold` 2 s). The command line can't ask for fallback temperatures, so a window that began to loop ran on to the end of the take.

### Transcription engines

Measured on the director's 3:12 talking-head take on an M4 Max, against Whisper Large v3:

| Engine | Time | Words | Differs from Large v3 | Word starts vs Large v3 |
|---|---|---|---|---|
| Apple (SpeechAnalyzer, Neural Engine) | 2.2 s (~85×) | 494 | 5.4% | median 0.08 s, 90% within 0.26 s |
| Whisper Large v3 Turbo | 7.0 s (~27×) | 487 | 1.9% | median 0.08 s, 90% within 0.18 s |
| Whisper Large v3 | 11.9 s (~16×) | 483 | n/a | n/a |

Most of Apple's difference is verbatim speech Whisper tidies away: false starts and a repeated phrase ("it transitioned that large. I think", "I think we should"), which an editor wants for finding retakes, plus "7" for "seven". Turbo's one real slip: "in finite time" as "by nighttime". Settings › Footage says this in each choice's line.

### Logging in batches

The editor logs footage in runs of up to 20 takes, each a fresh session, so no run grows past what one session can hold, and the director can circle while the rest is still being looked at.

- **When a batch starts.** A take is ready once Direction has looked at it (when it looks by itself), its words are in or settled, and its sound has been compared. The first batch starts at 5 ready takes; later batches at 20; the last with whatever is left. Takes in sync go in the same batch. One logging run at a time, and none while one is stopped or waiting for Try Again.
- **What a batch carries.** The job lists the scenes logged so far and, for each take in the batch, everything Direction found: picture size, sync, every shot with its times, size, movement, description, people, setting and flags, the gist of its text on screen (40 words, largest text first), its sounds, and its words (up to 1,200, then where to read the rest). The editor logs from that and calls a tool only to see a moment that matters. On the director's first film, logging two takes by reading tools took Codex 991,000 tokens and 3½ minutes.
- **Takes a run leaves.** A take that two finished runs didn't log goes to Unsorted with its first shot's description as its caption and the flag "Not logged by the editor", so logging finishes and the director can place it.

### Speed

- **Descriptions** are most of the time: about 2 s a shot for Qwen3-VL 8B on this Mac, nearly all of it writing the line. A shot whose middle frame is within 0.3 (feature-print distance) of one already described anywhere in the film, or 0.35 within its own take, reuses that shot's line ("same picture as shot 2"): one setup split by a small change, or another take of it. A shot whose first and last frames are within 0.3 doesn't move, and only its middle frame is sent (2.3 s instead of 3.1 s on the director's footage).
- **Text on screen** costs little next to shots: on the director's 3:12 screen recording it took 3.6 s (one stretch: the screen never changed, so one frame of 96 was read), and 0.2 s for the camera take's three shots, against about 14 s each to find shots. Reading is about 0.34 s a frame, 0.12 s with four at once; language correction doubled it and changed nothing Vision was sure of; a 3840 px frame reads no better and no faster than 1920.
- **A smaller describer was tried and isn't offered.** Qwen3.5 4B (4-bit, 3.1 GB) on the director's footage: 0.76 s a shot against Qwen3-VL 8B's 1.35 s (0.51 against 0.85 in batches of 8), 6.1 GB of memory against 7.5. But it missed the director's dreadlocks, and on one still frame of a screen it wrote "text scrolling rapidly", where 8B read what the page was about. Describing is already a small part of looking (see above), so the speed isn't worth the lines.
- **Sync** keeps every pair's answer, keyed by both takes' curves, so new footage is compared only against what's there. Pairs whose recording windows can't overlap (creation to last change, widened by the length and six hours) aren't compared at all. In an optimized build a pair of 1-minute takes takes 0.3 ms and two 1-hour takes 30 ms.

### 05 · The logging page

- Each take's row says where it is, with a bar only when the progress is real: "Describing 4 of 12 shots"; "Transcribing · about 0:08 left", estimated from how fast Whisper has run on this film; "Finding shots", "Logging · 1:12" and "Ready to log" without one (the spinner on the left says it's working). No bar loops.
- The title carries the time since the footage came in, "Logging footage 3:35 so far", and "Footage logged in 4:31" when it's done.
- Continue on the brief with footage attached goes straight to this page: it shows from the moment the first file starts coming in, so the drop zone never flashes.

### Sync

Takes that recorded the same moment (two cameras, a camera and a screen recording, a camera and a separate sound recorder, takes against a song) are found by their sound, as part of listening. Nothing is a "multicam" or "screen share" mode: takes are linked only when their sound matches, so a single-camera film, B-roll or silent footage is never linked and nothing about it changes.

- **How.** Every take with sound at least 10 s long becomes a loudness curve: its loudest unmuted track (a silent desktop-audio track is skipped), decoded at 8 kHz on Direction's own clock (the one it plays on), averaged every 10 ms and standardized. Every pair of curves is cross-correlated through the FFT. A pair is the same moment when the curves correlate at 0.6 or more over at least 10 s of overlap; the peak is placed between samples with a parabola. Pairs chain into groups. Curves are kept in the cache, so new footage costs only its own decoding. On this Mac, at no cost: two 3-minute takes take about a second.
- **The sound take.** One take in each group carries the sound the cut uses: a sound-only take if there is one (a recorder beats a camera mic), otherwise the loudest. Every take's offset is on its clock: sound take's time = take's time + offset. The director can change it (**Use This Take's Sound**); Direction keeps that choice when it compares again.
- **The director's say.** **Not in Sync** takes a take out of its group, and the pair is never linked again.
- **When.** By itself when footage arrives, alongside looking and listening; a take isn't ready to log until it's been compared. Checked takes and every pair's answer are remembered (see Speed), so new footage is compared only against what's there. The editor can run it with `direction_sync_takes`.
- **The editor.** `direction_dailies › syncGroups` lists the groups. A `cutaway` without `sourceRange` (give `seconds`) plays the same moment from a synced take, lined up to the frame: switching angles, a screen recording under the words about it, picture-in-picture with `reframe`. Logging logs synced takes as angles of one moment; the assembly lays the sound take (or the angle the brief wants seen most) on V1 and never lays its angles end to end.
- **Dailies.** A synced take's card has a line under its status, "🔗 In sync with B1 · its sound". The open take (frame 08) gets an **Angles** row above the transcript: one button per take (a waveform glyph on the sound take), and switching keeps the same moment. ← → do too, between synced takes. The take's context menu has **Use This Take's Sound** and **Not in Sync**.

### Text on screen

A screen recording, slides, a whiteboard or a sign can be found by what it says. Vision's text recognition reads it on this Mac; nothing is downloaded and nothing leaves the Mac.

- **How.** Each shot's middle frame is read at 1920 px. Lines Vision is less than 0.8 sure of are dropped (at 0.3 and 0.5 they're mostly noise), so are icons read as symbols ("•", "©"), and a line needs three letters or digits. "Al" alone becomes "AI": the system font draws I and l alike. A frame's lines come largest text first (titles, headings, then body, then menus), each size top to bottom and left to right, since rows across a screen run through every column.
- **Shots with text.** A shot whose middle has 12 words or more, and runs 4 s or longer, is read every 2 s. A frame is read again only when 0.1% of its pixels (a 480 px grey copy, changes over a tenth of the range) differ from the last frame read; otherwise it keeps that frame's lines. A caret or sensor noise doesn't count; a new line of text does. Other shots keep what their middle frame says.
- **Stretches.** Lines in 80% or more of a shot's frames stayed on screen throughout and make one stretch from the shot's start to its end (a window title, a slide's heading). The rest make stretches for as long as each frame shares half its lines with the one before and a quarter with the stretch's first, so a page scrolling makes a new stretch once most of it has gone. A stretch runs from halfway after the frame before it to halfway before the frame after it.
- **When.** After sounds, while a take is looked at; the logging page says "Reading the screen". Takes looked at before Direction read text are read once, by themselves (`TakeIndex.screenTextVersion`). A take whose text can't be read keeps everything else.
- **Search.** Each stretch is a search row: all its words in FTS5, a sentence vector of its gist. A shot's text-on-screen side counts like its description and its lines; it wins when it scores higher, or when it holds half the query or more and more of it than the others do (its words are read, not judged, so they count for more than its meaning). The hit says `screen` ("on screen" in Dailies), quotes the lines that matched, and its time is when that text is on screen, not the whole shot.
- **The editor.** `direction_shots` gives each shot's `onScreen` gist; `direction_screen_text` reads a take's stretches with their times; logging carries each take's gist and captions screen recordings by what they show.

## What the editor gets (tools)

| Tool | Arguments | Returns |
|---|---|---|
| `direction_shots` | `assetID?`, `sceneID?`, `offset`, `limit` | Shots with range, description, size, movement, people, flags, sounds, the gist of their text on screen, and small keyframe paths |
| `direction_contact_sheet` | `assetID`, `range?`, `frames` (4–36, default 16) | One image grid with source timecodes, and the time of each cell |
| `direction_frame` (extended) | `assetID` and `time` (source seconds), or the existing cut `time` | A real frame of a take, not only of the cut |
| `direction_watch` | `start`, `end` (cut seconds), `revision?`, `frames` (8–24, default 12) | A filmstrip image of the passage with timecodes, the words in it, sounds, and where the cuts fall. The closest thing to watching. |
| `direction_sync_takes` | `force?` | A job that finds takes in sync by their sound and writes `syncGroups` to Dailies |
| `direction_screen_text` | `assetID`, `range?` | The take's text on screen: stretches with source ranges and their lines, largest text first |
| `direction_search_footage` | `query`, `sceneID?`, `circledOnly?`, `limit` (default 12) | Ranked shots with a score, why they matched (`picture`, `words`, `both` or `screen`), and keyframe paths; a `screen` hit's range is when the text is on screen |

- Search ranks by the similarity of the query's sentence embedding to each shot's description, lines and text on screen, blended with FTS5 scores (0.6 meaning, 0.4 exact words), best shot per take first. `similarTo: shotID` ranks by Vision feature-print distance instead.
- `direction_dailies` gains an `index` field per take: `waiting`, `looking`, `done` or `failed`.
- **Check your work.** Every skill that cuts ends with: watch every passage you changed with `direction_watch` before delivering. The turnover's finishing tool refuses delivery if a changed range was never watched in that run, with `not_watched` and the ranges.

## The director's side

### 05 · Logging footage (copy change)
The stage line under the progress reads, in order as each starts: "Reading 214 takes" → "Finding shots" → "Looking at footage · 88 of 214" → "Listening · 120 of 214" → "Sorting into scenes". The counts are SF Mono.

### 54 · Settings, Footage
Frame: `screens/54-settings-footage.html` · 720 × 724. See `settings.md › 54`.

### 59 · Dailies, a take's shots
Frame: `screens/59-dailies-shots.html` · 1440 × 900.

Frame 08's state (2A T3 open in the take viewer), with the take's index shown under the viewer.

- Under the take's scrubber, a **Shots** row: one card per shot (the take has 4), each 168 wide: keyframe (16:9, radius 6), source range in SF Mono 11 text-3, the description in 12 text-2 (2 lines max), and a size chip ("Medium", plain chip). Flags appear as a neutral chip ("Soft at 0:42"). The shot under the playhead has a 1 pt text-1 ring.
- On the scrubber itself, shot boundaries are 1 pt ticks in text-4, and sounds are a thin lane (4 tall) under it: speech steel-7, laughter steel-9, music steel-8, silence empty. Hovering a sound shows "Laughter · 0:37–0:39".
- Section label above the row: "SHOTS · LOGGED BY THE EDITOR" with a small diamond.
- Clicking a shot seeks the take to its start. `←`/`→` with the row focused moves between shots.
- The contact sheet: a **Contact sheet** button (`.btn`, grid icon) beside the label opens the take's sheet as a popover, 640 wide, click a cell to seek.

### 60 · Dailies, search footage
Frame: `screens/60-dailies-search.html` · 1440 × 900.

`⌘F` in Dailies focuses a search field at the top of the take area (300 wide, `.input` with a magnifier, placeholder "Search footage"). Typing searches after 250 ms. The sample query is "Maya laughing".

- The take grid is replaced by results: a header "9 shots for “Maya laughing”" (13 text-2) with a **Circled only** toggle, then results grouped by scene with the scene label (`2 Maya, the problem`).
- Each result card is a take card (same size as frame 07's) showing the matching shot's keyframe, the take code, the shot's range, and one line: the description with the matched words in text-1, or a quoted line of dialogue when it matched on words. A tiny "picture" / "words" label (11 text-4) says why it matched.
- Circled takes keep their amber hand-drawn circle; suggestions keep the diamond.
- Click opens the take at that shot (frame 59). `↩` opens the first result. `esc` clears the search and returns to the grid.
- No results: "No shots look like “…”" with "Search words only" as a text link, which searches transcripts alone.
- While the index is still looking: a line under the header, "Still looking at 126 takes. Results will grow." with the count in SF Mono.

**Acceptance:**
- [ ] Search returns in under 300 ms for 2,000 shots on this Mac.
- [ ] Searching never sends footage or the query off this Mac. Only describing shots through OpenRouter sends keyframes.
- [ ] A take whose index failed still shows in Dailies with "Couldn't look at this take" and **Try again** in its context menu.

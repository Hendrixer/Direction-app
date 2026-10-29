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
| 6. Search | Apple's NaturalLanguage sentence embeddings (`NLEmbedding.sentenceEmbedding(for: .english)`, built into macOS) make a vector for each shot's description and for each line of dialogue. Descriptions and transcript words also go into SQLite FTS5. Vision feature prints from step 2 are kept per keyframe for "more like this shot". | Vectors in `project.sqlite`; the FTS index |

Steps 1–3, 5 and 6 are built into macOS or bundled and always run on this Mac. Step 4 is the one with a choice of engine.

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
- Without mlx-vlm and without an OpenRouter key, steps 1–3, 5 and 6 still run; descriptions are skipped and search uses words only.

Speed targets are for the sample film (214 takes, 3 h 12 min, about 1,900 shots): Standard finishes in about 35 minutes, and circling can start as soon as the first scene is logged.

### The pill while footage is looked at

Looking at footage is Direction's own work, done on the editor's behalf. Until the editor's logging run starts, the pill reads "Looking at footage · 88 of 214" (no shimmer: that means the editor itself is working). Once logging starts, the pill shows the run ("Logging 42 of 214") and the index carries on underneath.

### Listening

Transcription is Direction's work too. When footage arrives, the app transcribes every take with sound, one at a time, with the engine in Settings › Footage, alongside looking at it. The editor's logging run starts only once both are done, so the editor logs from the words. While Direction is still transcribing after the index finishes, the pill reads "Listening · 3 of 12".

- The app owns these jobs, never the editor's helper, so they outlive an editor run. A transcription job that was cancelled or whose process exited (an editor run that ended, a crash) is started again by the app, twice at most.
- Logging waits from the moment footage arrives: a take with no index yet counts as still being looked at, so the editor never starts before Direction has begun.
- Showing a film that's already open (the editor's `direction_open_project` with `showInApp`, a notification, Open Recent) brings its window forward. It never closes and reopens the film, which would cancel its running jobs.
- A transcript where Whisper got stuck repeating itself (a run of 60 words using fewer than 18 different ones) counts as missing and is made again.
- A take whose transcription failed (no speech on it, say) doesn't hold up logging. Its transcript section in Dailies says why and offers **Transcribe Again**.
- Whisper runs through its library rather than its command line, with fallback temperatures, each window started fresh (`condition_on_previous_text` off) and silences skipped where it would make words up (`hallucination_silence_threshold` 2 s). The command line can't ask for fallback temperatures, so a window that began to loop ran on to the end of the take.

### Sync

Takes that recorded the same moment (two cameras, a camera and a screen recording, a camera and a separate sound recorder, takes against a song) are found by their sound, as part of listening. Nothing is a "multicam" or "screen share" mode: takes are linked only when their sound matches, so a single-camera film, B-roll or silent footage is never linked and nothing about it changes.

- **How.** Every take with sound at least 10 s long becomes a loudness curve: its loudest unmuted track (a silent desktop-audio track is skipped), decoded at 8 kHz on Direction's own clock (the one it plays on), averaged every 10 ms and standardized. Every pair of curves is cross-correlated through the FFT. A pair is the same moment when the curves correlate at 0.6 or more over at least 10 s of overlap; the peak is placed between samples with a parabola. Pairs chain into groups. Curves are kept in the cache, so new footage costs only its own decoding. On this Mac, at no cost: two 3-minute takes take about a second.
- **The sound take.** One take in each group carries the sound the cut uses: a sound-only take if there is one (a recorder beats a camera mic), otherwise the loudest. Every take's offset is on its clock: sound take's time = take's time + offset. The director can change it (**Use This Take's Sound**); Direction keeps that choice when it compares again.
- **The director's say.** **Not in Sync** takes a take out of its group, and the pair is never linked again.
- **When.** By itself when footage arrives, alongside looking and listening; the editor's logging run waits for it. Checked takes are remembered, so it runs again only for new footage. The editor can run it with `direction_sync_takes`.
- **The editor.** `direction_dailies › syncGroups` lists the groups. A `cutaway` without `sourceRange` (give `seconds`) plays the same moment from a synced take, lined up to the frame: switching angles, a screen recording under the words about it, picture-in-picture with `reframe`. Logging logs synced takes as angles of one moment; the assembly lays the sound take (or the angle the brief wants seen most) on V1 and never lays its angles end to end.
- **Dailies.** A synced take's card has a line under its status, "🔗 In sync with B1 · its sound". The open take (frame 08) gets an **Angles** row above the transcript: one button per take (a waveform glyph on the sound take), and switching keeps the same moment. ← → do too, between synced takes. The take's context menu has **Use This Take's Sound** and **Not in Sync**.

## What the editor gets (tools)

| Tool | Arguments | Returns |
|---|---|---|
| `direction_shots` | `assetID?`, `sceneID?`, `offset`, `limit` | Shots with range, description, size, movement, people, flags, sounds, and small keyframe paths |
| `direction_contact_sheet` | `assetID`, `range?`, `frames` (4–36, default 16) | One image grid with source timecodes, and the time of each cell |
| `direction_frame` (extended) | `assetID` and `time` (source seconds), or the existing cut `time` | A real frame of a take, not only of the cut |
| `direction_watch` | `start`, `end` (cut seconds), `revision?`, `frames` (8–24, default 12) | A filmstrip image of the passage with timecodes, the words in it, sounds, and where the cuts fall. The closest thing to watching. |
| `direction_sync_takes` | `force?` | A job that finds takes in sync by their sound and writes `syncGroups` to Dailies |
| `direction_search_footage` | `query`, `sceneID?`, `circledOnly?`, `limit` (default 12) | Ranked shots with a score, why they matched (`picture`, `words` or `both`), and keyframe paths |

- Search ranks by the similarity of the query's sentence embedding to each shot's description and lines, blended with FTS5 scores (0.6 meaning, 0.4 exact words), best shot per take first. `similarTo: shotID` ranks by Vision feature-print distance instead.
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

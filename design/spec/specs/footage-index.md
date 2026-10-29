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
| 6. Search | A Core ML image-and-text encoder (SigLIP 2 base) makes a vector for each keyframe. Descriptions and transcript words go into SQLite FTS5. | Vectors in `project.sqlite`; the FTS index |

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

The engine decodes greedily (temperature 0) into this JSON with a 160-token limit, validated against the shape, with one retry. Because nothing is sampled creatively, the sampler differences between local engines (min-p versus top-n-sigma) don't matter here.

### Engines for descriptions

| Engine | Detail | Runs | Size | Speed target (M4 Max) | Notes |
|---|---|---|---|---|---|
| This Mac | Quick | FastVLM 1.5B with MLX Swift, in Direction's process | 1.4 GB | ~0.3 s a shot | Apple's own; shorter, plainer lines |
| This Mac | **Standard** (default) | Qwen3-VL 8B, 4-bit, MLX Swift | 5.8 GB | ~1 s a shot | Best balance |
| This Mac | Best | Qwen3-VL 30B-A3B, 4-bit, MLX Swift | 17 GB | ~1.5 s a shot | Needs 32 GB of memory or more |
| Gemini | — | Gemini Flash through the Gemini API with your key | — | Depends on upload | Footage leaves this Mac (360p proxies). Sees motion across a whole take, not only keyframes. |

- Local engines run in-process with `mlx-swift-lm` (MLXVLM). No Python. Weights download on first use to `~/Library/Application Support/Direction/Vision/` with progress in Settings › Footage, and show in Settings › Storage.
- If free disk space is less than the download plus 2 GB, the download doesn't start, and Settings shows "Only 13 GB free on Macintosh HD. Standard needs 5.8 GB." with Quick offered instead.
- Memory: Standard holds about 6 GB while it looks, and unloads 60 s after the last shot.
- Gemini sends each take's 360p proxy through the Files API and asks for the shot list and the same shape per shot, with timestamps; Direction's own shots (step 2) are kept and Gemini's lines are matched to them by time. Spend counts toward Settings › Services limits.
- A Gemini app subscription isn't an API key. The key comes from Google AI Studio and is entered in Settings › Services.

Speed targets are for the sample film (214 takes, 3 h 12 min, about 1,900 shots): Standard finishes in about 35 minutes, and circling can start as soon as the first scene is logged.

### The pill while footage is looked at

Looking at footage is Direction's own work, done on the editor's behalf. Until the editor's logging run starts, the pill reads "Looking at footage · 88 of 214" (no shimmer, no window edge: those mean the editor itself is working). Once logging starts, the pill shows the run ("Logging 42 of 214") and the index carries on underneath.

## What the editor gets (tools)

| Tool | Arguments | Returns |
|---|---|---|
| `direction_shots` | `assetID?`, `sceneID?`, `offset`, `limit` | Shots with range, description, size, movement, people, flags, sounds, and small keyframe paths |
| `direction_contact_sheet` | `assetID`, `range?`, `frames` (4–36, default 16) | One image grid with source timecodes, and the time of each cell |
| `direction_frame` (extended) | `assetID` and `time` (source seconds), or the existing cut `time` | A real frame of a take, not only of the cut |
| `direction_watch` | `start`, `end` (cut seconds), `revision?`, `frames` (8–24, default 12) | A filmstrip image of the passage with timecodes, the words in it, sounds, and where the cuts fall. The closest thing to watching. |
| `direction_search_footage` | `query`, `sceneID?`, `circledOnly?`, `limit` (default 12) | Ranked shots with a score, why they matched (`picture`, `words` or `both`), and keyframe paths |

- Search ranks by vector similarity of the query to keyframes, blended with FTS5 scores over descriptions and words (0.6 picture, 0.4 text), best shot per take first.
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
- [ ] Searching never sends footage or the query off this Mac unless the engine is Gemini, and even then the query stays local.
- [ ] A take whose index failed still shows in Dailies with "Couldn't look at this take" and **Try again** in its context menu.

# Speed and quality

Each film has one setting, **Faster · Balanced · Best**, on a slider in the editor popover and in Who's editing? (specs/editor.md › Speed and quality). The director never chooses a version or an effort. From the film's stop Direction picks:

- the editor's version and effort for each job (`EditorPicks`, Sources/DirectionApp/Phase2/Runs/EditorPicks.swift);
- the version for each made request, by what it needs (`MadePicks` and `MadeCatalog.route`, Sources/DirectionCore/Phase2/Made/MadeRouting.swift);
- the resolution a made shot is made at: 720p where a version lists it (else 768p) at Faster and Balanced, quicker and for about half, which this Mac sharpens to a cut half again as tall or more; 1080p where a version offers it at Best, and on a Mac that can't sharpen.

The picks below were researched on 8 Nov 2026. Refresh them by hand: read the sources again, change the tables in code and here, and say what moved in the commit. Then confirm the editor's picks with the bench (docs/bench.md).

## The editor

The rule behind the table: judgement (cutting, answering notes, a style's taste) stays on the strongest version at every stop, and only its effort moves. The list-like jobs (a breakdown, finishing) move to lighter versions. Nothing that looks at frames runs below Medium.

| Job | Faster | Balanced | Best |
|---|---|---|---|
| A/V script | Sonnet 5.5 · medium | Opus 5.5 · medium | Opus 5.5 · high |
| Breakdown | Haiku 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · medium |
| Logging takes | Sonnet 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · high |
| Assembly | Opus 5.5 · medium | Opus 5.5 · high | Opus 5.5 · xhigh |
| Notes | Opus 5.5 · medium | Opus 5.5 · high | Opus 5.5 · xhigh |
| Finishing | Haiku 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · medium |
| Styles | Opus 5.5 · medium | Opus 5.5 · high | Opus 5.5 · xhigh |
| Techniques | Sonnet 5.5 · medium | Opus 5.5 · medium | Opus 5.5 · high |

| Job (Codex) | Faster | Balanced | Best |
|---|---|---|---|
| A/V script | GPT-6.1 Terra · medium | GPT-6.1 Sol · medium | GPT-6.1 Sol · high |
| Breakdown | Terra · low | Terra · medium | Sol · medium |
| Logging takes | Terra · medium | Terra · medium | Sol · high |
| Assembly, Notes, Styles | Sol · medium | Sol · high | GPT-6 Astra · high |
| Finishing | Terra · low | Terra · medium | Sol · medium |
| Techniques | Terra · medium | Sol · medium | Sol · high |

Why:

- **Opus 5.5 for judgement at every stop.**
  - At medium it takes about as long per task as Sonnet 5.5 at high (7.0 min each on Artificial Analysis) and scores higher (48 against 42).
  - It's well ahead at reading pictures (Vision Arena 1296 against 1261).
  - Max adds 2 points for 1.6× the time and a long wait before the first word, so Best stops at Extra high.
- **Writing (A/V script, Techniques).** Quality is nearly flat above medium in Anthropic's own runs, and Sonnet's writing score is within 2 points of Opus. Extra high takes about 1.7× as long as high for writing it doesn't measurably improve.
- **Breakdown and Finishing.** Structured or mechanical work is Haiku 5.5's stated use. Medium is the floor: at low, Haiku stops early when the instructions are long, and Direction's are.
- **Logging takes.** It looks at many frames, and Haiku reads pictures poorly (46% on Chartography against Sonnet's 62%), so Faster stays on Sonnet. Research picked Haiku here; Direction doesn't.
- **Fable 5.1 is never picked.** It costs about 2.5× per token and is below Opus 5.5 on every number that matters here.
- **Codex.**
  - Terra is half Sol's price, the quickest per task, and pitched for visual reasoning and writing.
  - Low effort only on list jobs: Codex's own default is low, and logged runs at low used almost no thinking.
  - Astra at high matches its Extra high (55) and costs about 4× Sol, so it's only at Best.
  - GPT-6 Luna is never picked (Vision Arena 68th).
- **Codex fallbacks.** A version the installed Codex doesn't list falls to the next it does (Astra → Sol → Terra, Sol → Terra → Astra, Terra → Sol → Astra), else Codex's own default.

Sources, all read 8 Nov 2026:

- Artificial Analysis models leaderboard (intelligence index and minutes per task by effort): https://artificialanalysis.ai/leaderboards/models
- Vision Arena (dated 6 Nov 2026): https://arena.ai/leaderboard/vision
- Launch notes:
  - Claude Opus 5.5 (2026-09-22): https://www.anthropic.com/claude-opus-5-5
  - Sonnet 5.5 (2026-09-28): https://www.anthropic.com/claude-sonnet-5-5
  - Haiku 5.5 (2026-10-07): https://www.anthropic.com/claude-haiku-5-5
  - GPT-6.1 Sol (2026-09-29; OpenAI's post wouldn't load, so its developer forum)
  - GPT-6.1 Terra (2026-10-26): https://www.datacamp.com/blog/gpt-6-1-terra
- OpenAI's effort defaults: https://developers.openai.com/api/docs/guides/latest-model

Not yet measured on Direction's own work; the bench should settle both:

- Opus at medium against Sonnet at high for an assembly.
- Astra against Sol for notes.

No public benchmark measures reading video frames for these versions.

## Made picture and sound

The picks for each kind of request and what it needs are tried first, in order. A pick is skipped when it can't make the request:

- a person ByteDance won't take;
- no last frame;
- too short;
- no listed price;
- gone from OpenRouter's list.

After the picks, the Artificial Analysis ratings order the rest, as before.

| Request | Faster | Balanced | Best |
|---|---|---|---|
| Still with words (quoted in the ask) | GPT Image 2.6 Flare | GPT Image 2.6 Flare | GPT Image 2.6 Sunburst |
| Still | GPT Image 2.6 Flare | Nano Banana 2.1 | GPT Image 2.5 Sunburst |
| Shot or extension | Hailuo 3 Max | Hailuo 3 Max; with a person, Wan 3.0 | Seedance 2.5; with a person, Wan 3.0 |
| Shot that's mainly a camera move | Hailuo 3 Max | Hailuo 3 Max | Seedance 2.5; with a person, Hailuo 3 Max |
| Shot from words alone | Hailuo 3 Max | Gemini Omni 1.2 Flash | Wan 3.0 |
| Shot with sound | Gemini Omni 1.2 Flash | Wan 3.0 | Seedance 2.5; with a person, Hailuo 3 |
| Bridge (first and last frames) | Hailuo 3 Max | Wan 3.0 | Seedance 2.5; with a person, Wan 3.0 |
| Changed shot | FLUX Video Edit | FLUX Video Edit | Aleph 2.0 |
| Voice | Eleven v4 Turbo | Eleven v4 Turbo | Eleven v4 |

Music (Lyria 3 Clip), sound effects (Lyria 3 Clip) and sharpening (this Mac, FLUX Video Upscale above 1080p) didn't change.

Why:

- **Hailuo 3 Max for Faster and Balanced.**
  - It's rated within the margin of the best (silent image to video: 1122 against Seedance 2.5's 1131), with strong physics and camera control.
  - It takes about 15 s where the others take two to five minutes.
  - It costs about $0.08 a second.
  - It makes no sound, so a shot with sound skips it.
- **People.** Seedance refuses them. Wan 3.0 rates best at human anatomy of the versions that take people.
- **Words and camera moves are read from the ask.** Words in quotes (after a space, starting right after the quote, so 12" isn't words) and camera-move phrases (an orbit around, a push in, a crane shot; not "crane" alone).
- **Camera moves never go to Hailuo 3.** Its camera control rates far below the rest, and it's the version whose orbits failed.
- **Bridges.** No board measures first-to-last-frame shots; consistency over time is the nearest measure.
- **Stills.**
  - GPT Image leads every text-rendering board.
  - For keeping a frame and following several references, GPT Image 2.5 Sunburst rates best and Nano Banana 2.1 is close at about a sixth of the price.
- **Voice.** Eleven v4 rates best for speech and Turbo is its quick one. Fish Audio's Drama 3 rates close and costs far less, but OpenRouter lists no voices for it, so it isn't used until it's tried. Before this, voice was whichever speech version OpenRouter listed first, which changed whenever a new one was added.
- **Changed shots stay where they were.** Gemini Omni 1.2, Hailuo 3, Wan 3.0 and Seedance 2.5 all rate above Aleph 2.0 at changing video. But none is proven yet with a real take, a person in it, sent through OpenRouter (below).

Sources, all read 8 Nov 2026:

- OpenRouter's lists:
  - https://openrouter.ai/api/v1/videos/models
  - `…/models?output_modalities=image|speech|audio`
  - each version's page for its typical time
- Artificial Analysis (scores within about ±45 are ties):
  - https://artificialanalysis.ai/video/leaderboard/image-to-video
  - …/text-to-video
  - …/video-editing
  - https://artificialanalysis.ai/image/leaderboard/editing
  - https://artificialanalysis.ai/text-to-speech/leaderboard
- LMArena:
  - https://arena.ai/leaderboard/image-to-video
  - …/video-edit
  - …/image-edit/multi-image-edit
  - …/text-to-image/text-rendering

## Still to test, with real requests (they cost money: ask first)

1. **Gemini Omni 1.2 and a real person.** Make one shot and one changed shot from a frame of the director, and check that a refusal is caught as one.
2. **Changing video with other versions.** Send a take as video to Omni 1.2, Hailuo 3 and Seedance 2.5. If they take it, they can replace FLUX Video Edit and Aleph for changed shots.
3. **Bridges with the director at both ends.** Make them on Hailuo 3 Max, Wan 3.0, Omni 1.2 and Kling 3.0 Pro, and judge each with the made-shot check.
4. **Hailuo 3 Max on the asks that failed on Hailuo 3.** The orbits and the morphs.
5. **References on shots that start from a frame.** OpenRouter says `frame_images` wins over `input_references`, so the references may not reach the version.
6. **GPT Image's quality setting and price.** Check what Direction actually gets and pays.
7. **Sound effects.** Seed Audio 1.0 against Lyria 3 Clip, on five effects.

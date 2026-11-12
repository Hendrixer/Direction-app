# Speed and quality

Each film has one setting, **Fastest · Faster · Balanced · Best**, on a slider in the editor popover and in Who's editing? (specs/editor.md › Speed and quality). The director never chooses a version or an effort. From the film's stop Direction picks:

- the editor's version and effort for each job (`EditorPicks`, Sources/DirectionApp/Phase2/Runs/EditorPicks.swift);
- the version for each made request, by what it needs (`MadePicks` and `MadeCatalog.route`, Sources/DirectionCore/Phase2/Made/MadeRouting.swift);
- the resolution a made shot is made at: 720p where a version lists it (else 768p) at Fastest, Faster and Balanced, quicker and for about half, which this Mac sharpens to a cut half again as tall or more; 1080p where a version offers it at Best, and on a Mac that can't sharpen.

The picks below were researched on 8 Nov 2026. Fastest was added on 11 Nov 2026: Faster kept Opus 5.5 for cutting, so it wasn't the quick option the director expected; Fastest puts cutting, notes and styles on the second version too (Sonnet 5.5; Sol for Codex, which Faster already uses) and makes media as Faster does. Refresh them by hand: read the sources again, change the tables in code and here, and say what moved in the commit. Then confirm the editor's picks with the bench (docs/bench.md).

## The editor

The rule behind the table: from Faster up, judgement (cutting, answering notes, a style's taste) stays on the strongest version, and only its effort moves; at Fastest it runs on the second version. The list-like jobs (a breakdown, finishing) move to lighter versions. Nothing that looks at frames runs below Medium.

| Job | Fastest | Faster | Balanced | Best |
|---|---|---|---|---|
| A/V script | Sonnet 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · medium | Opus 5.5 · high |
| Breakdown | Haiku 5.5 · medium | Haiku 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · medium |
| Logging takes | Sonnet 5.5 · medium | Sonnet 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · high |
| Assembly | Sonnet 5.5 · medium | Opus 5.5 · medium | Opus 5.5 · high | Opus 5.5 · xhigh |
| Notes | Sonnet 5.5 · medium | Opus 5.5 · medium | Opus 5.5 · high | Opus 5.5 · xhigh |
| Finishing | Haiku 5.5 · medium | Haiku 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · medium |
| Styles | Sonnet 5.5 · medium | Opus 5.5 · medium | Opus 5.5 · high | Opus 5.5 · xhigh |
| Techniques | Sonnet 5.5 · medium | Sonnet 5.5 · medium | Opus 5.5 · medium | Opus 5.5 · high |

| Job (Codex) | Fastest | Faster | Balanced | Best |
|---|---|---|---|---|
| A/V script | GPT-6.1 Terra · medium | Terra · medium | GPT-6.1 Sol · medium | Sol · high |
| Breakdown | Terra · low | Terra · low | Terra · medium | Sol · medium |
| Logging takes | Terra · medium | Terra · medium | Terra · medium | Sol · high |
| Assembly, Notes, Styles | Sol · medium | Sol · medium | Sol · high | GPT-6 Astra · high |
| Finishing | Terra · low | Terra · low | Terra · medium | Sol · medium |
| Techniques | Terra · medium | Terra · medium | Sol · medium | Sol · high |

On Codex, Fastest and Faster pick the same: cutting there is already on Sol at Faster, and Astra (about 4× Sol) stays at Best.

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
| Bridge (first and last frames) | Wan 3.0 | Kling 3.0 Pro | Seedance 2.5; with a person, Kling 3.0 Pro |
| Changed shot | FLUX Video Edit | FLUX Video Edit | Aleph 2.0 |
| Voice | Eleven v4 Turbo | Eleven v4 Turbo | Eleven v4 |
| Sound effect | Seed Audio 1.0 | Seed Audio 1.0 | Seed Audio 1.0 |

Music (Lyria 3 Clip) and sharpening (this Mac, FLUX Video Upscale above 1080p) didn't change. Lyria takes a sound effect only when Seed Audio turns it down. Shots with references skip Hailuo 3 Max, which takes none. The bridge and sound effect rows changed after the paid trials (below).

Why:

- **Hailuo 3 Max for Faster and Balanced.**
  - It's rated within the margin of the best (silent image to video: 1122 against Seedance 2.5's 1131), with strong physics and camera control.
  - It takes about 15 s where the others take two to five minutes.
  - It costs about $0.08 a second.
  - It makes no sound, so a shot with sound skips it.
- **People.** Seedance refuses them. Wan 3.0 rates best at human anatomy of the versions that take people.
- **Words and camera moves are read from the ask.** Words in quotes (after a space, starting right after the quote, so 12" isn't words) and camera-move phrases (an orbit around, a push in, a crane shot; not "crane" alone).
- **Camera moves never go to Hailuo 3.** Its camera control rates far below the rest, and it's the version whose orbits failed.
- **Bridges.** No board measures first-to-last-frame shots, so the paid trials did. Hailuo 3 Max takes only one of the two frames. Kling 3.0 Pro showed what made the change (the director puts the headphones on); Wan 3.0 let them appear. Kling took four minutes and cost $0.56, Wan two minutes and $0.43, so Faster takes Wan.
- **Sound effects.** Lyria 3 Clip is a music version: asked for five effects, it made five pieces of music. Seed Audio 1.0 made the effects themselves, for well under a cent each.
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

## The paid trials (8 Nov 2026)

Run with `scripts/live-made.sh` (the director's key, a throwaway film, the version pinned, everything through Direction's own request path). 24 trials for $1.79 of the $5.79 planned: most failures were turned down before anything was made, and those cost nothing. Each finding below changed Direction or its picks.

1. **Gemini Omni 1.2 with a real person.** Not answered yet: Omni turned down every request before looking at it, because Direction asked for a shot without sound and Omni always makes sound ("generate_audio cannot be set to false"). Omni lists prices only with sound, so Direction no longer sends the setting to it, takes the sound off afterwards, and asks any other version that turns the setting down again without it.
2. **Changing a take with other versions.** Hailuo 3 and Seedance 2.5 turn down a take sent as data ("Only HTTPS URLs are allowed"); Omni took it, then failed without saying why. Direction sends every changed shot this way, so the changing versions (FLUX Video Edit, Aleph 2.0) need the same test before changed shots can be trusted.
3. **Bridges with the director at both ends.** Kling 3.0 Pro and Wan 3.0 made clean bridges (the check agreed); Kling's showed the cause of the change, Wan's didn't. Hailuo 3 Max turned it down: it takes one keyframe, not two. Omni turned it down for the sound setting (1). The bridge picks changed.
4. **Hailuo 3 Max on the asks that failed on Hailuo 3.** Both worked, in about 15 s each. The orbit went round the director, though the hair changed seen from the side (the check missed it). The cockpit morph was what was asked, but the check called it broken; the check now treats a change the ask describes as the shot, not a fault.
5. **References on a shot from a frame.** Not answered yet: Hailuo 3 Max takes no references at all ("does not support image input references"), so shots with references now skip it. OpenRouter's guide says `frame_images` win over `input_references`; a version that takes references has to show whether they still reach it.
6. **GPT Image's quality setting and price.** Direction sends no quality setting. Flare and Sunburst both made a clean 1536 × 864 still for a 16:9 film, alike to the eye. Both replies reported a cost of $0, as did every Lyria clip, so Direction's record said nothing was spent. Direction now looks up the generation record when a reply reports no cost, and counts the estimate if that says nothing either.
7. **Sound effects.** Seed Audio 1.0 made a glass shattering, thunder, footsteps on gravel and a camera shutter as sound, at their own lengths (0.6 to 7 s); its service turned the door creak down. Lyria 3 Clip made music for all five, 4 s each. Sound effects now go to Seed Audio, with Lyria behind it for an ask it turns down.

Also found: Hailuo 3 Max and Wan 3.0 sent shots with sound when asked for none. Direction now takes the sound off any shot made without `sound`.

### Round 2 (8 Nov 2026, evening)

8 requests for $0.11 of the $1.72 planned: three were turned down before anything was made, and one reported $0 (below).

1. **Gemini Omni 1.2 with a real person.** It made the shot in 43 s, with no refusal: the director looks up from the phone and smiles in one continuous move, stays themselves throughout, and leans in further than asked. Its sound came off. It reported a cost of $0 and Direction recorded $0; a finished shot that reports $0 is now looked up in the generation record (`generation_id`), and the estimate ($0.35 here) is counted if that says nothing.
2. **FLUX Video Edit and Aleph 2.0 turn down a take sent as data** ("Only HTTPS URLs are allowed"), as Hailuo 3 and Seedance did. Every changed shot fails today (nothing is charged), and FLUX Video Upscale is sent the same way. Changed shots need the take at an HTTPS address OpenRouter can fetch: a product decision, since the director's footage would sit there for the minutes it takes.
3. **References with a first frame** on Hailuo 3: turned down, since MiniMax's Hailuo versions "do not support frame_images and input_references in the same request". A shot from a frame with references now skips every Hailuo.
4. **What sound and stills cost.** Seed Audio's two effects were read from the generation record: $0.009 for 3.5 s, and $0.024 for 9.5 s made when 4 s was asked (cut to 4). It's paid by the second it makes and chooses the length, so effects are now priced at 10 s ($0.025). The GPT Image still and the Lyria clip had no cost in the record either, so Direction counted their estimates ($0.04 each). OpenRouter lists Lyria at $0, so it may be free for now; the trials now read the key's total before and after a run to settle it.
5. **Sound effects as the app makes them.** The door creak went through this time, worded "A sound effect, not speech: …" (round 1's was turned down); steady rain came back as steady rain. The music sting was 10 s of guitar.

## Still to test, with real requests (they cost money: ask first)

1. **Changed shots from an HTTPS address**, once the take has one: FLUX Video Edit and Aleph 2.0 against the same 2 s, and FLUX Video Upscale.
2. **References beside a first frame** on a version that takes both (Kling 3.0 Pro, Wan 3.0): OpenRouter's guide says `frame_images` win, so whether the reference still shows in the shot.
3. **Whether the replies that report $0 are charged** (Gemini Omni, GPT Image, Lyria): the key's total before and after the next run says.

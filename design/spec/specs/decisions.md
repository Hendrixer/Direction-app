# Fast decisions

Planned 31 Oct 2026, after the first films showed made shots placed that should have been thrown away. Judging made shots is built and in shadow; reading notes is planned.

## What a decision model is

A model that answers one narrow question by choosing from answers you give it, with a probability for each and a confidence, in about 0.15–0.3 s and for a fraction of a cent. It writes nothing. OpenRouter serves them on its decisions endpoint (`POST /api/alpha/decisions`) with the same key Direction already keeps:

- **GPT-6 Luna decisions** (OpenAI, `openai/gpt-6-luna-decisions`, 6 Oct 2026): words and up to 128 images a request, on a model built to see. About $0.10 a million input tokens, output free (third-party listings; OpenRouter's image rate isn't published).
- **Jev 1.14** (TypeSafe, `typesafe/jev-1.14`, 14 Oct 2026): words and images. $0.042 a million input tokens, output free. TypeSafe calls its image input experimental and says every decision model does worse on images than on words. Each side 256–1,568 px, PNG or JPEG.
- **Clef Flash** (Cloudflare): 4 images a request, under about 300 KB each.

No one has published a comparison of them on images, so Direction asks Luna and Jev both and compares (below).

A request is `{model, state, questions}`. Frames go in `state` inline, as `{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,…"}}` parts between text labels: the one shape every version takes (Jev also takes keyed `assets`, others don't). Each question is `{type: "choice", instructions, criteria: {label: what it means}}`; all of a request's questions are answered in parallel and can't see each other. Each answer is `{choice, probabilities, confidence}`, and `usage.cost` is the spend. `confidence` is how concentrated the answer is, not how likely it's right.

They don't plan, reason or write. The editor keeps all of that. A decision model is for the yes/no and which-one questions Direction asks many times, where waiting for the editor costs a minute and its judgment has been lenient.

## 1. Judging made shots (built, shadow)

Every way of a new shot, extension, bridge, changed shot or still is checked by Direction as soon as it comes back, before the editor sees it (`MadeChecker`, `Decisions`). Slow motion and sharpening work on real footage and aren't checked.

**One request a way to each version**, at once: GPT-6 Luna decisions, then Jev 1.14 (`Decisions.frameVersions`). Luna's answer is the check; where Luna can't answer, Jev's stands in; the other's is kept beside it (`otherChecks`) for comparing. The state labels each frame and quotes the ask: "5 frames of one shot made for a film, in order.", "Frame 1 of 5, at 0:00, the start:", the frame, … "It was made from this description: "…"". Frames are taken at the start, ¼, ½, ¾ and 0.1 s before the end, as JPEG with a 1,024 px long side (smaller ones are drawn up so neither side is under 256). A still is one frame.

| Question | Asked about | Answers |
|---|---|---|
| `look1`…`look5` | one frame each, by place ("Look only at frame 3 of 5."): "Is anything in it broken the way made pictures break?" | `clean` · `minor` (soft or odd in a small area) · `broken` (a melted or doubled face, hand or body, a malformed or fused object, a garbled picture) |
| `morph` | all five, in order: "Do the things in it move the way real things move?" | `moves` · `morphs` (changes shape, turns into something else, appears from nothing, melts) |
| `same` | the first and last frame: "Is anyone still the same person, and is it still the same place?" | `same` · `drifted` |
| `asked` | the whole, against the ask | `yes` · `partly` · `no` |

A still asks `look1` and `asked`. A way with no ask (none today) skips `asked`.

**The verdict** is the worst thing found: `broken` for any broken frame, `morphs`, `drifted` or `no`; `minor` for a minor frame or `partly`; otherwise `clean`. Findings are written for people: "Something looks broken at 0:03 and 0:05.", "A person or the place turns into someone or somewhere else by the end.", "It shows only part of what was asked."

**Where it shows:**
- The job result the editor reads: `check: {verdict, findings, frames: [{at, verdict}], shadow}` on each made way, or `{verdict: "unchecked", why}` (docs/made-media.md). The make-shot skill says to use it to know where to look, not instead of looking, and to say why when placing a way it called broken.
- The made clip's provenance keeps the whole check, every answer's probabilities included, and the other version's check, so thresholds can be set and the versions compared later (`MadeRecord.check`, `otherChecks`).
- The provenance popover's **Checked** row: "Looks clean", "Slightly off", "Looks broken at 0:03", with the findings in its tooltip.
- The log: `Checked Made/shot-….mp4: broken (…) by openai/gpt-6-luna-decisions-…; typesafe/jev-1.14-… says clean`.

**Spend:** what OpenRouter reports for each version's answer, in the ledger as kind `checking`, shown as "Checking" under Spent this month (hidden under half a cent). It counts toward the turnover and the month like any spend, and no check is made once the month's limit is reached. Expected cost: well under a cent a way.

**It never fails a way.** When neither version can answer (a 4xx/5xx, the month's limit) the clip is unchecked, with each version's reason; the shot is made and paid for either way.

**Shadow first.** Neither version has been measured on made shots, so for the first films the check holds nothing back (`MadeCheck.holdsBack = false`, `shadow: true`). To graduate:
1. After about 20 checked ways, compare each version's check with what happened to the way: placed by the editor or not, and kept by the director (in the accepted cut, with no note against it) or not. Both are in the film already: the made record, the cuts and the notes.
2. Keep the version that agrees with the director more and stop asking the other. Set thresholds on its answers' probabilities, per question (a `broken` at 0.55 may mean less than a `drifted` at 0.9).
3. Then a broken way is never placed first, and Direction makes it once more by itself with the same ask (inside the turnover's spend limit) before the editor sees it.

## 2. Reading a note as it's written (planned)

Text only, so Jev. As the director types a note, Direction asks *"What kind of note is this?"* (picture · sound · feeling · question) and *"Does it need something the footage doesn't have?"* (no · maybe · yes). The composer picks the kind chip itself, and a "yes" shows "This may need a made shot" before the note is turned over, with what Made with would cost. Today the director picks the kind and the editor finds out about made shots mid-turnover.

## Playbooks: should code decide the steps?

Asked 31 Oct: the editor decides every step itself. Would workflows in code, a playbook per kind of note that calls the editor only for reasoning, be faster and cheaper?

**What the films show** (read 31 Oct). Four notes across two films, all picture, all open-ended: a rounded picture-in-picture of the director with a shadow; a made shot that turns the camera to behind them; a screen recording of a video framed with padding and a background; on-screen text held longer and restyled as shiny metal. None is a "trim this" or "louder" a fixed playbook could take whole. Turnovers took 0.9, 1.0 and 8.4 minutes (the long one waiting on made shots). The editor was Codex on GPT-6.1 Terra and Sol, which default to low effort.

**No note router.** A router in front of the editor would send nearly every one of these notes to "other", and running the wrong playbook on a creative note costs a turnover. The editor stays the one who decides what a note needs. What changes:

1. **Recipes as tools, chosen by the editor** (next to build). Where the steps really are fixed, Direction runs them as one tool call and the editor supplies only the words and the judgment. First the made-shot recipe (make-shot §3–6): stills two to four ways, a decision model picks the still closest to the shot card, the chosen still animated two ways, each way checked, one retry with the editor's changed ask, and back comes the best way that passed with every check. The editor writes the shot card and the asks; code does the twenty calls between them. Then the recipes behind notes 1 and 3, which became a feature of their own: layouts.md.
2. **A turnover packet.** Direction gathers what every turnover starts by fetching (each note's range, frames at its time, the words said there, the clip under it) into the job text, so the editor's first minute isn't spent finding things.
3. **More thinking where it counts.** Settings › Engines › Version and effort sets it per job since 2026-11-03 (editor.md › Version and effort, per job): Extra high for assembly, notes and styles, High for the rest. The made-shot asks the director called bad were written at low effort; try High for turnovers before building anything else, and Claude Fable 5.1 for hard films.
4. **Revisit a router when notes repeat.** After about 50 notes, ask Jev offline what kind each was (trim · level · move · retime · words on screen · other) and build playbooks only for kinds that come up often.

## Not worth it now

- **A person in a frame:** Vision on this Mac already answers it, for nothing (`PeopleCheck`).
- **The editor's planning, read-backs and answers:** full reasoning; the editor's job.
- **Gating the editor's edits:** Direction already checks revisions, locks and must-keeps in code.

## Building the rest

- `Decisions.ask(questions, state:, version:, spend:)` in DirectionCore is the one client. Same key, same ledger, OpenRouter's errors as `openrouter_error`.
- Settings › Engines gains nothing: it's on when an OpenRouter key is set, and its spend shows under Checking.
- Versions follow the made-media rule: Direction picks, nobody chooses. Pin versioned ids; OpenRouter's "latest" aliases move.

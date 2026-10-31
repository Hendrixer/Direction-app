# Fast decisions (plan)

Not built yet. Planned 31 Oct 2026, after the first films showed made shots placed that should have been thrown away.

## What a decision model is

A model that answers one narrow question by choosing from answers you give it, with a probability for each and a confidence, in about 0.15–0.3 s and for a fraction of a cent. It writes nothing. OpenRouter serves them on its decisions endpoint (`/api/alpha/decisions`) with the same key Direction already keeps:

- **Jev** (TypeSafe): text only. About $0.04 per million input tokens; P50 0.21 s.
- **Clef Flash** (Cloudflare), **GPT-6 Luna decisions** (OpenAI): take images too, as base64 `image_url` parts in `state`. Same request shape as Jev.

They don't plan, reason or write. The editor keeps all of that. A decision model is for the yes/no and which-one questions Direction asks many times, where waiting for the editor costs a minute and its judgment has been lenient.

## Where it helps Direction

### 1. Judging made shots (first)

Every made shot comes back as two ways the editor is supposed to judge (make-shot skill › Judge every frame). It looked and placed shots it should have thrown away. Direction would judge them itself, as soon as each way arrives:

- Five frames (0, 25, 50, 75, 100 %), each asked: *"Is anything in this frame broken?"* → `clean` · `minor` (soft, slightly off) · `broken` (a melted face or hand, an object morphing, a tilted horizon). Image model.
- First and last frame together: *"Is this the same person / the same place?"* → `same` · `drifted`. Image model.
- The ask and the middle frame: *"Does the picture do what was asked?"* → `yes` · `partly` · `no`.

The verdicts go in the made clip's provenance (`check: {verdict, frames, confidence}`), in the job result the editor reads, and on the Made chip in Changes ("Checked: clean" / "Checked: a face drifts at 0:03"). A way that's `broken` is never the one placed first.

**Shadow first.** For the first films the check only records; it never blocks. Then compare its verdicts with what the director accepted and rejected in Changes, set the thresholds from that, and only then let Direction make a broken way once more by itself (inside the turnover's spend limit) before the editor sees it.

Cost: 7 small image questions a way, well under a cent. Time: under 2 s, beside a minute of making.

### 2. Reading a note as it's written (second)

Text only, so Jev. As the director types a note, Direction asks *"What kind of note is this?"* (picture · sound · feeling · question) and *"Does it need something the footage doesn't have?"* (no · maybe · yes). The composer picks the kind chip itself, and a "yes" shows "This may need a made shot" before the note is turned over, with what Made with would cost. Today the director picks the kind and the editor finds out about made shots mid-turnover.

### Not worth it now

- **A person in a frame:** Vision on this Mac already answers it, for nothing (`PeopleCheck`).
- **The editor's planning, read-backs and answers:** full reasoning; the editor's job.
- **Gating the editor's edits:** Direction already checks revisions, locks and must-keeps in code.

## Building it

- One `Decisions` client in DirectionCore beside `OpenRouter`: `ask(question, choices, state: [text | image], version) async throws -> (choice, probabilities, confidence)`. Same key, same spend ledger (kind `checking`), same refusal handling.
- Settings › Engines gains nothing: it's on when an OpenRouter key is set, and its spend shows under "Checking" in the month's meter.
- Versions follow the same rule as made media: Direction picks (an image model for frames, Jev for text), nobody chooses.

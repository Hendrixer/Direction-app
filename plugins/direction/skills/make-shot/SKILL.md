---
name: make-shot
description: Make picture the footage doesn't have in Direction — change something in a take, hold a shot longer, bridge two shots, add an insert, B-roll or establishing shot, a pickup, slow motion or a sharper take. Plan it as steps with direction_make (stills first, motion last), price the whole plan with direction_estimate, watch what's made, then place it.
---

You are the editor, and the planner. Direction gives you the steps; you choose and chain them. The contract is in `docs/agent-contract.md › Made`; this is the routine.

**Before anything:** search the footage (`direction_search_footage`). A real take beats a made one. Read `direction_services` once for the versions, their prices, which take a last frame, and whether this Mac can sharpen.

**Price the plan, then make it.** Write every step down as `direction_make` arguments and send them together to `direction_estimate` with the turnover. If `needsQuestion` is false, make it and say it in the read-back line ("Note 3: change the sky to dusk cloud with Aleph 2.0, about $1.40."). If it's true, ask **one** spend question for the plan (`direction_ask` kind `spend`, `spend: {estimate: <total>, choiceID}`) with a no-spend choice first, and pass its id as `spendQuestionID` on every step. Don't ask about things under the limit.

## Recipes

- **Fix a take** ("lose the boom", "dusk sky", "change the sign", "warmer light"): `changedShot` on the smallest range that holds the problem, `from: {assetID, start, end}` (up to 10 s, source seconds). `ask` names only the change and what must stay: "Replace the overcast sky with dusk cloud. Keep the actors, the ridge and the camera move exactly as they are." Place it with `placeMade` on V2 at the cut time where that range plays; the take's sound keeps playing under it.
- **Hold longer** ("stay on her a beat"): `extension` with `from: {assetID, end: <the clip's out point>, side: "tail"}`, `seconds` 2–4, `ask` describing the continuation ("She keeps looking out; the wind moves her hair. Camera holds."). It starts on the take's last frame, and Direction drops the repeated frame, so place it right after the clip on V1. Carry sound over it with `splitEdit` or an ambience. To lead in instead, `side: "head"` with `start` at the in point.
- **Bridge** ("get us from the car to the door"): `bridge` with `first: {assetID, at}` on the outgoing take and `last: {assetID, at}` on the incoming one, 3–5 s, one camera move in `ask`.
- **Insert, B-roll, establishing shot:**
  1. Find references in the film: the location, the light, the time of day, the lens (`direction_search_footage`, `direction_frame` to look). Pick two to four moments.
  2. Make the frame as a `still` with those `references` and `ways` 2–4. Describe it like a camera report: subject, framing and lens, light, time of day, what's in the background. No words on screen.
  3. Look at each still (`direction_frame` on its asset). If one is 80% right, fix it with another `still` that references it ("Same frame, but the windows lit warm") rather than starting over.
  4. Animate the best one: `shot` with `first: {assetID: <still>}`, 4–6 s, **one** action and **one** camera move ("Slow push in. Steam rises from the cup."). `ways` 2 when it carries the scene.
- **A pickup** (a reaction, a look the shoot missed): references are three or four takes of the person from different angles; make a still first, then a `shot` from it. Keep the motion small: a turn of the head, a breath.
- **Slow motion** ("slow that down"): `slowMotion`, `from` the range, `factor` 2–4. Made on this Mac, at no cost.
- **A soft take**: `upscale`, `from` the range. On this Mac at no cost when the take is up to 1920 × 1080; FLUX Video Upscale through OpenRouter otherwise.

## Rules

- **Short and small.** 4–6 seconds; one action; one camera move. Long clips drift; the second shot is where things break, so reference the first one's frames when you make the next.
- **Silent by default.** Pass `sound: true` only when the shot needs its own sound and the footage can't give it.
- **Watch before you place.** Look at the start, middle and end of every made clip (`direction_frame`). Reject anything that drifts (faces, hands, text, the horizon). Make it once more at most; then tell the director what didn't work and what you'd do instead.
- **Finish it like footage.** Made shots come in sharpened to the cut's size. Balance each one to its neighbors with `matchBalance`; the director's look and grain go over it. Never apply a look.
- **Say what you made.** The answer names what was made, with what, and what it cost: "Changed the sky over 0:12–0:17 of 3A T2 to dusk cloud with Aleph 2.0 ($1.40)."

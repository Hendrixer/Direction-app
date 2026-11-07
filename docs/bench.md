# Bench: measuring the editor (issue #6)

A set of real films is run before each release, and each run is scored the same way, so the editor's cutting gets better measurably and never quietly gets worse.

## The films

Each bench film is a Direction film with its footage, its brief, and the director's notes on its first assembly. Where the director cut it themselves, that cut is kept as the reference. Films stay outside this repository, wherever the director keeps them, with permission to use them.

## A run

Runs use the director's editor subscription (Claude Code or Codex), so they're started by hand, never by CI.

1. Copy the film (Finder › Duplicate) and open the copy, never the original.
2. Run the job being measured: an assembly from circled takes, or a turnover of the saved notes.
3. When the cut is ready, score it:

```sh
direction bench --project "~/Bench/Launch film copy.direction" --cut "Cut 2" --reference "Director's cut" \
  --previous ~/Bench/reports/launch-film-0.3.3.json --out ~/Bench/reports/launch-film-0.3.4.json
```

`--cut` is the cut to score (the latest when left out). `--reference` is the director's own cut. `--previous` is the last release's scorecard for the same film, and `--out` keeps this one.

## The scorecard

`measures` holds the numbers that are compared between releases:

| Measure | What it is | Better |
|---|---|---|
| `lengthOffSeconds` | How far outside the brief's length the cut is | lower |
| `mustKeepNotHeard` | The brief's must-keep lines not found in the words the cut plays | lower |
| `notesNotDone` | Notes in the turnover that made this cut that aren't done | lower |
| `soundOffTarget` | 1 when the mix misses the loudness target or the ceiling | lower |
| `framingProblems` | What the framing check finds: faces lost or cut by a crop, words where a phone's buttons go, words over a face | lower |
| `jumpCuts`, `cutsInsideWords`, `moreCutProblems` | What the cut check finds: the story jumping between two moments of a take or takes framed alike, and sound starting or stopping inside a word (`moreCutProblems`: past the check's list) | lower |
| `cutPointPrecision`, `cutPointRecall` | The editor's cut points within 3 frames of the director's, and the director's within 3 frames of the editor's | higher |
| `sameMaterial` | Share of the cut that plays the same moments of the same takes as the director's | higher |
| `runSeconds`, `toolCalls`, `tokens`, `spend` | What the run cost | lower; flagged when a quarter more |

The scorecard also shows the pace (shot lengths, overall and by quarter of the cut), each must-keep line, the turnover's notes, and the checks in full. With `--previous`, `worse` lists each measure that got worse, in words: "jumpCuts went from 1 to 3".

Must-keep lines are matched by their words in the transcript, ignoring case and punctuation. A must-keep that describes a shot, rather than quoting a line, never matches and should be checked by eye.

## Before a release

Score every bench film and read each `worse` list. A worse measure is either explained in the release notes (a deliberate trade, such as more spend for fewer jump cuts) or fixed before release.

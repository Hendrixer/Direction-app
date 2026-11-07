#!/usr/bin/env python3
"""Optional on-device speech acceptance test. First use may download Apple's model."""
import json
from pathlib import Path
import subprocess
import sys
import uuid

binary = Path(sys.argv[1]).resolve()
artifacts = Path(sys.argv[2]).resolve()
run = artifacts / ("speech-" + uuid.uuid4().hex[:8])
run.mkdir(parents=True)
source = run / "spoken-review.aiff"
project = run / "Speech.direction"
phrase = "Welcome to Direction. This is a local video editing test. Keep the opening sentence and remove this sentence. The director reviews the footage and leaves a comment."
subprocess.run(["/usr/bin/say", "-o", str(source), phrase], check=True)


def cli(*args):
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True, text=True, timeout=600)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


cli("create", project, "--name", "On-device speech verification")
asset = cli("import", source, "--project", project, "--append")["asset"]
recognition = cli("transcribe", asset["id"], "--project", project)
transcript = cli("transcript", "--project", project)
text = " ".join(word["text"] for word in transcript["words"])
assert recognition["provider"] == "apple-speech-analyzer"
assert len(transcript["words"]) >= 20, text
assert all(word in text.lower() for word in ["direction", "editing", "director", "comment"]), text
assert all(word["end"] > word["start"] for word in transcript["words"])
before = cli("inspect", "--project", project)
target = next(word for word in transcript["words"] if word["text"].strip(".,").lower() == "remove")
deleted = cli("call", "direction_edit", "--project", project, "--json", json.dumps({"baseEditRevision": before["project"]["editRevision"], "operations": [{"op": "removeWords", "wordIDs": [target["id"]]}]}))
after = cli("inspect", "--project", project)
duration = target["end"] - target["start"]
assert abs(before["durationSeconds"] - after["durationSeconds"] - duration) < .021
report = {"passed": True, "project": str(project), "source": str(source), "provider": recognition["provider"], "wordCount": len(transcript["words"]), "recognizedText": text, "deletedWord": target, "beforeSeconds": before["durationSeconds"], "afterSeconds": after["durationSeconds"]}
(artifacts / "speech-report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: on-device transcription returned {len(transcript['words'])} timed words; deleting one cut its exact duration.")

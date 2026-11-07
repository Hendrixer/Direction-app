#!/usr/bin/env python3
"""Exercise the shipped CLI, line API, and real MCP stdio transport with native media."""
import base64
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import uuid

binary, fixture, artifacts = map(lambda p: Path(p).resolve(), sys.argv[1:4])
run = artifacts / ("smoke-" + uuid.uuid4().hex[:8])
run.mkdir(parents=True)
project = run / "Smoke.direction"
checks = []


def check(condition, name):
    if not condition:
        raise AssertionError(name)
    checks.append(name)


def cli(*args):
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr}")
    return json.loads(result.stdout)


def call(name, params=None, target=project):
    return cli("call", name, "--project", target, "--json", json.dumps(params or {}))


def sec(value):
    return value["value"] / value["timescale"]


def mt(value):
    return {"value": round(value * 600_000), "timescale": 600_000}


class MCP:
    def __init__(self, *extra):
        self.extra = [str(a) for a in extra]

    def __enter__(self):
        self.log = (run / "mcp-stderr.log").open("ab")
        self.process = subprocess.Popen([str(binary), "mcp", "--project", str(project), *self.extra], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log)
        self.buffer = b""
        self.counter = 0
        return self

    def send(self, message):
        self.process.stdin.write(json.dumps(message).encode() + b"\n")
        self.process.stdin.flush()

    def request(self, method, params):
        self.counter += 1
        self.send({"jsonrpc": "2.0", "id": self.counter, "method": method, "params": params})
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                response = json.loads(line)
                if response.get("id") == self.counter:
                    if "error" in response:
                        raise RuntimeError(response["error"])
                    return response["result"]
            if select.select([self.process.stdout], [], [], min(1, max(0, deadline - time.monotonic())))[0]:
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    raise RuntimeError("MCP exited before responding")
                self.buffer += data
        raise TimeoutError(method)

    def tool(self, name, arguments=None):
        return self.request("tools/call", {"name": name, "arguments": arguments or {}})

    def all_at_once(self, calls):
        """Sends every tool call before reading any reply, as an editor running calls in parallel does.
        Returns the replies by id, or raises if a line isn't JSON (two replies written into each other)."""
        ids = []
        for name, arguments in calls:
            self.counter += 1
            ids.append(self.counter)
            self.send({"jsonrpc": "2.0", "id": self.counter, "method": "tools/call", "params": {"name": name, "arguments": arguments}})
        replies, deadline = {}, time.monotonic() + 90
        while len(replies) < len(ids) and time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                response = json.loads(line)
                if response.get("id") in ids:
                    replies[response["id"]] = response
            if len(replies) < len(ids) and select.select([self.process.stdout], [], [], 1)[0]:
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    raise RuntimeError("MCP exited before responding")
                self.buffer += data
        return replies

    def __exit__(self, *args):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)
        self.log.close()


cli("create", project, "--name", "Direction tool verification")
import_args = {"path": str(fixture), "append": True, "baseEditRevision": 0, "idempotencyKey": "source-import"}
imported = call("direction_import", import_args)
asset = imported["asset"]
check(len(asset["audio"]) == 2, "CLI imports two independent embedded audio streams")
retry = call("direction_import", import_args)
check(retry == imported, "Repeated import key preserves asset ID and revision")

transcript = {"assetID": asset["id"], "audioTrackID": asset["audio"][0]["id"], "language": "en-US", "provider": "deterministic-test-fixture", "words": []}
for i, text in enumerate(["Keep", "this", "short", "clear"]):
    transcript["words"].append({"id": f"w{i}", "text": text, "range": {"start": mt(.1 + i * .5), "duration": mt(.4)}})
call("direction_import_transcript", {"transcript": transcript})
comment = cli("comment", "--project", project, "--text", "Make this section tighter; preserve the first audio track.", "--start", 1, "--end", 2)
cut = call("direction_create_cut", {"name": "Before revision"})
check(comment["editRevision"] == 1 and bool(comment["transcriptContext"]), "Comment captures original revision and transcript")

cli("cut", "--project", project, "--start", 0, "--end", .5, "--base-revision", 1)
cli("audio", asset["id"], "--project", project, "--track", asset["audio"][1]["id"], "--muted", "true")
current = cli("inspect", "--project", project)
check(current["project"]["assets"][0]["audio"][1]["settings"]["muted"] and not current["project"]["assets"][0]["audio"][0]["settings"]["muted"], "Muting the second stream leaves the first enabled")
words = cli("transcript", "--project", project)["words"]
word = next(w for w in words if w["text"] == "short")
call("direction_edit", {"baseEditRevision": 3, "operations": [{"op": "removeWords", "wordIDs": [word["id"]]}]})
current = cli("inspect", "--project", project)
check(abs(current["durationSeconds"] - 2.1) < .001, "Text deletion ripple-cuts matching footage")
clip = current["sequence"]["clips"][0]
grade = dict(clip["grade"], exposure=.3, saturation=.7)
call("direction_edit", {"batch": {"baseEditRevision": 4, "idempotencyKey": "portrait-grade", "summary": "Portrait and color", "operations": [{"type": "format", "width": 180, "height": 320}, {"type": "color", "clipID": clip["id"], "grade": grade}]}})

context = cli("feedback", "--project", project, "--context", comment["id"])
check(context["comment"]["editRevision"] == 1 and context["currentEditRevision"] == 5, "Feedback retains original cut while reporting the new revision")
check(bool(context["frames"]) and Path(context["audioSample"]["path"]).is_file(), "Feedback produces real original PNG frames and mixed audio")
output = cli("export", run / "portrait.mp4", "--project", project)
check(output["editRevision"] == 5, "Export records the pinned revision")
probe_project = run / "Probe.direction"
cli("create", probe_project)
probe = cli("import", run / "portrait.mp4", "--project", probe_project)["asset"]
check((probe["video"][0]["width"], probe["video"][0]["height"]) == (180, 320) and abs(sec(probe["duration"]) - 2.1) < .04, "Native exported file has the edited duration and portrait dimensions")

api_requests = [{"id": "inspect", "method": "direction_inspect"}, {"id": "feedback", "method": "direction_feedback"}, {"id": "invalid", "method": "missing_tool"}]
api = subprocess.run([str(binary), "api", "--project", str(project)], input="".join(json.dumps(r) + "\n" for r in api_requests), text=True, capture_output=True, timeout=30)
responses = [json.loads(line) for line in api.stdout.splitlines()]
check(api.returncode == 0 and [r["id"] for r in responses] == [r["id"] for r in api_requests], "Local JSON API preserves request IDs")
check(responses[1]["result"]["comments"][0]["id"] == comment["id"] and responses[2]["error"]["code"] == "unknown_tool", "Local JSON API returns feedback and structured errors")

with MCP() as mcp:
    initialized = mcp.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "Direction verification", "version": "1"}})
    mcp.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    check(initialized["serverInfo"]["name"] == "Direction", "Official MCP initialization succeeds")
    listing = mcp.request("tools/list", {})
    check(len(listing["tools"]) >= 25, "MCP exposes the shared tool catalog")
    # An editor sends calls in parallel; each reply here is bigger than the pipe holds at once.
    try:
        together = mcp.all_at_once([("direction_capabilities", {})] * 6)
    except json.JSONDecodeError:
        together = {}
    check(len(together) == 6 and all(not r["result"].get("isError") for r in together.values()), "MCP answers calls sent all at once, each reply whole")
    response = mcp.tool("direction_feedback_context", {"commentID": comment["id"]})
    check(not response.get("isError"), "MCP reads contextual feedback")
    images = [base64.b64decode(c["data"]) for c in response["content"] if c["type"] == "image"]
    audio = [base64.b64decode(c["data"]) for c in response["content"] if c["type"] == "audio"]
    check(bool(images) and all(data.startswith(b"\x89PNG\r\n\x1a\n") for data in images), "MCP returns valid inline PNG pixels to multimodal agents")
    check(bool(audio) and audio[0][:4] == b"RIFF" and audio[0][8:12] == b"WAVE", "MCP returns valid inline WAV audio")
    stale = mcp.tool("direction_edit", {"baseEditRevision": 1, "operations": [{"op": "removeRange", "range": {"start": 0, "end": .1}}]})
    check(stale["isError"] and json.loads(stale["content"][0]["text"])["code"] == "stale_revision", "MCP rejects stale edits without mutation")
    invalid = mcp.tool("direction_edit", {"baseEditRevision": 5, "operations": [{"op": "audio", "assetID": asset["id"], "audioTrackID": asset["audio"][0]["id"], "audio": {"muted": "true"}}]})
    check(invalid["isError"] and json.loads(invalid["content"][0]["text"])["code"] == "invalid_arguments", "MCP rejects mistyped mute flags before writing")
    after_invalid = json.loads(mcp.tool("direction_inspect")["content"][0]["text"])
    check(after_invalid["project"]["editRevision"] == 5, "Invalid tool arguments leave the project revision unchanged")
    job_response = mcp.tool("direction_preview", {"start": 0, "end": 1})
    job = json.loads(job_response["content"][0]["text"])
    deadline = time.monotonic() + 60
    while job["status"] == "running" and time.monotonic() < deadline:
        time.sleep(.1)
        job = json.loads(mcp.tool("direction_job", {"jobID": job["id"]})["content"][0]["text"])
    check(job["status"] == "completed" and Path(job["result"]["path"]).is_file(), "MCP preview job renders and can be polled to completion")

# Started for one job, the server lists that job's tools and direction_more_tools, which runs the rest.
with MCP("--job", "script") as mcp:
    mcp.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "Direction verification", "version": "1"}})
    mcp.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    names = [t["name"] for t in mcp.request("tools/list", {})["tools"]]
    check("direction_script" in names and "direction_more_tools" in names and "direction_inspect" not in names and len(names) < len(listing["tools"]) / 3, "A job's tool list has its own tools and direction_more_tools")
    others = json.loads(mcp.tool("direction_more_tools")["content"][0]["text"])
    check(any(t["name"] == "direction_inspect" for t in others["tools"]), "direction_more_tools lists the tools the job wasn't given")
    inspected = mcp.tool("direction_more_tools", {"name": "direction_inspect", "arguments": {}})
    check(not inspected.get("isError") and json.loads(inspected["content"][0]["text"])["project"]["editRevision"] >= 1, "direction_more_tools runs a tool the job wasn't given")

report = {"passed": len(checks), "checks": checks, "project": str(project), "export": str(run / "portrait.mp4"), "mcpProtocol": initialized["protocolVersion"]}
(artifacts / "smoke-report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: {len(checks)} CLI / JSON API / MCP checks. Report: {artifacts / 'smoke-report.json'}")

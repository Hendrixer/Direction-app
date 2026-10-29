#!/usr/bin/env python3
"""Direction's vision helper (design/spec/specs/footage-index.md, Engines for descriptions).

Loads one mlx-vlm version once, then answers JSON lines on stdin/stdout:

    {"id": 1, "images": ["/path/a.jpg", ...], "prompt": "...", "max_tokens": 160}
    -> {"id": 1, "text": "..."}            or {"id": 1, "error": "..."}

The first line written is {"ready": true, "model": "..."} once the weights are loaded (they
download to the Hugging Face cache on first use), or {"ready": false, "error": "..."}.
{"quit": true} or end of input stops it. Decoding is greedy (temperature 0).

Run with the Python from `uv tool install mlx-vlm`.
"""
import argparse
import json
import os
import sys
import traceback


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--max-tokens", type=int, default=160)
    args = parser.parse_args()

    # Libraries print progress and warnings to stdout; keep stdout for the protocol only.
    protocol = os.fdopen(os.dup(1), "w", buffering=1)
    os.dup2(2, 1)
    sys.stdout = sys.stderr

    def reply(obj):
        protocol.write(json.dumps(obj, ensure_ascii=False) + "\n")
        protocol.flush()

    try:
        from mlx_vlm import load, generate
        from mlx_vlm.prompt_utils import apply_chat_template

        model, processor = load(args.model)
        config = getattr(model, "config", None)
    except Exception as error:  # noqa: BLE001 - the app shows the reason
        reply({"ready": False, "error": f"{type(error).__name__}: {error}"})
        return 1

    reply({"ready": True, "model": args.model})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as error:
            reply({"error": f"bad request: {error}"})
            continue
        if request.get("quit"):
            break
        rid = request.get("id")
        try:
            images = [str(p) for p in request.get("images", [])]
            prompt = apply_chat_template(processor, config, request["prompt"], num_images=len(images))
            result = generate(
                model,
                processor,
                prompt,
                image=images or None,
                max_tokens=int(request.get("max_tokens", args.max_tokens)),
                temperature=0.0,
                verbose=False,
            )
            text = getattr(result, "text", result)
            reply({"id": rid, "text": str(text).strip()})
        except Exception as error:  # noqa: BLE001
            traceback.print_exc(file=sys.stderr)
            reply({"id": rid, "error": f"{type(error).__name__}: {error}"})
    return 0


if __name__ == "__main__":
    sys.exit(main())

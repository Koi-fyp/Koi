"""Contract checker for three authenticated chat SSE turns."""
import argparse
import json
import os
import sys
import urllib.request

ENUM = {"neutral", "joy", "angry", "sorrow", "fun"}
PROMPTS = ("hello", "can we do a breathing exercise", "I feel unsafe and overwhelmed")


def frames(response):
    event = None
    data = []
    for raw in response:
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if not line:
            if event is not None:
                yield event, json.loads("\n".join(data))
            event, data = None, []
        elif line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data.append(line[5:].lstrip())


def check_turn(base, token, message):
    req = urllib.request.Request(
        base.rstrip("/") + "/api/v1/chat",
        data=json.dumps({"message": message, "session_history": []}).encode(),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as response:
        events = list(frames(response))
    names = [name for name, _ in events]
    if "companion_state" not in names or "delta" not in names or "done" not in names:
        raise AssertionError("missing required SSE event")
    first_delta = names.index("delta")
    if names.index("companion_state") > first_delta:
        raise AssertionError("companion_state follows first delta")
    if any("KOI_DEBUG_TRACE" in json.dumps(payload) or "system-prompt" in json.dumps(payload).lower()
           for _, payload in events):
        raise AssertionError("debug or system prompt text leaked")
    state = next(payload for name, payload in events if name == "companion_state")
    if state.get("emotion") not in ENUM:
        raise AssertionError("emotion outside contract enum")
    deltas = "".join(payload.get("text", "") for name, payload in events if name == "delta")
    done = next(payload for name, payload in events if name == "done")
    if done.get("full_text") != deltas:
        raise AssertionError("done.full_text mismatch")
    if done.get("companion_state") != state:
        raise AssertionError("done.companion_state mismatch")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base")
    parser.add_argument("--token-file")
    args = parser.parse_args()
    token = os.environ.get("KOI_TOKEN", "")
    if args.token_file:
        with open(args.token_file, encoding="utf-8") as handle:
            token = handle.read().strip()
    if not token:
        print("KOI_TOKEN or --token-file is required", file=sys.stderr)
        return 2
    for prompt in PROMPTS:
        check_turn(args.base, token, prompt)
    print("trace contract passed: 3 turns")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

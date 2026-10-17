"""Contract checker for authenticated chat SSE turns (run after the FINAL, trace-OFF deploy).

Prints one `RESULT <check> PASS|FAIL` line per check and exits 1 on any FAIL:
  trace_absent       no `trace` key in any `done` or `state` payload, no debug/system-prompt text
  greeting_delta     "hey, what's up?" yields >= 1 non-empty delta
  spacing_full_text  exercise turn: >= 2 deltas, each after the first starts with a space; done.full_text == "".join(deltas)
  risk_present       every turn has a `risk` event and done.risk equals it
plus the earlier per-turn contract checks (reported as `contract`). Never prints the token.
"""
import argparse
import json
import os
import sys
import urllib.request as _ur
_ur.HTTPRedirectHandler.max_repeats = 200      # Modal answers slow (cold-start) requests with HTTP 303 poll redirects
_ur.HTTPRedirectHandler.max_redirections = 200  # to the SAME url; urllib's default limit (4 repeats) gives up too early
import urllib.request

ENUM = {"neutral", "joy", "angry", "sorrow", "fun"}
PROMPTS = ("hello", "can we do a breathing exercise", "I feel unsafe and overwhelmed")
GREETING = {"message": "hey, what's up?"}
EXERCISE = {"message": "can we do a breathing exercise", "client_event": "start_breathing"}
TIMEOUT_S = 240


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


def post_turn(base, token, body):
    req = urllib.request.Request(
        base.rstrip("/") + "/api/v1/chat",
        data=json.dumps({"session_history": [], **body}).encode(),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as response:
        return list(frames(response))


def check_turn(events):
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
    risk_events = [payload for name, payload in events if name == "risk"]
    if not risk_events:
        raise AssertionError("missing risk event")
    if done.get("risk") != risk_events[-1]:
        raise AssertionError("done.risk mismatch")
    if "transcript" in names and names.index("transcript") > names.index("companion_state"):
        raise AssertionError("transcript follows companion_state")
    if done.get("full_text") != deltas:
        raise AssertionError("done.full_text mismatch")
    if done.get("companion_state") != state:
        raise AssertionError("done.companion_state mismatch")


def trace_problems(events):
    return ["`trace` key in %s" % name for name, payload in events
            if name in ("done", "state") and isinstance(payload, dict) and "trace" in payload]


def risk_problems(events):
    risks = [payload for name, payload in events if name == "risk"]
    done = next((payload for name, payload in events if name == "done"), {})
    if not risks:
        return ["no risk event"]
    if "risk" not in done:
        return ["done has no risk"]
    return [] if done["risk"] == risks[-1] else ["done.risk differs from streamed risk"]


def spacing_problems(events):
    deltas = [payload.get("text", "") for name, payload in events if name == "delta"]
    done = next((payload for name, payload in events if name == "done"), {})
    problems = []
    if len(deltas) < 2:
        problems.append("exercise turn gave %d delta(s); expected >= 2 sentences (did the exercise start?)" % len(deltas))
    for i in range(1, len(deltas)):
        if not (deltas[i][:1].isspace() or deltas[i - 1][-1:].isspace()):
            problems.append("delta %d has no leading space" % i)
    if done.get("full_text") != "".join(deltas):
        problems.append("done.full_text != joined deltas")
    return problems


def run(base, token):
    results = {name: [] for name in ("trace_absent", "greeting_delta", "spacing_full_text", "risk_present", "contract")}
    turns = [("greeting", GREETING), ("exercise", EXERCISE)] + [(p, {"message": p}) for p in PROMPTS]
    for label, body in turns:
        try:
            events = post_turn(base, token, body)
        except Exception as exc:  # HTTP error, timeout, bad SSE
            results["contract"].append("%s: %s" % (label, type(exc).__name__))
            if label == "greeting":
                results["greeting_delta"].append("request failed")
            if label == "exercise":
                results["spacing_full_text"].append("request failed")
            continue
        results["trace_absent"] += ["%s: %s" % (label, p) for p in trace_problems(events)]
        results["risk_present"] += ["%s: %s" % (label, p) for p in risk_problems(events)]
        try:
            check_turn(events)
        except (AssertionError, StopIteration) as exc:
            results["contract"].append("%s: %s" % (label, exc))
        if label == "greeting" and not any(
                name == "delta" and (payload.get("text") or "").strip() for name, payload in events):
            results["greeting_delta"].append("no non-empty delta")
        if label == "exercise":
            results["spacing_full_text"] += spacing_problems(events)
    for name, problems in results.items():
        print("RESULT %-17s %s%s" % (name, "FAIL" if problems else "PASS", ("  " + "; ".join(problems)) if problems else ""))
    return 1 if any(results.values()) else 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("base")
    parser.add_argument("--token-file")
    args = parser.parse_args(argv)
    token = os.environ.get("KOI_TOKEN", "")
    if args.token_file:
        with open(args.token_file, encoding="utf-8") as handle:
            token = handle.read().strip()
    if not token:
        print("KOI_TOKEN or --token-file is required", file=sys.stderr)
        return 2
    return run(args.base, token)


if __name__ == "__main__":
    raise SystemExit(main())

"""Minimal deployed-service contract smoke test."""
import os
import sys
import json

import requests


def main() -> int:
    base = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else os.environ.get("BASE_URL", "").rstrip("/")
    token = os.environ.get("KOI_TOKEN")
    if not base or not token:
        print("BASE_URL and KOI_TOKEN are required", file=sys.stderr)
        return 2
    headers = {"Authorization": f"Bearer {token}"}
    if requests.get(base + "/health", headers=headers, timeout=30).status_code != 200:
        return 1
    payload = {"message": "hello"}
    exercise_state = None
    for event_payload in (payload, {"message": "can we breathe?", "client_event": "start_breathing",
                                    "risk": {"risk_category": "LOW", "crisis_score": 0.1,
                                             "trigger_flags": [], "is_new": True}},
                          {"message": "done", "client_event": "playback_done"},
                          {"message": "check"}):
        if exercise_state:
            event_payload["exercise_state"] = exercise_state
        response = requests.post(base + "/api/v1/chat", headers={**headers, "Content-Type": "application/json"},
                                 json=event_payload, stream=True, timeout=180)
        if response.status_code != 200:
            print(response.text)
            return 1
        frame = []
        parsed = []
        for line in response.iter_lines(decode_unicode=True):
            if line:
                print(line)
                frame.append(line)
            elif frame:
                events = [x[7:] for x in frame if x.startswith("event: ")]
                data_lines = [x[6:] for x in frame if x.startswith("data: ")]
                if len(events) != 1 or len(data_lines) != 1:
                    print("invalid SSE frame: expected one event and one data line", file=sys.stderr)
                    return 1
                parsed.append((events[0], json.loads(data_lines[0])))
                frame = []
        if frame:
            print("unterminated SSE frame", file=sys.stderr)
            return 1
        deltas = [data["text"] for event, data in parsed if event == "delta"]
        done = next((data for event, data in parsed if event == "done"), None)
        states = [data for event, data in parsed if event == "companion_state"]
        risks = [data for event, data in parsed if event == "risk"]
        if not deltas or done is None or not risks:
            print("turn has no delta or done event", file=sys.stderr)
            return 1
        if done.get("risk") != risks[-1]:
            print("done.risk differs from streamed risk", file=sys.stderr)
            return 1
        if done.get("full_text") != "".join(deltas):
            print("done.full_text does not equal joined deltas", file=sys.stderr)
            return 1
        if states and done.get("companion_state") != states[-1]:
            print("done.companion_state differs from streamed state", file=sys.stderr)
            return 1
        for event, data in parsed:
            if event in {"companion_state", "done"}:
                state = data if event == "companion_state" else data.get("companion_state", {})
                if not 0 <= state.get("intensity", -1) <= 1:
                    print("intensity outside 0..1", file=sys.stderr)
                    return 1
            if event == "state":
                exercise_state = data["exercise_state"]
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

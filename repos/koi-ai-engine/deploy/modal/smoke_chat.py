"""Minimal deployed-service contract smoke test."""
import os
import sys

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
        for line in response.iter_lines(decode_unicode=True):
            if line:
                print(line)
                if "ack" in line:
                    print(line)
                frame.append(line)
            elif frame:
                data = next((x[6:] for x in frame if x.startswith("data: ")), None)
                if data and any(x.startswith("event: state") for x in frame):
                    exercise_state = __import__("json").loads(data)["exercise_state"]
                frame = []
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

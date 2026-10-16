"""Emotion/intensity sanity probe for the deployed chat service (stdlib only).

Usage:
    set KOI_TOKEN=<firebase id token>        (see get_anon_token.py)
    python emotion_probe.py <CHAT_BASE_URL>

Sends 10 short single-turn prompts (English, Roman Urdu, Urdu script), reads the SSE stream, and prints
what the model actually returned in `companion_state`, plus contract checks:
  - companion_state arrives BEFORE the first delta
  - emotion is one of the 5 canon strings, intensity is a number in 0..1
  - no JSON syntax leaks into delta text
It is a rough sanity check of the LoRA's emotion output, NOT an evaluation: `expected` is my guess of
what is reasonable, ten prompts prove nothing statistically. Look for: always-the-same emotion,
out-of-enum values, intensity stuck at one number.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request as _ur
_ur.HTTPRedirectHandler.max_repeats = 200      # Modal answers slow (cold-start) requests with HTTP 303 poll redirects
_ur.HTTPRedirectHandler.max_redirections = 200  # to the SAME url; urllib's default limit (4 repeats) gives up too early
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ENUM = {"neutral", "joy", "angry", "sorrow", "fun"}

PROMPTS = [
    ("en", "I just got the job offer I've been waiting for!!", {"joy", "fun"}),
    ("en", "My dog died this morning and I can't stop crying.", {"sorrow"}),
    ("en", "My roommate keeps eating my food and I'm so angry about it.", {"angry"}),
    ("en", "hey, what's up?", {"neutral", "fun", "joy"}),
    ("en", "Can you tell me a joke?", {"fun", "joy"}),
    ("en", "What time do libraries usually open?", {"neutral"}),
    ("en", "Thank you, that really helped me.", {"joy", "neutral"}),
    ("ur-roman", "Aaj mera exam bohat acha gaya, main bohat khush hoon!", {"joy", "fun"}),
    ("ur-roman", "Mujhe bohat akela mehsoos ho raha hai.", {"sorrow"}),
    ("ur", "مجھے بہت غصہ آ رہا ہے، کسی نے میرا فون توڑ دیا۔", {"angry"}),
]


def sse_frames(resp):
    ev, data, event_count = None, [], 0
    for raw in resp:
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if line == "":
            if ev is not None or data:
                yield ev, "\n".join(data), event_count, len(data)
            ev, data, event_count = None, [], 0
        elif line.startswith("event:"):
            ev = line[6:].strip()
            event_count += 1
        elif line.startswith("data:"):
            data.append(line[5:].lstrip(" "))
    if ev is not None or data:
        yield ev, "\n".join(data), event_count, len(data)


def ask(base, token, message, attempt=1):
    body = json.dumps({"message": message, "session_history": []}).encode()
    req = urllib.request.Request(
        base.rstrip("/") + "/api/v1/chat",
        data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + token},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=170) as resp:
            events = []
            for ev, data, event_count, data_count in sse_frames(resp):
                try:
                    payload = json.loads(data) if data else None
                except ValueError:
                    payload = {"_unparseable": data[:80]}
                events.append((ev, payload, event_count, data_count))
        return events, time.time() - t0, None
    except urllib.error.HTTPError as e:
        return [], time.time() - t0, "HTTP %d %s" % (e.code, e.read().decode("utf-8", "replace")[:200])
    except Exception as e:  # cold start / timeout: retry once
        if attempt == 1:
            print("  (request failed: %s -- retrying once, cold start?)" % e)
            return ask(base, token, message, 2)
        return [], time.time() - t0, str(e)


def main(argv):
    token = os.environ.get("KOI_TOKEN", "")
    if not argv or not token:
        print(__doc__)
        return 2
    base = argv[0]
    rows, problems = [], []
    for lang, text, expected in PROMPTS:
        events, secs, err = ask(base, token, text)
        if err:
            problems.append("%s: %s" % (text[:30], err))
            rows.append((lang, None, None, expected, secs, err, ""))
            continue
        names = [e for e, _, _, _ in events]
        if any(ec != 1 or dc != 1 for _, _, ec, dc in events):
            problems.append("%s: event has multiple event/data lines" % text[:30])
        cs = next((p for e, p, _, _ in events if e == "companion_state"), None)
        if cs is None:
            cs = next((p.get("companion_state") for e, p, _, _ in events if e == "done" and p), None)
            problems.append("%s: no companion_state event" % text[:30])
        first_delta = names.index("delta") if "delta" in names else None
        cs_idx = names.index("companion_state") if "companion_state" in names else None
        if first_delta is not None and (cs_idx is None or cs_idx > first_delta):
            problems.append("%s: companion_state NOT before first delta" % text[:30])
        deltas = "".join(p.get("text", "") for e, p, _, _ in events if e == "delta" and p)
        done = next((p for e, p, _, _ in events if e == "done" and p), None)
        risks = [p for e, p, _, _ in events if e == "risk" and p]
        if not risks:
            problems.append("%s: no risk event" % text[:30])
        elif done and done.get("risk") != risks[-1]:
            problems.append("%s: done.risk differs from streamed risk" % text[:30])
        if "transcript" in names and names.index("transcript") > (cs_idx if cs_idx is not None else len(names)):
            problems.append("%s: transcript follows companion_state" % text[:30])
        if not deltas:
            problems.append("%s: no delta event" % text[:30])
        if done and done.get("full_text") != deltas:
            problems.append("%s: done.full_text differs from joined deltas" % text[:30])
        if done and done.get("companion_state") != cs:
            problems.append("%s: done.companion_state differs from streamed state" % text[:30])
        if "{" in deltas or '"reply"' in deltas:
            problems.append("%s: JSON syntax leaked into delta text" % text[:30])
        emo = (cs or {}).get("emotion")
        inten = (cs or {}).get("intensity")
        if emo not in ENUM:
            problems.append("%s: emotion %r not in enum" % (text[:30], emo))
        if not isinstance(inten, (int, float)) or not (0 <= inten <= 1):
            problems.append("%s: intensity %r not in 0..1" % (text[:30], inten))
        done_intensity = (done or {}).get("companion_state", {}).get("intensity")
        if not isinstance(done_intensity, (int, float)) or not (0 <= done_intensity <= 1):
            problems.append("%s: done intensity %r not in 0..1" % (text[:30], done_intensity))
        rows.append((lang, emo, inten, expected, secs, deltas.replace("\n", " ")[:70], done.get("full_text", "") if done else ""))

    print("%-9s %-8s %-9s %-6s %-14s %s" % ("lang", "emotion", "intensity", "match", "expected", "reply"))
    for lang, emo, inten, expected, secs, tail, full_text in rows:
        if emo is None and inten is None:
            print("%-9s ERROR %s" % (lang, tail))
            continue
        print("%-9s %-8s %-9s %-6s %-14s %s" % (lang, emo, inten, "yes" if emo in expected else "no", "/".join(sorted(expected)), full_text))

    seen = [r[1] for r in rows if r[1]]
    ints = [r[2] for r in rows if isinstance(r[2], (int, float))]
    matches = sum(1 for r in rows if r[1] in r[3])
    print()
    print("distinct emotions returned: %s" % sorted(set(seen)))
    if ints:
        print("intensity range: %.2f .. %.2f" % (min(ints), max(ints)))
    print("matched my guess: %d / %d  (rough sanity only)" % (matches, len(rows)))
    if len(set(seen)) <= 1 and len(seen) >= 5:
        problems.append("emotion never varies (%s) -- avatar will look static" % (seen[0] if seen else None))
    if ints and len(set(round(i, 2) for i in ints)) == 1 and len(ints) >= 5:
        problems.append("intensity never varies (%s)" % ints[0])
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print(" -", p)
        return 1
    print("\nno contract problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

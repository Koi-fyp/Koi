"""Side-by-side reply bench: live local chat service vs hosted LLMs through deploy/modal/reply_api.py.

Usage (Ahmad runs it; it was never run by the agent):
    python agent_tasks\\bench_replies.py --prompts FILE --target local --target gemini:<model> --target openai_compat:<model>
    python agent_tasks\\bench_replies.py --smoke gemini:<model>        (one tiny call; prints OK / HTTP class / exception class)
FILE: one conversation per line, turns separated by " || " (blank lines and lines starting with # are skipped).
Each target replays every conversation turn by turn, with ITS OWN previous replies as history (a failed turn is
dropped from that target's history).
Targets / credentials (env only; never printed):
    local                  live chat service at --chat-url or KOI_CHAT_URL; token from KOI_TOKEN
    gemini:<model>         KOI_GEMINI_API_KEY
    openai_compat:<model>  KOI_OAI_API_KEY and KOI_OAI_BASE_URL (+ optional KOI_LLM_REASONING_EFFORT, as the server)
API targets use the same SYSTEM_PROMPT and JSON schema as the chat server (imported from chat_core) and the same
16-turn history cap (reply_api.HISTORY_TURNS). Output: agent_tasks\\reports\\bench\\bench_<ts>.md. Exit 0 always.
Options:
    --system-prompt-file PATH  replaces chat_core.SYSTEM_PROMPT for API targets only (the local target always uses the
                               deployed server's prompt). The prompt in use and its length are printed, not its text.
    --out-prefix NAME          output file agent_tasks\\reports\\bench\\<NAME>_<ts>.md (default "bench")
Heuristic columns (rough string checks, not judgements): closed_q, flagged, asserts_feeling, starts_it_sounds_like,
two_questions ('?' or the Urdu question mark used more than once), repeats_user (4+ consecutive words of the user's
turn), invents_effort (effort phrases), event_only_evidence_q (user turn has no judgement words AND a question in the
reply asks about evidence).
"""
import argparse
import importlib.util
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODAL = ROOT / "deploy" / "modal"
OUT_DIR = ROOT / "agent_tasks" / "reports" / "bench"
CLOSED_Q = {"have", "do", "did", "are", "is", "can", "will", "would", "could", "were", "has", "should"}
FLAGGED = ("completely normal", "i'm sure", "you will do", "excellent job", "of course", "you've got this")
ASSERTS_FEELING = ("you're feeling", "you are feeling", "you feel", "sounds like you")
INVENTS_EFFORT = ("put in", "worked hard", "your effort", "you prepared", "you studied", "you've been working")
# Words that make a user turn a self/future JUDGEMENT rather than a plain event (English + Roman Urdu). Rough.
JUDGEMENT = ("stupid", "always", "never", "nobody", "no one", "everyone", "hate", "useless", "worthless", "failure",
             "loser", "not good enough", "annoying", "terrible", "pathetic", "better off without", "i'm just", "im just",
             "kisi kaam ka nahi", "bekaar", "nikamma", "nalaiq", "koi pasand nahi")
EVIDENCE_Q = ("evidence", "proof", "what makes you think", "what makes you believe", "what makes you say",
              "for and against", "how do you know", "what tells you")
_SENT = re.compile(r"[^.!?\u061f\u06d4]+[.!?\u061f\u06d4]*")
_WORDS = re.compile(r"[\w']+", re.UNICODE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_server_bits():
    """(SYSTEM_PROMPT, CHAT_JSON_SCHEMA, _clamp_state, reply_api) from the server code, without starting anything."""
    sys.path.insert(0, str(MODAL))
    try:
        import chat_core
        import reply_api
    except Exception as exc:  # e.g. fastapi missing in this interpreter
        print("cannot import chat_core/reply_api: %s (use the koivenv interpreter)" % type(exc).__name__)
        return None
    return chat_core.SYSTEM_PROMPT, chat_core.CHAT_JSON_SCHEMA, chat_core._clamp_state, reply_api


# ---------------------------------------------------------------------------------------------- metrics
def _norm(text):
    return (text or "").replace("\u2019", "'").lower()


def sentences(text):
    return len([s for s in _SENT.findall(text or "") if s.strip(" \n\"'")])


def closed_q(text):
    for s in _SENT.findall(text or ""):
        if s.rstrip().endswith(("?", "\u061f")):
            words = re.findall(r"[a-z']+", _norm(s))
            if words and words[0] in CLOSED_Q:
                return True
    return False


def has_any(text, phrases):
    t = _norm(text)
    return any(p in t for p in phrases)


def starts_it_sounds_like(text):
    return _norm(text).lstrip(" \"'*").startswith("it sounds like")


def two_questions(text):
    return (text or "").count("?") + (text or "").count("؟") > 1


def repeats_user(reply, user, n=4):
    """True when the reply contains n+ consecutive words of the user's turn (case-insensitive)."""
    u, r = _WORDS.findall(_norm(user)), _WORDS.findall(_norm(reply))
    grams = {tuple(u[i:i + n]) for i in range(len(u) - n + 1)}
    return bool(grams) and any(tuple(r[i:i + n]) in grams for i in range(len(r) - n + 1))


def event_only_evidence_q(reply, user):
    """The user only described an event (no judgement words) yet a question in the reply asks for evidence."""
    if has_any(user, JUDGEMENT):
        return False
    return any(s.rstrip().endswith(("?", "؟")) and has_any(s, EVIDENCE_Q) for s in _SENT.findall(reply or ""))


def load_prompt_file(path):
    """Plain-text system prompt; surrounding whitespace stripped. Returns None (and says why) if unusable."""
    try:
        text = Path(path).read_text(encoding="utf-8").strip()
    except OSError as exc:
        print("cannot read --system-prompt-file: %s" % type(exc).__name__)
        return None
    if not text:
        print("--system-prompt-file is empty")
        return None
    return text


# ---------------------------------------------------------------------------------------------- targets
class LocalTarget:
    def __init__(self, url):
        self.name, self.url = "local", url
        self.token = os.environ.get("KOI_TOKEN", "")
        self.tc = _load("trace_check", MODAL / "tools" / "trace_check.py")   # raises 303 limits; 240 s timeout

    def ready(self):
        if not self.url:
            return "no --chat-url / KOI_CHAT_URL"
        return None if self.token else "KOI_TOKEN not set"

    def reply(self, history, message):
        events = self.tc.post_turn(self.url, self.token, {"message": message, "session_history": history})
        done = next((p for n, p in events if n == "done"), None)
        if not isinstance(done, dict):
            raise RuntimeError("no done event")
        return (done.get("companion_state") or {}).get("emotion"), done.get("full_text") or ""


class ApiTarget:
    def __init__(self, provider, model, bits):
        self.name = "%s:%s" % (provider, model)
        self.system, self.schema, self.clamp, self.api = bits
        if provider == "gemini":
            env = {"KOI_LLM_PROVIDER": "gemini", "KOI_LLM_MODEL": model,
                   "KOI_LLM_API_KEY": os.environ.get("KOI_GEMINI_API_KEY", "")}
        else:
            env = {"KOI_LLM_PROVIDER": "openai_compat", "KOI_LLM_MODEL": model,
                   "KOI_LLM_API_KEY": os.environ.get("KOI_OAI_API_KEY", ""),
                   "KOI_LLM_BASE_URL": os.environ.get("KOI_OAI_BASE_URL", ""),
                   "KOI_LLM_REASONING_EFFORT": os.environ.get("KOI_LLM_REASONING_EFFORT", "")}
        self.cfg = self.api.config(env)

    def ready(self):
        return None if self.cfg else "provider not configured (model / key env / base URL)"

    def reply(self, history, message):
        state, text = self.api.generate(self.cfg, self.system, history, message, self.schema, self.clamp)
        return state.get("emotion"), text


def make_target(spec, chat_url, bits):
    if spec == "local":
        return LocalTarget(chat_url)
    provider, _, model = spec.partition(":")
    if provider in ("gemini", "openai_compat") and model and bits:
        return ApiTarget(provider, model, bits)
    return None


def failure_label(exc):
    reason = getattr(exc, "reason", None)
    if reason:
        return reason                                   # reply_api enum (http_4xx, blocked, ...)
    code = getattr(exc, "code", None)
    if isinstance(code, int):
        return "HTTP %dxx" % (code // 100)
    return type(exc).__name__


# ---------------------------------------------------------------------------------------------- run
def smoke(spec, chat_url, bits):
    target = make_target(spec, chat_url, bits)
    if target is None:
        print("unknown target")
        return
    problem = target.ready()
    if problem:
        print(problem)
        return
    try:
        target.reply([], "hi")
        print("OK")
    except Exception as exc:
        print(failure_label(exc))


def cell(text):
    return (text or "").replace("|", "\\|").replace("\r", " ").replace("\n", " ")


HEUR = (("closed_q", "closed_q"), ("flagged", "flagged"), ("asserts", "asserts_feeling"),
        ("sounds_like", "starts_it_sounds_like"), ("two_q", "two_questions"), ("repeats", "repeats_user"),
        ("effort", "invents_effort"), ("evid", "event_only_evidence_q"))


def bench(prompt_file, specs, chat_url, bits, out_prefix="bench", prompt_label="chat_core.SYSTEM_PROMPT"):
    convs = [[t.strip() for t in line.split(" || ") if t.strip()]
             for line in Path(prompt_file).read_text(encoding="utf-8").splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    targets = []
    for spec in specs:
        target = make_target(spec, chat_url, bits)
        problem = "unknown target" if target is None else target.ready()
        if problem:
            print("skipping %s: %s" % (spec, problem))
        else:
            targets.append(target)
    rows = []
    for ci, turns in enumerate(convs, 1):
        for target in targets:
            history = []
            for ti, user in enumerate(turns, 1):
                t0 = time.monotonic()
                try:
                    emotion, reply = target.reply(list(history), user)
                    failed = None
                except Exception as exc:
                    emotion, reply, failed = None, "", failure_label(exc)
                latency = round(time.monotonic() - t0, 2)
                if failed is None:
                    history += [{"role": "user", "content": user}, {"role": "assistant", "content": reply}]
                rows.append({"conv": ci, "turn": ti, "user": user, "target": target.name, "emotion": emotion,
                             "latency": latency, "reply": reply, "failed": failed,
                             "sentences": sentences(reply) if failed is None else None,
                             "closed_q": closed_q(reply), "flagged": has_any(reply, FLAGGED),
                             "asserts": has_any(reply, ASSERTS_FEELING),
                             "sounds_like": starts_it_sounds_like(reply), "two_q": two_questions(reply),
                             "repeats": repeats_user(reply, user), "effort": has_any(reply, INVENTS_EFFORT),
                             "evid": event_only_evidence_q(reply, user)})
                print("conv %d turn %d %-28s %s" % (ci, ti, target.name, failed or "ok"))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    safe_prefix = re.sub(r"[^A-Za-z0-9_.-]", "_", out_prefix or "bench")
    out = OUT_DIR / ("%s_%s.md" % (safe_prefix, datetime.now().strftime("%Y%m%d_%H%M%S")))
    heads = [h for _, h in HEUR]
    lines = ["# Reply bench %s" % datetime.now().isoformat(timespec="seconds"), "",
             "Prompts: `%s`. API-target system prompt: %s. Heuristic columns are rough string checks, not judgements. "
             "Score the blank columns 1-5 by hand." % (Path(prompt_file).name, prompt_label), "",
             "| conv# | turn | user | target | emotion | latency_s | reply | sentences | " + " | ".join(heads)
             + " | nonsycophantic | socratic | growth | safe |",
             "|" + "---|" * (8 + len(heads) + 4)]
    for r in rows:
        reply = r["reply"] if r["failed"] is None else "**FAILED: %s**" % r["failed"]
        flags = " | ".join("Y" if (r["failed"] is None and r[k]) else "" for k, _ in HEUR)
        lines.append("| %d | %d | %s | %s | %s | %s | %s | %s | %s |  |  |  |  |" % (
            r["conv"], r["turn"], cell(r["user"]), r["target"], r["emotion"] or "", r["latency"], cell(reply),
            "" if r["sentences"] is None else r["sentences"], flags))
    lines += ["", "## Per-target summary", "",
              "| target | turns | mean sentences | " + " | ".join("%% %s" % h for h in heads)
              + " | % failed/blocked | mean latency_s |",
              "|" + "---|" * (3 + len(heads) + 2)]
    for target in targets:
        mine = [r for r in rows if r["target"] == target.name]
        ok = [r for r in mine if r["failed"] is None]

        def pct(key):
            return "%.0f" % (100.0 * sum(r[key] for r in ok) / len(ok)) if ok else "-"
        lines.append("| %s | %d | %s | %s | %.0f | %s |" % (
            target.name, len(mine), "%.1f" % (sum(r["sentences"] for r in ok) / len(ok)) if ok else "-",
            " | ".join(pct(k) for k, _ in HEUR),
            100.0 * (len(mine) - len(ok)) / len(mine) if mine else 0,
            "%.2f" % (sum(r["latency"] for r in ok) / len(ok)) if ok else "-"))
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", out)


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("--prompts")
    p.add_argument("--target", action="append", default=[])
    p.add_argument("--smoke")
    p.add_argument("--chat-url", default=os.environ.get("KOI_CHAT_URL", ""))
    p.add_argument("--system-prompt-file")
    p.add_argument("--out-prefix", default="bench")
    args = p.parse_args(argv)
    specs = [args.smoke] if args.smoke else args.target
    bits = load_server_bits() if any(s != "local" for s in specs) else None
    label = "chat_core.SYSTEM_PROMPT"
    if bits and args.system_prompt_file:
        custom = load_prompt_file(args.system_prompt_file)
        if custom is None:
            return
        bits = (custom,) + tuple(bits[1:])
        label = "file %s" % Path(args.system_prompt_file).name
    elif args.system_prompt_file:
        print("--system-prompt-file ignored: no API target")
    if bits:
        print("system prompt for API targets: %s (%d chars)" % (label, len(bits[0])))
    if "local" in specs:
        print("local target: uses the deployed server's own prompt")
    if args.smoke:
        smoke(args.smoke, args.chat_url, bits)
    elif args.prompts and args.target:
        bench(args.prompts, args.target, args.chat_url, bits, args.out_prefix, label)
    else:
        p.print_help()


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except SystemExit:
        pass
    except Exception as exc:  # never a traceback that could echo request details
        print("bench error: %s" % type(exc).__name__)
    sys.exit(0)

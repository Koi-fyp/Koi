"""What the user would see (left) and what happens under the hood (right), for three scripted conversations.
The LLM is a STUB that writes canned acknowledgements, so this shows the logic and the reviewed lines, not how the
real fine-tuned model sounds.      python demo_conversation.py"""
import director as D
import state_token as T

SECRET = "demo"
STUB = {"en": ["That sounds like a lot to carry.", "Thanks for sharing that.", "Okay, noted."],
        "ur-roman": ["Samajh sakta hoon, yeh kaafi heavy hai.", "Achha, share karne ka shukriya.", "Theek hai."],
        "ur": ["میں سمجھ سکتا ہوں، یہ کافی بھاری ہے۔", "بتانے کا شکریہ۔", "ٹھیک ہے۔"]}
_n = [0]


def stub_llm(d):
    _n[0] += 1
    return {"emotion": "sorrow", "intensity": 0.4}, iter(w + " " for w in STUB[d["lang"]][_n[0] % 3].split(" "))


def run(title, turns):
    print("\n" + "=" * 100 + f"\n{title}\n" + "=" * 100)
    tok, now = D.new_token(SECRET), 1_000_000.0
    for text, ev, tier, score in turns:
        now += 20
        evs = D.handle_turn({"text": text, "client_event": ev, "tier": tier, "score": score, "now": now}, tok,
                            secret=SECRET, phrase_fn=stub_llm)
        tok = evs[-1]["token"]
        who = f"USER: {text}" if text else f"[app: {ev}]"
        print(f"\n{who}   (TSD tier {tier})")
        for e in evs:
            if e["type"] == "sentence":
                tag = {"generated": "LLM ack", "reviewed": "fixed line", "fallback": "fallback"}[e["source"]]
                print(f"   KOI: {e['text']:<95} <- {tag}")
            elif e["type"] == "ui_action":
                print(f"   {'':95}    [ui: {e['name']}]")
            elif e["type"] == "handoff":
                print(f"   {'(normal companion reply)':<100}<- handoff to {e['to']}: {e['reason']}")
            elif e["type"] == "companion_state":
                print(f"   {'':95}    [avatar: {e['emotion']} {e['intensity']}]")
        st = T.verify(tok, SECRET)
        print(f"   {'':95}    [mode {st['policy']['mode']}, step {(st['ex'] or {}).get('step')}]")


run("1. English: offer -> 'what is it?' -> breathing -> mood -> go-to", [
    ("Today was really heavy, I just feel tired of everything", "none", "MODERATE", 0.5),
    ("what is it?", "none", "LOW", None), ("ok let's try", "none", "LOW", None),
    (None, "playback_done", "LOW", None), ("a bit better actually", "none", "LOW", None), ("yes", "none", "LOW", None)])
run("2. Roman Urdu: decline -> Socratic why-not -> alternative -> grounding, then distress mid-exercise", [
    ("yaar aaj bohat heavy feel ho raha hai", "none", "MODERATE", 0.5), ("nahi yaar", "none", "LOW", None),
    ("mujhe pasand nahi ye sab", "none", "LOW", None), ("chalo theek hai", "none", "LOW", None),
    ("pata nahi, ajeeb sa", "none", "LOW", None), ("ab bardasht nahi hota", "none", "LOW", None)])
run("3. Urdu script: task planning with the 0-10 confidence rule", [
    ("کوئی پلان بنانا ہے", "none", "LOW", None), ("شام کو سیر", "none", "LOW", None),
    ("عصر کے بعد", "none", "LOW", None), ("پانچ", "none", "LOW", None), ("گلی کے کونے تک سیر", "none", "LOW", None),
    ("آٹھ", "none", "LOW", None)])

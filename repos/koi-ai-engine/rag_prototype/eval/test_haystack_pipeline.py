"""Regression: Haystack pipeline == CrisisRouter.respond (the plain pipeline) on every dev query, every tier,
three gate settings. Stand-in encoder. Run: python eval/test_haystack_pipeline.py"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import test_crisis_router as tcr  # noqa: E402  (stub sentence_transformers + its own checks)
import haystack_pipeline as hp  # noqa: E402
import retrieval_pipeline as rp  # noqa: E402

fails = []


def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c:
        fails.append(n)


check("haystack telemetry singleton not created", hp.telemetry_disabled())
chunks, store = rp.load_corpus(), rp.load_example_store()
enc = tcr.StubEncoder()
FB, HL = tcr.FB, tcr.HL
total = mism = 0
for gate in (rp.CRISIS_GATE, 0.0, 1.01):
    R = rp.CrisisRouter(chunks, store, enc, gate=gate)
    P = hp.build_crisis_pipeline(R, FB, HL)
    for r in store:
        for tier in ("HIGH", "HIGH_CRISIS", "CRITICAL", "LOW", "MODERATE"):
            total += 1
            if R.respond(r["query"], tier, FB, HL) != hp.run_crisis(P, r["query"], tier):
                mism += 1
check(f"identical intervention_content on {total} (query, tier, gate) cases", mism == 0 and total == 216 * 5 * 3)
R = rp.CrisisRouter(chunks, store, enc)
P = hp.build_crisis_pipeline(R, FB, HL)
try:
    hp.run_crisis(P, "x", "SEVERE"); ok = False
except ValueError:
    ok = True
check("unknown tier raises ValueError through the pipeline", ok)
Pb = hp.build_crisis_pipeline(rp.CrisisRouter(chunks, store, tcr.Boom(), gate=0.0), FB, HL)
check("retrieval exception -> fallback through the pipeline", hp.run_crisis(Pb, "boom", "HIGH")["source"] == "fallback")
check("explicit language is passed through", hp.run_crisis(P, "anything", "CRITICAL", language="mixed")["language"] == "mixed")

# telemetry guard: importing haystack first with telemetry ON must make haystack_pipeline refuse
code = ("import os,sys; os.environ['HAYSTACK_TELEMETRY_ENABLED']='True'; import haystack; "
        f"sys.path[:0]=[{str(HERE.parent / 'scripts')!r}, {str(HERE)!r}]; import test_crisis_router; "
        "import haystack_pipeline")
env = dict(os.environ, HAYSTACK_TELEMETRY_ENABLED="True")
r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env, cwd=str(HERE))
check("haystack imported earlier with telemetry ON -> haystack_pipeline refuses to load",
      r.returncode != 0 and "telemetry enabled" in r.stderr)

# egress audit (stub encoder) in a fresh process
r = subprocess.run([sys.executable, str(HERE / "egress_audit.py"), "--stub"], capture_output=True, text=True)
check("egress audit (stub): 0 network attempts, PASS", r.returncode == 0 and "attempts 0" in r.stdout and "PASS" in r.stdout)
print("   ", r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr[-300:])

code = (f"import sys; sys.path.insert(0, {str(HERE)!r}); import egress_audit as ea, socket\n"
        "try:\n    socket.create_connection(('huggingface.co', 443), timeout=2)\nexcept OSError: pass\n"
        "print(len(ea.ATTEMPTS))")
r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
check("egress guard is not vacuous: a deliberate connection is recorded and blocked", r.stdout.strip() == "1")

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)

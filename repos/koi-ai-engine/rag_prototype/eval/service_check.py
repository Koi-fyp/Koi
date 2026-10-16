"""
M3 check on the REAL encoder (Ahmad's machine). Dev data only; never reads the holdout or the rule-E lock.

    python eval/service_check.py

Reports:
  1. cold load time of CrisisContentService (model + corpus + example store, once);
  2. with the content checks ON (content_safety), on dev, leave-scenario-out at the 0.5709 gate:
       share of in-scope messages that get grounded content, Hit@3 among those, false accepts on negatives;
     compared with the same numbers with the checks OFF (the measured system);
  3. latency of svc.intervention_content() at HIGH over all 216 dev queries (p50 / p95 / max, ms).
Dev numbers are optimistic (the gate was chosen on this data).
"""
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "scripts"), str(HERE)]
encoder = None
if "--stub" in sys.argv:                               # plumbing only; numbers meaningless
    from test_crisis_router import StubEncoder         # installs a stand-in sentence_transformers module
    encoder = StubEncoder()
import crisis_service as svc_mod  # noqa: E402  (sets offline/telemetry env first)
import content_safety as cs  # noqa: E402

svc = svc_mod.CrisisContentService.load(encoder=encoder)
R = svc.router
print(f"cold load: {svc.load_seconds:.1f} s")

rows = R.loso_scores()
pos = [r for r in rows if not r["neg"]]
neg = [r for r in rows if r["neg"]]


def summary(filter_on):
    def items(r):
        return cs.filter_indices(r["served"], R.chunks) if filter_on else r["served"]
    shown = [r for r in pos if r["score"] >= R.gate and items(r)]
    hit3 = sum(any(i in r["gold"] for i in items(r)) for r in shown)
    fa = sum(r["score"] >= R.gate and bool(items(r)) for r in neg)
    return len(shown), hit3, fa


for name, on in (("checks OFF (measured system)", False), ("checks ON  (served)         ", True)):
    n, h, fa = summary(on)
    print(f"{name}: grounded {n}/{len(pos)} = {n / len(pos):.0%} of in-scope; Hit@3 among grounded "
          f"{h}/{max(n, 1)} = {h / max(n, 1):.0%}; false accepts {fa}/{len(neg)} = {fa / len(neg):.0%}")

lat = []
for r in R.store:
    t0 = time.perf_counter()
    svc.intervention_content(r["query"], "HIGH")
    lat.append((time.perf_counter() - t0) * 1000)
lat.sort()
print(f"latency at HIGH over {len(lat)} queries: p50 {statistics.median(lat):.0f} ms, "
      f"p95 {lat[int(0.95 * (len(lat) - 1))]:.0f} ms, max {lat[-1]:.0f} ms")

"""Tests for M2 (content_safety, fallback_bank) and M3 (crisis_service, FastAPI wiring). Stand-in encoder: these
check plumbing and safety rules, not retrieval quality.   Run: python eval/test_m2_m3.py"""
import asyncio
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "scripts"), str(HERE)]
from test_crisis_router import StubEncoder  # noqa: E402  (installs a stand-in sentence_transformers)
import crisis_service as svc_mod  # noqa: E402
import content_safety as cs  # noqa: E402
import fallback_bank as fb  # noqa: E402
import haystack_pipeline as hp  # noqa: E402
import retrieval_pipeline as rp  # noqa: E402

fails = []


def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c:
        fails.append(n)


chunks = rp.load_corpus()
pool = rp.crisis_pool(chunks)
pool_ids = {chunks[i]["chunk_id"] for i in pool}
store = rp.load_example_store()

# ---- M2: content_safety
check("audience table covers exactly the 22 pool passages", set(cs.AUDIENCE) == pool_ids)
check("unknown chunk id is never servable (fail-closed)", not cs.is_servable({"chunk_id": "x", "text": "hello"}))
check("veto catches dosing / diagnosis / method / foreign numbers",
      all(cs.veto_hits(t) for t in ("take 50 mg twice", "you have a disorder", "an overdose", "call 988",
                                    "Have you made any plans to end your life?")))
serv = [i for i in pool if cs.is_servable(chunks[i])]
check("every servable passage is user-facing and veto-clean",
      all(cs.AUDIENCE[chunks[i]["chunk_id"]][0] == cs.USER_FACING and not cs.veto_hits(chunks[i]["text"]) for i in serv))
check("every veto-hit passage is not servable", all(not cs.is_servable(chunks[i]) for i in pool if cs.veto_hits(chunks[i]["text"])))
check("filter keeps order and drops the rest",
      cs.filter_indices(list(pool), chunks) == [int(i) for i in pool if cs.is_servable(chunks[i])])
print(f"     (servable passages with the current table: {len(serv)} of {len(pool)})")

# ---- M2: fallback_bank
keys = {"text", "chunk_id", "source_corpus", "evidence_role", "review_status"}
ok = True
for lang in ("en", "ur", "ur-roman", "mixed"):
    items = fb.fallback(lang)
    ok &= 1 <= len(items) <= 3 and all(set(i) == keys and i["text"].strip() for i in items)
    ok &= all(i["review_status"] == "draft-unreviewed" and i["source_corpus"] == "deterministic" for i in items)
    joined = " ".join(i["text"] for i in items)
    ok &= all(n in joined for n in ("1122", "15", "115", "1166"))
    ok &= not any(cs.veto_hits(i["text"]) for i in items)
check("fallback: 4 languages, <=3 contract items, all numbers present, marked draft, veto-clean", bool(ok))
check("fallback: unknown language -> English, never empty", fb.fallback("xx")[0]["chunk_id"].startswith("fallback.en."))
check("fallback: 'mixed' carries English and Urdu script",
      all(rp.ARABIC_SCRIPT.search(i["text"]) and "you" in i["text"] for i in fb.fallback("mixed")))
check("helpline is the 1166 line", fb.HELPLINE["number"] == "1166")

# ---- M3: service
check("crisis_service sets offline + telemetry-off env before loading",
      os.environ.get("HF_HUB_OFFLINE") == "1" and os.environ.get("HAYSTACK_TELEMETRY_ENABLED") == "False")
enc = StubEncoder()
S = svc_mod.CrisisContentService.load(encoder=enc)
check("service loads once with the content filter on", S.router.safety_filter is cs.filter_indices and S.load_seconds is not None)
try:
    svc_mod.CrisisContentService(rp.CrisisRouter(chunks, store, enc))
    ok = False
except ValueError:
    ok = True
check("service refuses a router without the content filter", ok)

# Gate 4-J cases over all 216 dev queries (gate 0 to exercise the grounded branch too)
S0 = svc_mod.CrisisContentService(rp.CrisisRouter(chunks, store, enc, gate=0.0, safety_filter=cs.filter_indices))
qs = [r["query"] for r in store]
crit_ok = low_ok = high_ok = True
n_grounded = n_filtered_to_fallback = 0
for q in qs:
    c = S0.intervention_content(q, "CRITICAL")
    crit_ok &= c["source"] == "fallback" and c["items"] == fb.fallback(c["language"]) and c["helpline"] == fb.HELPLINE
    low_ok &= S0.intervention_content(q, "LOW") is None and S0.intervention_content(q, "MODERATE") is None
    h = S0.intervention_content(q, "HIGH")
    high_ok &= h["source"] in ("grounded", "fallback") and 1 <= len(h["items"]) <= 3 and h["helpline"] == fb.HELPLINE
    if h["source"] == "grounded":
        n_grounded += 1
        high_ok &= all(i["chunk_id"] in pool_ids and cs.is_servable(chunks[[c["chunk_id"] for c in chunks].index(i["chunk_id"])])
                       for i in h["items"])
    else:
        r = S0.router.route(q)
        n_filtered_to_fallback += bool(r["served"]) and not S0.router.safe_items(r)
check("Gate 4-J: CRITICAL -> deterministic fallback, never a retrieved passage (216 queries)", bool(crit_ok))
check("Gate 4-J: LOW / MODERATE -> field omitted (None)", bool(low_ok))
check("Gate 4-J: HIGH -> grounded or fallback, 1-3 items, only servable passages", bool(high_ok))
check("not vacuous: some HIGH answers grounded AND some turned into fallback by the content filter",
      n_grounded > 0 and n_filtered_to_fallback > 0)
try:
    S0.intervention_content(qs[0], "SEVERE")
    ok = False
except ValueError:
    ok = True
check("unknown risk_category raises ValueError (no guessed tier)", ok)

# Haystack == plain router with the filter on
same = True
for q in qs:
    for tier in ("HIGH", "CRITICAL", "LOW"):
        same &= S0.intervention_content(q, tier) == S0.router.respond(q, tier, fb.fallback, fb.HELPLINE)
check("Haystack output == CrisisRouter.respond with the content filter on (648 cases)", bool(same))

# ---- M3: FastAPI wiring (throwaway app; the real route edit needs Ahmad's file)
try:
    from fastapi import FastAPI, Request
    from fastapi.testclient import TestClient
except ImportError:
    print("SKIP FastAPI wiring tests (fastapi not installed)")
else:
  try:
      TestClient(FastAPI())
  except TypeError as e:          # old starlette + httpx>=0.28 (TestClient passes a removed 'app' kwarg)
      print("SKIP FastAPI wiring tests (starlette/httpx mismatch: %s) -> run: pip install -U fastapi" % e)
  else:
      app = FastAPI()
      app.state.crisis_content = S0

      @app.post("/t")
      async def t(req: Request):
          body = await req.json()
          resp = {"risk_category": body["risk_category"]}
          content = req.app.state.crisis_content.intervention_content(body["message"], body["risk_category"])
          if content is not None:
              resp["intervention_content"] = content
          return resp

      cl = TestClient(app)
      j_low = cl.post("/t", json={"message": qs[0], "risk_category": "LOW"}).json()
      j_crit = cl.post("/t", json={"message": qs[0], "risk_category": "CRITICAL"}).json()
      j_high = cl.post("/t", json={"message": qs[0], "risk_category": "HIGH"}).json()
      check("FastAPI: LOW response has no intervention_content key", "intervention_content" not in j_low)
      check("FastAPI: CRITICAL response carries the fallback", j_crit["intervention_content"]["source"] == "fallback")
      check("FastAPI: HIGH response carries contract keys",
            set(j_high["intervention_content"]) == {"source", "language", "items", "helpline"})

      calls = []
      real_load = svc_mod.CrisisContentService.load
      svc_mod.CrisisContentService.load = classmethod(lambda cls, encoder=None: calls.append(1) or S0)
      try:
          app2 = FastAPI(lifespan=svc_mod.fastapi_lifespan())
          with TestClient(app2):
              pass
          check("fastapi_lifespan loads the service exactly once at startup",
                calls == [1] and app2.state.crisis_content is S0)
      finally:
          svc_mod.CrisisContentService.load = real_load

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)

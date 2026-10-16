"""Tests for eval/holdout_once.py with a stand-in encoder in a temp results dir. The real holdout is NOT
evaluated with a meaningful encoder here; the lock/refusal/preflight logic is what is tested.
Run: python eval/test_holdout_once.py"""
import contextlib, io, json, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import test_crisis_router as tcr  # noqa: E402  (installs the stub sentence_transformers; runs its own checks)
import holdout_once as ho  # noqa: E402
import retrieval_pipeline as rp  # noqa: E402

fails = []


def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c:
        fails.append(n)


def run(argv, **kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = ho.main(argv, encoder=tcr.StubEncoder(), **kw)
    return rc, buf.getvalue()


pos, neg, ex = ho.holdout_rows()
check("holdout labels: 57 positives, 32 negatives (30 by-design + 2 NONE), 7 none_flip excluded",
      (len(pos), len(neg), dict(ex)) == (57, 32, {"none_flip": 7}))
check("holdout gold ids all exist in corpus",
      all(g in {c["chunk_id"] for c in rp.load_corpus()} for r in pos for g in r["gold"]))

# stub-reproducible expectations so the full locked path can be exercised
router = rp.CrisisRouter(rp.load_corpus(), rp.load_example_store(), tcr.StubEncoder())
op = rp.dev_operating_point(router, 0.4)
stub_expected = dict(thr=rp.CRISIS_GATE, thr_tol=1e-4, n_pos=op["n_pos"], n_neg=op["n_neg"], far_k=op["far_k"])

with tempfile.TemporaryDirectory() as d:
    rc, out = run([], results_dir=d)
    check("no flag -> refuses (rc 3), no lock", rc == 3 and not (Path(d) / ho.LOCK_NAME).exists())
    rc, out = run(["--dry-run"], results_dir=d)
    check("dry run on dev: runs, prints MISMATCH for stub, creates no lock, reads no holdout queries",
          rc == 4 and "MISMATCH" in out and "DRY RUN" in out and not (Path(d) / ho.LOCK_NAME).exists())
    rc, out = run(["--i-checked-the-lock"], results_dir=d)
    check("real mode + preflight mismatch -> abort before lock (rc 4)",
          rc == 4 and "ABORT" in out and not list(Path(d).iterdir()))

with tempfile.TemporaryDirectory() as d:
    exp = dict(stub_expected, thr=op["thr"])            # make the stub "reproduce" so the locked path runs
    rc, out = run(["--i-checked-the-lock"], results_dir=d, expected=exp)
    lock = json.loads((Path(d) / ho.LOCK_NAME).read_text())
    res = list(Path(d).glob("holdout_once_*.json"))
    check("locked run completes: lock status completed, one results file, hashes recorded",
          rc == 0 and lock["status"] == "completed" and len(res) == 1 and lock["results_sha256"] == ho.sha256(res[0])
          and "eval/labels/koi_queries_master_draft.csv" in lock["input_sha256"])
    body = json.loads(res[0].read_text())["holdout"]
    check("results: n_pos 57 / n_neg 32, metrics and bundle present",
          body["n_pos"] == 57 and body["n_neg"] == 32 and len(body["bundle"]) == 3 and "far_ci" in body)
    rc, out = run(["--i-checked-the-lock"], results_dir=d, expected=exp)
    check("second run refused (rc 2)", rc == 2 and "Refusing" in out)
    (Path(d) / ho.LOCK_NAME).unlink()
    rc, out = run(["--i-checked-the-lock"], results_dir=d, expected=exp)
    check("deleting the lock is not enough: an existing results file still refuses", rc == 2)

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)

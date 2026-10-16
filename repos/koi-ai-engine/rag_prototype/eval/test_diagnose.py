"""Plumbing test for diagnose_handlabelled.py (stand-in encoder). Run: python test_diagnose.py"""
import contextlib, io, sys, types
from pathlib import Path
from sklearn.feature_extraction.text import HashingVectorizer

class _Stub:
    def __init__(self, *a, **k):
        self.v = HashingVectorizer(n_features=512, analyzer="char_wb", ngram_range=(2, 4), norm="l2", alternate_sign=False)
    def encode(self, texts, convert_to_numpy=True, show_progress_bar=False):
        return self.v.transform(texts).toarray()
_f = types.ModuleType("sentence_transformers"); _f.SentenceTransformer = _Stub
sys.modules["sentence_transformers"] = _f
sys.path.insert(0, str(Path(__file__).resolve().parent))
import diagnose_handlabelled as dg
import embedder_comparison as ec

fails = []
def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c: fails.append(n)

s = dg.summarise([1, 3, None, 12], [0.9, 1.0, 0.8, 1.0])
check("summarise: recall@k and median over found ranks", s["r1"] == 0.25 and s["r3"] == 0.5 and s["r10"] == 0.5 and s["median_rank"] == 3)
check("summarise: AnnoMI share averaged", abs(s["annomi_top10"] - 0.925) < 1e-9)
ec.MULTILINGUAL_QUERIES = ec.MULTILINGUAL_QUERIES[:12]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    out = dg.run(["minilm"], None)
o = buf.getvalue()
check("run: FULL and AUTH pools reported", "FULL" in o and "AUTH" in o)
check("run: AUTH pool contains no AnnoMI by construction",
      all(v["annomi_top10"] == 0.0 for k, v in out["minilm"].items() if k[2] == "AUTH"))
check("run: label sources printed", "Label sources" in o)
print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))

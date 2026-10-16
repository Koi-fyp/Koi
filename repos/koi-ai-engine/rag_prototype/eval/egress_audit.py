"""
Offline egress audit for the crisis path (state file v4.27 §8 item 4).

    python eval/egress_audit.py            # real me5-small from the local HF cache; must report 0 attempts
    python eval/egress_audit.py --stub     # plumbing check with a stand-in encoder (no model)

Before ANY import it sets HF_HUB_OFFLINE=1, TRANSFORMERS_OFFLINE=1, HAYSTACK_TELEMETRY_ENABLED=False, then
replaces socket.connect/connect_ex/create_connection/getaddrinfo with a guard that records and blocks every
attempt. It loads the corpus, the example store, the encoder and the Haystack pipeline, and runs every dev
query through HIGH, HIGH_CRISIS, CRITICAL and LOW. PASS = zero attempts and Haystack telemetry not created.
Limitation: only Python-level sockets are guarded (native-library networking would not be seen).
Finding from the 12 Oct runs: "Warning: You are sending unauthenticated requests to the HF Hub" -> without
HF_HUB_OFFLINE=1 the model load DOES contact huggingface.co. Production must set it.
"""
import os
import sys

for k, v in (("HF_HUB_OFFLINE", "1"), ("TRANSFORMERS_OFFLINE", "1"), ("HAYSTACK_TELEMETRY_ENABLED", "False")):
    os.environ[k] = v

import socket  # noqa: E402

ATTEMPTS = []


def _blocked(kind):
    def f(*a, **k):
        ATTEMPTS.append((kind, repr(a[1:] if kind in ("connect", "connect_ex") else a)[:120]))
        raise OSError(f"egress blocked by audit ({kind})")
    return f


socket.socket.connect = _blocked("connect")
socket.socket.connect_ex = _blocked("connect_ex")
socket.create_connection = _blocked("create_connection")
socket.getaddrinfo = _blocked("getaddrinfo")

from pathlib import Path  # noqa: E402

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "scripts"), str(HERE)]


def main(argv=None, encoder=None):
    argv = sys.argv[1:] if argv is None else argv
    if encoder is None and "--stub" in argv:
        from test_crisis_router import StubEncoder   # installs a stand-in sentence_transformers module
        encoder = StubEncoder()
    import retrieval_pipeline as rp
    import haystack_pipeline as hp
    if encoder is None:
        encoder = rp.E5Encoder()
    router = rp.CrisisRouter(rp.load_corpus(), rp.load_example_store(), encoder)
    fb = lambda lang: [{"text": "FALLBACK", "chunk_id": None, "source_corpus": "deterministic",
                        "evidence_role": None, "review_status": "not-required"}]
    pipe = hp.build_crisis_pipeline(router, fb, {"name": "Humraaz", "number": "1166"})
    n = 0
    for r in router.store:
        for tier in ("HIGH", "HIGH_CRISIS", "CRITICAL", "LOW"):
            hp.run_crisis(pipe, r["query"], tier)
            n += 1
    tel = hp.telemetry_disabled()
    ok = not ATTEMPTS and tel
    print(f"EGRESS AUDIT: {n} pipeline runs, network attempts {len(ATTEMPTS)}, haystack telemetry disabled {tel}"
          f" -> {'PASS' if ok else 'FAIL'}")
    for a in ATTEMPTS[:10]:
        print("  attempt:", a)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

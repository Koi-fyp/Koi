"""
Day 1/2 — Retrieval pipeline: hybrid dense+BM25 via RRF (locked design, §2).

Dense leg uses real sentence-transformers embeddings (all-MiniLM-L6-v2).
NOTE: this specific file cannot be *exercised* end-to-end inside the
Claude sandbox (huggingface.co is blocked there — confirmed live: 403,
x-deny-reason: host_not_allowed), so the embedding-model download and
actual retrieval run only happen on the real dev machine. The code itself
is written and maintained here to match what's actually running there —
this docstring exists so the file's history is legible, not to imply a
live substitution is still in effect.

BM25 (rank_bm25) is fully real everywhere, no substitution ever needed there.
"""
import json
import re
from pathlib import Path
from rank_bm25 import BM25Okapi
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np

PROC = Path(__file__).resolve().parent.parent / "data" / "processed"
ARABIC_SCRIPT = re.compile(r"[\u0600-\u06FF]")  # same range as super_run.ARABIC

def load_corpus():
    """Loads all corpus files. Chunks predating the `language` field default
    to 'en' and review_status 'not-required' -- every pre-mhGAP-PK source is
    English-only, so this is a factual default, not an assumption."""
    chunks = []
    for f in ["annomi_chunks.jsonl", "authoritative_chunks.jsonl", "mhgap_pk_chunks.jsonl"]:
        path = PROC / f
        if not path.exists():
            continue
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                c = json.loads(line)
                c.setdefault("language", "en")
                c.setdefault("review_status", "not-required")
                chunks.append(c)
    return chunks

def tokenize(text):
    """ASCII-only tokens. This is the REFERENCE tokenizer; kept unchanged because
    ablation.py ('hybrid_ascii (current)' arm) and its tests import it. It yields
    ZERO tokens for Urdu-script text."""
    return re.findall(r"[a-z0-9']+", text.lower())


def tokenize_unicode(text):
    """Unicode word tokens (Urdu-script words become tokens). Added 2026-10-12 after
    ablation.py: ASCII BM25 gave 0% R@1 on the Urdu probe for all four embedders.
    Limitation: \\w drops Urdu combining marks, so diacritised Urdu may split.
    Roman Urdu / code-switched retrieval is NOT evaluated yet (no verified labels)."""
    return re.findall(r"[\w']+", text.lower())


TOKENIZERS = {"ascii": tokenize, "unicode": tokenize_unicode}

DEFAULT_MODEL = 'sentence-transformers/all-MiniLM-L6-v2'


class HybridRetriever:
    def __init__(self, chunks, model_name=DEFAULT_MODEL, doc_prefix="", query_prefix="",
                 max_seq_length=None, cache_dir=None, bm25_tokenizer="unicode", bm25_policy="always"):
        """Defaults reproduce the reference pipeline exactly (MiniLM, no prefixes,
        no seq-length override, no cache). The extra args exist so the embedder can
        be swapped for the multilingual comparison; e5-family models need
        doc_prefix='passage: ' / query_prefix='query: ' (per their model cards --
        verify)."""
        self.chunks = chunks
        self.texts = [c["text"] for c in chunks]
        self.query_prefix = query_prefix
        # bm25_policy (added 2026-10-12, v4.27 §5 item 3): "always" = reference behaviour; "script_cond" = use
        # the BM25 leg only when the query contains Arabic-script characters (super_run.script_cond), dense
        # otherwise. NOTE: the served HIGH path is CrisisRouter below, which uses no BM25 at all.
        if bm25_policy not in ("always", "script_cond"):
            raise ValueError(f"bm25_policy must be 'always' or 'script_cond', got {bm25_policy!r}")
        self.bm25_policy = bm25_policy
        # --- BM25 (real) ---
        # bm25_tokenizer="ascii" reproduces the reference BM25 leg exactly.
        self.tok = TOKENIZERS[bm25_tokenizer]
        tokenized = [self.tok(t) for t in self.texts]
        self.bm25 = BM25Okapi(tokenized)
        # --- dense embeddings (real) ---
        self.model = SentenceTransformer(model_name)
        if max_seq_length:
            self.model.max_seq_length = max_seq_length
        docs = [doc_prefix + t for t in self.texts]
        cache_file = None
        if cache_dir:
            import hashlib
            key = hashlib.sha1("\x00".join([model_name, doc_prefix, str(max_seq_length)] + docs)
                               .encode("utf-8")).hexdigest()[:16]
            cache_file = Path(cache_dir) / f"emb_{key}.npy"
        if cache_file is not None and cache_file.exists():
            self.embeddings = np.load(cache_file)
        else:
            self.embeddings = self.model.encode(docs, convert_to_numpy=True, show_progress_bar=True)
            if cache_file is not None:
                cache_file.parent.mkdir(parents=True, exist_ok=True)
                np.save(cache_file, self.embeddings)

    def retrieve(self, query, k=10, eligible_mask=None):
        """eligible_mask: optional boolean list, same length as self.chunks,
        applied BEFORE ranking (models the locked eligibility-filter stage)."""
        idx_pool = [i for i in range(len(self.chunks)) if eligible_mask is None or eligible_mask[i]]
        if not idx_pool:
            return []

        # BM25 ranking over eligible pool
        # Empty-token guard: a query with no BM25 tokens must not feed corpus-order
        # noise into the fusion. Skip the BM25 leg and rank by dense only.
        q_tokens = self.tok(query)
        use_bm25 = bool(q_tokens) and (self.bm25_policy == "always" or bool(ARABIC_SCRIPT.search(query)))
        bm25_scores_full = self.bm25.get_scores(q_tokens) if use_bm25 else np.zeros(len(self.chunks))
        bm25_ranked = sorted(idx_pool, key=lambda i: -bm25_scores_full[i]) if use_bm25 else []

        # dense cosine ranking over eligible pool
        q_vec = self.model.encode([self.query_prefix + query], convert_to_numpy=True)
        cos_full = cosine_similarity(q_vec, self.embeddings)[0]
        dense_ranked = sorted(idx_pool, key=lambda i: -cos_full[i])

        # --- Reciprocal Rank Fusion (locked design) ---
        RRF_K = 60
        rrf_scores = {}
        for rank, i in enumerate(bm25_ranked):
            rrf_scores[i] = rrf_scores.get(i, 0) + 1.0 / (RRF_K + rank + 1)
        for rank, i in enumerate(dense_ranked):
            rrf_scores[i] = rrf_scores.get(i, 0) + 1.0 / (RRF_K + rank + 1)

        fused = sorted(rrf_scores.items(), key=lambda x: -x[1])[:k]
        results = []
        for i, score in fused:
            results.append({
                "chunk": self.chunks[i],
                "rrf_score": score,
                "cosine": float(cos_full[i]),
                "bm25": float(bm25_scores_full[i]),
                "bm25_used": use_bm25,
            })
        return results


ELIGIBLE_ROLES_BY_TIER = {
    "HIGH": {"AUTHORITATIVE_RECOMMENDATION", "AUTHORITATIVE_DEFINITION",
             "AUTHORITATIVE_PROCEDURE", "AUTHORITATIVE_PRINCIPLE",
             "EXPERT_SUPPORT_STRATEGY"},
    "CRITICAL": {"AUTHORITATIVE_RECOMMENDATION", "AUTHORITATIVE_DEFINITION",
                 "AUTHORITATIVE_PROCEDURE", "AUTHORITATIVE_PRINCIPLE"},
}


def chunk_is_eligible(chunk, risk_tier):
    """Single source of truth for tier eligibility: evidence_role allowed at the
    tier, plus the Urdu review gate at CRITICAL."""
    if chunk["evidence_role"] not in ELIGIBLE_ROLES_BY_TIER.get(risk_tier, set()):
        return False
    if risk_tier == "CRITICAL" and chunk.get("review_status") == "pending-native-review":
        return False
    return True


def eligibility_mask(chunks, risk_tier):
    """PRE-FILTER (changed from reference v0): the mask now enforces tier
    eligibility BEFORE ranking, so ineligible chunks cannot crowd eligible ones
    out of top-k. Reference v0 returned all-True for HIGH/CRITICAL and filtered
    only in answer_stage_filter() after top-k (see reference/). Below HIGH: no RAG."""
    return [chunk_is_eligible(c, risk_tier) for c in chunks]


def answer_stage_filter(retrieved, risk_tier):
    """The actual eligibility enforcement — locked §5: critical-risk answers
    require evidence_role starting with AUTHORITATIVE_, non-critical HIGH
    answers accept AUTHORITATIVE_* or EXPERT_SUPPORT_STRATEGY."""
    # Defense in depth: after the pre-filter this is a no-op on anything that came
    # through retrieve(); it still guards callers that pass an unmasked retrieval.
    # Includes the Urdu review gate at CRITICAL (via chunk_is_eligible).
    return [r for r in retrieved if chunk_is_eligible(r["chunk"], risk_tier)]


# =====================================================================================================
# CRISIS HIGH-TIER ROUTER  (added 2026-10-12; design = KOI_RAG_SEGMENT_STATE_v1.md v4.27 §5, DELEGATED)
# Mirrors the MEASURED system in eval/super_run.py exactly (pool, knn_votes, knn_route, coverage_sweep):
#   pool    = eligibility_mask(HIGH) & not AnnoMI & not r"\b988\b"            -> 22 chunks (AUTH_noUS)
#   votes   = K=7 nearest labelled store queries; weight = max(sim, 0); negatives add weight, no votes;
#             normalised by total neighbour weight
#   ranking = votes + 1e-6 * cosine(query, chunk), inside the pool             (no BM25 on this path)
#   gate    = vote share of the top-1 chunk >= CRISIS_GATE (rule G, dev-fitted, 40% coverage)
# CRITICAL never reaches retrieval. Below HIGH the field is omitted (None).
# =====================================================================================================
import csv as _csv
import importlib.util as _ilu

CRISIS_K = 7                     # super_run.KNN_K
CRISIS_TIEBREAK = 1e-6           # super_run.knn_route
CRISIS_GATE = 0.5709             # rule G on dev, me5-small, AUTH_noUS (state file v4.27 §4). Rounded as reported.
CRISIS_MAX_ITEMS = 3             # LOCKED: show top-3
CRISIS_MODEL = "intfloat/multilingual-e5-small"
US_ONLY = re.compile(r"\b988\b")  # super_run.US_ONLY
# risk_category strings: OPEN (state file v4.27 §6f: "HIGH_CRISIS"/"CRITICAL" in canon vs "HIGH"/"CRITICAL" here)
_HIGH = {"HIGH", "HIGH_CRISIS"}
_CRITICAL = {"CRITICAL"}
_BELOW_HIGH = {"LOW", "MODERATE"}
# language_detector.Language.value -> contract `language` (state file §8)
CONTRACT_LANGUAGE = {"english": "en", "urdu_native": "ur", "roman_urdu": "ur-roman", "code_switched": "mixed"}
EVAL = Path(__file__).resolve().parent.parent / "eval"


def crisis_pool(chunks):
    """AUTH_noUS indices, computed exactly as super_run.run() does."""
    elig = eligibility_mask(chunks, "HIGH")
    return np.asarray([i for i, (c, e) in enumerate(zip(chunks, elig))
                       if e and c["source_corpus"] != "AnnoMI" and not US_ONLY.search(c["text"])], dtype=int)


def _l2n(m):
    m = np.asarray(m, float)
    return m / np.clip(np.linalg.norm(m, axis=1, keepdims=True), 1e-12, None)


def knn_votes(sims, golds, is_neg, n_chunks, k=CRISIS_K, candidates=None):
    """sims: one query vs every store query. candidates: allowed neighbour indices (None = all)."""
    cand = np.arange(len(sims)) if candidates is None else np.asarray(candidates, int)
    votes = np.zeros(n_chunks)
    if not len(cand):
        return votes, []
    nb = cand[np.argsort(-sims[cand], kind="stable")[:k]]
    w = np.clip(sims[nb], 0, None)
    for j, wj in zip(nb, w):
        if not is_neg[j]:
            for g in golds[j]:
                votes[g] += wj
    tot = w.sum()
    return (votes / tot if tot > 0 else votes), list(nb)


class E5Encoder:
    """e5 prefixes per the model card. max_seq_length MUST equal embedder_comparison.MODELS['me5-small']['max_len']
    (that file was not available when this was written) -- verify_dev_reproduction() catches a mismatch."""
    def __init__(self, name=CRISIS_MODEL, max_seq_length=None, doc_prefix="passage: ", query_prefix="query: "):
        self.name, self.doc_prefix, self.query_prefix = name, doc_prefix, query_prefix
        self.model = SentenceTransformer(name)
        if max_seq_length:
            self.model.max_seq_length = max_seq_length

    def encode_queries(self, texts):
        return self.model.encode([self.query_prefix + t for t in texts], convert_to_numpy=True)

    def encode_passages(self, texts):
        return self.model.encode([self.doc_prefix + t for t in texts], convert_to_numpy=True)


def load_example_store(queries_py=EVAL / "multilingual_queries.py",
                       master_csv=EVAL / "labels" / "koi_queries_master_draft.csv"):
    """The labelled DEV queries = the kNN example store. Positives + negatives; MULTILINGUAL_AMBIGUOUS is NOT
    used (super_run excludes it too). Scenario ids from the master CSV (as super_run.scenario_map)."""
    spec = _ilu.spec_from_file_location("_koi_mq", str(queries_py))
    mq = _ilu.module_from_spec(spec)
    spec.loader.exec_module(mq)
    smap = {}
    if Path(master_csv).exists():
        with open(master_csv, encoding="utf-8-sig") as fh:
            for r in _csv.DictReader(fh):
                if r["split"] != "dev" and r["id"] in smap:
                    raise ValueError("duplicate id across splits")
                smap[r["id"]] = (r.get("scenario_id") or r["id"], r["split"])
    store = []
    for e in mq.MULTILINGUAL_QUERIES:
        store.append(dict(id=e["id"], lang=e["lang"], query=e["query"], gold=list(e.get("gt_chunk_ids", [])),
                          neg=False, scenario=smap.get(e["id"], (e["id"], None))[0]))
    for e in getattr(mq, "MULTILINGUAL_NEGATIVES", []):
        store.append(dict(id=e["id"], lang=e["lang"], query=e["query"], gold=[], neg=True,
                          scenario=smap.get(e["id"], (e["id"], None))[0]))
    leaked = [s["id"] for s in store if smap.get(s["id"], (None, "dev"))[1] not in ("dev", None)]
    if leaked:
        raise ValueError(f"store contains non-dev rows: {leaked[:5]}")
    return store


class CrisisRouter:
    def __init__(self, chunks, store, encoder, k=CRISIS_K, gate=CRISIS_GATE, max_items=CRISIS_MAX_ITEMS,
                 safety_filter=None):
        self.chunks, self.encoder, self.k, self.gate, self.max_items = chunks, encoder, k, gate, max_items
        # M2: optional fail-closed content filter, f(indices, chunks) -> kept indices (content_safety.filter_indices).
        # None = the measured system. Production builds it ON via scripts/crisis_service.py.
        self.safety_filter = safety_filter
        self.N = len(chunks)
        self.pool = crisis_pool(chunks)
        if not len(self.pool):
            raise ValueError("empty crisis pool")
        id2idx = {c["chunk_id"]: i for i, c in enumerate(chunks)}
        # super_run.build_items: unknown gold ids are dropped; a positive left with no gold is dropped
        kept = []
        for r in store:
            g = {id2idx[c] for c in r["gold"] if c in id2idx}
            if r["neg"] or g:
                kept.append((r, g))
        self.dropped = len(store) - len(kept)
        self.store = [r for r, _ in kept]
        self.golds = [g for _, g in kept]
        self.is_neg = [bool(r["neg"]) for r in self.store]
        self.scen = [r.get("scenario") or r["id"] for r in self.store]
        # passage embeddings only for the pool (cosine is only ever read inside the pool)
        Ep = _l2n(encoder.encode_passages([chunks[i]["text"] for i in self.pool]))
        self.E = np.zeros((self.N, Ep.shape[1]))
        self.E[self.pool] = Ep
        self.Qs = _l2n(encoder.encode_queries([r["query"] for r in self.store]))

    def _rank(self, votes, cos):
        s = votes + CRISIS_TIEBREAK * cos
        order = self.pool[np.argsort(-s[self.pool], kind="stable")]
        return order, float(votes[order[0]])

    def route(self, query, exclude_scenario=None):
        q = _l2n(self.encoder.encode_queries([query]))[0]
        cand = None if exclude_scenario is None else np.flatnonzero([s != exclude_scenario for s in self.scen])
        votes, nb = knn_votes(self.Qs @ q, self.golds, self.is_neg, self.N, self.k, cand)
        order, score = self._rank(votes, self.E @ q)
        # v4.29: only chunks with votes > 0 are served (a zero-vote chunk has no labelled support).
        # order/gate_score/accept are unchanged, so the measured ranking and the gate are untouched.
        served = [int(i) for i in order if votes[i] > 0][: self.max_items]
        return dict(order=order, gate_score=score, accept=score >= self.gate, neighbours=nb, served=served)

    def loso_scores(self):
        """Leave-scenario-out over the store, as super_run evaluates knn_route. Returns per-row dicts."""
        qq = self.Qs @ self.Qs.T
        cos = self.Qs @ self.E.T
        out = []
        for i in range(len(self.store)):
            cand = np.flatnonzero([self.scen[j] != self.scen[i] for j in range(len(self.store))])
            votes, _ = knn_votes(qq[i], self.golds, self.is_neg, self.N, self.k, cand)
            order, score = self._rank(votes, cos[i])
            served = [int(j) for j in order if votes[j] > 0][: self.max_items]          # v4.29
            out.append(dict(neg=self.is_neg[i], score=score, order=order, gold=self.golds[i], served=served))
        return out

    def safe_items(self, route):
        """Served indices after the optional content filter (order kept)."""
        served = route["served"]
        return list(served) if self.safety_filter is None else self.safety_filter(served, self.chunks)

    def respond(self, query, risk_category, fallback, helpline, language=None):
        """intervention_content dict, or None (omit) below HIGH. fallback(language) -> list of item dicts with
        the deterministic text; helpline = {"name","number"} (1166 UNVERIFIED). Unknown tier strings raise."""
        rc = (risk_category or "").strip().upper()
        if rc in _BELOW_HIGH:
            return None
        if language is None:
            from language_detector import detect_language
            language = CONTRACT_LANGUAGE[detect_language(query)["primary"].value]
        if rc in _CRITICAL:
            return _fallback_content(language, fallback, helpline)
        if rc not in _HIGH:
            raise ValueError(f"unrecognised risk_category {risk_category!r}; refusing to guess a tier")
        try:
            r = self.route(query)
        except Exception:
            return _fallback_content(language, fallback, helpline)
        idx = self.safe_items(r)
        if not r["accept"] or not idx:                    # v4.29 / M2: nothing servable -> fallback
            return _fallback_content(language, fallback, helpline)
        items = [{"text": self.chunks[i]["text"], "chunk_id": self.chunks[i]["chunk_id"],
                  "source_corpus": self.chunks[i]["source_corpus"],
                  "evidence_role": self.chunks[i]["evidence_role"],
                  "review_status": self.chunks[i].get("review_status")}
                 for i in idx]
        return {"source": "grounded", "language": language, "items": items, "helpline": dict(helpline)}


def _fallback_content(language, fallback, helpline):
    return {"source": "fallback", "language": language, "items": list(fallback(language)), "helpline": dict(helpline)}


def dev_operating_point(router, coverage=0.4):
    """Re-derive rule G's numbers on the store (LOSO). Same formulas as super_run.coverage_sweep/hit_at."""
    rows = router.loso_scores()
    pos = [r for r in rows if not r["neg"]]
    neg = np.array([r["score"] for r in rows if r["neg"]])
    ps = np.array([r["score"] for r in pos])
    h1 = np.array([int(r["order"][0] in r["gold"]) for r in pos])
    h3 = np.array([int(any(i in r["gold"] for i in r["order"][:3])) for r in pos])
    thr = float(np.quantile(ps, 1 - coverage))
    acc = ps >= thr
    return dict(n_pos=len(pos), n_neg=len(neg), hit1=float(h1.mean()), hit3=float(h3.mean()), thr=thr,
                cov_actual=float(acc.mean()), acc_hit1=float(h1[acc].mean()), acc_hit3=float(h3[acc].mean()),
                far=float((neg >= thr).mean()), far_k=int((neg >= thr).sum()))


if __name__ == "__main__":
    chunks = load_corpus()
    print(f"Loaded {len(chunks)} total chunks "
          f"({sum(1 for c in chunks if c['source_corpus']=='AnnoMI')} AnnoMI, "
          f"{sum(1 for c in chunks if c['source_corpus']=='WHO_mhGAP_2023')} WHO, "
          f"{sum(1 for c in chunks if c['source_corpus']=='SAMHSA_2025')} SAMHSA)")
    retriever = HybridRetriever(chunks)
    print("Retriever built (BM25 real; TF-IDF-cosine dense stand-in — see module docstring).")

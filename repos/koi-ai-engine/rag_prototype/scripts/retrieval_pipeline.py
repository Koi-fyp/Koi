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

def load_corpus():
    chunks = []
    for f in ["annomi_chunks.jsonl", "authoritative_chunks.jsonl"]:
        with open(PROC / f) as fh:
            for line in fh:
                chunks.append(json.loads(line))
    return chunks

def tokenize(text):
    return re.findall(r"[a-z0-9']+", text.lower())

class HybridRetriever:
    def __init__(self, chunks):
        self.chunks = chunks
        self.texts = [c["text"] for c in chunks]
        # --- BM25 (real) ---
        tokenized = [tokenize(t) for t in self.texts]
        self.bm25 = BM25Okapi(tokenized)
        # --- dense embeddings (real) ---
        self.model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')
        self.embeddings = self.model.encode(self.texts, convert_to_numpy=True, show_progress_bar=True)

    def retrieve(self, query, k=10, eligible_mask=None):
        """eligible_mask: optional boolean list, same length as self.chunks,
        applied BEFORE ranking (models the locked eligibility-filter stage)."""
        idx_pool = [i for i in range(len(self.chunks)) if eligible_mask is None or eligible_mask[i]]
        if not idx_pool:
            return []

        # BM25 ranking over eligible pool
        bm25_scores_full = self.bm25.get_scores(tokenize(query))
        bm25_ranked = sorted(idx_pool, key=lambda i: -bm25_scores_full[i])

        # dense cosine ranking over eligible pool
        q_vec = self.model.encode([query], convert_to_numpy=True)
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
            })
        return results


def eligibility_mask(chunks, risk_tier):
    """Locked §5 logic: broad retrieval, strict eligibility at answer stage.
    This mask models retrieval-stage eligibility (which corpora are even
    searchable at this tier) — the STRICTER answer-stage evidence_role check
    happens separately, after retrieval, per the locked architecture."""
    if risk_tier == "HIGH":
        return [True] * len(chunks)  # all sources eligible for retrieval
    elif risk_tier == "CRITICAL":
        # broad retrieval still allowed at CRITICAL per locked §5 —
        # eligibility restriction happens at evidence_role check post-retrieval,
        # not by shrinking the retrieval pool itself
        return [True] * len(chunks)
    else:
        return [False] * len(chunks)  # no RAG below HIGH


def answer_stage_filter(retrieved, risk_tier):
    """The actual eligibility enforcement — locked §5: critical-risk answers
    require evidence_role starting with AUTHORITATIVE_, non-critical HIGH
    answers accept AUTHORITATIVE_* or EXPERT_SUPPORT_STRATEGY."""
    eligible_roles_by_tier = {
        "HIGH": {"AUTHORITATIVE_RECOMMENDATION", "AUTHORITATIVE_DEFINITION",
                 "AUTHORITATIVE_PROCEDURE", "AUTHORITATIVE_PRINCIPLE",
                 "EXPERT_SUPPORT_STRATEGY"},
        "CRITICAL": {"AUTHORITATIVE_RECOMMENDATION", "AUTHORITATIVE_DEFINITION",
                     "AUTHORITATIVE_PROCEDURE", "AUTHORITATIVE_PRINCIPLE"},
    }
    allowed = eligible_roles_by_tier.get(risk_tier, set())
    return [r for r in retrieved if r["chunk"]["evidence_role"] in allowed]


if __name__ == "__main__":
    chunks = load_corpus()
    print(f"Loaded {len(chunks)} total chunks "
          f"({sum(1 for c in chunks if c['source_corpus']=='AnnoMI')} AnnoMI, "
          f"{sum(1 for c in chunks if c['source_corpus']=='WHO_mhGAP_2023')} WHO, "
          f"{sum(1 for c in chunks if c['source_corpus']=='SAMHSA_2025')} SAMHSA)")
    retriever = HybridRetriever(chunks)
    print("Retriever built (BM25 real; TF-IDF-cosine dense stand-in — see module docstring).")

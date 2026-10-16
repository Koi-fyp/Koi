# Section F — P1 Chat Service

## Starting hash
Command: `E:\Setups\anaconda\envs\koivenv\python.exe -c "hashlib.sha256(open(p,'rb').read().replace(b'\\r\\n',b'\\n')).hexdigest()[:12]"`
Raw output: `c61d7eac680b` (PASS; required `c61d7eac680b`)

## Implementation
Added/refactored:
- `deploy/modal/chat_core.py`
- `deploy/modal/stream_extract.py`
- `deploy/modal/chat_app.py`
- `deploy/modal/test_chat_contract.py`
- `deploy/modal/smoke_chat.py`

## Tests and commands
- `E:\Setups\anaconda\envs\koivenv\python.exe -m pytest deploy\modal\test_chat_contract.py -q` -> `8 passed in 0.64s`
- `E:\Setups\anaconda\envs\koivenv\python.exe test_task2.py` -> exit 0 (only pre-existing pydantic UserWarning from `app/core/config.py`)
- `E:\Setups\anaconda\envs\koivenv\python.exe -m pytest koi_policy\test_adapter_qwen.py -q` -> `4 passed, 1 warning in 0.13s`
- `E:\Setups\anaconda\envs\koivenv\python.exe -m py_compile deploy\modal\chat_core.py deploy\modal\stream_extract.py deploy\modal\chat_app.py deploy\modal\smoke_chat.py deploy\modal\test_chat_contract.py` -> exit 0
- Local fake-engine HTTP smoke -> HTTP 200, SSE order `latency`, `companion_state`, `delta`, `done`; CORS OPTIONS 200.

## Protected hashes (SHA-256 prefixes)
- `director.py` FC2D52A9E1D7
- `policy.py` 1A318EDFB932
- `intents.py` 39BE0F36A002
- `compose.py` CA135C692C52
- `journeys.json` 9C56B1366F88
- `catalogue.py` EBEEE43DB081
- `state_token.py` 2CB6BD501EB4

## Git evidence
`git --no-pager diff --stat` raw output:
```
app/api/routes.py 131 +-
app/models/schemas.py 16 +-
app/services/inference_service.py 30 +-
rag_prototype/data/processed/authoritative_chunks.jsonl 6 +-
rag_prototype/scripts/retrieval_pipeline.py 340 +-
5 files changed, 478 insertions(+), 45 deletions(-)
```
(These are unrelated pre-existing changes; preserved.) `git status --short` also reports the pre-existing modified/untracked app, rag_prototype, docs, policy, and root files. No protected file was edited and no commit was created.

## Skipped / notes
The task references three baseline scripts with expected counts 71/44/34, but no such baseline scripts are present in this checkout (only `test_task2.py` was found); they were not guessed or run. Live Modal smoke was not run (no deployment requested; no `modal serve/deploy` used). The full exercise matrix was not run against vLLM because vLLM is intentionally absent locally; fake-engine contract coverage was run. No files under `rag_prototype`, canon docs, or protected `koi_policy` files were modified.

Result: PASS-WITH-NOTES.

--- resumed 2026-10-17 ---
P1.a: git fetch origin --prune passed. Local HEAD ae5daf9 differs from origin/feat/exercise-director-modal 2923070 because local P4 commits are unpushed; no merge/reset performed.

P1.b commands: test_chat_contract 10 passed; test_crisis_core 5 passed; test_adapter_qwen 4 passed. Combined koi_policy baseline collection errored because four legacy test modules call SystemExit(0) during collection; no changes made. Required 71/44/34 named baseline scripts are absent per prior report.

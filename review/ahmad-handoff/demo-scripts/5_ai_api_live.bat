@echo off
@echo off
call conda activate koi2-ai
cd /d E:\Koi\koi2-ai
set AGENTROUTER_API_KEY=sk-XtgEGKOgsvRjjnO4Tqo17KW2Df3iwZGVjRG6NknNIpXi0l12
if not defined AGENTROUTER_API_KEY (echo AGENTROUTER_API_KEY is not set in this window & exit /b 1)
set PYTHONUTF8=1
set AGENTROUTER_BASE_URL=https://agentrouter.org
set AGENTROUTER_MODEL=deepseek-v4-flash
set AGENTROUTER_PROTOCOL=anthropic_messages
set AGENTROUTER_THINKING=disabled
set KOI2_PROVIDER=agentrouter
set KOI2_AUTHZ=web
set KOI2_FIREBASE_PROJECT_ID=demo-koi-platform-web1
set FIRESTORE_EMULATOR_HOST=127.0.0.1:5180
set FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:5199
set KOI2_CORS_ORIGINS=http://localhost:3107,http://127.0.0.1:3107
python -m koi2_ai.api

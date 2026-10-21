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
set FIRESTORE_EMULATOR_HOST=127.0.0.1:5180
set KOI2_FIREBASE_PROJECT_ID=demo-koi-platform-web1
set KOI2_JOB_STORE=web
set KOI2_PROVIDER=agentrouter
python -B scripts/web_e2e_emulator.py --live --cap 3
pause

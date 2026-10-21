@echo off
call conda activate koi2-ai
cd /d E:\Koi\koi2-ai
set PYTHONUTF8=1
set AGENTROUTER_API_KEY=sk-XtgEGKOgsvRjjnO4Tqo17KW2Df3iwZGVjRG6NknNIpXi0l12
set FIRESTORE_EMULATOR_HOST=127.0.0.1:5180
set KOI2_FIREBASE_PROJECT_ID=demo-koi-platform-web1
set KOI2_JOB_STORE=web
set KOI2_PROVIDER=mock
python -m koi2_ai.worker --store web --poll-seconds 15

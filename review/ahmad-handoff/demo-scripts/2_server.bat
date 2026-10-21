@echo off
call conda activate koi-web
cd /d E:\Koi\web-final\repos\koi-backend\nextjs_app
set npm_config_cache=E:\Koi\npm-cache
set NEXT_TELEMETRY_DISABLED=1
set GOOGLE_APPLICATION_CREDENTIALS=
set FIREBASE_ADMIN_SDK=
set NODE_OPTIONS=
set KOI_AI_BASE=http://127.0.0.1:8100
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\demo-env.ps1; npm run dev -- --hostname 127.0.0.1 --port 3107"

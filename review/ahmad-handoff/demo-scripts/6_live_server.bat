@echo off
call conda activate koi-web
cd /d E:\Koi\web-final\repos\koi-backend\nextjs_app
set npm_config_cache=E:\Koi\npm-cache
set NEXT_TELEMETRY_DISABLED=1
set GOOGLE_APPLICATION_CREDENTIALS=
set NODE_OPTIONS=
set FIRESTORE_EMULATOR_HOST=
set FIREBASE_AUTH_EMULATOR_HOST=
set KOI_PLATFORM_FIREBASE_PROJECT_ID=
set FIREBASE_ADMIN_SDK=
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:KOI_PLATFORM_CURSOR_SIGNING_KEY=(Get-Content E:\Koi\private\cursor_key.txt -Raw).Trim(); . .\scripts\web5-cloud-env.ps1 -ServiceAccountFile E:\Koi\private\koi-service-account.json -RulesEvidenceFile .local\koi-web5\verified-rules.json; npm run start -- --hostname 127.0.0.1 --port 3107"

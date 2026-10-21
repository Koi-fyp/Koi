@echo off
call conda activate koi-web
cd /d E:\Koi\web-final\repos\koi-backend\nextjs_app
set npm_config_cache=E:\Koi\npm-cache
set NEXT_TELEMETRY_DISABLED=1
set GOOGLE_APPLICATION_CREDENTIALS=
set FIREBASE_ADMIN_SDK=
set NODE_OPTIONS=
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo-emulators.ps1

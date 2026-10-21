@echo off
call conda activate koi-web
cd /d E:\Koi\web-final\repos\koi-backend\nextjs_app
set GOOGLE_APPLICATION_CREDENTIALS=
set FIREBASE_ADMIN_SDK=
set NODE_OPTIONS=
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\demo-env.ps1; $p = Read-Host 'Choose a fictional demo password (12-128 characters)' -AsSecureString; $env:KOI_DEMO_PASSWORD = [System.Net.NetworkCredential]::new('', $p).Password; node scripts/seed-koi-demo.cjs"
pause

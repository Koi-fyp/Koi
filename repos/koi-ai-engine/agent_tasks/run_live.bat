@echo off
setlocal EnableDelayedExpansion
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
rem ===== KOI overnight live runner. Deploys chat + crisis (min containers 0), runs the live checks, writes logs.
rem ===== Never echoes secrets. Place at E:\Koi\Koi-App\repos\koi-ai-engine\agent_tasks\run_live.bat
cd /d E:\Koi\Koi-App\repos\koi-ai-engine
if errorlevel 1 exit /b 9
set "PY=E:\Setups\anaconda\envs\koivenv\python.exe"
set "OUT=agent_tasks\reports\live"
set "TOOLS=deploy\modal\tools"
set "KEYFILE=E:\Koi\secrets\firebase_web_api_key.txt"
set "SAFILE=E:\Koi\secrets\firebase-service-account.json"
set "TOKFILE=%TEMP%\koi_tok.txt"
if not exist "%OUT%" mkdir "%OUT%"
set "SUM=%OUT%\SUMMARY.txt"
echo live run started %date% %time% > "%SUM%"

if not exist "%KEYFILE%" goto :nokey
set /p WEBKEY=<"%KEYFILE%"

"%PY%" -m modal app list > "%OUT%\00_apps_before.txt" 2>&1
"%PY%" -m modal volume ls koi-crisis-assets > "%OUT%\00_crisis_volume.txt" 2>&1

rem ---------- CHAT: deploy with trace ON (smoke test only; redeployed with trace OFF at the end)
set KOI_EXERCISES=1
set KOI_MIN_CONTAINERS=0
set KOI_CORS_ORIGINS=*
set KOI_DEBUG_TRACE=1
"%PY%" -m modal deploy deploy\modal\chat_app.py > "%OUT%\01_chat_deploy.txt" 2>&1
echo chat deploy rc=!errorlevel! >> "%SUM%"
set "CHAT_URL="
for /f "delims=" %%U in ('%PY% %TOOLS%\extract_url.py %OUT%\01_chat_deploy.txt') do set "CHAT_URL=%%U"
if "%CHAT_URL%"=="" goto :crisis
echo CHAT_URL=%CHAT_URL% >> "%SUM%"

rem ---------- token (anonymous) + same-project check
if exist "%TOKFILE%" del "%TOKFILE%"
if exist "%SAFILE%" (
  "%PY%" %TOOLS%\get_anon_token.py %WEBKEY% --sa "%SAFILE%" --token-file "%TOKFILE%" > "%OUT%\02_token_check.txt" 2>&1
) else (
  "%PY%" %TOOLS%\get_anon_token.py %WEBKEY% --token-file "%TOKFILE%" > "%OUT%\02_token_check.txt" 2>&1
)
echo token step rc=!errorlevel! >> "%SUM%"
set "KOI_TOKEN="
if exist "%TOKFILE%" set /p KOI_TOKEN=<"%TOKFILE%"
if exist "%TOKFILE%" del "%TOKFILE%"

"%PY%" %TOOLS%\wait_ready.py %CHAT_URL%/health 8 25 > "%OUT%\03_chat_ready.txt" 2>&1
echo chat ready rc=!errorlevel! >> "%SUM%"
"%PY%" %TOOLS%\auth_check.py %CHAT_URL% /api/v1/chat > "%OUT%\04_chat_auth_check.txt" 2>&1
echo chat auth_check rc=!errorlevel! >> "%SUM%"
"%PY%" deploy\modal\smoke_chat.py %CHAT_URL% > "%OUT%\05_smoke_chat.txt" 2>&1
echo smoke_chat rc=!errorlevel! >> "%SUM%"
"%PY%" %TOOLS%\emotion_probe.py %CHAT_URL% > "%OUT%\06_emotion_probe.txt" 2>&1
echo emotion_probe rc=!errorlevel! >> "%SUM%"

:crisis
rem ---------- CRISIS
set KOI_FIREBASE_SECRET=firebase-service-account
set KOI_MAX_CATEGORY=HIGH
set KOI_MIN_CONTAINERS=0
set KOI_AUTH_DISABLED=
"%PY%" -m modal deploy deploy\modal\crisis_app.py > "%OUT%\10_crisis_deploy.txt" 2>&1
echo crisis deploy rc=!errorlevel! >> "%SUM%"
set "CRISIS_URL="
for /f "delims=" %%U in ('%PY% %TOOLS%\extract_url.py %OUT%\10_crisis_deploy.txt') do set "CRISIS_URL=%%U"
if "%CRISIS_URL%"=="" goto :final
echo CRISIS_URL=%CRISIS_URL% >> "%SUM%"
"%PY%" %TOOLS%\wait_ready.py %CRISIS_URL%/health 10 30 > "%OUT%\11_crisis_ready.txt" 2>&1
echo crisis ready rc=!errorlevel! >> "%SUM%"
"%PY%" %TOOLS%\auth_check.py %CRISIS_URL% /api/v1/crisis > "%OUT%\12_crisis_auth_check.txt" 2>&1
echo crisis auth_check rc=!errorlevel! >> "%SUM%"
"%PY%" %TOOLS%\smoke_crisis.py %CRISIS_URL% > "%OUT%\13_smoke_crisis.txt" 2>&1
echo smoke_crisis rc=!errorlevel! >> "%SUM%"

:final
rem ---------- CHAT again WITHOUT trace (final state), then list apps
rem Always runs, even when CHAT_URL is empty, so a trace-ON chat can never stay live silently.
if "%CHAT_URL%"=="" echo WARNING: CHAT_URL empty; running the no-trace redeploy anyway >> "%SUM%"
set KOI_EXERCISES=1
set KOI_MIN_CONTAINERS=0
set KOI_CORS_ORIGINS=*
set KOI_DEBUG_TRACE=0
"%PY%" -m modal deploy deploy\modal\chat_app.py > "%OUT%\20_chat_redeploy_no_trace.txt" 2>&1
set "REDEPLOY_RC=!errorlevel!"
echo chat redeploy rc=!REDEPLOY_RC! >> "%SUM%"

:done
"%PY%" -m modal app list > "%OUT%\21_apps_after.txt" 2>&1
if not "!REDEPLOY_RC!"=="0" (
  echo *** FAIL: no-trace chat redeploy rc=!REDEPLOY_RC! - the trace-ON chat may still be live. Redeploy with KOI_DEBUG_TRACE=0. ***
  echo FAIL: no-trace chat redeploy rc=!REDEPLOY_RC! >> "%SUM%"
  set "KOI_TOKEN="
  set "WEBKEY="
  exit /b 3
)
set "KOI_TOKEN="
set "WEBKEY="
echo live run finished %date% %time% >> "%SUM%"
exit /b 0

:nokey
echo MISSING %KEYFILE% - nothing was run >> "%SUM%"
exit /b 2

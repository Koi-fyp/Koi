@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ===== Ahmad runs this. Deploys via run_live.bat (unchanged), then verifies the FINAL (trace-OFF) deploy. Never echoes secrets.
cd /d E:\Koi\Koi-App\repos\koi-ai-engine || exit /b 9
set "PY=E:\Setups\anaconda\envs\koivenv\python.exe"
set "GIT=C:\Program Files\Git\cmd\git.exe"
if not exist "%GIT%" set "GIT=git"
set "CURL=C:\Windows\System32\curl.exe"
set "T=deploy\modal\tools" & set "L=agent_tasks\reports\live" & set "O=agent_tasks\reports\live3"
if not exist "%O%" mkdir "%O%"
set "LOG=%O%\VERIFY.txt"
> "%LOG%" echo deploy_and_verify started %date% %time%
rem (1) refuse to deploy uncommitted code
set "DIRTY="
for /f "delims=" %%L in ('"%GIT%" status --porcelain -- deploy koi_policy docs') do (set "DIRTY=1" & >> "%LOG%" echo dirty: %%L)
if defined DIRTY (echo *** ABORT: uncommitted changes under deploy\ koi_policy\ docs\ - see %LOG% *** & exit /b 4)
rem (2) warm the previous deployments, (3) deploy + live checks with run_live.bat as-is
call :urls
if defined CHAT_URL call :warm "%CHAT_URL%"
if defined CRISIS_URL call :warm "%CRISIS_URL%"
call agent_tasks\run_live.bat
set "LIVE_RC=!errorlevel!"
>> "%LOG%" echo run_live rc=!LIVE_RC!
if not "!LIVE_RC!"=="0" (echo *** ABORT: run_live.bat rc=!LIVE_RC! - see %L%\SUMMARY.txt *** & exit /b 5)
rem (4) URLs of the FINAL deploy (same extract_url.py as run_live), warm, token (same step as run_live), smoke_only
call :urls
if not defined CHAT_URL (echo *** ABORT: no chat URL in %L%\20_chat_redeploy_no_trace.txt *** & exit /b 6)
if not defined CRISIS_URL (echo *** ABORT: no crisis URL in %L%\10_crisis_deploy.txt *** & exit /b 6)
>> "%LOG%" echo CHAT_URL=%CHAT_URL%& >> "%LOG%" echo CRISIS_URL=%CRISIS_URL%
call :warm "%CHAT_URL%" & call :warm "%CRISIS_URL%"
set "TOKFILE=%TEMP%\koi_tok.txt" & set "KOI_TOKEN=" & set "WEBKEY="
if exist "E:\Koi\secrets\firebase_web_api_key.txt" set /p WEBKEY=<"E:\Koi\secrets\firebase_web_api_key.txt"
if exist "%TOKFILE%" del "%TOKFILE%"
%PY% %T%\get_anon_token.py !WEBKEY! --token-file "%TOKFILE%" > "%O%\token_check.txt" 2>&1
set "WEBKEY="
if exist "%TOKFILE%" (set /p KOI_TOKEN=<"%TOKFILE%" & del "%TOKFILE%")
call agent_tasks\smoke_only.bat %CHAT_URL% %CRISIS_URL%
set "KOI_TOKEN="
xcopy /y /q agent_tasks\reports\live2\*.txt "%O%\" > nul
%PY% %T%\health_check.py %CHAT_URL% %CRISIS_URL% > "%O%\health_check.txt" 2>&1
rem (5) five verdict lines; trace_check counts only if THIS smoke_only run executed it (its SUMMARY is rewritten each run)
set "RAN=0" & findstr /c:"trace_check rc=" "%O%\SUMMARY.txt" > nul 2>&1 && set "RAN=1"
set "FAILS=0"
for %%N in (trace_absent greeting_delta spacing_full_text risk_present health) do (
  set "F=%O%\trace_check.txt" & set "V=FAIL"
  if "%%N"=="health" (set "F=%O%\health_check.txt" & set "RAN=1")
  if "!RAN!"=="1" (findstr /r /c:"^RESULT %%N  *PASS" "!F!" > nul 2>&1 && set "V=PASS")
  if "!V!"=="FAIL" set "FAILS=1"
  echo !V! %%N& >> "%LOG%" echo !V! %%N
)
if "!FAILS!"=="1" exit /b 1
exit /b 0
:urls
set "CHAT_URL=" & set "CRISIS_URL="
for /f "delims=" %%U in ('%PY% %T%\extract_url.py %L%\20_chat_redeploy_no_trace.txt 2^>nul') do set "CHAT_URL=%%U"
for /f "delims=" %%U in ('%PY% %T%\extract_url.py %L%\10_crisis_deploy.txt 2^>nul') do set "CRISIS_URL=%%U"
exit /b 0
:warm
for /l %%I in (1,1,4) do (
  "%CURL%" -s -L -f -o nul --max-time 240 "%~1/health" && exit /b 0
  ping -n 21 127.0.0.1 > nul
)
>> "%LOG%" echo warm FAILED after 4 tries: %~1
exit /b 0

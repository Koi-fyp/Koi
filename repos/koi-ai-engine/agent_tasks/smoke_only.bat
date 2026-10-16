@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~dp0.."
set "PY=E:\Setups\anaconda\envs\koivenv\python.exe"
set "OUT=%ROOT%\agent_tasks\reports\live2"
if not exist "%OUT%" mkdir "%OUT%"
set "SUM=%OUT%\SUMMARY.txt"
> "%SUM%" echo smoke-only started %date% %time%
set "CHAT_URL=%~1"
set "CRISIS_URL=%~2"
if "%CHAT_URL%"=="" for /f "tokens=1,* delims==" %%A in ('findstr /b "CHAT_URL=" "%ROOT%\agent_tasks\reports\live\SUMMARY.txt"') do set "CHAT_URL=%%B"
if "%CRISIS_URL%"=="" for /f "tokens=1,* delims==" %%A in ('findstr /b "CRISIS_URL=" "%ROOT%\agent_tasks\reports\live\SUMMARY.txt"') do set "CRISIS_URL=%%B"
if "%CHAT_URL%"=="" goto :missing
if "%CRISIS_URL%"=="" goto :missing
call :run "chat_ready" "%PY%" "%ROOT%\deploy\modal\tools\wait_ready.py" "%CHAT_URL%/health" 8 25
call :run "chat_auth_check" "%PY%" "%ROOT%\deploy\modal\tools\auth_check.py" "%CHAT_URL%" /api/v1/chat
call :run "smoke_chat" "%PY%" "%ROOT%\deploy\modal\smoke_chat.py" "%CHAT_URL%"
call :run "emotion_probe" "%PY%" "%ROOT%\deploy\modal\tools\emotion_probe.py" "%CHAT_URL%"
if defined KOI_TOKEN call :run "trace_check" "%PY%" "%ROOT%\deploy\modal\tools\trace_check.py" "%CHAT_URL%"
call :run "crisis_ready" "%PY%" "%ROOT%\deploy\modal\tools\wait_ready.py" "%CRISIS_URL%/health" 10 30
call :run "crisis_auth_check" "%PY%" "%ROOT%\deploy\modal\tools\auth_check.py" "%CRISIS_URL%" /api/v1/crisis
call :run "smoke_crisis" "%PY%" "%ROOT%\deploy\modal\tools\smoke_crisis.py" "%CRISIS_URL%"
>> "%SUM%" echo smoke-only finished %date% %time%
exit /b 0
:run
set "NAME=%~1"
shift
%* > "%OUT%\%NAME%.txt" 2>&1
set "RC=!errorlevel!"
>> "%SUM%" echo %NAME% rc=!RC!
exit /b 0
:missing
>> "%SUM%" echo missing CHAT_URL or CRISIS_URL; pass both as arguments or populate reports\live\SUMMARY.txt
exit /b 2

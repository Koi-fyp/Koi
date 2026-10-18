@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ===== Ahmad runs this. Deploys the SEPARATE CPU Modal app "koi-speech" (deploy\speech\speech_app.py).
rem PROPOSED, NOT DEPLOYED until Ahmad runs it. Run agent_tasks\upload_voices.bat first.
rem Never echoes secrets: the Firebase secret is referenced by name only (firebase-service-account) and the
rem Modal CLI reads its own token from your profile. Output goes to agent_tasks\reports\speech\deploy.txt.
rem Optional: set KOI_SPEECH_MIN_CONTAINERS=1 before running to keep one warm container (costs CPU time).
cd /d "%~dp0.." || exit /b 9
set "PY=E:\Setups\anaconda\envs\koivenv\python.exe"
set "GIT=C:\Program Files\Git\cmd\git.exe"
if not exist "%GIT%" set "GIT=git"
set "O=agent_tasks\reports\speech"
if not exist "%O%" mkdir "%O%"
rem refuse to deploy uncommitted speech code
set "DIRTY="
for /f "delims=" %%L in ('"%GIT%" status --porcelain -- deploy\speech') do (set "DIRTY=1" & echo dirty: %%L)
if defined DIRTY (echo *** ABORT: uncommitted changes under deploy\speech *** & exit /b 4)
"%PY%" -B -m pytest -p no:cacheprovider deploy\speech\test_speech_core.py -q > "%O%\pre_deploy_tests.txt" 2>&1
if errorlevel 1 (echo *** ABORT: speech tests failed - see %O%\pre_deploy_tests.txt *** & exit /b 5)
"%PY%" -m modal deploy deploy\speech\speech_app.py > "%O%\deploy.txt" 2>&1
set "RC=!errorlevel!"
type "%O%\deploy.txt"
echo deploy rc=!RC!  (look for the koi-speech ...modal.run URL above; RHUBARB_SHA256 WARNING means the zip was not verified)
echo next: set KOI_TOKEN, then  "%PY%" -B agent_tasks\acceptance\speech_smoke.py ^<URL^>
exit /b !RC!

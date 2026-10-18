@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ===== Ahmad runs this, once (re-run with --force to overwrite). Uploads the 4 Piper voices to Modal Volume "koi-voices".
rem Files land at the volume root as <id>.onnx and <id>.onnx.json; speech_app.py mounts the volume read-only at /voices.
rem PROPOSED, NOT DEPLOYED. Prints no secrets (the Modal CLI reads its own token from your profile).
cd /d "%~dp0.." || exit /b 9
set "PY=E:\Setups\anaconda\envs\koivenv\python.exe"
set "SRC=E:\Koi\voice-lab\voices"
set "FORCE="
if /i "%~1"=="--force" set "FORCE=--force"
set "MISSING="
for %%V in (ur_PK-fasih-medium ur_PK-aegis_female-medium en_US-hfc_male-medium en_US-hfc_female-medium) do (
  if not exist "%SRC%\%%V.onnx" (echo missing: %SRC%\%%V.onnx & set "MISSING=1")
  if not exist "%SRC%\%%V.onnx.json" (echo missing: %SRC%\%%V.onnx.json & set "MISSING=1")
)
if defined MISSING (echo *** ABORT: voice files missing *** & exit /b 4)
rem create fails harmlessly if the volume already exists
"%PY%" -m modal volume create koi-voices
for %%V in (ur_PK-fasih-medium ur_PK-aegis_female-medium en_US-hfc_male-medium en_US-hfc_female-medium) do (
  "%PY%" -m modal volume put %FORCE% koi-voices "%SRC%\%%V.onnx" /%%V.onnx || (echo *** put failed: %%V.onnx *** & exit /b 5)
  "%PY%" -m modal volume put %FORCE% koi-voices "%SRC%\%%V.onnx.json" /%%V.onnx.json || (echo *** put failed: %%V.onnx.json *** & exit /b 5)
)
"%PY%" -m modal volume ls koi-voices /
echo upload_voices done
exit /b 0

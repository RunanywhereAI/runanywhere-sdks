@echo off
rem Launch RunAnywhere AI (dev run, straight from the repo). The desktop shortcut
rem points here. Paths are relative to this file, so it works wherever the repo lives.
setlocal
rem ELECTRON_RUN_AS_NODE makes electron.exe behave as plain Node (no window) —
rem clear it, or the app silently never opens.
set "ELECTRON_RUN_AS_NODE="

set "APP=%~dp0"
set "REPO=%~dp0..\.."
set "ELECTRON=%REPO%\sdk\runanywhere-electron\node_modules\electron\dist\electron.exe"

rem Pass --gpu through to use the CUDA prebuild (needs an NVIDIA driver stack).
if not exist "%ELECTRON%" (
  echo Electron not found at "%ELECTRON%".
  echo Run: npm install   in sdk\runanywhere-electron
  pause
  exit /b 1
)

start "" "%ELECTRON%" "%APP%." %*

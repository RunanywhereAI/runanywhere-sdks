@echo off
rem Launch RunAnywhere AI (dev run, from this app folder). The desktop shortcut
rem points here. Paths are relative to this file, so it works wherever the app lives.
setlocal
rem ELECTRON_RUN_AS_NODE makes electron.exe behave as plain Node (no window) —
rem clear it, or the app silently never opens.
set "ELECTRON_RUN_AS_NODE="

set "APP=%~dp0"
rem This app's own Electron devDependency. Nothing outside this folder is read:
rem the SDK arrives from npm like any other dependency.
set "ELECTRON=%APP%node_modules\electron\dist\electron.exe"

rem Pass --gpu through to use the CUDA prebuild (needs an NVIDIA driver stack).
if not exist "%ELECTRON%" (
  echo Electron not found at "%ELECTRON%".
  echo Run: npm install
  pause
  exit /b 1
)

start "" "%ELECTRON%" "%APP%." %*

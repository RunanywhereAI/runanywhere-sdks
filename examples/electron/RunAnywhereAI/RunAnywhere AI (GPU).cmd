@echo off
rem Launch RunAnywhere AI on the NVIDIA GPU (CUDA build). Requires an NVIDIA GPU
rem with a current driver; falls back to CPU automatically if the CUDA prebuild
rem is missing. The desktop shortcut "RunAnywhere AI (GPU)" points here.
setlocal
rem ELECTRON_RUN_AS_NODE makes electron.exe behave as plain Node (no window).
set "ELECTRON_RUN_AS_NODE="

set "APP=%~dp0"
rem This app's own Electron devDependency. Nothing outside this folder is read:
rem the SDK arrives from npm like any other dependency.
set "ELECTRON=%APP%node_modules\electron\dist\electron.exe"

if not exist "%ELECTRON%" (
  echo Electron not found at "%ELECTRON%".
  echo Run: npm install
  pause
  exit /b 1
)

start "" "%ELECTRON%" "%APP%." --gpu %*

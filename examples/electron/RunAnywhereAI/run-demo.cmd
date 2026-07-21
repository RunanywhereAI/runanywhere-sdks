@echo off
rem Double-click to launch the RunAnywhere Electron demo.
rem Paths are relative to this file, so it works wherever the repo lives.
setlocal
rem Clear ELECTRON_RUN_AS_NODE — if set, Electron runs as plain Node (no window).
set "ELECTRON_RUN_AS_NODE="
rem %~dp0 is this file's folder (examples\electron\RunAnywhereAI\); repo root is 3 up.
set "REPO=%~dp0..\..\.."
set "RUNANYWHERE_NATIVE_PATH=%REPO%\sdk\runanywhere-electron\prebuilds\win32-x64\runanywhere_native.node"
cd /d "%REPO%"
echo Launching RunAnywhere demo...  (close this window to quit the app)
call npx electron examples/electron/RunAnywhereAI
if errorlevel 1 pause

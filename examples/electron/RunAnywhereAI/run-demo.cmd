@echo off
rem Double-click to launch the RunAnywhere Electron demo.
rem Paths are relative to this file, so it works wherever the repo lives.
setlocal
rem Clear ELECTRON_RUN_AS_NODE — if set, Electron runs as plain Node (no window).
set "ELECTRON_RUN_AS_NODE="
rem %~dp0 is this file's folder (examples\electron\RunAnywhereAI\); repo root is 3 up.
set "REPO=%~dp0..\..\.."
set "RUNANYWHERE_NATIVE_PATH=%REPO%\sdk\runanywhere-electron\prebuilds\win32-x64-vulkan\runanywhere_native.node"
set "ELECTRON_EXE=%REPO%\sdk\runanywhere-electron\node_modules\electron\dist\electron.exe"
if not exist "%RUNANYWHERE_NATIVE_PATH%" (
  echo Accelerated native addon not found at %RUNANYWHERE_NATIVE_PATH%
  echo Build and bundle the native addon first.
  pause
  exit /b 1
)
if not exist "%ELECTRON_EXE%" (
  echo Electron runtime not found at %ELECTRON_EXE%
  echo Install the SDK development dependencies first.
  pause
  exit /b 1
)
cd /d "%REPO%"
echo Launching RunAnywhere demo...  (close this window to quit the app)
"%ELECTRON_EXE%" examples/electron/RunAnywhereAI
if errorlevel 1 pause

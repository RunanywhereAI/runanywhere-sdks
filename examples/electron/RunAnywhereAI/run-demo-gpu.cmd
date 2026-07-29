@echo off
rem Double-click to launch the RunAnywhere demo with the accelerated build.
setlocal
set "ELECTRON_RUN_AS_NODE="
set "REPO=%~dp0..\..\.."
set "RUNANYWHERE_NATIVE_PATH=%REPO%\sdk\runanywhere-electron\prebuilds\win32-x64-vulkan\runanywhere_native.node"
set "ELECTRON_EXE=%REPO%\sdk\runanywhere-electron\node_modules\electron\dist\electron.exe"
if not exist "%RUNANYWHERE_NATIVE_PATH%" (
  echo Accelerated native addon not found.
  echo Build and bundle the Windows prebuild first.
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

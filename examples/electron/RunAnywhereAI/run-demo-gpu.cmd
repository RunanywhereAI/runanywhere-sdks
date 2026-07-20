@echo off
rem Double-click to launch the RunAnywhere demo on the NVIDIA GPU (CUDA build).
rem Requires the CUDA prebuild at prebuilds/win32-x64-cuda/ (build it with the
rem RAC_GPU_CUDA CMake flag; see the SDK README "Building for GPU").
setlocal
set "ELECTRON_RUN_AS_NODE="
set "REPO=%~dp0..\..\.."
set "RUNANYWHERE_NATIVE_PATH=%REPO%\sdk\runanywhere-electron\prebuilds\win32-x64-cuda\runanywhere_native.node"
if not exist "%RUNANYWHERE_NATIVE_PATH%" (
  echo GPU addon not found at %RUNANYWHERE_NATIVE_PATH%
  echo Build the CUDA prebuild first ^(see the SDK README^), or use run-demo.cmd for CPU.
  pause
  exit /b 1
)
cd /d "%REPO%"
echo Launching RunAnywhere demo on GPU (CUDA)...  (close this window to quit the app)
call npx electron examples/electron/RunAnywhereAI
if errorlevel 1 pause

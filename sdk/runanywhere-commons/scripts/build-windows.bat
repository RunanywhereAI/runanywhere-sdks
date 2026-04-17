@echo off
setlocal enabledelayedexpansion

set "BACKENDS=llamacpp"
set "CLEAN=0"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="all" set "BACKENDS=all"
if /I "%~1"=="llamacpp" set "BACKENDS=llamacpp"
if /I "%~1"=="onnx" set "BACKENDS=onnx"
if /I "%~1"=="--clean" set "CLEAN=1"
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
shift
goto parse_args

:usage
echo Usage: build-windows.bat [all^|llamacpp^|onnx] [--clean]
exit /b 0

:args_done
for %%I in ("%~dp0.") do set "SCRIPT_HOME=%%~fI"
set "ROOT=%SCRIPT_HOME%"
set "WINDOWS_SCRIPT_DIR=%ROOT%\scripts\windows"
set "BUILD_DIR=%ROOT%\build-windows-x64"
set "DIST_DIR=%ROOT%\dist\windows\x64"
set "BUILD_ONNX=OFF"
set "BUILD_LLAMA=OFF"

if /I "%BACKENDS%"=="all" (
  set "BUILD_ONNX=ON"
  set "BUILD_LLAMA=ON"
)
if /I "%BACKENDS%"=="onnx" set "BUILD_ONNX=ON"
if /I "%BACKENDS%"=="llamacpp" set "BUILD_LLAMA=ON"

if "%CLEAN%"=="1" (
  if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
  if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo ========================================
echo RunAnywhere Windows Build
echo ========================================
echo Root: %ROOT%
echo Backends: %BACKENDS%
echo Build Dir: %BUILD_DIR%
echo Dist Dir: %DIST_DIR%

if /I "%BUILD_ONNX%"=="ON" (
  echo Preparing Sherpa-ONNX Windows dependencies...
  call "%WINDOWS_SCRIPT_DIR%\download-sherpa-onnx.bat"
  if errorlevel 1 exit /b 1
)

cmake -S "%ROOT%" -B "%BUILD_DIR%" -G "Visual Studio 17 2022" -A x64 ^
  -DRAC_BUILD_SHARED=ON ^
  -DRAC_BUILD_BACKENDS=ON ^
  -DRAC_BACKEND_LLAMACPP=%BUILD_LLAMA% ^
  -DRAC_BUILD_VLM=%BUILD_LLAMA% ^
  -DRAC_VLM_USE_MTMD=%BUILD_LLAMA% ^
  -DRAC_BACKEND_ONNX=%BUILD_ONNX% ^
  -DRAC_BACKEND_RAG=OFF ^
  -DRAC_BUILD_PLATFORM=OFF ^
  -DRAC_BUILD_TESTS=OFF
if errorlevel 1 exit /b 1

cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 exit /b 1

if not exist "%BUILD_DIR%\Release\rac_commons.dll" (
  echo ERROR: rac_commons.dll was not produced.
  exit /b 1
)
copy /y "%BUILD_DIR%\Release\rac_commons.dll" "%DIST_DIR%\rac_commons.dll" >nul
if errorlevel 1 exit /b 1

if exist "%BUILD_DIR%\src\backends\llamacpp\Release\rac_backend_llamacpp.dll" (
  copy /y "%BUILD_DIR%\src\backends\llamacpp\Release\rac_backend_llamacpp.dll" "%DIST_DIR%\rac_backend_llamacpp.dll" >nul
)

if exist "%BUILD_DIR%\src\backends\onnx\Release\rac_backend_onnx.dll" (
  copy /y "%BUILD_DIR%\src\backends\onnx\Release\rac_backend_onnx.dll" "%DIST_DIR%\rac_backend_onnx.dll" >nul
)

if /I "%BUILD_ONNX%"=="ON" (
  for %%F in ("%ROOT%\third_party\sherpa-onnx-windows\bin\*.dll") do (
    if exist "%%~F" copy /y "%%~F" "%DIST_DIR%\" >nul
  )
  for %%F in ("%ROOT%\third_party\sherpa-onnx-windows\lib\*.dll") do (
    if exist "%%~F" copy /y "%%~F" "%DIST_DIR%\" >nul
  )
)

echo Build complete. Artifacts in %DIST_DIR%

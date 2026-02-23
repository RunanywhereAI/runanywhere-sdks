@echo off
setlocal enabledelayedexpansion
:: =============================================================================
:: RunAnywhere Commons - Windows Build Script
:: =============================================================================
::
:: Builds RACommons and selected backends for Windows (native MSVC).
::
:: USAGE:
::   scripts\build-windows.bat [options]
::
:: OPTIONS:
::   --skip-backends     Build RACommons only; do not build backend frameworks
::   --backend NAME      Build specific backend: llamacpp, onnx, all (default: all)
::                       - llamacpp: LLM text generation (GGUF models)
::                       - onnx:     STT/TTS/VAD (ONNX Runtime + Sherpa-ONNX)
::                       - all:      Both backends (default)
::   --clean             Remove build and dist directories before building
::   --release           Release build (default)
::   --debug             Debug build
::   --shared            Build shared libraries (DLL/.lib) - default for Windows
::   --static            Build static libraries (.lib only)
::   --package           Create release ZIP under dist\windows\packages
::   --generator NAME    CMake generator (e.g. Ninja, "Visual Studio 17 2022"). If omitted, CMake picks a default.
::   --arch ARCH         Architecture: x64, Win32, ARM64. Used only with Visual Studio generators. If omitted, not passed.
::   --verbose, -v      Verbose build output (cmake --build --verbose)
::   --help, -h          Show this help
::
:: OUTPUTS:
::   dist\windows\bin\   RACommons and backend DLLs (if shared)
::   dist\windows\lib\   Import libraries (.lib) and static libs
::   dist\windows\include\  Public headers
::
:: EXAMPLES:
::   REM Full build (all backends, Release, shared) - requires ONNX deps in third_party\
::   scripts\build-windows.bat
::
::   REM Build only LlamaCPP backend (no ONNX dependencies)
::   scripts\build-windows.bat --backend llamacpp
::
::   REM Build only RACommons (no backends)
::   scripts\build-windows.bat --skip-backends
::
::   REM Clean build with packaging
::   scripts\build-windows.bat --clean --package
::
::   REM Debug build with static libs
::   scripts\build-windows.bat --debug --static
::
::   REM Build with specific architecture
::   scripts\build-windows.bat --arch ARM64
::
:: PREREQUISITES:
::   - CMake in PATH
::   - A supported generator and toolchain (e.g. Visual Studio with C++ workload, or Ninja + cl in PATH).
::     If --generator is not set, CMake chooses a default; run from "Developer Command Prompt for VS" if using Ninja.
::   - For ONNX backend: Sherpa-ONNX and ONNX Runtime in third_party\ (see DEPENDENCIES above).
::
:: =============================================================================

:: -----------------------------------------------------------------------------
:: Resolve script and project directories
:: -----------------------------------------------------------------------------
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:\=/%"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "PROJECT_ROOT=%PROJECT_ROOT:\=/%"
set "BUILD_DIR=%PROJECT_ROOT%/build/windows"
set "DIST_DIR=%PROJECT_ROOT%/dist/windows"

:: -----------------------------------------------------------------------------
:: Default options (override via command-line)
:: -----------------------------------------------------------------------------
set "SKIP_BACKENDS=0"
set "BUILD_BACKEND=all"
set "CLEAN_BUILD=0"
set "BUILD_TYPE=Release"
set "BUILD_SHARED=1"
set "CREATE_PACKAGE=0"
set "CMAKE_GENERATOR="
set "CMAKE_ARCH="
set "VERBOSE=0"

:: -----------------------------------------------------------------------------
:: Parse command-line arguments
:: -----------------------------------------------------------------------------
:parse_loop
if "%~1"=="" goto parse_done
if /i "%~1"=="--skip-backends"  set "SKIP_BACKENDS=1" & shift & goto parse_loop
if /i "%~1"=="--backend"        set "BUILD_BACKEND=%~2" & shift & shift & goto parse_loop
if /i "%~1"=="--clean"          set "CLEAN_BUILD=1" & shift & goto parse_loop
if /i "%~1"=="--release"       set "BUILD_TYPE=Release" & shift & goto parse_loop
if /i "%~1"=="--debug"         set "BUILD_TYPE=Debug" & shift & goto parse_loop
if /i "%~1"=="--shared"        set "BUILD_SHARED=1" & shift & goto parse_loop
if /i "%~1"=="--static"        set "BUILD_SHARED=0" & shift & goto parse_loop
if /i "%~1"=="--package"       set "CREATE_PACKAGE=1" & shift & goto parse_loop
if /i "%~1"=="--generator"     set "CMAKE_GENERATOR=%~2" & shift & shift & goto parse_loop
if /i "%~1"=="--arch"          set "CMAKE_ARCH=%~2" & shift & shift & goto parse_loop
if /i "%~1"=="--verbose" set "VERBOSE=1" & shift & goto parse_loop
if /i "%~1"=="-v"        set "VERBOSE=1" & shift & goto parse_loop
if /i "%~1"=="--help"   goto show_help
if /i "%~1"=="-h"       goto show_help
echo [ERROR] Unknown option: %~1
echo [ERROR] Run with --help to see available options
echo.
exit /b 1
:parse_done
goto parse_ok

:show_help
echo RunAnywhere Commons - Windows Build
echo.
echo USAGE: scripts\build-windows.bat [options]
echo.
echo OPTIONS:
echo   --skip-backends   Build RACommons only
echo   --backend NAME    all ^| llamacpp ^| onnx  (default: all)
echo   --clean           Clean build and dist first
echo   --release         Release build (default)
echo   --debug           Debug build
echo   --shared          Shared libs / DLL (default)
echo   --static          Static libs only
echo   --package         Create ZIP under dist\windows\packages
echo   --generator NAME  CMake generator (auto-detect if omitted)
echo   --arch ARCH       x64 ^| Win32 ^| ARM64  (default: x64)
echo   --verbose, -v    Verbose build output
echo   --help, -h        Show this help
echo.
echo EXAMPLES:
echo   scripts\build-windows.bat                    # Full build (needs third_party deps)
echo   scripts\build-windows.bat --backend llamacpp # LlamaCPP only
echo   scripts\build-windows.bat --clean --package  # Clean build + ZIP
echo.
exit /b 0

:parse_ok

:: Validate backend name
set "BACKEND_VALID=0"
if /i "!BUILD_BACKEND!"=="all" set "BACKEND_VALID=1"
if /i "!BUILD_BACKEND!"=="llamacpp" set "BACKEND_VALID=1"
if /i "!BUILD_BACKEND!"=="onnx" set "BACKEND_VALID=1"

if "!BACKEND_VALID!"=="0" (
  echo [ERROR] Invalid --backend: !BUILD_BACKEND!
  echo [ERROR] Valid backend options are: all, llamacpp, onnx
  exit /b 1
)

:: Version (from VERSION file or default)
:: -----------------------------------------------------------------------------
set "VERSION=0.1.0"
if exist "%PROJECT_ROOT%\VERSION" (
  set /p VERSION=<"%PROJECT_ROOT%\VERSION"
  set "VERSION=!VERSION: =!"
)

:: -----------------------------------------------------------------------------
:: Log helpers (all comments in English)
:: -----------------------------------------------------------------------------
echo.
echo [RunAnywhere Commons - Windows Build]
echo Version:        %VERSION%
echo Build type:     %BUILD_TYPE%
echo Backends:       %BUILD_BACKEND%
echo Skip backends:   %SKIP_BACKENDS%
echo Shared libs:     %BUILD_SHARED%
echo Clean first:     %CLEAN_BUILD%
echo Create package:  %CREATE_PACKAGE%
echo Verbose:         %VERBOSE%
echo.

:: -----------------------------------------------------------------------------
:: Clean build and dist if requested
:: -----------------------------------------------------------------------------
if "%CLEAN_BUILD%"=="1" (
  echo [STEP] Cleaning build and dist directories...
  if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
  if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"
)

:: -----------------------------------------------------------------------------
:: Ensure dist layout exists (create after possible clean)
:: -----------------------------------------------------------------------------
set "DIST_BIN=%DIST_DIR%\bin"
set "DIST_LIB=%DIST_DIR%\lib"
set "DIST_INC=%DIST_DIR%\include"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
if not exist "%DIST_BIN%" mkdir "%DIST_BIN%"
if not exist "%DIST_LIB%" mkdir "%DIST_LIB%"
if not exist "%DIST_INC%" mkdir "%DIST_INC%"

:: -----------------------------------------------------------------------------
:: CMake generator and arch: only pass -G / -A when user explicitly set them
:: (do not assume install location e.g. C:\); let CMake choose default otherwise
:: -----------------------------------------------------------------------------
if "%CMAKE_GENERATOR%"=="" (
  echo [INFO] Generator: not set - CMake will choose default
) else (
  echo [INFO] Generator: %CMAKE_GENERATOR% %CMAKE_ARCH%
)

:: -----------------------------------------------------------------------------
:: Require cmake in PATH
:: -----------------------------------------------------------------------------
where cmake >nul 2>nul
if errorlevel 1 (
  echo [ERROR] cmake not found in PATH
  echo [ERROR] CMake is required to build this project
  echo.
  echo [ERROR] Troubleshooting steps:
  echo [ERROR]   1. Install CMake from: https://cmake.org/download/
  echo [ERROR]   2. Add CMake to your system PATH
  echo [ERROR]   3. Restart your terminal/command prompt
  echo [ERROR]   4. Verify installation: cmake --version
  echo.
  exit /b 1
)

:: -----------------------------------------------------------------------------
:: Build backend CMake flags (mirror iOS/Android script options)
:: -----------------------------------------------------------------------------
set "RAC_BUILD_BACKENDS=ON"
set "RAC_BACKEND_LLAMACPP=ON"
set "RAC_BACKEND_ONNX=ON"
set "RAC_BACKEND_WHISPERCPP=OFF"

if "%SKIP_BACKENDS%"=="1" (
  set "RAC_BUILD_BACKENDS=OFF"
  set "RAC_BACKEND_LLAMACPP=OFF"
  set "RAC_BACKEND_ONNX=OFF"
) else (
  if /i "%BUILD_BACKEND%"=="llamacpp" (
    set "RAC_BACKEND_LLAMACPP=ON"
    set "RAC_BACKEND_ONNX=OFF"
  )
  if /i "%BUILD_BACKEND%"=="onnx" (
    set "RAC_BACKEND_LLAMACPP=OFF"
    set "RAC_BACKEND_ONNX=ON"
  )
)

:: RAC_BUILD_SHARED: 1 -> ON, 0 -> OFF
set "RAC_SHARED_FLAG=OFF"
if "%BUILD_SHARED%"=="1" set "RAC_SHARED_FLAG=ON"

:: -----------------------------------------------------------------------------
:: Configure: run CMake with all RAC options
:: -----------------------------------------------------------------------------
echo [STEP] Configuring CMake...
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

set "CMAKE_ARGS=-DCMAKE_BUILD_TYPE=%BUILD_TYPE%"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BUILD_PLATFORM=OFF"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BUILD_JNI=OFF"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BUILD_TESTS=OFF"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BUILD_BACKENDS=%RAC_BUILD_BACKENDS%"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BACKEND_LLAMACPP=%RAC_BACKEND_LLAMACPP%"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BACKEND_ONNX=%RAC_BACKEND_ONNX%"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BACKEND_WHISPERCPP=%RAC_BACKEND_WHISPERCPP%"
set "CMAKE_ARGS=%CMAKE_ARGS% -DRAC_BUILD_SHARED=%RAC_SHARED_FLAG%"

:: Pass -G and -A only when user specified them; quote generator so names with spaces work
set "GEN_ARCH_ARGS="
if not "%CMAKE_GENERATOR%"=="" set "GEN_ARCH_ARGS=-G "%CMAKE_GENERATOR%""
if not "%CMAKE_ARCH%"=="" set "GEN_ARCH_ARGS=%GEN_ARCH_ARGS% -A %CMAKE_ARCH%"

cmake %CMAKE_ARGS% %GEN_ARCH_ARGS% "%PROJECT_ROOT%"
if %errorlevel% NEQ 0 (
  echo.
  echo [ERROR] CMake configure failed
  echo [ERROR] The CMake configuration step encountered an error
  echo [ERROR] For more details, check the CMake output above
  echo.
  cd /d "%SCRIPT_DIR%"
  exit /b 1
)

echo [OK] CMake configured.
echo.

:: -----------------------------------------------------------------------------
:: Build
:: -----------------------------------------------------------------------------
echo [STEP] Building...
set "BUILD_EXTRA="
if "%VERBOSE%"=="1" set "BUILD_EXTRA=--verbose"
cmake --build . --config %BUILD_TYPE% -j %BUILD_EXTRA%
if %errorlevel% NEQ 0 (
  echo.
  echo [ERROR] Build failed
  echo [ERROR] The compilation step encountered errors
  echo [ERROR] For more details, check the compiler output above
  echo.
  cd /d "%SCRIPT_DIR%"
  exit /b 1
)
echo [OK] Build succeeded.

:: -----------------------------------------------------------------------------
:: Copy artifacts to dist (multi-config generators use Build subdir)
:: -----------------------------------------------------------------------------
echo [STEP] Copying artifacts to dist...

set "BUILD_OUT="
if exist "%BUILD_DIR%\%BUILD_TYPE%" set "BUILD_OUT=%BUILD_DIR%\%BUILD_TYPE%"
if exist "%BUILD_DIR%\Release" set "BUILD_OUT=%BUILD_DIR%\Release"
if exist "%BUILD_DIR%\Debug" set "BUILD_OUT=%BUILD_DIR%\Debug"
if "%BUILD_OUT%"=="" set "BUILD_OUT=%BUILD_DIR%"

:: Copy DLLs to bin (root and backend subdirs for both Ninja and Visual Studio layouts)
if exist "%BUILD_OUT%\rac_commons.dll" copy /y "%BUILD_OUT%\rac_commons.dll" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\rac_backend_llamacpp.dll" copy /y "%BUILD_OUT%\rac_backend_llamacpp.dll" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\rac_backend_onnx.dll" copy /y "%BUILD_OUT%\rac_backend_onnx.dll" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\src\backends\llamacpp\rac_backend_llamacpp.dll" copy /y "%BUILD_OUT%\src\backends\llamacpp\rac_backend_llamacpp.dll" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\src\backends\onnx\rac_backend_onnx.dll" copy /y "%BUILD_OUT%\src\backends\onnx\rac_backend_onnx.dll" "%DIST_BIN%\" >nul

:: Copy import libs / static libs to lib
if exist "%BUILD_OUT%\rac_commons.lib" copy /y "%BUILD_OUT%\rac_commons.lib" "%DIST_LIB%\" >nul
if exist "%BUILD_OUT%\rac_backend_llamacpp.lib" copy /y "%BUILD_OUT%\rac_backend_llamacpp.lib" "%DIST_LIB%\" >nul
if exist "%BUILD_OUT%\rac_backend_onnx.lib" copy /y "%BUILD_OUT%\rac_backend_onnx.lib" "%DIST_LIB%\" >nul
if exist "%BUILD_OUT%\src\backends\llamacpp\rac_backend_llamacpp.lib" copy /y "%BUILD_OUT%\src\backends\llamacpp\rac_backend_llamacpp.lib" "%DIST_LIB%\" >nul
if exist "%BUILD_OUT%\src\backends\onnx\rac_backend_onnx.lib" copy /y "%BUILD_OUT%\src\backends\onnx\rac_backend_onnx.lib" "%DIST_LIB%\" >nul

:: PDB files (optional, for debugging)
if exist "%BUILD_OUT%\rac_commons.pdb" copy /y "%BUILD_OUT%\rac_commons.pdb" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\rac_backend_llamacpp.pdb" copy /y "%BUILD_OUT%\rac_backend_llamacpp.pdb" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\rac_backend_onnx.pdb" copy /y "%BUILD_OUT%\rac_backend_onnx.pdb" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\src\backends\llamacpp\rac_backend_llamacpp.pdb" copy /y "%BUILD_OUT%\src\backends\llamacpp\rac_backend_llamacpp.pdb" "%DIST_BIN%\" >nul
if exist "%BUILD_OUT%\src\backends\onnx\rac_backend_onnx.pdb" copy /y "%BUILD_OUT%\src\backends\onnx\rac_backend_onnx.pdb" "%DIST_BIN%\" >nul

:: Headers: rac and backends
if exist "%PROJECT_ROOT%\include\rac" (
  xcopy /e /i /y "%PROJECT_ROOT%\include\rac" "%DIST_INC%\rac" >nul
)
if exist "%PROJECT_ROOT%\include\*.h" (
  copy /y "%PROJECT_ROOT%\include\*.h" "%DIST_INC%\" >nul
)

echo [OK] Artifacts copied to %DIST_DIR%

:: -----------------------------------------------------------------------------
:: Create release package (ZIP) if requested
:: -----------------------------------------------------------------------------
if "%CREATE_PACKAGE%"=="1" (
  echo [STEP] Creating release package...
  set "PKG_DIR=%DIST_DIR%\packages"
  if not exist "%PKG_DIR%" mkdir "%PKG_DIR%"
  set "ZIP_NAME=RunAnywhereCommons-windows-%VERSION%.zip"
  set "ZIP_PATH=%PKG_DIR%\%ZIP_NAME%"
  :: Use PowerShell Compress-Archive to create ZIP (bin, lib, include as root entries)
  powershell -NoProfile -Command "Compress-Archive -Path '%DIST_BIN%','%DIST_LIB%','%DIST_INC%' -DestinationPath '%ZIP_PATH%' -Force"
  if exist "%ZIP_PATH%" (
    echo [OK] Package created: %ZIP_PATH%
  ) else (
    echo [WARN] Package creation failed; ensure PowerShell Compress-Archive is available.
  )
)

echo.
echo [Build Complete]
echo.
cd /d "%SCRIPT_DIR%"
endlocal
exit /b 0

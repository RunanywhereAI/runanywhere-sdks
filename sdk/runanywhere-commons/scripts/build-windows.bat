@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: build-windows.bat
:: Windows build script for runanywhere-commons (x64, MSVC)
::
:: Usage: build-windows.bat [options] [backends]
::        backends: onnx | llamacpp | all (default: all)
::                  - onnx: STT/TTS/VAD (ONNX Runtime)
::                  - llamacpp: LLM text generation (GGUF models)
::                  - all: onnx + llamacpp (default)
::
:: Options:
::   --clean     Clean build directory before building
::   --shared    Build shared libraries (default: static)
::   --test      Build and run tests
::   --help      Show this help message
::
:: Examples:
::   build-windows.bat                    Build all backends (static)
::   build-windows.bat --shared           Build all backends (shared)
::   build-windows.bat llamacpp           Build only LlamaCPP
::   build-windows.bat onnx              Build only ONNX backend
::   build-windows.bat --clean all        Clean build, all backends
::   build-windows.bat --test             Build all + run tests
::
:: Prerequisites:
::   - CMake 3.22+
::   - Visual Studio 2022 (or Build Tools) with C++ workload
:: =============================================================================

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%.."
set "BUILD_DIR=%ROOT_DIR%\build\windows-x64"
set "DIST_DIR=%ROOT_DIR%\dist\windows\x64"

:: =============================================================================
:: Load Versions
:: =============================================================================
call :load_versions

:: =============================================================================
:: Defaults
:: =============================================================================
set "CLEAN_BUILD=0"
set "BUILD_SHARED=OFF"
set "BUILD_TESTS=OFF"
set "RUN_TESTS=0"
set "BUILD_ONNX=OFF"
set "BUILD_LLAMACPP=OFF"
set "BACKENDS="

:: =============================================================================
:: Parse Options
:: =============================================================================
:parse_args
if "%~1"=="" goto :done_args
if "%~1"=="--clean" (
    set "CLEAN_BUILD=1"
    shift
    goto :parse_args
)
if "%~1"=="--shared" (
    set "BUILD_SHARED=ON"
    shift
    goto :parse_args
)
if "%~1"=="--test" (
    set "BUILD_TESTS=ON"
    set "RUN_TESTS=1"
    shift
    goto :parse_args
)
if "%~1"=="--help" goto :show_help
if "%~1"=="-h" goto :show_help

:: Must be a backend argument
set "BACKENDS=%~1"
shift
goto :parse_args

:done_args

:: Default backends = all
if "%BACKENDS%"=="" set "BACKENDS=all"

if "%BACKENDS%"=="all" (
    set "BUILD_ONNX=ON"
    set "BUILD_LLAMACPP=ON"
) else if "%BACKENDS%"=="onnx" (
    set "BUILD_ONNX=ON"
) else if "%BACKENDS%"=="llamacpp" (
    set "BUILD_LLAMACPP=ON"
) else (
    echo [ERROR] Unknown backend: %BACKENDS%
    echo Usage: %~nx0 [options] [onnx ^| llamacpp ^| all]
    exit /b 1
)

:: =============================================================================
:: Print Header
:: =============================================================================
echo.
echo ========================================
echo  RunAnywhere Windows Build
echo ========================================
echo.
echo  Architecture:  x64
echo  Backends:      ONNX=%BUILD_ONNX%, LlamaCPP=%BUILD_LLAMACPP%
if "%BUILD_SHARED%"=="ON" (echo  Library type:  Shared) else (echo  Library type:  Static)
echo  Tests:         %BUILD_TESTS%
echo  Build dir:     %BUILD_DIR%
echo  Dist dir:      %DIST_DIR%
echo.

:: =============================================================================
:: Prerequisites
:: =============================================================================
echo [CHECK] Checking prerequisites...

where cmake >nul 2>&1
if errorlevel 1 (
    echo [ERROR] cmake not found. Install CMake 3.22+ and add to PATH.
    exit /b 1
)
for /f "tokens=3" %%v in ('cmake --version 2^>^&1 ^| findstr /i "version"') do (
    echo [OK] Found cmake %%v
)

:: Check for Visual Studio
where cl >nul 2>&1
if errorlevel 1 (
    echo [WARN] cl.exe not in PATH. Attempting to find Visual Studio...
    call :find_vs
    if errorlevel 1 (
        echo [ERROR] Visual Studio 2022 with C++ workload not found.
        echo         Install from https://visualstudio.microsoft.com/
        exit /b 1
    )
)
echo [OK] MSVC compiler available

:: =============================================================================
:: Clean Build
:: =============================================================================
if "%CLEAN_BUILD%"=="1" (
    echo [CLEAN] Removing previous build...
    if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%" 2>nul
    if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%" 2>nul
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

:: =============================================================================
:: Configure
:: =============================================================================
echo.
echo ========================================
echo  Configuring CMake
echo ========================================
echo.

cmake -B "%BUILD_DIR%" ^
    -G "Visual Studio 17 2022" -A x64 ^
    -DRAC_BUILD_BACKENDS=ON ^
    -DRAC_BACKEND_ONNX=%BUILD_ONNX% ^
    -DRAC_BACKEND_LLAMACPP=%BUILD_LLAMACPP% ^
    -DRAC_BACKEND_WHISPERCPP=OFF ^
    -DRAC_BACKEND_RAG=ON ^
    -DRAC_BUILD_TESTS=%BUILD_TESTS% ^
    -DRAC_BUILD_SHARED=%BUILD_SHARED% ^
    -DRAC_BUILD_PLATFORM=OFF ^
    "%ROOT_DIR%"

if errorlevel 1 (
    echo [ERROR] CMake configure failed.
    exit /b 1
)
echo [OK] CMake configure complete

:: =============================================================================
:: Build
:: =============================================================================
echo.
echo ========================================
echo  Building
echo ========================================
echo.

cmake --build "%BUILD_DIR%" --config Release -- /m
if errorlevel 1 (
    echo [ERROR] Build failed.
    exit /b 1
)
echo [OK] Build complete

:: =============================================================================
:: Copy to Distribution Directory
:: =============================================================================
echo.
echo [DIST] Copying libraries to distribution directory...

if "%BUILD_SHARED%"=="ON" (set "LIB_EXT=dll") else (set "LIB_EXT=lib")

:: Core library
if exist "%BUILD_DIR%\Release\rac_commons.lib" (
    copy /y "%BUILD_DIR%\Release\rac_commons.lib" "%DIST_DIR%\" >nul
    echo [OK] Copied rac_commons.lib
)

:: ONNX backend
if "%BUILD_ONNX%"=="ON" (
    if exist "%BUILD_DIR%\src\backends\onnx\Release\rac_backend_onnx.lib" (
        copy /y "%BUILD_DIR%\src\backends\onnx\Release\rac_backend_onnx.lib" "%DIST_DIR%\" >nul
        echo [OK] Copied rac_backend_onnx.lib
    )
)

:: LlamaCPP backend
if "%BUILD_LLAMACPP%"=="ON" (
    if exist "%BUILD_DIR%\src\backends\llamacpp\Release\rac_backend_llamacpp.lib" (
        copy /y "%BUILD_DIR%\src\backends\llamacpp\Release\rac_backend_llamacpp.lib" "%DIST_DIR%\" >nul
        echo [OK] Copied rac_backend_llamacpp.lib
    )
)

:: Headers
echo [DIST] Copying headers...
if not exist "%DIST_DIR%\include" mkdir "%DIST_DIR%\include"
xcopy /s /y /q "%ROOT_DIR%\include\rac" "%DIST_DIR%\include\rac\" >nul
echo [OK] Copied headers

:: =============================================================================
:: Run Tests
:: =============================================================================
if "%RUN_TESTS%"=="1" (
    echo.
    echo ========================================
    echo  Running Tests
    echo ========================================
    echo.

    set "TEST_DIR=%BUILD_DIR%\tests\Release"
    set "TESTS_PASSED=0"
    set "TESTS_FAILED=0"

    for %%t in (test_core test_extraction test_download_orchestrator) do (
        if exist "!TEST_DIR!\%%t.exe" (
            echo --- %%t ---
            "!TEST_DIR!\%%t.exe" --run-all
            if errorlevel 1 (
                set /a TESTS_FAILED+=1
            ) else (
                set /a TESTS_PASSED+=1
            )
            echo.
        )
    )

    echo ========================================
    echo  Test Results: !TESTS_PASSED! passed, !TESTS_FAILED! failed
    echo ========================================
)

:: =============================================================================
:: Summary
:: =============================================================================
echo.
echo ========================================
echo  Build Complete!
echo ========================================
echo.
echo  Distribution: %DIST_DIR%
echo.
dir /b "%DIST_DIR%\*.lib" 2>nul
echo.
echo  To use in your project:
echo    Include: /I"%DIST_DIR%\include"
echo    Link:    /LIBPATH:"%DIST_DIR%" rac_commons.lib
echo.

exit /b 0

:: =============================================================================
:: Subroutines
:: =============================================================================

:show_help
echo Usage: %~nx0 [options] [backends]
echo.
echo Backends:
echo   onnx        STT/TTS/VAD (ONNX Runtime + Sherpa-ONNX)
echo   llamacpp    LLM text generation (GGUF models via llama.cpp)
echo   all         onnx + llamacpp (default)
echo.
echo Options:
echo   --clean     Clean build directory before building
echo   --shared    Build shared libraries (default: static)
echo   --test      Build and run tests
echo   --help      Show this help message
echo.
echo Examples:
echo   %~nx0                        Build all backends (static)
echo   %~nx0 --shared               Build all backends (shared)
echo   %~nx0 llamacpp               Build only LlamaCPP
echo   %~nx0 --clean --test all     Clean build, all backends, run tests
exit /b 0

:load_versions
:: Read VERSIONS file and set variables
set "VERSIONS_FILE=%ROOT_DIR%\VERSIONS"
if not exist "%VERSIONS_FILE%" (
    echo [ERROR] VERSIONS file not found at %VERSIONS_FILE%
    exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%a in ("%VERSIONS_FILE%") do (
    set "line=%%a"
    if not "!line:~0,1!"=="#" if not "%%a"=="" (
        set "%%a=%%b"
    )
)
goto :eof

:find_vs
:: Try to set up VS environment
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" exit /b 1
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH exit /b 1
if exist "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" (
    call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
    exit /b 0
)
exit /b 1

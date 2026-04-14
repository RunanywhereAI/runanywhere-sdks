@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: download-sherpa-onnx.bat
:: Download Sherpa-ONNX pre-built binaries for Windows x64
::
:: Usage: download-sherpa-onnx.bat [--force]
::
:: Options:
::   --force    Re-download even if already present
::
:: Prerequisites:
::   - curl (included in Windows 10+)
::   - tar  (included in Windows 10+)
:: =============================================================================

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%..\.."
set "DEST_DIR=%ROOT_DIR%\third_party\sherpa-onnx-windows"

:: Load versions
call :load_versions
if not defined SHERPA_ONNX_VERSION_WINDOWS set "SHERPA_ONNX_VERSION_WINDOWS=1.12.23"
set "VERSION=%SHERPA_ONNX_VERSION_WINDOWS%"

:: Parse options
set "FORCE=0"
if "%~1"=="--force" set "FORCE=1"
if "%~1"=="--help" goto :show_help
if "%~1"=="-h" goto :show_help

:: Check if already downloaded
if exist "%DEST_DIR%\lib" if "%FORCE%"=="0" (
    echo [OK] Sherpa-ONNX already downloaded at %DEST_DIR%
    echo      Use --force to re-download.
    exit /b 0
)

:: Determine URL
set "URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/v%VERSION%/sherpa-onnx-v%VERSION%-win-x64-shared.tar.bz2"
set "ARCHIVE_NAME=sherpa-onnx-v%VERSION%-win-x64-shared"

echo.
echo ========================================
echo  Downloading Sherpa-ONNX for Windows
echo ========================================
echo.
echo  Version:     %VERSION%
echo  URL:         %URL%
echo  Destination: %DEST_DIR%
echo.

:: Clean existing
if exist "%DEST_DIR%" (
    echo [CLEAN] Removing existing directory...
    rmdir /s /q "%DEST_DIR%" 2>nul
)

:: Create temp dir
set "TEMP_DL=%TEMP%\sherpa_onnx_dl_%RANDOM%"
mkdir "%TEMP_DL%" 2>nul

:: Download
echo [DOWNLOAD] Downloading Sherpa-ONNX v%VERSION%...
curl -L -o "%TEMP_DL%\sherpa-onnx.tar.bz2" "%URL%"
if errorlevel 1 (
    echo [ERROR] Download failed.
    rmdir /s /q "%TEMP_DL%" 2>nul
    exit /b 1
)

:: Extract
echo [EXTRACT] Extracting archive...
mkdir "%DEST_DIR%" 2>nul
tar -xjf "%TEMP_DL%\sherpa-onnx.tar.bz2" -C "%TEMP_DL%"
if errorlevel 1 (
    echo [ERROR] Extraction failed.
    rmdir /s /q "%TEMP_DL%" 2>nul
    exit /b 1
)

:: Move contents (strip top-level directory)
for /d %%d in ("%TEMP_DL%\sherpa-onnx-*") do (
    xcopy /s /y /q "%%d\*" "%DEST_DIR%\" >nul
)

:: Download C API headers if missing
if not exist "%DEST_DIR%\include\sherpa-onnx\c-api\c-api.h" (
    echo [DOWNLOAD] Downloading C API headers...
    mkdir "%DEST_DIR%\include\sherpa-onnx\c-api" 2>nul
    curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v%VERSION%/sherpa-onnx/c-api/c-api.h" ^
        -o "%DEST_DIR%\include\sherpa-onnx\c-api\c-api.h"
)

:: Cleanup temp
rmdir /s /q "%TEMP_DL%" 2>nul

:: Verify
echo [VERIFY] Checking installation...
set "VERIFY_OK=1"

if not exist "%DEST_DIR%\lib" (
    echo [ERROR] lib directory not found
    set "VERIFY_OK=0"
)
if not exist "%DEST_DIR%\include\sherpa-onnx\c-api\c-api.h" (
    echo [ERROR] C API header not found
    set "VERIFY_OK=0"
)

if "%VERIFY_OK%"=="0" (
    echo [ERROR] Verification failed.
    exit /b 1
)

:: Summary
echo.
echo [OK] Sherpa-ONNX v%VERSION% downloaded successfully!
echo.
echo  Libraries: %DEST_DIR%\lib\
dir /b "%DEST_DIR%\lib\*.lib" 2>nul
dir /b "%DEST_DIR%\lib\*.dll" 2>nul
echo.
echo  Headers: %DEST_DIR%\include\
echo.

exit /b 0

:: =============================================================================
:: Subroutines
:: =============================================================================

:show_help
echo Usage: %~nx0 [--force]
echo   --force    Re-download even if already present
exit /b 0

:load_versions
set "VERSIONS_FILE=%ROOT_DIR%\VERSIONS"
if not exist "%VERSIONS_FILE%" exit /b 1
for /f "usebackq tokens=1,* delims==" %%a in ("%VERSIONS_FILE%") do (
    set "line=%%a"
    if not "!line:~0,1!"=="#" if not "%%a"=="" set "%%a=%%b"
)
goto :eof

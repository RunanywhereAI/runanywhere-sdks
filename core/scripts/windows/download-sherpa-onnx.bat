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
set "REPOSITORY=%SHERPA_ONNX_REPO_DESKTOP%"
set "RELEASE_TAG=%SHERPA_ONNX_RELEASE_TAG_DESKTOP%"
set "SOURCE_COMMIT=%SHERPA_ONNX_COMMIT_DESKTOP%"
set "EXPECTED_SHA256=%SHERPA_ONNX_WINDOWS_X64_SHA256%"

:: Parse options
set "FORCE=0"
if "%~1"=="--force" set "FORCE=1"
if "%~1"=="--help" goto :show_help
if "%~1"=="-h" goto :show_help

:: Check if the exact pinned stack is already downloaded.
set "CACHE_VALID=0"
call :verify_provenance >nul 2>&1
if not errorlevel 1 set "CACHE_VALID=1"
if "%CACHE_VALID%"=="1" if "%FORCE%"=="0" (
    echo [OK] Exact Sherpa-ONNX stack already downloaded at %DEST_DIR%
    echo      Use --force to re-download.
    exit /b 0
)

:: Determine URL
set "ASSET_NAME=sherpa-onnx-v%VERSION%-win-x64-shared-rac-ort%ONNX_VERSION_WINDOWS%.tar.bz2"
set "URL=https://github.com/%REPOSITORY%/releases/download/%RELEASE_TAG%/%ASSET_NAME%"
set "ARCHIVE_NAME=%ASSET_NAME:.tar.bz2=%"

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

:: Download. GitHub release assets 503 / REFUSED_STREAM on Windows HTTP/2
:: (schannel). Force HTTP/1.1 and wrap curl's retries in an outer backoff.
echo [DOWNLOAD] Downloading Sherpa-ONNX v%VERSION%...
set "ATTEMPT=0"
:download_retry
set /a ATTEMPT+=1
echo [DOWNLOAD] attempt %ATTEMPT%/8
curl -L --fail --show-error --http1.1 --connect-timeout 30 --max-time 900 --retry 3 ^
    --retry-delay 5 --retry-all-errors -o "%TEMP_DL%\sherpa-onnx.tar.bz2" "%URL%"
if errorlevel 1 (
    if %ATTEMPT% LSS 8 (
        echo [DOWNLOAD] retrying after 8s...
        timeout /t 8 /nobreak >nul
        goto download_retry
    )
    echo [ERROR] Download failed for %URL%
    rmdir /s /q "%TEMP_DL%" 2>nul
    exit /b 1
)

:: Guard against a truncated or HTML/error body slipping past curl.
set "DL_SIZE=0"
for %%A in ("%TEMP_DL%\sherpa-onnx.tar.bz2") do set "DL_SIZE=%%~zA"
if %DL_SIZE% LSS 1000000 (
    echo [ERROR] Downloaded archive is only %DL_SIZE% bytes; expected a multi-MB tarball.
    rmdir /s /q "%TEMP_DL%" 2>nul
    exit /b 1
)

for /f %%H in ('powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%TEMP_DL%\sherpa-onnx.tar.bz2').Hash.ToLower()"') do set "ACTUAL_SHA256=%%H"
if /i not "%ACTUAL_SHA256%"=="%EXPECTED_SHA256%" (
    echo [ERROR] Archive SHA-256 mismatch: expected %EXPECTED_SHA256%, got %ACTUAL_SHA256%
    rmdir /s /q "%TEMP_DL%" 2>nul
    exit /b 1
)
echo [OK] Verified archive SHA-256: %ACTUAL_SHA256%

:: Extract. Windows' bundled bsdtar hangs indefinitely decompressing .tar.bz2
:: on CI (its bzip2 filter stalls with no console), so use 7-Zip — preinstalled
:: on GitHub windows runners — to turn .tar.bz2 into a plain .tar, then plain
:: tar (no bzip2) to lay it down, dropping the archive's top-level directory.
:: -y answers any 7-Zip prompt so it can never block on stdin.
echo [EXTRACT] Decompressing (7-Zip)...
mkdir "%DEST_DIR%" 2>nul
7z x -y "%TEMP_DL%\sherpa-onnx.tar.bz2" -o"%TEMP_DL%"
if errorlevel 1 (
    echo [ERROR] 7-Zip bzip2 decompression failed.
    rmdir /s /q "%TEMP_DL%" 2>nul
    exit /b 1
)
echo [EXTRACT] Unpacking tar...
tar -xf "%TEMP_DL%\sherpa-onnx.tar" --strip-components=1 -C "%DEST_DIR%"
if errorlevel 1 (
    echo [ERROR] Extraction failed.
    rmdir /s /q "%TEMP_DL%" 2>nul
    exit /b 1
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
if not exist "%DEST_DIR%\PROVENANCE.txt" (
    echo [ERROR] Release provenance file not found
    set "VERIFY_OK=0"
) else (
    call :verify_provenance
    if errorlevel 1 (
        echo [ERROR] Release provenance does not match the pinned runtime stack
        set "VERIFY_OK=0"
    )
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

:verify_provenance
if not exist "%DEST_DIR%\PROVENANCE.txt" exit /b 1
powershell -NoProfile -Command "$lines = [IO.File]::ReadAllLines((Join-Path $env:DEST_DIR 'PROVENANCE.txt')); if (($lines -notcontains ('sherpa_onnx_version=' + $env:VERSION)) -or ($lines -notcontains ('runanywhere_source_commit=' + $env:SOURCE_COMMIT)) -or ($lines -notcontains ('onnxruntime_version=' + $env:ONNX_VERSION_WINDOWS))) { exit 1 }"
exit /b %errorlevel%

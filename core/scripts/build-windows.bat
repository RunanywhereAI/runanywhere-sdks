@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: build-windows.bat
:: Windows build script for runanywhere-commons (x64, MSVC)
::
:: Produces the SHARED release shape via the windows-x64-shared-release preset:
:: rac_commons.dll + rac_backend_<id>.dll + runanywhere_<id>.dll carriers, staged
:: into core/dist/windows/x64/{lib,include}. Fails closed if any expected
:: artifact is missing.
::
:: Usage: build-windows.bat [options] [backends]
::        backends: onnx | llamacpp | sherpa | all (default: all)
::                  - onnx:     embeddings / segmentation / diarization
::                  - llamacpp: LLM + VLM text generation (GGUF models)
::                  - sherpa:   STT / TTS / VAD  (needs the prefetched prebuilt,
::                              see core\scripts\windows\download-sherpa-onnx.bat)
::                  - all: onnx + llamacpp + sherpa (default)
::
:: Options:
::   --clean     Clean build directory before building
::   --test      Build and run tests
::   --help      Show this help message
::
:: Examples:
::   build-windows.bat                    Build all backends (shared)
::   build-windows.bat llamacpp           Build only LlamaCPP
::   build-windows.bat onnx               Build only ONNX backend
::   build-windows.bat sherpa             Build only Sherpa (STT/TTS/VAD)
::   build-windows.bat --clean all        Clean build, all backends
::   build-windows.bat --test             Build all + run tests
::
:: Prerequisites:
::   - CMake 3.24+
::   - Visual Studio 2022 (or Build Tools) with C++ workload
:: =============================================================================

:: REPO_ROOT, not core/. This is THE bug that shipped a commons-only Windows
:: bundle with zero engines through 0.20.25: this script used to configure
:: core/CMakeLists.txt, which is a standalone project(RunAnywhereCommons) that
:: never calls add_subdirectory(engines) — only the REPO-ROOT CMakeLists.txt
:: does. So no engine target was ever created, every backend copy below was a
:: silent no-op, and the script still exited 0.
set "SCRIPT_DIR=%~dp0"
set "COMMONS_DIR=%SCRIPT_DIR%.."
set "REPO_ROOT=%SCRIPT_DIR%..\.."
:: Owned by the windows-x64-shared-release preset's binaryDir.
set "BUILD_DIR=%REPO_ROOT%\build\windows-x64-shared-release"
:: Stays under core/ — release.yml zips core/dist/windows.
set "DIST_DIR=%COMMONS_DIR%\dist\windows\x64"

:: =============================================================================
:: Load Versions
:: =============================================================================
call :load_versions

:: =============================================================================
:: Defaults
:: =============================================================================
set "CLEAN_BUILD=0"
set "BUILD_TESTS=OFF"
set "RUN_TESTS=0"
set "BUILD_ONNX=OFF"
set "BUILD_LLAMACPP=OFF"
set "BUILD_SHERPA=OFF"
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
    set "BUILD_SHERPA=ON"
) else if "%BACKENDS%"=="onnx" (
    set "BUILD_ONNX=ON"
) else if "%BACKENDS%"=="llamacpp" (
    set "BUILD_LLAMACPP=ON"
) else if "%BACKENDS%"=="sherpa" (
    set "BUILD_SHERPA=ON"
) else (
    echo [ERROR] Unknown backend: %BACKENDS%
    echo Usage: %~nx0 [options] [onnx ^| llamacpp ^| sherpa ^| all]
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
echo  Backends:      ONNX=%BUILD_ONNX%, LlamaCPP=%BUILD_LLAMACPP%, Sherpa=%BUILD_SHERPA%
echo  Library type:  Shared ^(rac_commons.dll + plugin DLLs^)
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
    echo [ERROR] cmake not found. Install CMake %MIN_CMAKE_VERSION%+ and add to PATH.
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

:: Drive the preset rather than hand-rolling flags. The preset is rooted at the
:: repo root (so add_subdirectory(engines) runs) and carries the proven
:: electron-windows flag set: RAC_BUILD_SHARED=ON + RAC_STATIC_PLUGINS=OFF,
:: which is what produces rac_backend_<id>.dll AND the runanywhere_<id>.dll
:: carriers. Narrowed backend selections are expressed as -D overrides ON TOP
:: of the preset, never by dropping it.
pushd "%REPO_ROOT%" >nul
cmake --preset windows-x64-shared-release ^
    -DRAC_BACKEND_ONNX=%BUILD_ONNX% ^
    -DRAC_BACKEND_LLAMACPP=%BUILD_LLAMACPP% ^
    -DRAC_BACKEND_SHERPA=%BUILD_SHERPA% ^
    -DRAC_BUILD_TESTS=%BUILD_TESTS%
if errorlevel 1 (
    popd >nul
    echo [ERROR] CMake configure failed.
    exit /b 1
)
popd >nul
echo [OK] CMake configure complete

:: =============================================================================
:: Build
:: =============================================================================
echo.
echo ========================================
echo  Building
echo ========================================
echo.

:: Named targets, mirroring the proven electron-windows job — NOT the default ALL
:: target. Building ALL also builds runanywhere_cloud, which does not link on
:: MSVC: "unresolved external symbol g_cloud_stt_ops". That is the same PE
:: data-symbol problem documented for QHexRT in bindings/electron/AGENTS.md
:: (a carrier referencing an op table as DATA needs __declspec(dllimport) on the
:: shared declaration). Linux gets cloud for free; Windows cannot ship it until
:: that is fixed, so RAC_BACKEND_CLOUD=OFF in the preset and cloud is absent here.
set "BUILD_TARGETS=rac_commons"
if "%BUILD_LLAMACPP%"=="ON" set "BUILD_TARGETS=!BUILD_TARGETS! runanywhere_llamacpp"
if "%BUILD_ONNX%"=="ON"     set "BUILD_TARGETS=!BUILD_TARGETS! runanywhere_onnx"
if "%BUILD_SHERPA%"=="ON"   set "BUILD_TARGETS=!BUILD_TARGETS! runanywhere_sherpa"
echo [BUILD] targets: !BUILD_TARGETS!
cmake --build "%BUILD_DIR%" --config Release --target !BUILD_TARGETS! -- /m
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

:: Blanket glob + hard gates, ported from core/scripts/build-linux.sh:43-73.
:: NEVER name a per-backend output path again: the previous version hardcoded
:: %BUILD_DIR%\src\backends\<id>\Release\, a layout that stopped existing when
:: the engines moved to the top-level engines/ tree. Every copy was `if exist`
:: -guarded, so all six became silent no-ops and the release shipped a
:: commons-only zip for multiple versions with CI fully green.
rmdir /s /q "%DIST_DIR%" 2>nul
mkdir "%DIST_DIR%\lib" 2>nul
mkdir "%DIST_DIR%\include" 2>nul

echo [DIST] Staging DLLs + import libs from the build tree...
for /r "%BUILD_DIR%" %%f in (rac_commons*.dll rac_backend_*.dll runanywhere_*.dll) do (
    copy /y "%%f" "%DIST_DIR%\lib\" >nul && echo   + %%~nxf
)
for /r "%BUILD_DIR%" %%f in (rac_commons*.lib rac_backend_*.lib runanywhere_*.lib) do (
    copy /y "%%f" "%DIST_DIR%\lib\" >nul && echo   + %%~nxf
)
:: onnxruntime*.dll live under %BUILD_DIR%\_deps\onnxruntime-src\lib and are
:: swept by this same glob; sherpa's vendor runtime is NOT in the build tree.
for /r "%BUILD_DIR%" %%f in (onnxruntime*.dll) do (
    copy /y "%%f" "%DIST_DIR%\lib\" >nul && echo   + %%~nxf
)
if "%BUILD_SHERPA%"=="ON" (
    if exist "%COMMONS_DIR%\third_party\sherpa-onnx-windows\lib\sherpa-onnx-c-api.dll" (
        copy /y "%COMMONS_DIR%\third_party\sherpa-onnx-windows\lib\sherpa-onnx-c-api.dll" "%DIST_DIR%\lib\" >nul
        echo   + sherpa-onnx-c-api.dll
    ) else (
        echo [ERROR] sherpa-onnx-c-api.dll missing. Run core\scripts\windows\download-sherpa-onnx.bat
        echo         first, or sherpa builds as a NON-ROUTABLE stub.
        exit /b 1
    )
)

:: Duplicate-basename visibility (build-linux.sh hard-fails here; this only warns).
:: The recursive glob can find the same file name in two build subtrees and
:: `copy /y` silently keeps the last. Warning rather than failing because CMake
:: legitimately copies vendor runtimes beside targets, and a false hard-fail here
:: would block the whole release train.
for /f %%n in ('powershell -NoProfile -Command "$d=Get-ChildItem -Path '%BUILD_DIR%' -Recurse -File -Include rac_commons*.dll,rac_backend_*.dll,runanywhere_*.dll,onnxruntime*.dll ^| Group-Object Name ^| Where-Object Count -gt 1; if ($d) { $d ^| ForEach-Object { Write-Host ('  DUPLICATE: ' + $_.Name + ' x' + $_.Count) } }; ($d ^| Measure-Object).Count"') do set "DUPES=%%n"
if not "!DUPES!"=="0" (
    echo [WARN]  !DUPES! duplicate basename^(s^) above; `copy /y` keeps the last one.
    echo         Expected for vendor runtimes CMake copies beside targets. Promote this
    echo         to a hard failure once real CI output confirms which are benign.
)

:: Private-engine leak guard (mirrors build-linux.sh) — qhexrt/QNN must never
:: reach a public bundle.
for /r "%DIST_DIR%\lib" %%f in (*qhexrt* *qnn* *Qnn*) do (
    echo [ERROR] private engine artifact leaked into the public bundle: %%~nxf
    exit /b 1
)

:: Headers
echo [DIST] Copying headers...
xcopy /s /y /q "%COMMONS_DIR%\include\rac" "%DIST_DIR%\include\rac\" >nul
echo [OK] Copied headers

:: =============================================================================
:: FAIL CLOSED — assert every expected artifact is present.
:: Without this the bundle can ship hollow and nothing notices (see above).
:: =============================================================================
echo.
echo [VERIFY] Asserting required artifacts...
set "MISSING=0"
call :require rac_commons.dll
if "%BUILD_LLAMACPP%"=="ON" (
    call :require rac_backend_llamacpp.dll
    call :require runanywhere_llamacpp.dll
)
if "%BUILD_ONNX%"=="ON" (
    call :require rac_backend_onnx.dll
    call :require runanywhere_onnx.dll
    call :require onnxruntime.dll
)
if "%BUILD_SHERPA%"=="ON" (
    call :require rac_backend_sherpa.dll
    call :require runanywhere_sherpa.dll
    call :require sherpa-onnx-c-api.dll
)
if not "!MISSING!"=="0" (
    echo [ERROR] !MISSING! required artifact^(s^) missing from %DIST_DIR%\lib — refusing to
    echo         produce a hollow Windows bundle. This is the failure the release
    echo         pipeline silently shipped before this gate existed.
    exit /b 1
)
echo [OK] all required artifacts present

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

    if !TESTS_FAILED! GTR 0 (
        echo [ERROR] !TESTS_FAILED! test suite^(s^) failed.
        exit /b 1
    )
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
dir /b "%DIST_DIR%\lib" 2>nul
echo.
echo  To use in your project:
echo    Include: /I"%DIST_DIR%\include"
echo    Link:    /LIBPATH:"%DIST_DIR%\lib" rac_commons.lib
echo    Runtime: copy %DIST_DIR%\lib\*.dll beside your executable
echo.

exit /b 0

:: =============================================================================
:: Subroutines
:: =============================================================================

:show_help
echo Usage: %~nx0 [options] [backends]
echo.
echo Backends:
echo   onnx        embeddings / segmentation / diarization (ONNX Runtime)
echo   llamacpp    LLM + VLM text generation (GGUF models via llama.cpp)
echo   sherpa      STT / TTS / VAD (needs download-sherpa-onnx.bat first)
echo   all         onnx + llamacpp + sherpa (default)
echo.
echo Options:
echo   --clean     Clean build directory before building
echo   --test      Build and run tests
echo   --help      Show this help message
echo.
echo Examples:
echo   %~nx0                        Build all backends (shared)
echo   %~nx0 llamacpp               Build only LlamaCPP
echo   %~nx0 --clean --test all     Clean build, all backends, run tests
exit /b 0

:require
:: Assert one artifact exists in DIST_DIR\lib; increments MISSING if not.
:: Called only from the fail-closed verify block.
if not exist "%DIST_DIR%\lib\%~1" (
    echo   [MISSING] %~1
    set /a MISSING+=1
) else (
    echo   [ok] %~1
)
goto :eof

:load_versions
:: Read VERSIONS file and set variables
:: core/VERSIONS — COMMONS_DIR, not REPO_ROOT (ROOT_DIR was split into the two).
set "VERSIONS_FILE=%COMMONS_DIR%\VERSIONS"
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

@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
where bash >nul 2>nul
if errorlevel 1 (
    echo error: bash not found on PATH. Install Git Bash or WSL.>&2
    exit /b 2
)
bash "%SCRIPT_DIR%run" %*

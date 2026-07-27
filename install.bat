@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

:: ============================================================
::  Sinapsis v4.9 — Installer for Windows
::  Skills on Demand for Claude Code
::  https://github.com/Luispitik/sinapsis
:: ============================================================

set "CLAUDE_HOME=%USERPROFILE%\.claude"
set "SKILLS_DIR=%CLAUDE_HOME%\skills"
set "LIBRARY_DIR=%SKILLS_DIR%\_library"
set "ARCHIVED_DIR=%SKILLS_DIR%\_archived"
set "COMMANDS_DIR=%CLAUDE_HOME%\commands"
set "HOMUNCULUS_DIR=%CLAUDE_HOME%\homunculus\projects"
set "SCRIPT_DIR=%~dp0"

echo.
echo ============================================================
echo   Sinapsis v4.9 -- Skills on Demand for Claude Code
echo   The system that learns and adapts to you
echo ============================================================
echo.

:: Detect upgrade vs fresh install
set "UPGRADING=false"
if exist "%SKILLS_DIR%\_catalog.json" set "UPGRADING=true"

:: Step 1: Check prerequisites
echo [1/8] Checking prerequisites...

where claude >nul 2>&1
if %errorlevel% neq 0 (
    echo   ! Claude Code not found in PATH
    echo     Install it first: https://claude.ai/code
    echo     Continuing anyway...
) else (
    echo   OK Claude Code detected
)

where node >nul 2>&1
if %errorlevel% neq 0 (
    echo   ERROR: Node.js not found.
    echo          Sinapsis hooks require Node.js.
    echo          Install it: https://nodejs.org
    pause
    exit /b 1
) else (
    for /f "tokens=*" %%v in ('node --version') do echo   OK Node.js %%v detected
)

:: v4.8.1 (audit finding #3 + review): the old check trusted `where python3`, but on
:: Windows that resolves to the Microsoft Store shim -- it answers `where` yet does
:: not execute, so the shim's notice was printed as "OK ... detected" and the real
:: warning never showed. Mirror install.sh: try `py -3` first (the real launcher),
:: then `python`, and only accept a command whose --version reports "Python 3.".
:: Also uses !errorlevel! -- %errorlevel% inside a parenthesised block is stale.
set "PY_VER="
for /f "delims=" %%v in ('py -3 --version 2^>^&1') do set "PY_VER=%%v"
echo(!PY_VER!| findstr /C:"Python 3." >nul 2>&1
if !errorlevel! equ 0 (
    echo   OK !PY_VER! detected
) else (
    set "PY_VER="
    for /f "delims=" %%v in ('python --version 2^>^&1') do set "PY_VER=%%v"
    echo(!PY_VER!| findstr /C:"Python 3." >nul 2>&1
    if !errorlevel! equ 0 (
        echo   OK !PY_VER! detected
    ) else (
        echo   ! Python 3 not found -- observation hooks will be disabled
        echo     Install it: https://python.org (optional but recommended^)
    )
)

if exist "%CLAUDE_HOME%" (
    echo   OK .claude\ exists
) else (
    echo   -- Creating .claude\
    mkdir "%CLAUDE_HOME%"
)

:: Step 2: Backup if upgrading
echo [2/8] Checking for existing installation...

:: v4.8.1: wmic is deprecated and removed in Windows 11 24H2+ -- use PowerShell.
:: Comment kept outside the block: :: inside parentheses breaks cmd.exe parsing.
if "%UPGRADING%"=="true" (
    echo   ! Existing installation detected -- creating backup
    for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "dt=%%I"
    set "BACKUP_DIR=%CLAUDE_HOME%\_backup_!dt!"
    mkdir "!BACKUP_DIR!" 2>nul
    xcopy "%SKILLS_DIR%" "!BACKUP_DIR!\skills_backup\" /E /I /Q >nul 2>&1
    xcopy "%COMMANDS_DIR%" "!BACKUP_DIR!\commands_backup\" /E /I /Q >nul 2>&1
    echo   OK Backup saved to !BACKUP_DIR!
) else (
    echo   OK Fresh install
)

:: Step 3: Create directory structure
echo [3/8] Creating directory structure...

if not exist "%SKILLS_DIR%" mkdir "%SKILLS_DIR%"
if not exist "%LIBRARY_DIR%" mkdir "%LIBRARY_DIR%"
if not exist "%ARCHIVED_DIR%" mkdir "%ARCHIVED_DIR%"
if not exist "%COMMANDS_DIR%" mkdir "%COMMANDS_DIR%"
if not exist "%CLAUDE_HOME%\projects" mkdir "%CLAUDE_HOME%\projects"
if not exist "%HOMUNCULUS_DIR%" mkdir "%HOMUNCULUS_DIR%"
if not exist "%SKILLS_DIR%\_daily-summaries" mkdir "%SKILLS_DIR%\_daily-summaries"
type nul > "%CLAUDE_HOME%\homunculus\.last-learn" 2>nul

echo   OK Directories created

:: Step 4: Copy core config files
echo [4/8] Installing core config files...

:: Parse --force-update flag
set "FORCE_UPDATE=false"
for %%a in (%*) do (
    if "%%a"=="--force-update" set "FORCE_UPDATE=true"
)

:: Catalog always updates (system file, not user data)
copy /Y "%SCRIPT_DIR%core\_catalog.json" "%SKILLS_DIR%\_catalog.json" >nul

:: User data files: preserve on upgrade, only create if missing
:: Bug #9 fix: unconditional copy destroyed learned instincts, custom rules, and project registry
for %%f in (_passive-rules.json _sinapsis-projects.json _instincts-index.json) do (
    if "!FORCE_UPDATE!"=="true" (
        copy /Y "%SCRIPT_DIR%core\%%f" "%SKILLS_DIR%\%%f" >nul
        echo   !  %%f force-updated (--force-update^)
    ) else if not exist "%SKILLS_DIR%\%%f" (
        copy /Y "%SCRIPT_DIR%core\%%f" "%SKILLS_DIR%\%%f" >nul
    ) else (
        echo   -- %%f preserved (user data^)
    )
)

if not exist "%SKILLS_DIR%\_operator-state.json" (
    copy /Y "%SCRIPT_DIR%core\_operator-state.template.json" "%SKILLS_DIR%\_operator-state.json" >nul
    echo   OK Operator state created
) else (
    echo   -- Existing operator state preserved
)

if not exist "%CLAUDE_HOME%\CLAUDE.md" (
    copy /Y "%SCRIPT_DIR%core\CLAUDE.md.template" "%CLAUDE_HOME%\CLAUDE.md" >nul
    echo   OK CLAUDE.md created
) else (
    echo   ! CLAUDE.md already exists - not overwritten
    echo     Check core\CLAUDE.md.template for updates
)

echo   OK Core config files installed

:: Step 5: Copy hook scripts
echo [5/8] Installing hook scripts...

copy /Y "%SCRIPT_DIR%core\_passive-activator.sh" "%SKILLS_DIR%\_passive-activator.sh" >nul
copy /Y "%SCRIPT_DIR%core\_instinct-activator.sh" "%SKILLS_DIR%\_instinct-activator.sh" >nul
copy /Y "%SCRIPT_DIR%core\_session-learner.sh" "%SKILLS_DIR%\_session-learner.sh" >nul
copy /Y "%SCRIPT_DIR%core\_project-context.sh" "%SKILLS_DIR%\_project-context.sh" >nul
copy /Y "%SCRIPT_DIR%core\_eod-gather.sh" "%SKILLS_DIR%\_eod-gather.sh" >nul
copy /Y "%SCRIPT_DIR%core\_dream.sh" "%SKILLS_DIR%\_dream.sh" >nul
copy /Y "%SCRIPT_DIR%core\_precompact-guard.sh" "%SKILLS_DIR%\_precompact-guard.sh" >nul

:: NOTE (v4.8.0): the team layer (Plexus) lives in the private team edition.
:: This installer neither installs nor removes _plexus-sync.sh / plexus.md.

echo   OK 6 hook scripts + dream cycle installed
echo   NOTE: On Windows, hooks run via Git Bash or WSL. See README for details.

:: Step 6: Configure settings.json
echo [6/8] Configuring hooks in settings.json...

:: v4.8.1 (audit finding #1): the old behaviour registered nothing when the file
:: already existed. _merge-hooks.js creates it when missing, otherwise deep-merges
:: (dedup by command, existing entries preserved, malformed file left untouched).
node "%SCRIPT_DIR%core\_merge-hooks.js" "%SCRIPT_DIR%core\settings.template.json" "%CLAUDE_HOME%\settings.json" >nul 2>&1
if !errorlevel! equ 0 (
    echo   OK Sinapsis hooks wired into settings.json (existing entries preserved^)
) else (
    echo   ! Could not update settings.json -- left untouched
    echo     Review core\settings.template.json and merge hooks manually
)

:: Step 7: Copy skills
echo [7/8] Installing skills...

:: v4.8.1 (audit finding #3): without /E the skill SUBDIRS -- hooks/observe.sh and
:: observe_v3.py -- never reached disk on Windows and the observer recorded nothing.
:: NOTE: comments must stay OUTSIDE the block below: cmd.exe delimits parenthesised
:: blocks before recognising :: comments, so a comment inside the block is parsed.
set "skill_count=0"
for /D %%d in ("%SCRIPT_DIR%skills\*") do (
    set "skill_name=%%~nxd"
    if not exist "%SKILLS_DIR%\!skill_name!" mkdir "%SKILLS_DIR%\!skill_name!"
    xcopy "%%d\*" "%SKILLS_DIR%\!skill_name!\" /E /I /Y /Q >nul 2>&1
    echo   OK !skill_name!
    set /a skill_count+=1
)

:: Step 8: Copy slash commands
echo [8/8] Installing slash commands...

set "cmd_count=0"
for %%f in ("%SCRIPT_DIR%commands\*.md") do (
    copy /Y "%%f" "%COMMANDS_DIR%\" >nul
    set /a cmd_count+=1
)
echo   OK %cmd_count% commands installed

:: Done!
echo.
echo ============================================================
if "%UPGRADING%"=="true" (
    echo   Sinapsis v4.9 upgrade complete!
) else (
    echo   Sinapsis v4.9 installed!
)
echo ============================================================
echo.
echo   What was installed:
echo   - 3 global skills (sinapsis-learning + sinapsis-instincts + skill-router)
echo   - %skill_count% total skills
echo   - %cmd_count% slash commands (/evolve, /system-status, /eod...)
echo   - 6 hook scripts + dream cycle (passive-activator, instinct-activator, session-learner, project-context, eod-gather, dream, precompact-guard)
echo   - Core config: catalog, passive rules, instincts index, operator state
echo.
echo   Next step:
echo   1. Open Claude Code in any project folder
echo   2. Sinapsis will guide you through first-time setup
echo   3. Choose your mode: Skills on Demand, manual, or vanilla
echo.
echo   Useful commands:
echo   /system-status    -- System dashboard
echo   /evolve           -- Evolve patterns into skills
echo   /analyze-session  -- Review learned proposals
echo   /passive-status   -- Active passive rules
echo   /eod              -- Save context for tomorrow
echo.
echo   Windows note: hooks require Node.js. Git Bash recommended for .sh scripts.
echo   See README for WSL/Git Bash configuration details.
echo.
echo   Sinapsis learns from you. Every session feeds the next.
echo.

endlocal
pause

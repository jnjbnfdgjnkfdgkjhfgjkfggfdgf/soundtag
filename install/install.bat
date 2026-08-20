@echo off
setlocal enabledelayedexpansion

REM SoundTag installer for Windows (batch)
REM Downloads SoundTag into a .\soundtag folder, installs deps and starts it.

set "REPO=https://github.com/soundtag1/soundtag.git"
set "RAW=https://raw.githubusercontent.com/soundtag1/soundtag/main"
set "INSTALL_DIR=%CD%\soundtag"

echo Installing SoundTag to %INSTALL_DIR%

REM Check Node.js
where node >nul 2>nul
if %errorlevel% neq 0 (
  echo [ERROR] Node.js is required. Please install Node.js and re-run.
  pause
  exit /b 1
)

REM Warn if ffmpeg missing
where ffmpeg >nul 2>nul
if %errorlevel% neq 0 (
  echo [WARNING] ffmpeg not found. The sound stream may not work until it is installed.
)

REM Fetch the app: prefer git clone, else download files with curl
where git >nul 2>nul
if %errorlevel% equ 0 (
  if exist "%INSTALL_DIR%\.git" (
    echo Updating existing install...
    git -C "%INSTALL_DIR%" pull --ff-only
  ) else (
    git clone --depth 1 "%REPO%" "%INSTALL_DIR%"
  )
) else (
  echo git not found - downloading files directly.
  mkdir "%INSTALL_DIR%\public" 2>nul
  curl -fsSL "%RAW%/server.js" -o "%INSTALL_DIR%\server.js"
  curl -fsSL "%RAW%/package.json" -o "%INSTALL_DIR%\package.json"
  curl -fsSL "%RAW%/public/login.html" -o "%INSTALL_DIR%\public\login.html"
  curl -fsSL "%RAW%/public/control.html" -o "%INSTALL_DIR%\public\control.html"
  curl -fsSL "%RAW%/public/listener.html" -o "%INSTALL_DIR%\public\listener.html"
)

cd /d "%INSTALL_DIR%"

REM Install dependencies from package.json
npm install

echo.
echo SoundTag installed.
echo Tip: set your own control-panel login before starting:
echo   set SOUNDTAG_USER=admin
echo   set SOUNDTAG_PASS=your-secret-password
echo (If unset, a random password is generated and printed on start.)
echo.
echo Starting SoundTag at http://localhost:3000
node server.js
pause

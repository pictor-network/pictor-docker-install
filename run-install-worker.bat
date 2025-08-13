@echo off
setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM ───────── Elevate to Administrator if needed ─────────
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator privileges...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ===============================================
echo  Pictor Worker - Windows Installer (via .BAT)
echo ===============================================
echo.

REM ───────── Run the PowerShell installer ─────────
set PS1_PATH=%~dp0install-worker.ps1
if not exist "%PS1_PATH%" (
  echo ❌ Cannot find install-worker.ps1 next to this .bat file.
  echo    Make sure both files are in the same folder.
  echo.
  pause
  exit /b 1
)

echo ▶ Running PowerShell installer...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
set EXITCODE=%ERRORLEVEL%

echo.
if not "%EXITCODE%"=="0" (
  echo ❌ Installer exited with error code %EXITCODE%.
  echo.
  echo Press any key to exit...
  pause >nul
  exit /b %EXITCODE%
)

echo ✅ Installer finished.
echo.

REM ───────── Show container status ─────────
echo ▶ Showing container status:
docker ps -a --filter "name=pictor-worker"
echo.

REM ───────── Stream logs so user can see progress ─────────
echo ▶ Streaming logs for 'pictor-worker' (press Ctrl+C to stop)...
docker logs -f pictor-worker

echo.
echo Done. Press any key to close.
pause >nul
exit /b 0

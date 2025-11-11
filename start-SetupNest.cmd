@echo off
setlocal ENABLEDELAYEDEXPANSION

:: --- 1) Se relancer en Administrateur si besoin (1 seul prompt UAC) ---
whoami /groups | find "S-1-5-32-544" >NUL
if not %errorlevel%==0 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

:: --- 2) Localisation & log ---
set SCRIPT_DIR=%~dp0
set PS1=%SCRIPT_DIR%install-gui.ps1
set LOG=%TEMP%\SetupNest-launch-%DATE:~-4%%DATE:~3,2%%DATE:~0,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%-!RANDOM!.log
set LOG=%LOG: =0%  && rem supprime espaces dans l'heure (00:00:00 -> 00)

echo [INFO ] Lancement de install-gui.ps1 en STA... > "%LOG%"

:: --- 3) Lancer PowerShell en STA (pas de relance interne) ---
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA ^
  -File "%PS1%" 1>>"%LOG%" 2>&1

set RC=%ERRORLEVEL%

if not %RC%==0 (
  echo [ERROR] Le script ne s'est pas lance correctement. Code: %RC%
  echo [ERROR] Consulte le log: "%LOG%"
  echo.
  echo --- Extrait du log ---
  for /f "tokens=1* delims=]" %%A in ('find /n /v "" ^< "%LOG%" ^| findstr /b /c:"[1]" /c:"[2]" /c:"[3]" /c:"[4]" /c:"[5]"') do @echo %%B
  echo.
  pause
)
exit /b %RC%

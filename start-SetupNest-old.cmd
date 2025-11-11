@echo off
setlocal enableextensions
pushd "%~dp0"

rem === Config ===
set "SCRIPT=%~dp0install-gui.ps1"
set "LOG=%TEMP%\SetupNest-launch-%DATE:~-4%%DATE:~3,2%%DATE:~0,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%-%RANDOM%.log"
set "LOG=%LOG: =0%"  rem retire espaces potentiels dans l'heure

rem === Verifs de base ===
if not exist "%SCRIPT%" (
  echo [ERROR] Script introuvable: "%SCRIPT%"
  echo [HINT ] Verifie que "install-gui.ps1" est bien a cote de ce .cmd
  pause
  popd & endlocal & exit /b 10
)

rem === Choix de PowerShell: pwsh en priorite, sinon Windows PowerShell ===
where pwsh.exe >nul 2>nul
if %errorlevel%==0 ( set "PS=pwsh.exe" ) else ( set "PS=powershell.exe" )

echo [INFO ] Lancement de install-gui.ps1 en STA... > "%LOG%"

rem === Lancement en STA avec logs ===
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%" 1>>"%LOG%" 2>&1
set "ERR=%ERRORLEVEL%"

if not "%ERR%"=="0" (
  echo.
  echo [ERROR] Le script ne s'est pas lance correctement. Code: %ERR%
  echo [ERROR] Consulte le log: "%LOG%"
  echo.
  rem Affiche les 120 dernieres lignes du log pour debug rapide
  "%PS%" -NoLogo -NoProfile -Command ^
    "Write-Host '--- Extrait du log ---'; if (Test-Path '%LOG%'){ Get-Content -Path '%LOG%' -Tail 120 | ForEach-Object { Write-Host $_ } } else { Write-Host 'Log introuvable.' }"
  echo.
  pause
) else (
  rem Nettoyage si tout va bien
  del "%LOG%" >nul 2>&1
)

popd
endlocal

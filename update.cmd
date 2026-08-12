@echo off
setlocal

set "UPDATER=%~dp0update-portable.ps1"
if not exist "%UPDATER%" set "UPDATER=%~dp0scripts\update-portable.ps1"

pushd "%TEMP%" >nul || exit /b 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%" %*
set "CODE=%ERRORLEVEL%"
popd
exit /b %CODE%

@echo off
:: Reset Audio Controller - Run as Administrator
setlocal EnableDelayedExpansion

echo ============================================
echo   Audio Controller Reset (Windows 11)
echo ============================================
echo.

:: Self-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo [1/6] Stopping audio services...
net stop Audiosrv /y 2>nul
net stop AudioEndpointBuilder /y 2>nul
timeout /t 1 /nobreak >nul

echo.
echo [2/6] Re-enabling any disabled audio devices...
powershell -NoProfile -Command ^
  "Get-PnpDevice -Class 'AudioEndpoint','Media' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 0 -or $_.Status -eq 'ERROR' -or $_.Status -eq 'UNKNOWN' } | ForEach-Object { Write-Host ('  Enabling: ' + $_.FriendlyName + '  [' + $_.Status + ']'); Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue }"

echo.
echo [3/6] Restarting audio driver nodes (forces jack re-detect)...
powershell -NoProfile -Command ^
  "Get-PnpDevice -Class 'Media' -Status 'OK' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ('  Cycling: ' + $_.FriendlyName); Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500; Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue }"

echo.
echo [4/6] Scanning for hardware changes...
pnputil /scan-devices
timeout /t 2 /nobreak >nul

echo.
echo [5/6] Starting audio services...
net start AudioEndpointBuilder 2>nul
net start Audiosrv 2>nul
timeout /t 2 /nobreak >nul

echo.
echo [6/6] Current playback endpoints:
powershell -NoProfile -Command ^
  "Get-CimInstance Win32_SoundDevice | Select-Object Name, Status, StatusInfo | Format-Table -AutoSize"

echo.
echo ============================================
echo   Done.
echo ============================================
echo.
echo If your aux headset still isn't listed:
echo   1. Unplug and replug the 3.5mm jack now.
echo   2. Right-click speaker icon ^> Sound settings
echo      ^> More sound settings ^> Playback tab
echo      ^> right-click empty area ^> tick BOTH
echo      "Show Disabled Devices" and "Show
echo      Disconnected Devices".
echo   3. If jack still dead: open Realtek / your
echo      audio control panel and turn OFF
echo      "Jack detection" (or set front jack to
echo      "Headphone" manually).
echo.
pause

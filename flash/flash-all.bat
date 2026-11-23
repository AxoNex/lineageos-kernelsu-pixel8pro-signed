@ECHO OFF
SETLOCAL
REM ============================================================================
REM  flash-all.bat -- one-click flash script for Windows
REM
REM  Usage: put this script, all .img files and avb_pkmd.bin from the fastboot
REM         package in the same directory, boot the device into bootloader mode,
REM         then double-click this script.
REM
REM  Steps:
REM    1. Verify the device is husky - Pixel 8 Pro
REM    2. Flash the hardware trust root avb_custom_key - REQUIRED before relock
REM    3. fastboot flashall to flash all partitions
REM
REM  After flashing: fastboot reboot to confirm boot, then fastboot flashing lock.
REM ============================================================================

REM cd to the script's directory so fastboot flashall finds the .img files
cd /d "%~dp0"

REM fastboot flashall requires ANDROID_PRODUCT_OUT to locate images + flash script
set ANDROID_PRODUCT_OUT=%CD%

where fastboot >nul 2>nul
if %errorlevel% neq 0 (
  echo fastboot not found. Install platform-tools and add it to PATH.
  echo https://developer.android.com/tools/releases/platform-tools
  goto :exit
)

echo Available devices:
fastboot devices -l

for /f "tokens=2" %%a in ('fastboot getvar product 2^>^&1 ^| find "product:"') do set "product=%%a"
if not "%product%" == "husky" (
  echo Error: this package is for husky - Pixel 8 Pro - but device is %product%
  goto :exit
)

echo.
echo === 1/2 Flash hardware trust root: avb_custom_key ===
fastboot erase avb_custom_key
if %errorlevel% neq 0 goto :exit
fastboot flash avb_custom_key avb_pkmd.bin
if %errorlevel% neq 0 goto :exit

echo.
echo === 2/2 Flash all partitions: fastboot flashall ===
fastboot flashall --skip-reboot
if %errorlevel% neq 0 goto :exit

echo.
echo Flash complete.
echo Next steps:
echo   fastboot reboot          -- confirm the system boots
echo   fastboot flashing lock   -- relock after confirming

:exit
echo.
echo Press any key to exit...
pause >nul

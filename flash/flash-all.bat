@ECHO OFF
SETLOCAL EnableExtensions
REM ============================================================================
REM  flash-all.bat —— 一键线刷脚本（Windows）
REM
REM  用法：把本脚本与线刷包内的所有 .img 文件、avb_pkmd.bin 放在同一目录，
REM        设备进入 bootloader 后双击运行本脚本。
REM
REM  流程：
REM    1. 校验设备为 husky（Pixel 8 Pro）
REM    2. 刷入硬件信任根公钥 avb_custom_key（回锁 bootloader 前必须）
REM    3. fastboot flashall 刷入所有分区（android-info.txt + fastboot-info.txt）
REM
REM  刷完先 fastboot reboot 开机确认正常，再手动 fastboot flashing lock 回锁。
REM ============================================================================

REM 切到脚本所在目录，确保 fastboot flashall 能找到 .img 与 android-info.txt
cd /d "%~dp0"

where fastboot >nul 2>nul
if %errorlevel% neq 0 (
  echo fastboot 未找到，请先安装 platform-tools 并加入 PATH
  echo https://developer.android.com/tools/releases/platform-tools
  goto :exit
)

echo 可用设备：
fastboot devices -l

for /f "tokens=2" %%a in ('fastboot getvar product 2^>^&1 ^| find "product:"') do set "product=%%a"
if not "%product%" == "husky" (
  echo 错误：此线刷包用于 husky（Pixel 8 Pro），当前设备是 %product%
  goto :exit
)

echo.
echo === 1/2 刷入硬件信任根公钥 ^(avb_custom_key^) ===
fastboot erase avb_custom_key
if %errorlevel% neq 0 goto :exit
fastboot flash avb_custom_key avb_pkmd.bin
if %errorlevel% neq 0 goto :exit

echo.
echo === 2/2 刷入所有分区 ^(fastboot flashall^) ===
fastboot flashall --skip-reboot
if %errorlevel% neq 0 goto :exit

echo.
echo 刷入完成。
echo 下一步：
echo   fastboot reboot           （开机确认系统正常）
echo   fastboot flashing lock    （确认无误后再回锁）

:exit
echo.
echo 按任意键退出...
pause >nul

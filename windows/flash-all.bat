@echo off
rem ============================================================================
rem  Pixel 8 Pro (husky) 线刷脚本 —— Windows
rem  用法: flash-all.bat        保留数据（不擦除）
rem        flash-all.bat -w     清除用户数据
rem  需在 bootloader (fastboot) 模式下运行。
rem ============================================================================
setlocal
set "DIR=%~dp0"
set "IMG=%DIR%images"
set "FB=fastboot"

where fastboot >nul 2>nul
if errorlevel 1 (
    echo [ERROR] fastboot not found in PATH. Install platform-tools.
    exit /b 1
)

set "WIPE=0"
if /I "%~1"=="-w" set "WIPE=1"

echo [STEP] Ensure device is in bootloader (fastboot) mode
"%FB%" getvar product 2>nul | findstr /I "husky" >nul || echo [WARN] husky not detected

echo [STEP] Flashing static partitions
"%FB%" flash boot            "%IMG%\boot.img"
"%FB%" flash init_boot       "%IMG%\init_boot.img"
"%FB%" flash vendor_boot     "%IMG%\vendor_boot.img"
"%FB%" flash dtbo            "%IMG%\dtbo.img"
"%FB%" flash vbmeta          "%IMG%\vbmeta.img"
"%FB%" flash vbmeta_system   "%IMG%\vbmeta_system.img"
"%FB%" flash vbmeta_vendor   "%IMG%\vbmeta_vendor.img"
"%FB%" flash pvmfw           "%IMG%\pvmfw.img"

if "%WIPE%"=="1" (
    echo [STEP] Wiping user data
    "%FB%" erase userdata
    "%FB%" erase metadata
)

echo [STEP] Rebooting to fastbootd
"%FB%" reboot fastboot

if exist "%IMG%\super_empty.img" (
    "%FB%" wipe-super "%IMG%\super_empty.img"
    "%FB%" flash system     "%IMG%\system.img"
    "%FB%" flash system_ext "%IMG%\system_ext.img"
    "%FB%" flash product    "%IMG%\product.img"
    "%FB%" flash vendor     "%IMG%\vendor.img"
) else if exist "%IMG%\super.img" (
    "%FB%" flash super "%IMG%\super.img"
) else (
    echo [WARN] super_empty.img / super.img not found
)

echo [STEP] Rebooting
"%FB%" reboot
echo Done. First boot may take a while.
endlocal

#!/usr/bin/env bash
# ============================================================================
#  Pixel 8 Pro (husky) 线刷脚本 —— Linux / macOS
#  用法: ./flash-all.sh         # 保留数据（不擦除）
#        ./flash-all.sh -w      # 清除用户数据
#  需在 bootloader (fastboot) 模式下运行。
# ============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="$DIR/images"
FB="fastboot"

command -v "$FB" >/dev/null 2>&1 || { echo "[ERROR] 未找到 fastboot，请安装 platform-tools"; exit 1; }

WIPE=0
[[ "${1:-}" == "-w" ]] && WIPE=1

need() { [[ -f "$IMG/$1" ]] || { echo "[ERROR] 缺少镜像: images/$1"; exit 1; }; }

echo "[STEP] 请确保设备已进入 bootloader (fastboot) 模式"
"$FB" getvar product 2>/dev/null | grep -qi "husky" || echo "[WARN] 未识别到 husky，请确认设备连接与模式"

echo "[STEP] 刷写静态分区"
for p in boot init_boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor pvmfw; do
  need "$p.img"
  "$FB" flash "$p" "$IMG/$p.img"
done

if [[ $WIPE -eq 1 ]]; then
  echo "[STEP] 清除用户数据 (-w)"
  "$FB" erase userdata || true
  "$FB" erase metadata || true
fi

echo "[STEP] 进入 fastbootd 刷写动态分区 (super)"
"$FB" reboot fastboot

if [[ -f "$IMG/super_empty.img" ]]; then
  "$FB" wipe-super "$IMG/super_empty.img"
  for p in system system_ext product vendor; do
    need "$p.img"
    "$FB" flash "$p" "$IMG/$p.img"
  done
elif [[ -f "$IMG/super.img" ]]; then
  "$FB" flash super "$IMG/super.img"
else
  echo "[WARN] 未找到 super_empty.img 或 super.img，跳过动态分区"
fi

echo "[STEP] 重启"
"$FB" reboot
echo "完成。首次启动可能较慢。"

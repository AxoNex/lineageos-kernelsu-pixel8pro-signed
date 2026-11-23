#!/bin/sh
# ============================================================================
#  flash-all.sh —— 一键线刷脚本（Linux / macOS）
#
#  用法：把本脚本与线刷包内的所有 .img 文件、avb_pkmd.bin 放在同一目录，
#        设备进入 bootloader 后执行：  sh flash-all.sh
#
#  流程：
#    1. 校验设备为 husky（Pixel 8 Pro）
#    2. 刷入硬件信任根公钥 avb_custom_key（回锁 bootloader 前必须）
#    3. fastboot flashall 刷入所有分区（android-info.txt + fastboot-info.txt）
#
#  刷完先 fastboot reboot 开机确认正常，再手动 fastboot flashing lock 回锁。
# ============================================================================
set -e

# 切到脚本所在目录，确保 fastboot flashall 能找到 .img 与 android-info.txt
cd "$(dirname "$0")"

command -v fastboot >/dev/null 2>&1 || {
  echo "fastboot 未找到，请先安装 platform-tools 并加入 PATH"
  echo "https://developer.android.com/tools/releases/platform-tools"
  exit 1
}

echo "可用设备："
fastboot devices -l

product=$(fastboot getvar product 2>&1 | sed -n 's/^product:[[:space:]]*//p' | tr -d '\r')
if [ "$product" != "husky" ]; then
  echo "错误：此线刷包用于 husky（Pixel 8 Pro），当前设备是 ${product:-未知}"
  exit 1
fi

echo ""
echo "=== 1/2 刷入硬件信任根公钥 (avb_custom_key) ==="
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_pkmd.bin

echo ""
echo "=== 2/2 刷入所有分区 (fastboot flashall) ==="
fastboot flashall --skip-reboot

echo ""
echo "刷入完成。"
echo "下一步："
echo "  fastboot reboot           # 开机确认系统正常"
echo "  fastboot flashing lock    # 确认无误后再回锁（务必已刷入信任根）"

#!/usr/bin/env bash
# ============================================================================
#  一键总入口：依次执行 ①→⑦
#  用法: ./scripts/make_all.sh
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

echo
echo "=============================================================="
echo "  Pixel 8 Pro ($DEVICE_CODENAME) 自签名 ROM 一键制作"
echo "  源码树 : $ANDROID_BUILD_TOP"
echo "  输出目录: $OUT_DIR"
echo "=============================================================="
echo

STAGES=(
  "00-init-keys.sh"
  "01-build-target-files.sh"
  "02-sign-images.sh"
  "03-make-fastboot-package.sh"
  "04-make-ota.sh"
  "05-setup-updater.sh"
  "06-avb-custom-key.sh"
)

for s in "${STAGES[@]}"; do
  echo
  echo ">>>>>>>>>>>>>>>>>>>> 执行 $s <<<<<<<<<<<<<<<<<<<<"
  bash "$SCRIPT_DIR/$s"
done

echo
echo "=============================================================="
ok "全部完成。成品输出于: $OUT_DIR"
echo "  - 线刷包    : $FASTBOOT_DIR"
echo "  - OTA 包    : $OTA_DIR"
echo "  - 硬件信任根: $AVB_DIR"
echo "  - 更新源    : $UPDATER_DIR"
echo "=============================================================="
echo
echo "下一步: 参考 docs/05 与 windows/flash-all.* 刷机；"
echo "        参考 $AVB_DIR/relock-bootloader.md 回锁 bootloader。"

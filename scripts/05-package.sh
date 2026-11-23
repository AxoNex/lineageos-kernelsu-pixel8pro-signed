#!/usr/bin/env bash
# ============================================================================
#  05-package.sh —— 生成线刷包 + updates.json
#
#  - ota extract --all --fastboot : 提取全部镜像 + 生成线刷目录（含 fastboot-info.txt）
#  - 打包线刷 zip
#  - 调 gen-updates-json.py 生成 updates.json（裸数组，LineageOS 24 格式）
#  产物: $OUT_DIR/${UPSTREAM_VERSION}-fastboot.zip + $PAGES_DIR/updates.json
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "05: 生成线刷包 + updates.json"
resolve_paths
require_cmds zip stat

source "$WORK_DIR/upstream.env"

AVB_PKMD="$KEYS_DIR/avb_pkmd.bin"

# ---- 1. 提取线刷镜像 --------------------------------------------------------
info "提取线刷镜像（--all 提取全部分区 + --fastboot 生成 fastboot-info.txt）"
FASTBOOT_DIR="$OUT_DIR/fastboot"
rm -rf "$FASTBOOT_DIR"
mkdir -p "$FASTBOOT_DIR"
# 必须用 --all：默认只提取"可能被补丁"的镜像(system+boot+vbmeta)，会漏掉
# product/system_ext/vendor/system_dlkm/vendor_dlkm 等动态分区，导致线刷包不完整。
"$AVBROOT_BIN" ota extract -i "$PATCHED_OTA" -d "$FASTBOOT_DIR" --all --fastboot

# 加入 bootloader 信任根公钥 + 一键线刷脚本（脚本内含「刷入信任根」步骤）
cp "$AVB_PKMD" "$FASTBOOT_DIR/avb_pkmd.bin"
cp "$TOOLKIT_ROOT/flash/flash-all.sh" "$FASTBOOT_DIR/flash-all.sh"
cp "$TOOLKIT_ROOT/flash/flash-all.bat" "$FASTBOOT_DIR/flash-all.bat"

# ---- 2. 打包线刷 zip --------------------------------------------------------
FASTBOOT_ZIP="$OUT_DIR/${UPSTREAM_VERSION}-fastboot.zip"
info "打包线刷包: $(basename "$FASTBOOT_ZIP")"
rm -f "$FASTBOOT_ZIP"
(cd "$FASTBOOT_DIR" && zip -q -r "$FASTBOOT_ZIP" .)

# ---- 3. 生成 updates.json ---------------------------------------------------
info "生成 updates.json"
mkdir -p "$PAGES_DIR"

# OTA 对外下载地址：GitHub Release 资产（下载器可跟随 302，无需直连 200）
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  OTA_DOWNLOAD_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${UPSTREAM_VERSION}/${UPSTREAM_VERSION}-ota.zip"
else
  OTA_DOWNLOAD_URL="${UPDATER_BASE_URL%/updates.json}/${UPSTREAM_VERSION}-ota.zip"
fi

python3 "$TOOLKIT_ROOT/scripts/gen-updates-json.py" \
  --ota "$PATCHED_OTA" \
  --url "$OTA_DOWNLOAD_URL" \
  --version "$UPSTREAM_VERSION" \
  --type "${UPSTREAM_TYPE,,}" \
  --os-patch-level "${OS_PATCH_LEVEL:-}" \
  --os-sdk-level "${OS_SDK_LEVEL:-}" \
  --datetime "$UPSTREAM_DATETIME" \
  --out "$PAGES_DIR/updates.json"

cat >> "$WORK_DIR/upstream.env" <<EOF
FASTBOOT_ZIP='$FASTBOOT_ZIP'
OTA_DOWNLOAD_URL='$OTA_DOWNLOAD_URL'
EOF
ok "05 完成"

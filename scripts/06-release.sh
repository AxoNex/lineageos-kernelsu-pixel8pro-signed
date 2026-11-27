#!/usr/bin/env bash
# ============================================================================
#  06-release.sh —— 发布到 GitHub Releases（线刷包 + OTA + 信任根公钥）
#
#  GitHub Pages 的 updates.json 由 workflow 的 upload-pages-artifact 步骤上传
#  （本脚本只负责 Releases 资产）
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "06: 发布 GitHub Releases"
resolve_paths
require_cmd gh
source "$WORK_DIR/upstream.env"

AVB_PKMD="$KEYS_DIR/avb_pkmd.bin"
GH_REPO_ARG=()
[[ -n "${GITHUB_REPOSITORY:-}" ]] && GH_REPO_ARG=(--repo "$GITHUB_REPOSITORY")

# 证书指纹清单（由 04 生成）：方便随时比对设备上实际信任的 otacerts
EXTRA_ASSETS=()
[[ -f "$OUT_DIR/otacert-fingerprints.txt" ]] && EXTRA_ASSETS+=("$OUT_DIR/otacert-fingerprints.txt")

if gh release view "$UPSTREAM_VERSION" "${GH_REPO_ARG[@]}" >/dev/null 2>&1; then
  info "Release ${UPSTREAM_VERSION} 已存在，追加/覆盖资产"
  gh release upload "$UPSTREAM_VERSION" \
    "$PATCHED_OTA" \
    "$FASTBOOT_ZIP" \
    "$AVB_PKMD#avb_pkmd.bin" \
    "${EXTRA_ASSETS[@]}" \
    --clobber "${GH_REPO_ARG[@]}"
else
  info "创建 Release ${UPSTREAM_VERSION}"
  gh release create "$UPSTREAM_VERSION" \
    "$PATCHED_OTA" \
    "$FASTBOOT_ZIP" \
    "$AVB_PKMD#avb_pkmd.bin" \
    "${EXTRA_ASSETS[@]}" \
    --title "$UPSTREAM_VERSION" \
    --notes "自签名 LineageOS 构建（blu_spark 内核 + 自定义更新源）

OTA 更新源: ${UPDATER_BASE_URL}
信任根公钥: avb_pkmd.bin（首次回锁 bootloader 前 flash 到 avb_custom_key 分区）
" \
    "${GH_REPO_ARG[@]}"
fi
ok "06 完成"

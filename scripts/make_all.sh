#!/usr/bin/env bash
# ============================================================================
#  make_all.sh —— 一键执行完整重打包流程
#
#  顺序: 00 检测上游 → 01 下载 → 02 恢复密钥 → 03 改 product
#        → 04 重打包签名 → 05 线刷包+updates.json → 06 发布 Releases
#
#  参数: --skip-check  跳过 00 检测（CI 中已单独执行过检测时使用）
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "Pixel 8 Pro ROM 一键重打包"
resolve_paths

SKIP_CHECK=false
[[ "${1:-}" == "--skip-check" ]] && SKIP_CHECK=true

if [[ "$SKIP_CHECK" == "false" ]]; then
  "$SCRIPT_DIR/00-check-upstream.sh"
fi

SHOULD_BUILD="$(cat "$WORK_DIR/SHOULD_BUILD" 2>/dev/null || echo false)"
if [[ "$SHOULD_BUILD" != "true" ]]; then
  ok "上游无新版本，本次跳过构建发布"
  exit 0
fi

"$SCRIPT_DIR/01-download.sh"
"$SCRIPT_DIR/02-keys.sh"
"$SCRIPT_DIR/03-patch-product.sh"
"$SCRIPT_DIR/04-patch-ota.sh"
"$SCRIPT_DIR/05-package.sh"
"$SCRIPT_DIR/06-release.sh"

ok "全部流程完成 ✅"
info "线刷包 : ${FASTBOOT_ZIP:-<见 .work/upstream.env>}"
info "OTA 包 : ${PATCHED_OTA:-<见 .work/upstream.env>}"
info "更新源 : $PAGES_DIR/updates.json"

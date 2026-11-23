#!/usr/bin/env bash
# ============================================================================
#  00-check-upstream.sh —— 检测上游 LineageOS 是否有新版本
#  通过 LineageOS v2 API 拉取最新构建，与已发布的 Release 比对，
#  有新版则写 $WORK_DIR/upstream.env + SHOULD_BUILD=true，否则 SHOULD_BUILD=false
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "00: 检测上游是否有新版本"
resolve_paths
require_cmds curl jq

info "查询 LineageOS API: ${LINEAGE_API}"
API_JSON="$(curl -fsSL --retry 3 "$LINEAGE_API")"

# 取最新构建（数组第 0 项）
VERSION_MAJOR="$(echo "$API_JSON" | jq -r '.[0].version')"          # 24.0
UPSTREAM_DATE="$(echo "$API_JSON" | jq -r '.[0].date')"             # 2026-11-20
UPSTREAM_DATETIME="$(echo "$API_JSON" | jq -r '.[0].datetime')"     # unix 秒
UPSTREAM_TYPE="$(echo "$API_JSON" | jq -r '.[0].type')"             # nightly

# 精确到构建日期的版本号，如 24.0-20261120-NIGHTLY-husky（而非仅 24.0）
UPSTREAM_VERSION="${VERSION_MAJOR}-${UPSTREAM_DATE//-/}-${UPSTREAM_TYPE^^}-${DEVICE_CODENAME}"

# OTA 文件是 files[0]
OTA_FILENAME="$(echo "$API_JSON" | jq -r '.[0].files[0].filename')"
OTA_URL="$(echo "$API_JSON" | jq -r '.[0].files[0].url')"
OTA_SHA256="$(echo "$API_JSON" | jq -r '.[0].files[0].sha256')"
OTA_SIZE="$(echo "$API_JSON" | jq -r '.[0].files[0].size')"
OS_PATCH_LEVEL="$(echo "$API_JSON" | jq -r '.[0].files[0].os_patch_level // empty')"
OS_SDK_LEVEL="$(echo "$API_JSON" | jq -r '.[0].files[0].os_sdk_level // empty')"

[[ -n "$VERSION_MAJOR" && "$VERSION_MAJOR" != "null" ]] || { err "无法解析上游版本号"; exit 1; }
[[ -n "$UPSTREAM_DATE" && "$UPSTREAM_DATE" != "null" ]] || { err "无法解析上游构建日期"; exit 1; }
[[ -n "$OTA_URL" && "$OTA_URL" != "null" ]] || { err "上游未提供 OTA 下载地址"; exit 1; }

# 是否已发布过该版本？（FORCE_BUILD=true 强制构建；gh 不可用时视为未发布）
if [[ "${FORCE_BUILD:-false}" != "true" ]] && command -v gh >/dev/null 2>&1; then
  GH_REPO_ARG=()
  [[ -n "${GITHUB_REPOSITORY:-}" ]] && GH_REPO_ARG=(--repo "$GITHUB_REPOSITORY")
  if gh release view "$UPSTREAM_VERSION" "${GH_REPO_ARG[@]}" >/dev/null 2>&1; then
    ok "版本 ${UPSTREAM_VERSION} 已发布，跳过构建"
    echo "false" > "$WORK_DIR/SHOULD_BUILD"
    exit 0
  fi
fi

info "发现新版本: ${UPSTREAM_VERSION} (unix=${UPSTREAM_DATETIME})"
info "  OTA : ${OTA_FILENAME}"
info "  size: ${OTA_SIZE} bytes  sha256=${OTA_SHA256}"

cat > "$WORK_DIR/upstream.env" <<EOF
UPSTREAM_VERSION='${UPSTREAM_VERSION}'
UPSTREAM_DATETIME='${UPSTREAM_DATETIME}'
UPSTREAM_TYPE='${UPSTREAM_TYPE}'
OTA_FILENAME='${OTA_FILENAME}'
OTA_URL='${OTA_URL}'
OTA_SHA256='${OTA_SHA256}'
OTA_SIZE='${OTA_SIZE}'
OS_PATCH_LEVEL='${OS_PATCH_LEVEL}'
OS_SDK_LEVEL='${OS_SDK_LEVEL}'
EOF
echo "true" > "$WORK_DIR/SHOULD_BUILD"
ok "00 完成：可开始构建"

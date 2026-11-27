#!/usr/bin/env bash
# ============================================================================
#  00-check-upstream.sh —— 检测上游 LineageOS 是否有新版本
#  通过 LineageOS v2 API 拉取构建列表：
#    - 默认取最新（数组第 0 项）
#    - 若设置了 TARGET_VERSION，则在列表中查找指定版本（支持多种写法）
#  有目标版本则写 $WORK_DIR/upstream.env + SHOULD_BUILD=true，否则 SHOULD_BUILD=false
#
#  TARGET_VERSION 可接受（不区分大小写、忽略首尾空白）：
#    20261120                        # 构建日期（紧凑）
#    2026-11-20                      # 构建日期（API 原格式）
#    24.0-20261120                   # 版本号+日期
#    24.0-20261120-NIGHTLY-husky     # 完整版本号（= Release 标签）
#  留空 = 取最新构建。
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "00: 检测上游是否有新版本"
resolve_paths
require_cmds curl jq

info "查询 LineageOS API: ${LINEAGE_API}"
API_JSON="$(curl -fsSL --retry 3 "$LINEAGE_API")"
[[ -n "$API_JSON" && "$API_JSON" != "null" ]] || { err "LineageOS API 返回为空"; exit 1; }

# ---- 选择目标构建 -----------------------------------------------------------
IDX=0
if [[ -n "${TARGET_VERSION:-}" ]]; then
  TARGET_UPPER="$(printf '%s' "$TARGET_VERSION" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
  MATCH_IDX="$(printf '%s' "$API_JSON" | jq -r --arg t "$TARGET_UPPER" --arg dev "$DEVICE_CODENAME" '
    to_entries
    | map(
        .value as $b
        | ($b.date | gsub("-"; "")) as $dc
        | {
            i: .key,
            date: ($b.date | ascii_upcase),
            dc: ($dc | ascii_upcase),
            short: (($b.version + "-" + $dc) | ascii_upcase),
            full: (($b.version + "-" + $dc + "-" + ($b.type | ascii_upcase) + "-" + $dev) | ascii_upcase)
          }
      )
    | map(select(.date == $t or .dc == $t or .short == $t or .full == $t))
    | .[0].i // empty
  ')"
  if [[ -z "$MATCH_IDX" ]]; then
    err "未在上游构建列表中找到指定版本: ${TARGET_VERSION}"
    warn "上游可用版本（最新在前）:"
    printf '%s' "$API_JSON" | jq -r --arg dev "$DEVICE_CODENAME" \
      '.[] | "\(.version)-\(.date | gsub("-"; ""))-\(.type | ascii_upcase)-\($dev)"'
    exit 1
  fi
  IDX="$MATCH_IDX"
  ok "已选定上游版本（列表索引 [$IDX]）: ${TARGET_VERSION}"
fi

# 取选中构建
VERSION_MAJOR="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].version")"          # 24.0
UPSTREAM_DATE="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].date")"             # 2026-11-20
UPSTREAM_DATETIME="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].datetime")"     # unix 秒
UPSTREAM_TYPE="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].type")"             # nightly

# 精确到构建日期的版本号，如 24.0-20261120-NIGHTLY-husky（而非仅 24.0）
UPSTREAM_VERSION="${VERSION_MAJOR}-${UPSTREAM_DATE//-/}-${UPSTREAM_TYPE^^}-${DEVICE_CODENAME}"

# OTA 文件是 files[0]
OTA_FILENAME="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].files[0].filename")"
OTA_URL="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].files[0].url")"
OTA_SHA256="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].files[0].sha256")"
OTA_SIZE="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].files[0].size")"
OS_PATCH_LEVEL="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].files[0].os_patch_level // empty")"
OS_SDK_LEVEL="$(printf '%s' "$API_JSON" | jq -r ".[$IDX].files[0].os_sdk_level // empty")"

[[ -n "$VERSION_MAJOR" && "$VERSION_MAJOR" != "null" ]] || { err "无法解析上游版本号"; exit 1; }
[[ -n "$UPSTREAM_DATE" && "$UPSTREAM_DATE" != "null" ]] || { err "无法解析上游构建日期"; exit 1; }
[[ -n "$OTA_URL" && "$OTA_URL" != "null" ]] || { err "上游未提供 OTA 下载地址"; exit 1; }

# 是否已发布过该版本？（FORCE_BUILD=true 强制构建；gh 不可用时视为未发布）
if [[ "${FORCE_BUILD:-false}" != "true" ]] && command -v gh >/dev/null 2>&1; then
  GH_REPO_ARG=()
  [[ -n "${GITHUB_REPOSITORY:-}" ]] && GH_REPO_ARG=(--repo "$GITHUB_REPOSITORY")
  if gh release view "$UPSTREAM_VERSION" "${GH_REPO_ARG[@]}" >/dev/null 2>&1; then
    ok "版本 ${UPSTREAM_VERSION} 已发布，跳过构建（如需重建请勾选 force）"
    echo "false" > "$WORK_DIR/SHOULD_BUILD"
    exit 0
  fi
fi

info "目标版本: ${UPSTREAM_VERSION} (unix=${UPSTREAM_DATETIME})${TARGET_VERSION:+, 由输入指定}"
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

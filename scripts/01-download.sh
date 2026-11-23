#!/usr/bin/env bash
# ============================================================================
#  01-download.sh —— 下载 avbroot、官方 OTA、blu_spark boot 镜像
#  产物：$DOWNLOAD_DIR/{avbroot, <ota>, <blu_spark_boot.img>}
#  追加 upstream.env: BOOT_IMG / BLUSPARK_FILENAME
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "01: 下载 avbroot + 官方 OTA + blu_spark 内核"
resolve_paths
require_cmds curl unzip jq sha256sum

source "$WORK_DIR/upstream.env"

# ---- avbroot（缓存可复用）--------------------------------------------------
AVBROOT_BIN="$DOWNLOAD_DIR/avbroot"
if [[ ! -x "$AVBROOT_BIN" ]]; then
  info "下载 avbroot ${AVBROOT_VERSION}"
  curl -fsSL --retry 3 -o "$DOWNLOAD_DIR/avbroot.zip" "$AVBROOT_URL"
  echo "${AVBROOT_SHA256}  $DOWNLOAD_DIR/avbroot.zip" | sha256sum -c - >/dev/null
  unzip -qo "$DOWNLOAD_DIR/avbroot.zip" -d "$DOWNLOAD_DIR/avbroot-dist"
  BIN="$(find "$DOWNLOAD_DIR/avbroot-dist" -maxdepth 1 -type f -name 'avbroot' | head -1)"
  [[ -n "$BIN" ]] || { err "解压后未找到 avbroot 可执行文件"; exit 1; }
  mv "$BIN" "$AVBROOT_BIN"
  chmod +x "$AVBROOT_BIN"
  ok "avbroot ${AVBROOT_VERSION} 就绪"
else
  ok "avbroot 已缓存"
fi
export AVBROOT_BIN

# ---- 官方 OTA --------------------------------------------------------------
OTA_ZIP="$DOWNLOAD_DIR/$OTA_FILENAME"
if [[ ! -f "$OTA_ZIP" ]]; then
  info "下载官方 OTA: $OTA_FILENAME"
  curl -fsSL --retry 3 -o "$OTA_ZIP" "$OTA_URL"
else
  ok "OTA 已缓存"
fi
info "校验 OTA sha256..."
ACTUAL="$(sha256_of "$OTA_ZIP")"
if [[ "$ACTUAL" != "$OTA_SHA256" ]]; then
  err "OTA sha256 不匹配：期望 ${OTA_SHA256}，实际 ${ACTUAL}"
  rm -f "$OTA_ZIP"
  exit 1
fi
ok "OTA 校验通过（${OTA_SIZE} bytes）"

# ---- blu_spark boot --------------------------------------------------------
info "查询 blu_spark 最新 release（${BLUSPARK_REPO}）"
BS_JSON="$(curl -fsSL --retry 3 "https://api.github.com/repos/${BLUSPARK_REPO}/releases/latest")"
# 匹配 gs-los 且非 -next 的 .img 资产（短 hash 后缀每次发布会变）
BS_URL="$(echo "$BS_JSON" | jq -r '.assets[].browser_download_url' \
  | grep -E 'blu_spark_gs-los-v[0-9]+-[0-9a-f]+\.img$' \
  | grep -v -- '-next' | head -1)"
[[ -n "$BS_URL" && "$BS_URL" != "null" ]] || { err "未在 blu_spark release 中找到 gs-los boot 镜像"; exit 1; }
BS_FILENAME="$(basename "$BS_URL")"
BOOT_IMG="$DOWNLOAD_DIR/$BS_FILENAME"
if [[ ! -f "$BOOT_IMG" ]]; then
  info "下载 blu_spark boot: $BS_FILENAME"
  curl -fsSL --retry 3 -o "$BOOT_IMG" "$BS_URL"
else
  ok "blu_spark boot 已缓存"
fi

cat >> "$WORK_DIR/upstream.env" <<EOF
BLUSPARK_FILENAME='${BS_FILENAME}'
BOOT_IMG='${BOOT_IMG}'
EOF
ok "01 完成"

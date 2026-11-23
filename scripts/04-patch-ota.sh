#!/usr/bin/env bash
# ============================================================================
#  04-patch-ota.sh —— avbroot 重新打包 + 签名 OTA
#
#  - --prepatched <blu_spark boot> : 替换 boot 为 blu_spark 内核（校验兼容）
#  - --replace product <img>       : 替换 product 为改过属性的分区
#  - 自动替换 system/recovery 内 otacerts.zip 为自定义 OTA 证书
#  产物: $OUT_DIR/${UPSTREAM_VERSION}-ota.zip（补丁后的全量 OTA）
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "04: avbroot 重新打包 + 签名 OTA"
resolve_paths
source "$WORK_DIR/upstream.env"

AVB_KEY="$KEYS_DIR/avb.key"
OTA_KEY="$KEYS_DIR/ota.key"
OTA_CRT="$KEYS_DIR/ota.crt"
AVB_PKMD="$KEYS_DIR/avb_pkmd.bin"
OTA_ZIP="$DOWNLOAD_DIR/$OTA_FILENAME"
PATCHED_OTA="$OUT_DIR/${UPSTREAM_VERSION}-ota.zip"

PASS_AVB_ARG=(); PASS_OTA_ARG=()
if [[ -n "${KEY_PASSPHRASE:-}" ]]; then
  PASS_AVB_ARG=(--pass-avb-env-var KEY_PASSPHRASE)
  PASS_OTA_ARG=(--pass-ota-env-var KEY_PASSPHRASE)
fi

info "ota patch: 替换 boot=blu_spark，替换 product=改过属性"
"$AVBROOT_BIN" ota patch \
  -i "$OTA_ZIP" \
  -o "$PATCHED_OTA" \
  --key-avb "$AVB_KEY" \
  --key-ota "$OTA_KEY" \
  --cert-ota "$OTA_CRT" \
  --prepatched "$BOOT_IMG" \
  --replace product "$PRODUCT_NEW_IMG" \
  "${PASS_AVB_ARG[@]}" "${PASS_OTA_ARG[@]}"

info "校验补丁后 OTA 的签名"
"$AVBROOT_BIN" ota verify -i "$PATCHED_OTA" --cert-ota "$OTA_CRT" --public-key-avb "$AVB_PKMD"

cat >> "$WORK_DIR/upstream.env" <<EOF
PATCHED_OTA='$PATCHED_OTA'
EOF
ok "04 完成：$PATCHED_OTA"

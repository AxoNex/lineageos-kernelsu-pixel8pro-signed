#!/usr/bin/env bash
# ============================================================================
#  02-keys.sh —— 从 SIGNING_KEYS（base64 tar）恢复签名密钥到 $KEYS_DIR
#  产物：avb.key / ota.key / ota.crt / avb_pkmd.bin
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "02: 恢复签名密钥"
resolve_paths

AVB_KEY="$KEYS_DIR/avb.key"
OTA_KEY="$KEYS_DIR/ota.key"
OTA_CRT="$KEYS_DIR/ota.crt"
AVB_PKMD="$KEYS_DIR/avb_pkmd.bin"

if [[ -f "$AVB_KEY" && -f "$OTA_KEY" && -f "$OTA_CRT" && -f "$AVB_PKMD" ]]; then
  ok "密钥已存在，跳过恢复"
  export AVB_KEY OTA_KEY OTA_CRT AVB_PKMD
  exit 0
fi

if [[ -z "${SIGNING_KEYS:-}" ]]; then
  err "缺少 SIGNING_KEYS（base64 编码的密钥 tarball）。"
  err "请先运行 init-keys 工作流生成密钥，并把输出存入 GitHub Secret「SIGNING_KEYS」。"
  exit 1
fi

info "从 SIGNING_KEYS 恢复密钥..."
TAR_TMP="$TMP_DIR/keys-tar"
mkdir -p "$TAR_TMP"
echo "$SIGNING_KEYS" | base64 -d > "$TMP_DIR/keys.tar"
tar -xf "$TMP_DIR/keys.tar" -C "$TAR_TMP"

for f in avb.key ota.key ota.crt avb_pkmd.bin; do
  FOUND="$(find "$TAR_TMP" -name "$f" | head -1)"
  [[ -n "$FOUND" ]] || { err "SIGNING_KEYS 中缺少 $f"; exit 1; }
  mv "$FOUND" "$KEYS_DIR/$f"
done
chmod 600 "$KEYS_DIR"/avb.key "$KEYS_DIR"/ota.key 2>/dev/null || true

export AVB_KEY OTA_KEY OTA_CRT AVB_PKMD
ok "02 完成"

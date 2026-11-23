#!/usr/bin/env bash
# ============================================================================
#  init-keys.sh —— 生成签名密钥 + 信任根（首次或密钥轮换时手动运行）
#
#  产物：avb.key / ota.key / ota.crt / avb_pkmd.bin
#  并输出 base64 编码的 tarball，供存入 GitHub Secret「SIGNING_KEYS」。
#
#  ⚠️ 密钥必须长期保留：丢失 = 无法给后续 OTA 签名 = 需解锁+清数据+换新钥。
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "初始化签名密钥 + 信任根（仅首次/轮换时运行）"
resolve_paths
require_cmds curl unzip sha256sum base64

AVB_KEY="$KEYS_DIR/avb.key"
OTA_KEY="$KEYS_DIR/ota.key"
OTA_CRT="$KEYS_DIR/ota.crt"
AVB_PKMD="$KEYS_DIR/avb_pkmd.bin"

# 安全保护：已有密钥则不覆盖
if [[ -f "$AVB_KEY" || -f "$OTA_KEY" || -f "$OTA_CRT" || -f "$AVB_PKMD" ]]; then
  err "已存在密钥文件，拒绝覆盖。如确需轮换，请先删除 $KEYS_DIR 后重试。"
  exit 1
fi

# ---- 下载 avbroot（若未缓存）------------------------------------------------
AVBROOT_BIN="$DOWNLOAD_DIR/avbroot"
if [[ ! -x "$AVBROOT_BIN" ]]; then
  info "下载 avbroot ${AVBROOT_VERSION}"
  curl -fsSL --retry 3 -o "$DOWNLOAD_DIR/avbroot.zip" "$AVBROOT_URL"
  echo "${AVBROOT_SHA256}  $DOWNLOAD_DIR/avbroot.zip" | sha256sum -c - >/dev/null
  unzip -qo "$DOWNLOAD_DIR/avbroot.zip" -d "$DOWNLOAD_DIR/avbroot-dist"
  BIN="$(find "$DOWNLOAD_DIR/avbroot-dist" -maxdepth 1 -type f -name 'avbroot' | head -1)"
  mv "$BIN" "$AVBROOT_BIN"; chmod +x "$AVBROOT_BIN"
fi
export AVBROOT_BIN

PASS_ARG=()
[[ -n "${KEY_PASSPHRASE:-}" ]] && PASS_ARG=(--pass-env-var KEY_PASSPHRASE)

info "生成 AVB 签名密钥（rsa4096，签 vbmeta/分区 hashtree）"
"$AVBROOT_BIN" key generate-key -t rsa4096 -o "$AVB_KEY" "${PASS_ARG[@]}"

info "生成 OTA 签名密钥（rsa4096，签 payload）"
"$AVBROOT_BIN" key generate-key -t rsa4096 -o "$OTA_KEY" "${PASS_ARG[@]}"

info "生成 OTA 自签证书"
"$AVBROOT_BIN" key generate-cert -k "$OTA_KEY" -o "$OTA_CRT" \
  --subject "CN=Pixel8Pro OTA" --validity 10000 "${PASS_ARG[@]}"

info "编码 AVB 公钥（bootloader 信任根）"
"$AVBROOT_BIN" key encode-avb -k "$AVB_KEY" -o "$AVB_PKMD" "${PASS_ARG[@]}"

chmod 600 "$AVB_KEY" "$OTA_KEY" 2>/dev/null || true

# ---- 打包成 base64 供存入 Secret -------------------------------------------
info "打包密钥为 SIGNING_KEYS（base64 tar）"
tar -C "$KEYS_DIR" -cf "$TMP_DIR/keys.tar" avb.key ota.key ota.crt avb_pkmd.bin
SIGNING_KEYS_B64="$(base64 -w0 "$TMP_DIR/keys.tar" 2>/dev/null || base64 "$TMP_DIR/keys.tar" | tr -d '\n')"

echo ""
ok "密钥生成完成！请完成以下两步："
echo ""
echo "  ① 将下面整段内容存入 GitHub Secret「SIGNING_KEYS」："
echo "     (仓库 Settings → Secrets and variables → Actions → New repository secret)"
echo "──────────────────── SIGNING_KEYS 开始 ────────────────────"
echo "$SIGNING_KEYS_B64"
echo "──────────────────── SIGNING_KEYS 结束 ────────────────────"
if [[ -n "${KEY_PASSPHRASE:-}" ]]; then
  echo "  ② 将密钥口令也存入 Secret「KEY_PASSPHRASE」。"
else
  echo "  ② （未设置口令，密钥为明文，无需 KEY_PASSPHRASE）"
fi
echo ""
info "信任根公钥: $AVB_PKMD"
info "首次刷机回锁 bootloader 的步骤见 docs/06-线刷与回锁.md"

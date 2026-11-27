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

info "ota patch: 替换 boot=blu_spark，替换 product=改过属性，替换 system/recovery 的 otacerts"
# --clear-vbmeta-flags：官方 LineageOS 构建 vbmeta header flags=0x3
#   (HASHTREE_DISABLED|VERIFICATION_DISABLED)，即关闭了 verified boot。
#   回锁 bootloader 需要 verified boot 生效，故清零这些 flag 重新启用，
#   再用 avb.key 重签整个信任链。
# --zip-mode seekable：默认的 streaming 模式会写入 zip data descriptor；
#   部分消费端（含某些设备的更新器 zip 解析）会把 payload.bin 的字节偏移算错，
#   导致从错误偏移读到全零、update_engine 报 kDownloadInvalidMetadataMagicString(21)。
#   seekable 模式不写 data descriptor，偏移声明与真实字节位置一致，兼容性更好。
PATCH_LOG="$OUT_DIR/avbroot-ota-patch.log"
"$AVBROOT_BIN" ota patch \
  -i "$OTA_ZIP" \
  -o "$PATCHED_OTA" \
  --key-avb "$AVB_KEY" \
  --key-ota "$OTA_KEY" \
  --cert-ota "$OTA_CRT" \
  --prepatched "$BOOT_IMG" \
  --replace product "$PRODUCT_NEW_IMG" \
  --clear-vbmeta-flags \
  --zip-mode seekable \
  "${PASS_AVB_ARG[@]}" "${PASS_OTA_ARG[@]}" 2>&1 | tee "$PATCH_LOG"

# 关键校验：avbroot 必须真的把 system 分区的 otacerts.zip 换成我们的证书。
# 设备上运行的 update_engine 用「当前系统」的 otacerts.zip 校验新 payload；
# 若这里没替换，设备仍信任官方证书 → 安装我们自签的 OTA 会瞬间失败
# （错误码通常是 kDownloadStateInitializationError / 签名校验失败）。
# avbroot 只在成功写回新 zip 后才打印该行，因此可作为「确实替换过」的可靠证据。
if ! grep -q "Patched otacerts.zip offsets in system" "$PATCH_LOG"; then
  err "avbroot 没有替换 system 的 otacerts.zip！"
  err "设备将仍信任官方证书，无法通过内置更新器安装自签 OTA。"
  err "详见 avbroot 输出：$PATCH_LOG"
  exit 1
fi
ok "已确认 system 的 otacerts.zip 已替换为我们的 OTA 证书"

info "校验补丁后 OTA 的签名"
"$AVBROOT_BIN" ota verify -i "$PATCHED_OTA" --cert-ota "$OTA_CRT" --public-key-avb "$AVB_PKMD"

# ---- 产物级校验：zip 内不得含 data descriptor ----
# 【实测根因】设备端 LineageOS 更新器会自己按 zip 本地头逐条累计出
# payload.bin 的字节偏移（不直接用 ota-property-files 里那个数）。
# avbroot 默认的 streaming zip 模式会给每个条目追加 16 字节 data descriptor，
# 并把本地头里的 crc / 压缩后大小 / 原始大小全部置 0。更新器累计时没算这
# 16 字节，于是偏移少了 16×(payload.bin 之前的条目数)，正好落进 payload.bin
# 本地头里被置 0 的几个字段 → 读到 "00 00 00 00"，update_engine 报：
#   invalid delta magic: 00000000  Expected: 43724155
#   ErrorCode::kDownloadInvalidMetadataMagicString (21)
# 实测：一版 zip 真实偏移 3250，更新器用了 3218，差额 32 = 2×16（两个 data descriptor）。
# 用 seekable 模式（不写 data descriptor）即可避免。
info "校验产物 OTA：zip 内不得含 data descriptor"
DD_ENTRIES="$(python3 - "$PATCHED_OTA" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    data = f.read(4 * 1024 * 1024)  # 前 4MB 足以覆盖所有本地文件头
bad, i = [], 0
while True:
    i = data.find(b'PK\x03\x04', i)
    if i < 0 or i + 30 > len(data):
        break
    flags = struct.unpack_from('<H', data, i + 6)[0]
    nlen = struct.unpack_from('<H', data, i + 26)[0]
    name = data[i + 30:i + 30 + nlen].decode('ascii', 'replace')
    if flags & 0x08:
        bad.append(name)
    i += 4
print(','.join(bad))
PY
)"
if [[ -n "$DD_ENTRIES" ]]; then
  err "zip 含 data descriptor 的条目：$DD_ENTRIES"
  err "设备更新器会算错 payload.bin 偏移，报 kDownloadInvalidMetadataMagicString(21)。"
  err "必须用 --zip-mode seekable 重新打包。"
  exit 1
fi
ok "zip 内无 data descriptor（seekable 模式）"

# 附加校验：ota-property-files 声明的 payload 偏移确实指向 CrAU 魔数
META_TXT="$(unzip -p "$PATCHED_OTA" 'META-INF/com/android/metadata' 2>/dev/null || true)"
DECL_OFF="$(printf '%s\n' "$META_TXT" | tr -d '\r' \
            | grep -oE 'payload\.bin:[0-9]+' | head -n1 | cut -d: -f2 || true)"
if [[ -n "$DECL_OFF" ]]; then
  DECL_MAGIC="$(od -An -tx1 -j "$DECL_OFF" -N 4 "$PATCHED_OTA" 2>/dev/null | tr -d ' \n' || true)"
  if [[ "$DECL_MAGIC" != "43724155" ]]; then
    err "ota-property-files 声明偏移 $DECL_OFF 处不是 CrAU（读到 ${DECL_MAGIC:-空}）"
    exit 1
  fi
  ok "ota-property-files 声明偏移 $DECL_OFF 处为 CrAU"
fi

# ---- 产物级校验：直接确认 system 分区里的 otacerts.zip 就是我们的证书 ----
# 上面那条日志断言只能证明「avbroot 替换了某个它认出来的 otacerts.zip」，
# 无法证明换的是正确的那一个。这里把产物 system 里的真文件抽出来做指纹
# 比对——不一致就当场让构建失败，避免发布一个设备装不上的包。
info "校验产物 system 分区内的 otacerts.zip 证书指纹"
SYSCHECK_DIR="$TMP_DIR/syscheck"
rm -rf "$SYSCHECK_DIR"; mkdir -p "$SYSCHECK_DIR"
"$AVBROOT_BIN" ota extract -i "$PATCHED_OTA" -d "$SYSCHECK_DIR" -p system

OTACERT_ZIP="$SYSCHECK_DIR/otacerts.zip"
if ! debugfs -R "dump /etc/security/otacerts.zip $OTACERT_ZIP" \
        "$SYSCHECK_DIR/system.img" >/dev/null 2>&1; then
  warn "debugfs 直接读取失败，改为先剥离 AVB footer 再取"
  mkdir -p "$SYSCHECK_DIR/raw"
  ( cd "$SYSCHECK_DIR/raw" && "$AVBROOT_BIN" avb unpack -i "$SYSCHECK_DIR/system.img" )
  debugfs -R "dump /etc/security/otacerts.zip $OTACERT_ZIP" \
      "$SYSCHECK_DIR/raw/raw.img" >/dev/null 2>&1
fi
if [[ ! -s "$OTACERT_ZIP" ]]; then
  err "无法从产物 system 分区中取出 otacerts.zip"
  exit 1
fi

ACTUAL_FP="$(unzip -p "$OTACERT_ZIP" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | head -n1 | tr 'A-F' 'a-f' || true)"
EXPECT_FP="$(openssl x509 -in "$OTA_CRT" -noout -fingerprint -sha256 2>/dev/null | head -n1 | tr 'A-F' 'a-f' || true)"
if [[ -z "$ACTUAL_FP" || -z "$EXPECT_FP" ]]; then
  err "无法计算证书指纹（openssl / unzip 异常）"
  exit 1
fi
if [[ "$ACTUAL_FP" != "$EXPECT_FP" ]]; then
  err "产物 system 内的 otacerts.zip 证书与 ota.crt 不一致！"
  err "  system otacerts : $ACTUAL_FP"
  err "  ota.crt         : $EXPECT_FP"
  err "设备将信任错误的证书，内置更新器安装本包会失败。"
  exit 1
fi
{
  echo "ota.crt (OTA 签名证书) : $EXPECT_FP"
  echo "system otacerts.zip    : $ACTUAL_FP"
} > "$OUT_DIR/otacert-fingerprints.txt"
ok "system otacerts 证书指纹一致：$EXPECT_FP"
rm -rf "$SYSCHECK_DIR"

cat >> "$WORK_DIR/upstream.env" <<EOF
PATCHED_OTA='$PATCHED_OTA'
EOF
ok "04 完成：$PATCHED_OTA"

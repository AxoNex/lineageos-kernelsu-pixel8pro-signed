#!/usr/bin/env bash
# ============================================================================
#  ⑤ OTA 更新包制作
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

step "⑤ OTA 更新包制作"

[[ -f "$WORK_DIR/signed_tf.env" ]] || { err "未找到 signed_tf.env，请先运行 02-sign-images.sh"; exit 1; }
[[ -f "$WORK_DIR/keys_path.env" ]] || { err "未找到 keys_path.env，请先运行 00-init-keys.sh"; exit 1; }
source "$WORK_DIR/signed_tf.env"
source "$WORK_DIR/keys_path.env"

cd "$ANDROID_BUILD_TOP"
# shellcheck source=/dev/null
source build/envsetup.sh >/dev/null 2>&1

# releasekey 路径（不带扩展名，工具自动补 .pk8/.x509.pem）
RELEASEKEY="$KEYS_PATH/releasekey"

OTA_NAME="${DEVICE_CODENAME}-${LINEAGE_VERSION}-$(date +%Y%m%d-%H%M%S)-ota.zip"

info "生成 OTA（block 模式，releasekey 签名）…"
ota_from_target_files \
  -k "$RELEASEKEY" \
  --block --backup=true \
  "$SIGNED_TF" \
  "$OTA_DIR/$OTA_NAME"

ok "OTA 包: $OTA_DIR/$OTA_NAME"
sha256sum "$OTA_DIR/$OTA_NAME" > "$OTA_DIR/$OTA_NAME.sha256"

echo "OTA_NAME=$OTA_NAME" > "$WORK_DIR/ota.env"
ok "校验和已写入 $OTA_DIR/$OTA_NAME.sha256"

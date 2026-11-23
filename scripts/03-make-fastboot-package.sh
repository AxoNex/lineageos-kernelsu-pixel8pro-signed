#!/usr/bin/env bash
# ============================================================================
#  ④ 线刷包（fastboot）打包
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

step "④ 线刷包（fastboot）打包"

[[ -f "$WORK_DIR/signed_tf.env" ]] || { err "未找到 signed_tf.env，请先运行 02-sign-images.sh"; exit 1; }
source "$WORK_DIR/signed_tf.env"
require_var SIGNED_TF

TAG="$(build_tag)"
PKG="$FASTBOOT_DIR/$TAG"
mkdir -p "$PKG/images"

# ---- 解包镜像 ---------------------------------------------------------------
info "从 target-files 解包 IMAGES/*.img …"
unzip -o -j "$SIGNED_TF" 'IMAGES/*.img' -d "$PKG/images" >/dev/null
COUNT="$(find "$PKG/images" -name '*.img' | wc -l)"
ok "已解包 $COUNT 个镜像到 $PKG/images"

# ---- 复制刷机脚本 -----------------------------------------------------------
cp "$TOOLKIT_ROOT/windows/flash-all.sh"   "$PKG/flash-all.sh"
cp "$TOOLKIT_ROOT/windows/flash-all.bat"  "$PKG/flash-all.bat"
chmod +x "$PKG/flash-all.sh"

# ---- android-info.txt（供 fastboot update 参考，非必需）--------------------
cat > "$PKG/images/android-info.txt" <<EOF
require board=$DEVICE_CODENAME
EOF

# ---- 校验和 -----------------------------------------------------------------
( cd "$PKG" && sha256sum images/*.img > SHA256SUMS )
ok "校验和已写入 $PKG/SHA256SUMS"

# ---- 打包 zip ---------------------------------------------------------------
( cd "$FASTBOOT_DIR" && zip -r -q "$TAG-factory.zip" "$TAG" )
ok "线刷包: $FASTBOOT_DIR/$TAG-factory.zip"

echo "FASTBOOT_PKG=$FASTBOOT_DIR/$TAG-factory.zip" > "$WORK_DIR/fastboot.env"
echo "FASTBOOT_TAG=$TAG" >> "$WORK_DIR/fastboot.env"

ok "线刷目录（含镜像与脚本）: $PKG"

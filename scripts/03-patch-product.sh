#!/usr/bin/env bash
# ============================================================================
#  03-patch-product.sh —— 修改 product 分区：追加 lineage.updater.uri
#
#  流程: ota extract -p product → avb unpack(→raw.img) → debugfs 改 build.prop
#        → avb pack(重签+重建 hashtree) → product.new.img
#  追加 upstream.env: PRODUCT_NEW_IMG
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "03: 修改 product 分区（追加 lineage.updater.uri）"
resolve_paths
require_cmds debugfs e2fsck

source "$WORK_DIR/upstream.env"

AVB_KEY="$KEYS_DIR/avb.key"
OTA_ZIP="$DOWNLOAD_DIR/$OTA_FILENAME"

# ---- 1. 提取 product 分区 ---------------------------------------------------
info "提取 product 分区"
"$AVBROOT_BIN" ota extract -i "$OTA_ZIP" -d "$EXTRACT_DIR" -p product
PRODUCT_IMG="$EXTRACT_DIR/product.img"
[[ -f "$PRODUCT_IMG" ]] || { err "未提取到 product.img"; exit 1; }

# ---- 2. avb unpack → avb.toml + raw.img ------------------------------------
info "avb unpack product.img"
UNPACK_DIR="$MODIFY_DIR/product-unpack"
mkdir -p "$UNPACK_DIR"
(
  cd "$UNPACK_DIR"
  "$AVBROOT_BIN" avb unpack -i "$PRODUCT_IMG"
)
RAW_IMG="$UNPACK_DIR/raw.img"
[[ -f "$RAW_IMG" ]] || { err "未生成 raw.img"; exit 1; }

# ---- 3. debugfs 追加 lineage.updater.uri ------------------------------------
info "追加 lineage.updater.uri=${UPDATER_BASE_URL}"
e2fsck -f -y "$RAW_IMG" >/dev/null 2>&1 || true   # 清理脏标志，避免 debugfs -w 拒绝

BP_TMP="$TMP_DIR/build.prop"
debugfs -R "cat /build.prop" "$RAW_IMG" > "$BP_TMP" 2>/dev/null \
  || { err "无法读取 product/build.prop"; exit 1; }

if grep -q '^lineage.updater.uri=' "$BP_TMP"; then
  warn "build.prop 已含 lineage.updater.uri，跳过追加"
else
  echo "lineage.updater.uri=${UPDATER_BASE_URL}" >> "$BP_TMP"
  # 写回：删旧 inode → 写入新文件 → 恢复权限位 0644
  debugfs -w -R "rm /build.prop" "$RAW_IMG" >/dev/null 2>&1 || true
  debugfs -w -R "write $BP_TMP /build.prop" "$RAW_IMG" >/dev/null 2>&1 \
    || { err "写入 /build.prop 失败"; exit 1; }
  debugfs -w -R "set_inode_field /build.prop mode 0100644" "$RAW_IMG" >/dev/null 2>&1 || true
  ok "已追加 lineage.updater.uri"
fi
e2fsck -f -y "$RAW_IMG" >/dev/null 2>&1 || true

# ---- 4. avb pack（重签 + 重建 hashtree）-------------------------------------
info "avb pack product.img（重签 + 重建 hashtree）"
PASS_ARG=()
[[ -n "${KEY_PASSPHRASE:-}" ]] && PASS_ARG=(--pass-env-var KEY_PASSPHRASE)
(
  cd "$UNPACK_DIR"
  "$AVBROOT_BIN" avb pack -o "$MODIFY_DIR/product.new.img" -k "$AVB_KEY" \
    --recompute-size "${PASS_ARG[@]}"
)
[[ -f "$MODIFY_DIR/product.new.img" ]] || { err "product.new.img 生成失败"; exit 1; }

cat >> "$WORK_DIR/upstream.env" <<EOF
PRODUCT_NEW_IMG='$MODIFY_DIR/product.new.img'
EOF
ok "03 完成"

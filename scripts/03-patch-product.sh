#!/usr/bin/env bash
# ============================================================================
#  03-patch-product.sh —— 修改 product 分区：追加 lineage.updater.uri
#
#  流程: ota extract -p product → avb unpack(→raw.img) → debugfs 改 /etc/build.prop
#        → avb pack(重签+重建 hashtree) → product.new.img
#  追加 upstream.env: PRODUCT_NEW_IMG
#
#  ⚠️ 路径要点（android init property_service.cpp 源码确认）：
#    Android S 起 product 分区的规范属性文件是 **/product/etc/build.prop**；
#    init 的 load_properties_from_partition() 先读 "/<分区>/etc/build.prop"，
#    成功即返回，绝不加载 legacy 的 /product/build.prop（除非 etc 版缺失且
#    ro.product.build.version.sdk <= 30）。因此必须改 /etc/build.prop，
#    改 /build.prop 会被忽略（属性不生效）。
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "03: 修改 product 分区（向 /etc/build.prop 追加 lineage.updater.uri）"
resolve_paths
require_cmds debugfs e2fsck

source "$WORK_DIR/upstream.env"

AVB_KEY="$KEYS_DIR/avb.key"
OTA_ZIP="$DOWNLOAD_DIR/$OTA_FILENAME"

# 分区内属性文件路径（规范位置，见文件头说明）
PROP_IN_IMG="/etc/build.prop"

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
BP_VERIFY="$TMP_DIR/build.prop.verify"

# 用 dump（而不是 cat）提取：cat 在部分 debugfs 版本/镜像上会静默返回空，
# 导致后续把只有一行的空文件写回、截断整个 build.prop。
rm -f "$BP_TMP"
debugfs -R "dump $PROP_IN_IMG $BP_TMP" "$RAW_IMG" >/dev/null 2>&1 || true
[[ -s "$BP_TMP" ]] || {
  err "从镜像提取 $PROP_IN_IMG 失败（文件为空或不存在）。"
  err "若官方镜像使用 legacy 布局，请先确认分区内实际属性文件路径后再改。"
  exit 1
}
# 健全性检查：真实 build.prop 必然含 ro.* 属性，否则说明提取不完整
grep -q '^ro\.' "$BP_TMP" || {
  err "提取到的 $PROP_IN_IMG 不含任何 ro.* 属性，疑似提取不完整，已中止（不写回，避免截断）"
  exit 1
}
info "已提取 $PROP_IN_IMG（$(wc -l < "$BP_TMP") 行）"

if grep -q '^lineage\.updater\.uri=' "$BP_TMP"; then
  warn "$PROP_IN_IMG 已含 lineage.updater.uri，跳过追加"
else
  echo "lineage.updater.uri=${UPDATER_BASE_URL}" >> "$BP_TMP"
  # 写回：删旧 inode → 写入新文件 → 恢复权限位 0644
  debugfs -w -R "rm $PROP_IN_IMG" "$RAW_IMG" >/dev/null 2>&1 || true
  debugfs -w -R "write $BP_TMP $PROP_IN_IMG" "$RAW_IMG" >/dev/null 2>&1 \
    || { err "写入 $PROP_IN_IMG 失败"; exit 1; }
  debugfs -w -R "set_inode_field $PROP_IN_IMG mode 0100644" "$RAW_IMG" >/dev/null 2>&1 || true
  ok "已追加 lineage.updater.uri"
fi
e2fsck -f -y "$RAW_IMG" >/dev/null 2>&1 || true

# ---- 3b. 写回后校验（绝不静默截断） ----------------------------------------
info "校验写回结果"
rm -f "$BP_VERIFY"
debugfs -R "dump $PROP_IN_IMG $BP_VERIFY" "$RAW_IMG" >/dev/null 2>&1 || true
[[ -s "$BP_VERIFY" ]] || { err "写回后无法从镜像读取 $PROP_IN_IMG"; exit 1; }
grep -q '^ro\.' "$BP_VERIFY" || {
  err "写回后 $PROP_IN_IMG 丢失 ro.* 属性（原内容被破坏），已中止"
  exit 1
}
grep -q "^lineage\.updater\.uri=${UPDATER_BASE_URL}$" "$BP_VERIFY" || {
  err "写回后未找到 lineage.updater.uri=${UPDATER_BASE_URL}，已中止"
  exit 1
}
ok "校验通过：$PROP_IN_IMG 含原属性 + lineage.updater.uri（共 $(wc -l < "$BP_VERIFY") 行）"

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

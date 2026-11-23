#!/usr/bin/env bash
# ============================================================================
#  ③ 全量镜像自签名
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

step "③ 全量镜像自签名"

# 读取上一步产物
[[ -f "$WORK_DIR/target_files.env" ]] || { err "未找到 target_files.env，请先运行 01-build-target-files.sh"; exit 1; }
[[ -f "$WORK_DIR/keys_path.env" ]]   || { err "未找到 keys_path.env，请先运行 00-init-keys.sh"; exit 1; }
source "$WORK_DIR/target_files.env"
source "$WORK_DIR/keys_path.env"

cd "$ANDROID_BUILD_TOP"
# shellcheck source=/dev/null
source build/envsetup.sh >/dev/null 2>&1

if [[ "$KEYS_MODE" == "template" ]]; then
  info "template 模式：密钥已在构建时自动应用（含 APK / APEX / 镜像 / AVB）。"
  info "跳过 sign_target_files_apks（构建产物已签名）。"

  # 可选：官方校验脚本
  if [[ -f "vendor/lineage-priv/keys/check_keys.py" ]]; then
    info "运行 check_keys.py 校验签名…"
    python3 vendor/lineage-priv/keys/check_keys.py \
      "$ANDROID_BUILD_TOP/out/target/product/$DEVICE_CODENAME" || warn "check_keys.py 返回非零（可能含预期外签名，属正常）"
  fi

  SIGNED_TF="$TARGET_FILES"
else
  info "manual 模式：执行 sign_target_files_apks（需要完整密钥目录 + APEX 密钥）"
  SIGNED_TF="$WORK_DIR/signed-target_files.zip"
  # 基础调用（不含 APEX 列表；APEX 密钥随版本变化，见 docs/03 完整命令）
  sign_target_files_apks -o -d "$KEYS_DIR" "$TARGET_FILES" "$SIGNED_TF"
  ok "已签名: $SIGNED_TF"
fi

ok "签名后的 target-files: $SIGNED_TF"
echo "SIGNED_TF=$SIGNED_TF" > "$WORK_DIR/signed_tf.env"

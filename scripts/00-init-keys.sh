#!/usr/bin/env bash
# ============================================================================
#  ① 生成签名密钥（含 APEX 密钥 + AVB 硬件信任根密钥）
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

step "① 生成签名密钥（含 AVB 硬件信任根密钥）"
require_dir "$ANDROID_BUILD_TOP" "LineageOS 源码"

cd "$ANDROID_BUILD_TOP"

if [[ "$KEYS_MODE" == "template" ]]; then
  info "模式: template（推荐）—— 使用 LineageOS 官方模板"

  if [[ -d "vendor/lineage-priv/keys" ]]; then
    warn "vendor/lineage-priv/keys 已存在，跳过生成。"
    warn "如需重新生成：删除该目录后重跑本脚本（注意：密钥变更后需做密钥迁移，见 docs/03）。"
  else
    info "复制模板 lineage/scripts/lineage-priv-template -> vendor/lineage-priv/keys"
    if [[ ! -d "lineage/scripts/lineage-priv-template" ]]; then
      err "未找到 lineage/scripts/lineage-priv-template，请确认源码树完整。"
      exit 1
    fi
    mkdir -p vendor/lineage-priv
    cp -r lineage/scripts/lineage-priv-template vendor/lineage-priv/keys

    info "（可选）编辑 vendor/lineage-priv/keys/make_key.sh 可修改证书 subject"
    info "正在生成密钥，请稍候…"
    ( cd vendor/lineage-priv/keys && ./keys.sh )

    ok "密钥生成完成。"
  fi

  KEYS_PATH="$ANDROID_BUILD_TOP/vendor/lineage-priv/keys"

  # 校验关键产物
  for f in platform.x509.pem releasekey.pk8 avb.pk8 avb_custom_key.bin; do
    [[ -f "$KEYS_PATH/$f" ]] || { err "缺少密钥文件: $KEYS_PATH/$f"; exit 1; }
  done
  ok "已确认关键密钥：releasekey.pk8 / avb.pk8 / avb_custom_key.bin"

else
  info "模式: manual —— 需手工生成密钥，此处仅给出指引（不做自动化）"
  cat <<'GUIDE'

请参照 LineageOS 官方文档（wiki.lineageos.org/signing_builds.html）生成密钥：

  1) 通用密钥:
     subject='/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/[email protected]'
     mkdir -p ~/.android-certs
     for cert in bluetooth cyngn-app media networkstack nfc platform releasekey sdk_sandbox shared testcert verity; do
       ./development/tools/make_key ~/.android-certs/$cert "$subject"
     done

  2) APEX 密钥: 需将 make_key 中的 2048 改为 4096 后逐个生成（数量极多）。
     强烈建议改用 template 模式（config.env 中 KEYS_MODE=template），
     它自动生成全部密钥与 AVB 信任根，并让构建自动套用。

  3) AVB 密钥: 生成后需导出 avb_custom_key.bin 公钥用于回锁。

手动模式下后续步骤（签名/OTA）需要完整的密钥目录，请确保已备齐。
GUIDE
  warn "manual 模式未自动化。请准备好密钥目录后继续后续步骤，或改用 template 模式。"
  KEYS_PATH="$KEYS_DIR"
fi

# 记录密钥路径，供后续脚本使用
echo "KEYS_PATH=$KEYS_PATH" > "$WORK_DIR/keys_path.env"
ok "密钥路径已记录: $KEYS_PATH"

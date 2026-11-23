#!/usr/bin/env bash
# ============================================================================
#  ⑦ 提取硬件信任根（AVB 自定义公钥）并生成回锁指引
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

step "⑦ 提取硬件信任根 + 回锁引导"

[[ -f "$WORK_DIR/keys_path.env" ]] || { err "未找到 keys_path.env，请先运行 00-init-keys.sh"; exit 1; }
source "$WORK_DIR/keys_path.env"

# 定位 avb_custom_key.bin（公钥，用于刷入设备）
AVB_PUB=""
for d in "$KEYS_PATH" "$ANDROID_BUILD_TOP/vendor/lineage-priv/keys"; do
  [[ -f "$d/avb_custom_key.bin" ]] && { AVB_PUB="$d/avb_custom_key.bin"; break; }
done
if [[ -z "$AVB_PUB" ]]; then
  err "未找到 avb_custom_key.bin，请确认已用 template 模式生成密钥。"
  err "（若使用 manual 模式，请用 avbtool extract_public_key 导出公钥。）"
  exit 1
fi

# 私钥（用于签名 vbmeta，构建时已使用）
AVB_PRIV=""
for d in "$KEYS_PATH" "$ANDROID_BUILD_TOP/vendor/lineage-priv/keys"; do
  [[ -f "$d/avb.pk8" ]] && { AVB_PRIV="$d/avb.pk8"; break; }
done

cp "$AVB_PUB" "$AVB_DIR/avb_custom_key.bin"
[[ -n "$AVB_PRIV" ]] && cp "$AVB_PRIV" "$AVB_DIR/avb.pk8"

info "硬件信任根公钥: $AVB_PUB"
ok "已复制到: $AVB_DIR/avb_custom_key.bin"
info "公钥 SHA256: $(sha256_of "$AVB_PUB")"
[[ -n "$AVB_PRIV" ]] && info "私钥（勿外泄）: $AVB_DIR/avb.pk8"

# ---- 生成回锁指引 -----------------------------------------------------------
GUIDE="$AVB_DIR/relock-bootloader.md"
cat > "$GUIDE" <<EOF
# Pixel 8 Pro ($DEVICE_CODENAME) bootloader 回锁指引

> 硬件信任根已导出为 \`avb_custom_key.bin\`（本目录）。

## 前置条件（务必满足）
1. 设备当前 bootloader 为「已解锁」状态。
2. 已通过「线刷包」或「OTA」刷入本套自签名系统，且**能正常开机**。
3. **开发者选项 → OEM 解锁（OEM unlocking）已开启**（回锁前最后确认！）。

## 步骤
\`\`\`bash
# 1. 进入 bootloader
adb reboot bootloader

# 2. 刷入硬件信任根（自定义 AVB 公钥）
fastboot flash avb_custom_key avb_custom_key.bin

# 3. 回锁 bootloader
fastboot flashing lock
\`\`\`

## 回锁后行为
- bootloader 将以 \`avb_custom_key.bin\` 作为信任根，验证 vbmeta 启动链。
- 若所有镜像均以对应的 \`avb.pk8\` 签名，系统可正常启动。
- 屏幕可能显示「橙色/yellow」或「自编译系统」提示，属正常。

## 若无法启动（软砖）如何自救
\`\`\`bash
# 前提：回锁前已开启「OEM 解锁」，否则可能无法再次解锁！
fastboot flashing unlock   # 会清空用户数据
\`\`\`

## 重要警告
- 回锁后若镜像签名与信任根不匹配，设备将无法启动。
- 回锁会清空用户数据。
- 一旦回锁且未开启 OEM 解锁，设备将无法再解锁（永久锁死）。
EOF

ok "回锁指引已生成: $GUIDE"

cat <<EOF

================================================================
  硬件信任根已就绪。回锁前请再次确认：
  1) 系统已用本套密钥自签名并可正常启动
  2) 开发者选项已开启「OEM 解锁」
================================================================
EOF

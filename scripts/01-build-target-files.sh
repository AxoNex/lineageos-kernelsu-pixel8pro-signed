#!/usr/bin/env bash
# ============================================================================
#  ② 构建 target-files 包（可选：注入 blu_spark 内核）
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

step "② 构建 target-files 包（含 otatools）"
require_dir "$ANDROID_BUILD_TOP" "LineageOS 源码"

cd "$ANDROID_BUILD_TOP"
# shellcheck source=/dev/null
source build/envsetup.sh >/dev/null 2>&1

# ---- 可选：blu_spark 内核注入 ----------------------------------------------
inject_bluspark() {
  info "查找内核源码目录…"
  local kernel_dir=""
  kernel_dir="$(ls -d kernel/google/* 2>/dev/null | head -1 || true)"
  if [[ -z "$kernel_dir" ]]; then
    kernel_dir="$(ls -d device/google/*-kernel 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "$kernel_dir" ]]; then
    warn "未自动定位内核源码目录。"
    warn "请手动将 blu_spark 内核源码（$BLUSPARK_REPO）集成到内核目录后重跑。"
    warn "详见 docs/02-构建-LineageOS-和-blu_spark.md"
    return
  fi
  info "内核目录: $kernel_dir"
  info "添加 blu_spark 远程并拉取（不自动切分支，需人工确认匹配版本）…"
  git -C "$kernel_dir" remote add bluspark "$BLUSPARK_REPO" 2>/dev/null \
    || git -C "$kernel_dir" remote set-url bluspark "$BLUSPARK_REPO"
  git -C "$kernel_dir" fetch bluspark
  warn "已拉取 blu_spark 分支列表。请确认与 LineageOS $LINEAGE_VERSION 匹配的分支后，"
  warn "在 $kernel_dir 中执行:  git checkout <bluspark分支>"
  warn "切分支完成后重新运行本脚本即可继续构建。"
}

if [[ "${BLUSPARK_INJECT:-false}" == "true" ]]; then
  inject_bluspark
  warn "若尚未切换 blu_spark 分支，请先处理后再继续（重新运行本脚本）。"
fi

# ---- AVB 信任根提示 --------------------------------------------------------
if [[ "${WITH_AVB:-false}" == "true" ]]; then
  warn "已启用 WITH_AVB=true：请确认设备树中已设置（例如 device/google/shusky/BoardConfig.mk 或其 include 中）："
  warn "    WITH_AVB := true"
  warn "否则 vbmeta 可能不会用自建 avb.pk8 签名。"
fi

# ---- 构建 -------------------------------------------------------------------
info "选择设备: $DEVICE_CODENAME"
breakfast "$DEVICE_CODENAME"

info "构建 target-files 包与 otatools（耗时较长）…"
mka target-files-package otatools

# ---- 校验产物 ---------------------------------------------------------------
TARGET_FILES="$(ls -t "$TARGET_FILES_GLOB"/*-target_files-*.zip 2>/dev/null | head -1 || true)"
if [[ -z "$TARGET_FILES" ]]; then
  err "未找到 target-files 包，构建可能失败。"
  exit 1
fi

ok "target-files 包: $TARGET_FILES"
echo "TARGET_FILES=$TARGET_FILES" > "$WORK_DIR/target_files.env"

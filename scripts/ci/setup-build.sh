#!/usr/bin/env bash
# ============================================================================
#  CI 前置脚本（GitHub Actions build-release.yml 调用）
#  ① 安装构建依赖  ② repo 初始化/同步  ③ 注入 blu_spark 内核
#  ④ 恢复签名密钥（保证 OTA 连续性）  ⑤ 写入更新源属性  ⑥ 生成 config.env
#
#  所有配置均通过环境变量传入（见 workflow 的 env / inputs）。
# ============================================================================
set -euo pipefail

# ---- 变量（均可被环境覆盖）--------------------------------------------------
ANDROID_BUILD_TOP="${ANDROID_BUILD_TOP:-/opt/lineage}"
DEVICE="${DEVICE_CODENAME:-husky}"
LINEAGE_BRANCH="${LINEAGE_BRANCH:-lineage-24.0}"
LINEAGE_MANIFEST="${LINEAGE_MANIFEST:-https://github.com/LineageOS/android.git}"
BLUSPARK_REPO="${BLUSPARK_REPO:-https://github.com/engstk/gs}"
BLUSPARK_BRANCH="${BLUSPARK_BRANCH:-blu_spark-17-los}"
BLUSPARK_INJECT="${BLUSPARK_INJECT:-true}"
# 可手动指定内核源码目录（如 kernel/google/zuma），留空则自动探测
BLUSPARK_KERNEL_DIR="${BLUSPARK_KERNEL_DIR:-}"
OUT_DIR="${OUT_DIR:-$ANDROID_BUILD_TOP/release}"
KEYS_MODE="${KEYS_MODE:-template}"
WITH_AVB="${WITH_AVB:-true}"
UPDATER_URI="${UPDATER_URI:-}"
SYNC_UPSTREAM="${SYNC_UPSTREAM:-true}"
CLEAN_BUILD="${CLEAN_BUILD:-false}"

# 本脚本位于 <toolkit>/scripts/ci/，toolkit 根为其上两级
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

c_mag='\033[0;35m'; c_grn='\033[0;32m'; c_yel='\033[0;33m'; c_rst='\033[0m'
step() { echo -e "\n${c_mag}[STEP]${c_rst} $*"; }
ok()   { echo -e "${c_grn}[ OK ]${c_rst} $*"; }
warn() { echo -e "${c_yel}[WARN]${c_rst} $*"; }

# ---- ① 依赖 -----------------------------------------------------------------
step "安装构建依赖…"
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y -qq >/dev/null 2>&1 || true
  sudo apt-get install -y -qq \
    git-core gnupg flex bison build-essential zip curl zlib1g-dev \
    libc6-dev-i386 libncurses5 x11proto-core-dev libx11-dev lib32z1-dev \
    libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig \
    python3 python3-pip repo ccache openssl rsync >/dev/null 2>&1 || true
fi
ok "依赖就绪"

# ---- ② repo 同步 ------------------------------------------------------------
if [[ "$CLEAN_BUILD" == "true" ]]; then
  step "清理 out 目录…"
  rm -rf "$ANDROID_BUILD_TOP/out"
fi

step "repo 同步 LineageOS（$LINEAGE_BRANCH）…"
if [[ "$SYNC_UPSTREAM" != "false" ]]; then
  if [[ ! -d "$ANDROID_BUILD_TOP/.repo" ]]; then
    mkdir -p "$ANDROID_BUILD_TOP"
    ( cd "$ANDROID_BUILD_TOP" && repo init -u "$LINEAGE_MANIFEST" -b "$LINEAGE_BRANCH" --git-lfs )
  fi
  ( cd "$ANDROID_BUILD_TOP" && repo sync -c -j"$(nproc)" --force-sync --no-clone-bundle --no-tags )
  ok "LineageOS 源码就绪"
else
  warn "SYNC_UPSTREAM=false，跳过 repo sync（使用现有源码）"
fi
require_dir() { [[ -d "$1" ]] || { echo "[ERROR] 目录不存在: $1" >&2; exit 1; }; }
require_dir "$ANDROID_BUILD_TOP/.repo"

# ---- ③ blu_spark 内核注入 ---------------------------------------------------
if [[ "$BLUSPARK_INJECT" == "true" ]]; then
  step "注入 blu_spark 内核（$BLUSPARK_BRANCH）…"
  kernel_dir="$BLUSPARK_KERNEL_DIR"
  if [[ -z "$kernel_dir" ]]; then
    kernel_dir="$(ls -d "$ANDROID_BUILD_TOP"/kernel/google/* 2>/dev/null | head -1 || true)"
    [[ -z "$kernel_dir" ]] && kernel_dir="$(ls -d "$ANDROID_BUILD_TOP"/device/google/*-kernel 2>/dev/null | head -1 || true)"
  fi
  if [[ -n "$kernel_dir" && -d "$kernel_dir/.git" ]]; then
    git -C "$kernel_dir" remote add bluspark "$BLUSPARK_REPO" 2>/dev/null \
      || git -C "$kernel_dir" remote set-url bluspark "$BLUSPARK_REPO"
    git -C "$kernel_dir" fetch --depth 1 bluspark "$BLUSPARK_BRANCH"
    git -C "$kernel_dir" checkout -f -B "bluspark-${BLUSPARK_BRANCH}" FETCH_HEAD
    ok "内核目录 $kernel_dir 已切到 $BLUSPARK_BRANCH"
  else
    warn "未定位内核源码目录，跳过 blu_spark 注入（可设 BLUSPARK_KERNEL_DIR 指定）"
  fi
fi

# ---- ④ 恢复签名密钥 ---------------------------------------------------------
step "恢复签名密钥…"
KEYS_DIR="$ANDROID_BUILD_TOP/vendor/lineage-priv/keys"
if [[ -n "${SIGNING_KEYS:-}" ]]; then
  echo "$SIGNING_KEYS" | base64 -d | tar xz -C "$ANDROID_BUILD_TOP"
  if [[ -f "$KEYS_DIR/avb_custom_key.bin" && -f "$KEYS_DIR/releasekey.pk8" ]]; then
    ok "已从 SIGNING_KEYS 恢复密钥到 $KEYS_DIR"
  else
    warn "SIGNING_KEYS 恢复后仍缺少关键密钥，稍后将重新生成（注意密钥变更会破坏 OTA 连续性！）"
  fi
else
  warn "未配置 SIGNING_KEYS secret → 将生成全新密钥（仅限首次构建）。"
  warn "构建完成后务必把 vendor/lineage-priv/keys 打包为 base64 存入仓库 Secret 的 SIGNING_KEYS。"
fi

# ---- ⑤ 写入更新源属性 -------------------------------------------------------
if [[ -n "$UPDATER_URI" ]]; then
  step "写入更新源属性 lineage.updater.uri=$UPDATER_URI"
  mk_file="$(ls "$ANDROID_BUILD_TOP"/device/google/*/lineage_*.mk 2>/dev/null | head -1 || true)"
  [[ -z "$mk_file" ]] && mk_file="$(ls "$ANDROID_BUILD_TOP"/device/google/*/"$DEVICE"*.mk 2>/dev/null | head -1 || true)"
  if [[ -n "$mk_file" ]]; then
    if ! grep -q "lineage.updater.uri" "$mk_file" 2>/dev/null; then
      {
        echo ""
        echo "# 自定义 OTA 更新源（由 CI 自动注入）"
        echo "PRODUCT_PROPERTY_OVERRIDES += \\"
        echo "    lineage.updater.uri=$UPDATER_URI"
      } >> "$mk_file"
      ok "已写入 $mk_file"
    else
      ok "$mk_file 已包含 lineage.updater.uri，跳过"
    fi
  else
    warn "未找到设备 mk 文件，请手动在设备树设置 lineage.updater.uri=$UPDATER_URI"
  fi
fi

# ---- ⑥ 生成 config.env ------------------------------------------------------
step "生成 $TOOLKIT_ROOT/config.env"
cat > "$TOOLKIT_ROOT/config.env" <<EOF
DEVICE_CODENAME="$DEVICE"
LINEAGE_VERSION="$LINEAGE_BRANCH"
ANDROID_BUILD_TOP="$ANDROID_BUILD_TOP"
KEYS_MODE="$KEYS_MODE"
KEYS_DIR=""
WITH_AVB="$WITH_AVB"
UPDATER_BASE_URL="${UPDATER_URI:-https://updates.example.com/updates.json}"
OTA_DOWNLOAD_BASE="https://example.com"
BLUSPARK_REPO="$BLUSPARK_REPO"
BLUSPARK_INJECT="$BLUSPARK_INJECT"
OUT_DIR="$OUT_DIR"
EOF
ok "config.env 已生成"

echo
echo "=============================================================="
echo "  CI 前置完成。源码: $ANDROID_BUILD_TOP  输出: $OUT_DIR"
echo "=============================================================="

#!/usr/bin/env bash
# ============================================================================
#  common.sh —— 公共函数库（被各步骤脚本 source）
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 加载配置 ---------------------------------------------------------------
CONFIG_FILE="${TOOLKIT_ROOT}/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  echo "[ERROR] 未找到配置文件: $CONFIG_FILE" >&2
  echo "        请先执行: cp config.env.example config.env 并填写。" >&2
  exit 1
fi

# ---- 颜色输出 ---------------------------------------------------------------
c_red='\033[0;31m'; c_grn='\033[0;32m'; c_yel='\033[0;33m'
c_blu='\033[0;34m'; c_mag='\033[0;35m'; c_rst='\033[0m'
info() { echo -e "${c_blu}[INFO]${c_rst} $*"; }
ok()   { echo -e "${c_grn}[ OK ]${c_rst} $*"; }
warn() { echo -e "${c_yel}[WARN]${c_rst} $*"; }
err()  { echo -e "${c_red}[ERROR]${c_rst} $*" >&2; }
step() { echo -e "${c_mag}[STEP]${c_rst} $*"; }

# ---- 工具函数 ---------------------------------------------------------------
# 校验必填变量
require_var() {
  local name="$1" val
  val="${!name:-}"
  if [[ -z "$val" ]]; then
    err "配置项 ${name} 未设置，请在 config.env 中填写。"
    exit 1
  fi
}

# 校验目录存在
require_dir() {
  local d="$1" what="$2"
  if [[ ! -d "$d" ]]; then
    err "${what} 目录不存在: $d"
    exit 1
  fi
}

# 校验命令存在
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 1; }
}

# 生成时间戳
build_tag() {
  echo "${DEVICE_CODENAME}-${LINEAGE_VERSION}-$(date +%Y%m%d-%H%M%S)"
}

# 计算 SHA256（兼容 sha256sum / shasum）
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else err "无可用 sha256 工具"; exit 1; fi
}

# ---- 派生路径（供后续脚本复用）---------------------------------------------
# 在 common.sh 被 source 后即计算好
resolve_paths() {
  require_var ANDROID_BUILD_TOP
  require_var DEVICE_CODENAME
  require_var OUT_DIR

  export ANDROID_BUILD_TOP DEVICE_CODENAME OUT_DIR

  # target-files 包所在目录
  TARGET_FILES_GLOB="$ANDROID_BUILD_TOP/out/target/product/$DEVICE_CODENAME/obj/PACKAGING/target_files_intermediates"
  export TARGET_FILES_GLOB

  # 各阶段产物目录
  export WORK_DIR="$OUT_DIR/work"          # 中间产物
  export FASTBOOT_DIR="$OUT_DIR/fastboot"  # 线刷包
  export OTA_DIR="$OUT_DIR/ota"            # OTA 包
  export AVB_DIR="$OUT_DIR/avb"            # 硬件信任根
  export UPDATER_DIR="$OUT_DIR/updater"    # 更新源文件

  mkdir -p "$WORK_DIR" "$FASTBOOT_DIR" "$OTA_DIR" "$AVB_DIR" "$UPDATER_DIR"
}

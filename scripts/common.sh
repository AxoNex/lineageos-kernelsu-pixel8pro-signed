#!/usr/bin/env bash
# ============================================================================
#  common.sh —— 公共函数库（被各步骤脚本 source）
#
#  变量来源优先级：本地 config.env（若存在）→ 环境变量（CI 中由 workflow 注入）
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 加载本地配置（若存在；CI 中通常不存在，直接读环境变量）-------------------
CONFIG_FILE="${TOOLKIT_ROOT}/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# ---- 默认值 -----------------------------------------------------------------
DEVICE_CODENAME="${DEVICE_CODENAME:-husky}"
LINEAGE_API_BASE="${LINEAGE_API_BASE:-https://download.lineageos.org/api/v2/devices}"
BLUSPARK_REPO="${BLUSPARK_REPO:-engstk/gs}"
AVBROOT_VERSION="${AVBROOT_VERSION:-3.39.1}"
AVBROOT_SHA256="${AVBROOT_SHA256:-145378039c372a1c80f3d0df7bdbe59b4ca6f612c10949da426278bb8b9994d7}"
WORK_DIR="${WORK_DIR:-$TOOLKIT_ROOT/.work}"

# ---- 颜色输出 ---------------------------------------------------------------
c_red='\033[0;31m'; c_grn='\033[0;32m'; c_yel='\033[0;33m'
c_blu='\033[0;34m'; c_mag='\033[0;35m'; c_rst='\033[0m'
info() { echo -e "${c_blu}[INFO]${c_rst} $*"; }
ok()   { echo -e "${c_grn}[ OK ]${c_rst} $*"; }
warn() { echo -e "${c_yel}[WARN]${c_rst} $*"; }
err()  { echo -e "${c_red}[ERROR]${c_rst} $*" >&2; }
step() { echo -e "${c_mag}[STEP]${c_rst} $*"; }

# ---- 工具函数 ---------------------------------------------------------------
require_var() {
  local name="$1" val
  val="${!name:-}"
  if [[ -z "$val" ]]; then
    err "必填变量未设置: ${name}（在 config.env 或环境变量中填写）"
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 1; }
}

require_cmds() {
  local c
  for c in "$@"; do require_cmd "$c"; done
}

# 计算 SHA256（兼容 sha256sum / shasum）
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else err "无可用 sha256 工具"; exit 1; fi
}

# ---- 派生路径与更新源地址 ----------------------------------------------------
resolve_paths() {
  mkdir -p "$WORK_DIR"

  export DOWNLOAD_DIR="$WORK_DIR/download"     # 下载的 OTA/内核/avbroot
  export AVBROOT_BIN="$DOWNLOAD_DIR/avbroot"   # avbroot 可执行文件（各脚本共用，避免跨进程丢失）
  export KEYS_DIR="$WORK_DIR/keys"             # 签名密钥
  export EXTRACT_DIR="$WORK_DIR/extract"       # 从 OTA 解出的分区
  export MODIFY_DIR="$WORK_DIR/modify"         # 修改后的分区
  export OUT_DIR="$WORK_DIR/out"               # 最终产物（线刷包/OTA/更新源）
  export PAGES_DIR="$WORK_DIR/pages"           # GitHub Pages 部署目录
  export TMP_DIR="$WORK_DIR/tmp"               # avbroot 临时文件（放磁盘避免爆 RAM）

  mkdir -p "$DOWNLOAD_DIR" "$KEYS_DIR" "$EXTRACT_DIR" "$MODIFY_DIR" \
           "$OUT_DIR" "$PAGES_DIR" "$TMP_DIR"

  # 更新源地址：优先 UPDATER_BASE_URL，否则从 GitHub Pages 推导
  if [[ -z "${UPDATER_BASE_URL:-}" ]]; then
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
      local owner="${GITHUB_REPOSITORY%%/*}"
      local repo="${GITHUB_REPOSITORY##*/}"
      export UPDATER_BASE_URL="https://${owner}.github.io/${repo}/updates.json"
    else
      export UPDATER_BASE_URL="https://updates.example.com/updates.json"
      warn "未设置 UPDATER_BASE_URL 且不在 CI 环境，使用占位地址: ${UPDATER_BASE_URL}"
    fi
  fi

  # avbroot 用 tempfile 库，尊重 TMPDIR（避免写入 RAM 型 /tmp 导致 OOM）
  export TMPDIR="$TMP_DIR"

  # 注意：release tag 带 "v" 前缀（如 v3.39.1），而资产文件名不带（avbroot-3.39.1-...）
  export AVBROOT_URL="https://github.com/chenxiaolong/avbroot/releases/download/v${AVBROOT_VERSION}/avbroot-${AVBROOT_VERSION}-x86_64-unknown-linux-gnu.zip"
  export LINEAGE_API="${LINEAGE_API_BASE}/${DEVICE_CODENAME}/builds"
}

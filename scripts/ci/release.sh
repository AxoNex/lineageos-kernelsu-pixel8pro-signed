#!/usr/bin/env bash
# ============================================================================
#  CI 发布脚本（GitHub Actions build-release.yml 调用，在 make_all.sh 之后）
#  ① 从构建产物提取版本与元数据  ② 生成 updates.json（新格式）
#  ③ 创建 GitHub Release 并上传资产  ④ 准备 GitHub Pages 载荷
# ============================================================================
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?必须设置 GITHUB_REPOSITORY (owner/repo)}"
DEVICE="${DEVICE_CODENAME:-husky}"
ANDROID_BUILD_TOP="${ANDROID_BUILD_TOP:-/opt/lineage}"
OUT_DIR="${OUT_DIR:-$ANDROID_BUILD_TOP/release}"
RELEASE_TYPE="${RELEASE_TYPE:-UNOFFICIAL}"
LINEAGE_MAJOR_MINOR="${LINEAGE_MAJOR_MINOR:-24.0}"

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEN_JSON="$TOOLKIT_ROOT/scripts/gen-updates-json.py"
WORKSPACE="${GITHUB_WORKSPACE:-$TOOLKIT_ROOT}"

c_mag='\033[0;35m'; c_grn='\033[0;32m'; c_rst='\033[0m'
step() { echo -e "\n${c_mag}[STEP]${c_rst} $*"; }
ok()   { echo -e "${c_grn}[ OK ]${c_rst} $*"; }

# ---- ① 定位产物 -------------------------------------------------------------
step "定位构建产物…"
FASTBOOT_ZIP="$(ls -t "$OUT_DIR"/fastboot/*-factory.zip 2>/dev/null | head -1 || true)"
OTA_ZIP="$(ls -t "$OUT_DIR"/ota/*-ota.zip 2>/dev/null | head -1 || true)"
AVB_KEY="$OUT_DIR/avb/avb_custom_key.bin"
[ -n "$FASTBOOT_ZIP" ] || { echo "[ERROR] 未找到线刷包 (fastboot/*-factory.zip)"; exit 1; }
[ -n "$OTA_ZIP" ]      || { echo "[ERROR] 未找到 OTA 包 (ota/*-ota.zip)"; exit 1; }
ok "线刷包: $FASTBOOT_ZIP"
ok "OTA 包: $OTA_ZIP"

# ---- ② 提取版本与元数据 -----------------------------------------------------
step "提取版本元数据…"
BUILD_PROP="$ANDROID_BUILD_TOP/out/target/product/$DEVICE/system/build.prop"
FULL_VERSION=""
PATCH_LEVEL=""
SDK_LEVEL=""
if [[ -f "$BUILD_PROP" ]]; then
  FULL_VERSION="$(grep '^ro.lineage.version=' "$BUILD_PROP" | head -1 | cut -d= -f2- || true)"
  PATCH_LEVEL="$(grep '^ro.build.version.security_patch=' "$BUILD_PROP" | head -1 | cut -d= -f2- || true)"
  SDK_LEVEL="$(grep '^ro.build.version.sdk=' "$BUILD_PROP" | head -1 | cut -d= -f2- || true)"
fi
[ -n "$FULL_VERSION" ] || FULL_VERSION="${LINEAGE_MAJOR_MINOR}-$(date +%Y%m%d)-${RELEASE_TYPE}-${DEVICE}"
[ -n "$PATCH_LEVEL" ] || PATCH_LEVEL="$(date +%Y-%m-%d)"
ok "版本: $FULL_VERSION (type=$RELEASE_TYPE, patch=$PATCH_LEVEL, sdk=${SDK_LEVEL:-?})"

TAG="$FULL_VERSION"
OTA_URL="https://github.com/$REPO/releases/download/$TAG/$(basename "$OTA_ZIP")"

# ---- ③ 生成 updates.json ----------------------------------------------------
step "生成 updates.json（LineageOS 24 新格式）…"
mkdir -p "$OUT_DIR/updater"
GEN_ARGS=( --ota "$OTA_ZIP" --url "$OTA_URL" --version "$FULL_VERSION" --type "$RELEASE_TYPE" --out "$OUT_DIR/updater/updates.json" )
[ -n "$PATCH_LEVEL" ] && GEN_ARGS+=( --os-patch-level "$PATCH_LEVEL" )
[ -n "$SDK_LEVEL" ] && GEN_ARGS+=( --os-sdk-level "$SDK_LEVEL" )
python3 "$GEN_JSON" "${GEN_ARGS[@]}"
ok "updates.json 已生成"

# ---- ④ 创建 Release 并上传资产 ---------------------------------------------
step "创建/更新 GitHub Release: $TAG"
NOTES="## $TAG

- 设备: \`$DEVICE\`（Pixel 8 Pro）
- 类型: \`$RELEASE_TYPE\`
- 基于: LineageOS \`$LINEAGE_MAJOR_MINOR\` + blu_spark

### 资产
- 线刷包: \`$(basename "$FASTBOOT_ZIP")\`
- OTA 包: \`$(basename "$OTA_ZIP")\`
- 硬件信任根: \`avb_custom_key.bin\`

### 安装
线刷参考 docs/05；OTA 通过系统更新（更新源已自动部署到 GitHub Pages）安装。"

ASSETS=( "$FASTBOOT_ZIP" "$OTA_ZIP" )
[ -f "$AVB_KEY" ] && ASSETS+=( "$AVB_KEY" )

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber
else
  gh release create "$TAG" "${ASSETS[@]}" --repo "$REPO" --title "$TAG" --notes "$NOTES"
fi
ok "Release 已发布: https://github.com/$REPO/releases/tag/$TAG"

# ---- ⑤ 准备 Pages 载荷 ------------------------------------------------------
step "准备 GitHub Pages 载荷…"
PAGES_DIR="$WORKSPACE/_pages"
mkdir -p "$PAGES_DIR"
cp "$OUT_DIR/updater/updates.json" "$PAGES_DIR/updates.json"
cat > "$PAGES_DIR/index.html" <<HTML
<!doctype html><meta charset="utf-8"><title>$DEVICE OTA</title>
<pre>updates.json → <a href="updates.json">updates.json</a></pre>
HTML
ok "Pages 载荷: $PAGES_DIR"

# ---- ⑥ 输出摘要 -------------------------------------------------------------
cat <<EOF

===============================================================
  发布完成
  Release : https://github.com/$REPO/releases/tag/$TAG
  更新源  : https://${REPO%%/*}.github.io/${REPO#*/}/updates.json
  OTA URL : $OTA_URL
===============================================================
EOF

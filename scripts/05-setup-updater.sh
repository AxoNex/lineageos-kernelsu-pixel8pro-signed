#!/usr/bin/env bash
# ============================================================================
#  ⑥ 自定义 OTA 更新源：生成 updates.json（LineageOS 24 新格式）+ 设备端属性
#     片段 + 服务示例
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
resolve_paths

step "⑥ 自定义 OTA 更新源（LineageOS 24 裸数组格式）"

[[ -f "$WORK_DIR/ota.env" ]] || { err "未找到 ota.env，请先运行 04-make-ota.sh"; exit 1; }
source "$WORK_DIR/ota.env"

# ---- 从 target-files 提取版本元数据（若可用）------------------------------
FULL_VERSION=""
PATCH_LEVEL=""
SDK_LEVEL=""
if [[ -f "$WORK_DIR/signed_tf.env" ]]; then
  source "$WORK_DIR/signed_tf.env"
  if [[ -f "$SIGNED_TF" ]]; then
    get_prop() {
      unzip -p "$SIGNED_TF" 'SYSTEM/build.prop' 2>/dev/null | grep "^$1=" | head -1 | cut -d= -f2- || true
    }
    FULL_VERSION="$(get_prop ro.lineage.version)"
    PATCH_LEVEL="$(get_prop ro.build.version.security_patch)"
    SDK_LEVEL="$(get_prop ro.build.version.sdk)"
  fi
fi
# 回退到 config 值
[[ -n "$FULL_VERSION" ]] || FULL_VERSION="${LINEAGE_VERSION}-$(date +%Y%m%d)-${RELEASE_TYPE:-UNOFFICIAL}-${DEVICE_CODENAME}"
[[ -n "$PATCH_LEVEL" ]] || PATCH_LEVEL="$(date +%Y-%m-%d)"

# ---- 1) 生成 updates.json（新格式：裸 JSON 数组）---------------------------
info "生成 updates.json（LineageOS 24 格式）…"
GEN_ARGS=(
  --ota "$OTA_DIR/$OTA_NAME"
  --url "$OTA_DOWNLOAD_BASE/$OTA_NAME"
  --version "$FULL_VERSION"
  --type "${RELEASE_TYPE:-UNOFFICIAL}"
  --out "$UPDATER_DIR/updates.json"
)
[[ -n "$PATCH_LEVEL" ]] && GEN_ARGS+=( --os-patch-level "$PATCH_LEVEL" )
[[ -n "$SDK_LEVEL" ]] && GEN_ARGS+=( --os-sdk-level "$SDK_LEVEL" )
python3 "$SCRIPT_DIR/gen-updates-json.py" "${GEN_ARGS[@]}"
ok "updates.json 已生成: $UPDATER_DIR/updates.json"

# ---- 2) 设备端属性修改片段 ------------------------------------------------
info "生成设备端更新源属性片段 …"
cat > "$UPDATER_DIR/device_property.mk" <<EOF
# 将以下内容加入设备 tree（例如 device/google/shusky/lineage_${DEVICE_CODENAME}.mk），
# 然后重新构建，系统更新 App 即会指向自定义更新源。
# 占位符 {device}/{type}/{incr} 会被系统更新 App 自动替换（不写占位符也可，固定 URL 直接生效）。
# 注意：URL 必须 HTTPS 且直接返回 200（不能 302 重定向）。
PRODUCT_PROPERTY_OVERRIDES += \\
    lineage.updater.uri=$UPDATER_BASE_URL
EOF
ok "设备端属性片段: $UPDATER_DIR/device_property.mk"

# ---- 3) 静态服务示例 -------------------------------------------------------
info "生成静态服务示例（serve.py / nginx.conf）…"
cat > "$UPDATER_DIR/serve.py" <<'PYEOF'
#!/usr/bin/env python3
"""极简 OTA 静态服务：本目录下同时放 updates.json 与 OTA zip 即可。
用法: python3 serve.py   # 监听 0.0.0.0:8000"""
import http.server, os

PORT = 8000

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()
    def guess_type(self, path):
        if path.endswith(".json"):
            return "application/json"
        return super().guess_type(path)

os.chdir(os.path.dirname(os.path.abspath(__file__)))
print(f"Serving OTA on http://0.0.0.0:{PORT}")
http.server.ThreadingHTTPServer(("", PORT), Handler).serve_forever()
PYEOF

cat > "$UPDATER_DIR/nginx.conf" <<'EOF'
# 参考 Nginx 配置：把 updates.json 与 OTA zip 放到同一 web 根目录。
# 注意：更新源 URL 必须直接返回 200（不能 302 重定向），否则系统更新 App 会报错。
server {
    listen 80;
    server_name updates.example.com;

    root /var/www/ota;
    autoindex off;

    # 更新源 JSON 接口（裸 JSON 数组）
    location = /updates.json {
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
        try_files /updates.json =404;
    }

    # OTA zip 下载
    location /downloads/ {
        types { application/zip zip; }
    }
}
EOF
ok "服务示例已生成: $UPDATER_DIR/serve.py / $UPDATER_DIR/nginx.conf"

# ---- 4) 提示 ---------------------------------------------------------------
cat <<EOF

================================================================
  更新源就绪。部署要点：
  1) 把 updates.json 与 OTA zip 放到同一目录（zip 地址 = OTA_DOWNLOAD_BASE）
  2) 运行 python3 serve.py 或按 nginx.conf 部署
  3) 在设备 tree 加入 device_property.mk 的内容后重新构建并刷入
  4) 更新源 URL 必须 HTTPS 且直接 200（Updater OkHttp followRedirects=false）
================================================================
EOF

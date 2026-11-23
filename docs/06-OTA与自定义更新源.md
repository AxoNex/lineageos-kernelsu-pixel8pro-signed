# 06 · OTA 包与自定义更新源

## OTA 包制作

`04-make-ota.sh` 调用：

```bash
ota_from_target_files \
  -k "$KEYS_PATH/releasekey" \
  --block --backup=true \
  signed-target_files.zip \
  ota.zip
```

Pixel 8 Pro 为虚拟 A/B 设备，产出的 OTA 为 payload 风格，可由 Recovery（sideload）或系统更新安装。

## 自定义更新源（LineageOS 24 新格式）

### 设备端：改系统更新指向

系统更新 App（`org.lineageos.updater`）通过系统属性 `lineage.updater.uri` 读取更新源地址（空则回退资源里的 `updater_server_url`）。在设备 tree 中加入：

```make
PRODUCT_PROPERTY_OVERRIDES += \
    lineage.updater.uri=https://updates.example.com/updates.json
```

占位符 `{device}` / `{type}`（=`releaseType` 小写）/ `{incr}`（=`buildVersionIncremental`）会被 App 自动替换；不写占位符也可，固定 URL 直接生效。

### ⚠️ 两个关键限制（LineageOS 24）

1. **必须 HTTPS**，且 URL 必须**直接返回 200**（Updater 的 OkHttp 客户端 `followRedirects(false)`，遇到 302 会抛 `Unexpected HTTP status: 302`）。
2. **响应体是裸 JSON 数组**，不再是旧版 `{"response":[...]}`：

```json
[
  {
    "datetime": 1700000000,
    "files": [
      {
        "filename": "husky-24.0-20251123-UNOFFICIAL-ota.zip",
        "sha256": "<OTA zip 的真实 SHA256>",
        "size": 1234567890,
        "url": "https://example.com/downloads/husky-...-ota.zip",
        "os_patch_level": "2025-11-05",
        "os_sdk_level": 36,
        "ota_property_files": "payload.bin:OFFSET:SIZE,payload_properties.txt:OFFSET:SIZE"
      }
    ],
    "type": "UNOFFICIAL",
    "version": "24.0-20251123-UNOFFICIAL-husky"
  }
]
```

字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `datetime` | Long | Unix 秒级时间戳 |
| `files[].filename` | String | OTA 文件名 |
| `files[].sha256` | String | **OTA zip 真实 SHA256**（作为 `downloadId` 并用于校验，错误会导致安装失败） |
| `files[].size` | Long | 字节数 |
| `files[].url` | String | OTA 下载地址 |
| `files[].os_patch_level` | String? | 安全补丁日期 `YYYY-MM-DD`（可选） |
| `files[].os_sdk_level` | Int? | SDK 版本（可选） |
| `files[].ota_property_files` | String? | 逗号分隔 `path:offset:size`，用于 AB 流式安装；省略则回退整包下载安装 |
| `type` | String | 版本类型（对应 `ro.lineage.releasetype`） |
| `version` | String | 版本号（建议 = 新构建的 `ro.lineage.version`，用于判断是否有更新） |

`ota_property_files` 的 `offset` = zip 内压缩数据偏移（局部文件头 30 字节 + 文件名长 + extra 长，累计），`size` = 压缩后大小，路径为 `payload.bin` / `payload_metadata.bin` / `payload_properties.txt`。

### 生成 updates.json

`05-setup-updater.sh` 会自动调用 `scripts/gen-updates-json.py` 生成上述新格式的 `updates.json`（自动计算 sha256 / size / ota_property_files，并从 target-files 提取 `ro.lineage.version` / 安全补丁 / SDK）。

手动生成：

```bash
python3 scripts/gen-updates-json.py \
  --ota husky-...-ota.zip \
  --url https://example.com/downloads/husky-...-ota.zip \
  --version 24.0-20251123-UNOFFICIAL-husky \
  --type UNOFFICIAL \
  --out updates.json
```

### 部署

- 极简：把 `updates.json` 与 OTA zip 放同一目录，`python3 serve.py`（监听 8000）。
- 生产：用 `nginx.conf` 作参考部署 Nginx（更新源 URL 直接返回 200）。
- GitHub 场景：用 `.github/workflows/build-release.yml` 自动部署到 GitHub Pages（见 docs/08）。

## 后续替换具体更新源

当前 `UPDATER_BASE_URL` / `OTA_DOWNLOAD_BASE` 为占位值。确定具体源后只需：
1. 改 `config.env` 中这两个地址；
2. 重跑 `05-setup-updater.sh` 重新生成 `updates.json` 与属性片段；
3. 把 OTA zip 上传到对应下载地址。

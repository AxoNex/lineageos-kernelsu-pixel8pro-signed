# 05 · OTA 与自定义更新源

## 更新源地址存在哪

LineageOS 24 的 Updater 优先读系统属性 **`lineage.updater.uri`**；若未设置，
回退到 App 内置默认 `https://download.lineageos.org/api/v2/devices/{device}/builds`。

官方构建**不设置** `lineage.updater.uri`，所以默认走官方源。本工具在
`product/build.prop` 追加：

```
lineage.updater.uri=https://<owner>.github.io/<repo>/updates.json
```

（`product` 分区是 ext4，属性在 `/product/build.prop`；`build.prop` 允许非 `ro.`
属性，更新器通过 `SystemProperties.get()` 读取。）

## updates.json 格式（LineageOS 24，已变更）

响应体是**裸 JSON 数组**（不是旧版 `{"response": [...]}`）：

```json
[
  {
    "datetime": 1795138123,
    "files": [
      {
        "filename": "24.0-20261120-NIGHTLY-husky-ota.zip",
        "sha256": "<OTA zip 真实 sha256>",
        "size": 1505109676,
        "url": "https://github.com/<owner>/<repo>/releases/download/.../<ota>.zip",
        "os_patch_level": "2026-11-01",
        "os_sdk_level": 37,
        "ota_property_files": "payload_metadata.bin:…:…,payload.bin:…:…,payload_properties.txt:…:…"
      }
    ],
    "type": "nightly",
    "version": "24.0-20261120-NIGHTLY-husky"
  }
]
```

本工具用 `scripts/gen-updates-json.py` 自动生成（含 `sha256`/`size`/
`ota_property_files` 计算）。

## 两个硬性约束（否则更新器报错）

1. **updates.json 的 URL 必须 HTTPS 且直接返回 200**：更新器 HTTP 客户端设了
   `followRedirects(false)`，302 会报 `Unexpected HTTP status: 302`。
   → 所以 `updates.json` 放 **GitHub Pages**（直连 200），而不是
   `releases/latest/download`（302）。
2. **响应是裸数组**：上面格式，不能包 `{"response":...}`。

> OTA 文件本体的 `files[].url` **可以**是 302（下载器会跟随重定向），
> 所以 OTA 本体放 GitHub Releases 没问题。

## 更新器如何工作

- 更新器下载 `updates.json`，取 `version`/`datetime` 与设备当前构建比对，
  判断是否有更新。
- 下载 OTA 时用 `sha256` 作为 downloadId 校验完整性；有 `ota_property_files`
  则走 AB 流式安装，否则回退整包下载安装。
- 关键：avbroot 已把系统内 `otacerts.zip` 换成**你的 OTA 证书**，所以
  更新器只接受你自己签名的 OTA——既能从你的源升级，又拒绝官方原版 OTA。

## 自定义服务器（可选）

默认用 GitHub Pages 托管 `updates.json`，零额外服务器。若想换成自建服务器，
只需把 `UPDATER_BASE_URL` 指向你的服务器（HTTPS + 直连 200），并托管
`updates.json`；OTA 文件 URL 在 `gen-updates-json.py` 里按需改写。

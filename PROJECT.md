# Pixel 8 Pro (husky) 自签名 ROM 一键重打包工具

基于 **LineageOS 官方构建 + blu_spark 内核**，用 [avbroot](https://github.com/chenxiaolong/avbroot)
在**免费版 GitHub runner** 上完成「解包 → 修改 → 重打包 → 自签名」，
产出**线刷包 + OTA 包 + 自定义更新源**，并生成**设备硬件信任根**以支持 bootloader 回锁。

## 核心思路（与源码构建路线不同）

不重新编译 AOSP（源码构建需 ~250GB 磁盘 / 32GB 内存，免费 runner 无法承受），
而是**重打包官方 OTA**：

```
官方 LineageOS OTA (1.4GiB)
   │  avbroot ota extract
   ▼
解包分区 ──► product/build.prop 追加 lineage.updater.uri（自定义更新源）
   │            boot 替换为 blu_spark gs-los 内核镜像
   ▼
avbroot ota patch（重签 + 换 OTA 证书 + 重建 AVB 信任链）
   ▼
自签名 OTA 包 + 线刷包 + updates.json
```

整个流程只做解压 / 改文本 / 重打包 / 签名，磁盘与内存占用小，
**免费版 ubuntu-latest runner 即可完成**。

## 特性

1. **全自动**：GitHub Actions 定期（cron）+ 手动触发，检测上游新版本，有新版才构建发布。
2. **blu_spark 内核**：自动从 `engstk/gs` release 匹配 `gs-los` boot 镜像（LineageOS 专用）。
3. **自定义更新源**：写入 `lineage.updater.uri`，OTA 通过 GitHub Releases 分发、`updates.json` 通过 GitHub Pages 托管。
4. **自签名 + 硬件信任根**：avbroot 生成 AVB/OTA 密钥，`avb_pkmd.bin` 烧入 `avb_custom_key` 分区后即可回锁 bootloader。
5. **密钥持久化**：签名密钥以 base64 存入 GitHub Secret，跨构建复用（保证 OTA 连续性）。

## 目录结构

```
pixel8pro-rom-toolkit/
├── .github/workflows/
│   ├── build-release.yml      # 定期/手动：检测→构建→签名→发布
│   └── init-keys.yml          # 一次性：生成签名密钥
├── scripts/
│   ├── common.sh              # 公共函数库
│   ├── make_all.sh            # 一键执行完整流程
│   ├── 00-check-upstream.sh   # 检测上游新版本
│   ├── 01-download.sh         # 下载 avbroot/OTA/blu_spark
│   ├── 02-keys.sh             # 从 Secret 恢复密钥
│   ├── 03-patch-product.sh    # 追加 lineage.updater.uri
│   ├── 04-patch-ota.sh        # avbroot 重打包 + 签名
│   ├── 05-package.sh          # 线刷包 + updates.json
│   ├── 06-release.sh          # 发布 Releases
│   ├── init-keys.sh           # 生成密钥（本地/手动）
│   └── gen-updates-json.py    # 生成 LineageOS 24 updates.json
├── docs/                      # 中文文档
├── config.env.example         # 配置模板
├── LICENSE                    # Apache-2.0
└── .gitignore
```

## 快速开始

1. 把本目录推到 GitHub 仓库（**仓库必须 public** 才能启用免费 Pages）。
2. 手动运行一次 **「Init Signing Keys」** 工作流，把打印的 base64 存入 Secret `SIGNING_KEYS`（口令则存 `KEY_PASSPHRASE`）。
3. 在 Settings → Pages 把 Source 设为 **GitHub Actions**。
4. 运行 **「Build & Release」** 工作流（或等每周日自动触发）。

详细步骤见 [docs/02-首次配置.md](docs/02-首次配置.md)。

## 文档

| 文档 | 内容 |
|------|------|
| [01-概览与前置条件](docs/01-概览与前置条件.md) | 原理、前置条件、术语 |
| [02-首次配置](docs/02-首次配置.md) | 密钥、Secret、GitHub Pages 一次性配置 |
| [03-工作原理](docs/03-工作原理.md) | 重打包流水线各步骤细节 |
| [04-线刷与回锁](docs/04-线刷与回锁.md) | fastboot 线刷 + 烧信任根 + 回锁 bootloader |
| [05-OTA与自定义更新源](docs/05-OTA与自定义更新源.md) | updates.json 格式、更新器工作方式 |
| [06-常见问题](docs/06-常见问题.md) | FAQ |

## 依赖工具版本（构建时自动下载/校验）

- avbroot v3.39.1（x86_64-unknown-linux-gnu，sha256 校验）
- blu_spark gs-los boot 镜像（GitHub API 动态匹配）
- LineageOS v2 API（检测版本 + 下载 OTA）

## License

本项目采用 [Apache License 2.0](LICENSE)。blu_spark 内核与 LineageOS 为各自项目所有，
本工具仅下载引用、不二次分发其源码。

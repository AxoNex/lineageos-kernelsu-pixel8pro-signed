# Pixel 8 Pro 自签名 ROM 一键制作工具

面向 **Pixel 8 Pro（代号 `husky`）** 的线刷包 / OTA 更新包一键制作脚本，基于 **LineageOS + blu_spark 内核**。

核心能力：

1. **签名密钥生成引导** —— 一键生成全部签名密钥（含 APEX 密钥与 AVB 信任根密钥）；
2. **全量镜像自签名** —— 对 vbmeta / boot / init_boot / vendor_boot / system / vendor 等全部镜像自签名；
3. **硬件信任根 + bootloader 回锁** —— 生成 `avb_custom_key.bin` 并引导刷入，实现回锁支持；
4. **线刷包（fastboot）一键打包** —— 输出可一键线刷的完整包；
5. **OTA 更新包制作** —— 输出可被 Recovery / 系统更新安装的 OTA 包；
6. **自定义系统更新源** —— 修改系统更新指向自定义源（先实现可用逻辑，具体更新源后续再替换）；
7. **GitHub Actions 自动构建** —— 定期/手动触发，拉取最新上游 LineageOS + blu_spark，全自动 构建→签名→打包→发布 Releases→自动部署更新服务器（版本号与上游同步）。

---

## 目录结构

```
pixel8pro-rom-toolkit/
├── README.md                        # 本文件
├── config.env.example               # 配置模板（复制为 config.env 后填写）
├── .github/
│   └── workflows/
│       └── build-release.yml        # 自动构建 + 发布工作流
├── scripts/                         # 制作脚本（运行于 Linux 构建机）
│   ├── common.sh                    # 公共函数库
│   ├── 00-init-keys.sh              # ① 生成签名密钥（含 AVB 信任根）
│   ├── 01-build-target-files.sh     # ② 构建 target-files 包（含 blu_spark 注入）
│   ├── 02-sign-images.sh            # ③ 全量镜像自签名
│   ├── 03-make-fastboot-package.sh  # ④ 线刷包打包
│   ├── 04-make-ota.sh               # ⑤ OTA 更新包制作
│   ├── 05-setup-updater.sh          # ⑥ 自定义更新源（updates.json + 服务示例）
│   ├── 06-avb-custom-key.sh         # ⑦ 提取硬件信任根 + 回锁引导
│   ├── gen-updates-json.py          # 生成 LineageOS 24 新格式 updates.json
│   ├── make_all.sh                  # 一键总入口
│   └── ci/
│       ├── setup-build.sh           # CI 前置（repo sync + blu_spark + 密钥恢复）
│       └── release.sh               # CI 发布（gh release + Pages 更新源）
├── windows/                         # Windows 端刷机脚本
│   ├── flash-all.sh                 # Linux/macOS 线刷
│   ├── flash-all.bat                # Windows 线刷
│   └── relock-bootloader.md         # 回锁 bootloader 指引
└── docs/                            # 详细文档
    ├── 01-概览与前置条件.md
    ├── 02-构建-LineageOS-和-blu_spark.md
    ├── 03-密钥生成与自签名.md
    ├── 04-AVB信任根与回锁.md
    ├── 05-线刷包制作.md
    ├── 06-OTA与自定义更新源.md
    ├── 07-常见问题.md
    └── 08-GitHub-Actions-工作流.md   # GitHub Actions 配置说明
```

---

## 快速开始（在 Linux 构建机上执行）

> 构建 LineageOS 需要 Linux（推荐 Ubuntu 20.04/22.04）、约 250GB 磁盘、16GB+ 内存。本工具只负责「打包 + 签名 + 生成更新源」，不负责从头编译（编译命令也已封装在 ①/② 步骤中）。

```bash
# 1. 配置
cp config.env.example config.env
#   编辑 config.env：填 ANDROID_BUILD_TOP（LineageOS 源码根目录）、OUT_DIR、UPDATER_BASE_URL 等

# 2. 一键制作（依次执行 ①→⑦）
./scripts/make_all.sh

# 或分步执行：
./scripts/00-init-keys.sh
./scripts/01-build-target-files.sh
./scripts/02-sign-images.sh
./scripts/03-make-fastboot-package.sh
./scripts/04-make-ota.sh
./scripts/05-setup-updater.sh
./scripts/06-avb-custom-key.sh
```

成品会输出到 `OUT_DIR`（见 config.env），包含：

- `fastboot/` —— 线刷包（`flash-all.sh` / `flash-all.bat` + 全部镜像）
- `ota/` —— 签名 OTA 包 + `updates.json`
- `avb/` —— 硬件信任根 `avb_custom_key.bin` + 回锁指引

---

## GitHub Actions 自动构建（可选）

`.github/workflows/build-release.yml` 提供全自动流水线：定期（cron）或手动触发，拉取最新上游 `lineage-24.0` + `blu_spark-17-los`，自动 构建→签名→打包→发布 GitHub Releases（线刷包 + OTA 包）→ 部署更新服务器到 GitHub Pages。版本号与上游同步（tag = `ro.lineage.version`）。

只需在仓库配置两处（其余自动派生）：

| 配置项 | 位置 | 说明 |
|--------|------|------|
| **签名密钥** `SIGNING_KEYS` | Settings → Secrets | `vendor/lineage-priv/keys` 打包后 base64（保证 OTA 连续性） |
| **runner 标签** `RUNNER_LABELS` | Settings → Variables | self-hosted runner 标签（完整构建需 ~250GB/32GB） |

更新服务器地址自动派生为 `https://<owner>.github.io/<repo>/updates.json` —— 你只需把仓库名告诉 workflow（默认即当前仓库），无需手填完整 URL。

完整说明见 [docs/08-GitHub-Actions-工作流.md](docs/08-GitHub-Actions-工作流.md)。

---

## 核心原理速览

| 需求 | 实现方式 |
|------|----------|
| LineageOS + blu_spark | 基于 LineageOS 源码树构建，`engstk/gs`（blu_spark Pixel 6/7/8/9）内核在构建前注入/替换预编译内核 |
| 自定义更新源 | 修改系统更新 App 读取的 `lineage.updater.uri` 属性指向自建源，源端提供标准 JSON 接口 |
| 全量自签名 | `sign_target_files_apks` 对 APK/APEX/镜像统一替换签名，`ota_from_target_files` 用 releasekey 签名 OTA |
| 硬件信任根 | `keys.sh` 生成的 `avb.pk8`（私钥，用于签名 vbmeta）+ `avb_custom_key.bin`（公钥，刷入 `avb_custom_key` 分区），配合 `WITH_AVB := true` |
| 回锁支持 | 解锁状态下刷入 `avb_custom_key.bin`，随后 `fastboot flashing lock` 回锁，bootloader 以自建密钥为信任根验证启动链 |

---

## ⚠️ 免责声明

- 刷机、回锁 bootloader 均有风险，可能导致数据丢失或设备无法启动（软砖）。
- 回锁前**务必**在开发者选项中开启「OEM 解锁」，否则一旦回锁后无法再解锁。
- 请先在**已解锁**状态下完整验证「系统可正常启动 + 所有镜像签名正确」之后，再执行回锁。
- 本工具不包含 Google 专有镜像（radio/bootloader），仅处理 LineageOS 构建产物。
- 使用本工具产生的任何后果由使用者自行承担。

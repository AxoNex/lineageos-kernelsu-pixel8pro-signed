# 08 · GitHub Actions 自动构建与发布工作流

通过 GitHub Actions 实现：**定期/手动触发 → 拉取最新上游 LineageOS + blu_spark → 全自动构建 → 签名 → 打包 → 发布 GitHub Releases → 自动部署更新服务器**。版本号与上游同步（`24.0` 主版本自动来自 `version.mk`）。

## 工作流文件

`.github/workflows/build-release.yml` —— 主工作流，两个触发源：

| 触发 | 说明 |
|------|------|
| `schedule`（cron） | 定期自动，默认每周日 02:00 UTC，可改 `cron` 行 |
| `workflow_dispatch` | 手动触发，可覆盖 `release_type` / `bluspark_branch` / `clean_build` / `sync_upstream` |

## 运行环境（重要）

完整 LineageOS 构建需 **~250GB 磁盘 / 32GB+ 内存 / 数小时**，GitHub 免费托管 runner（14GB 磁盘 / 7GB 内存 / 6h 上限）**无法胜任**，必须使用 **self-hosted runner**（或付费 larger runner）。

配置 runner 标签：在仓库 **Settings → Secrets and variables → Actions → Variables** 新建变量：

```
名称:  RUNNER_LABELS
值:    ["self-hosted","linux","x64","android-build"]   # 换成你的 runner 标签
```

不设置则回退到默认标签 `["self-hosted","linux","android-build"]`。

## 只需配置的几处（其余自动派生）

| 配置项 | 位置 | 说明 |
|--------|------|------|
| **签名密钥（必配）** | 仓库 **Secret** `SIGNING_KEYS` | `vendor/lineage-priv/keys` 目录打包后 base64；保证 OTA 连续性 |
| **runner 标签** | 仓库 **Variable** `RUNNER_LABELS` | self-hosted runner 标签（见上） |
| **GitHub 仓库地址** | 无需配置 | 自动取 `github.repository`，更新源派生为 `https://<owner>.github.io/<repo>/updates.json` |
| 设备/上游/内核分支 | workflow 顶部 `env:` | 已有默认值，按需改 |

> 更新源地址即「GitHub 仓库地址」派生：`https://<owner>.github.io/<repo>/updates.json`。
> 你只需把 **repo 名称**（owner/repo）告诉 workflow（默认就是当前仓库），无需手填完整 URL。

## 首次配置步骤

1. **启用 GitHub Pages**：仓库 Settings → Pages → Source 选 **GitHub Actions**（一次性）。
2. **准备 runner**：一台 Linux 构建机装好 self-hosted runner，标签如上。
3. **首次运行**：手动 `workflow_dispatch` 触发。首次会生成全新签名密钥。
4. **保存密钥**：构建完成后，登录 runner 打包密钥：
   ```bash
   cd /opt/lineage
   tar cz vendor/lineage-priv/keys | base64 -w0
   ```
   把输出粘贴到仓库 Secret `SIGNING_KEYS`。之后每次构建都复用同一套密钥。
5. **验证更新源**：访问 `https://<owner>.github.io/<repo>/updates.json` 应返回 200 的 JSON 数组。

## 工作流做了什么

```
setup-build.sh（前置）
  ├─ 安装构建依赖
  ├─ repo init/sync（lineage-24.0）
  ├─ 注入 blu_spark 内核（blu_spark-17-los，可配）
  ├─ 从 SIGNING_KEYS 恢复密钥
  ├─ 写入 lineage.updater.uri 属性
  └─ 生成 config.env
        ↓
make_all.sh（复用现有 ①→⑦ 脚本）
  ├─ 生成密钥 → 构建 target-files → 自签名 → 线刷包 → OTA
  └─ updates.json（新格式）+ avb_custom_key.bin
        ↓
release.sh（发布）
  ├─ 提取 ro.lineage.version（版本与上游同步）
  ├─ 用 gen-updates-json.py 生成 updates.json（LineageOS 24 新格式）
  ├─ gh release create 上传 线刷包 + OTA + avb_custom_key.bin
  └─ 准备 GitHub Pages 载荷
        ↓
GitHub Pages 部署（configure-pages → upload → deploy）
```

## 版本同步原理

- `repo init -b lineage-24.0`，构建后系统属性 `ro.lineage.version` = `24.0-YYYYMMDD-<type>-husky`（主版本 `24.0` 自动来自上游 `vendor/lineage/config/version.mk`）。
- Release 的 tag 直接用 `ro.lineage.version`，与上游主版本号保持一致。
- `RELEASE_TYPE`（env/input）控制版本后缀的 buildtype（UNOFFICIAL/NIGHTLY/SNAPSHOT/EXPERIMENTAL）。

## 更新服务器说明

- `updates.json` 部署到 GitHub Pages，**直接返回 200**（满足 LineageOS 24 Updater `followRedirects(false)` 的要求；GitHub `releases/latest/download/...` 会 302，不可用作更新源 URL）。
- OTA 文件本身放 GitHub Releases（资产 ≤2GB），`updates.json` 里的 `url` 指向 release 资产地址。
- 设备端属性由 `setup-build.sh` 自动写入设备树 `lineage_husky.mk`。

## 注意事项

- **不要**把签名密钥提交到仓库；用 Secret `SIGNING_KEYS`。
- 若更换签名密钥，已刷机设备的 OTA 会失效（需密钥迁移）。
- blu_spark 分支须与 LineageOS 内核版本线匹配；默认 `blu_spark-17-los`，如不符请改 `BLUSPARK_BRANCH`。
- GitHub Pages 仓库名建议全小写（URL 派生更稳妥）。

# 02 · 构建 LineageOS 与集成 blu_spark 内核

## LineageOS 构建

Pixel 8 Pro 的 LineageOS 设备树位于 `device/google/shusky`（与 Pixel 8 的 shiba 共用同一套 shusky 树）。

```bash
cd "$ANDROID_BUILD_TOP"
source build/envsetup.sh
breakfast husky
mka target-files-package otatools   # 由脚本 01-build-target-files.sh 自动执行
```

产出 target-files 包（脚本会自动记录其路径）。

## 集成 blu_spark 内核

blu_spark 内核源码：**https://github.com/engstk/gs**（Pixel 6/7/8/9 系列）。Pixel 8 Pro 属 Tensor G3（zuma），由该仓库覆盖。

### 方式 A：源码注入（推荐，脚本已封装）

将 blu_spark 内核源码接入 LineageOS 内核树（通常为 `kernel/google/shusky` 或 `kernel/google/zuma`）：

```bash
cd kernel/google/shusky            # 以实际内核目录为准
git remote add bluspark https://github.com/engstk/gs
git fetch bluspark
git checkout <与 LineageOS 版本匹配的 blu_spark 分支>
```

在 `config.env` 中设 `BLUSPARK_INJECT=true`，脚本 `01-build-target-files.sh` 会自动：
1. 定位内核目录；
2. 添加并 fetch blu_spark 远程；
3. 提示你确认/切换匹配的分支。

> 注意：blu_spark 分支需与你所用 LineageOS 内核版本匹配（同一内核版本线）。切换后请核对 `defconfig` 与内核模块与 Pixel 8 Pro 一致。

### 方式 B：替换预编译内核 Image

若 LineageOS 使用预编译内核（`device/google/shusky-kernel` 下的 `Image.lz4` 等），用 blu_spark 构建出的 `Image.lz4` 替换即可。构建 blu_spark 内核请参考其仓库 README 的编译脚本。

## AVB 构建开关

回锁需要 vbmeta 用自建 AVB 密钥签名。在设备树中启用：

```make
WITH_AVB := true
```

（加入 `device/google/shusky/BoardConfig.mk` 或其 include 文件；脚本会在构建前提示确认。）

## 构建耗时

首次完整构建可能需数小时。之后增量构建会快很多。

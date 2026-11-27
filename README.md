<div align="center">
  <h1>Modified LineageOS for Pixel 8 Pro</h1>
  <p>基于LineageOS官方构建的KernelSU+自定义信任根的完整方案</p>

  [![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/AxoNex/lineageos-kernelsu-pixel8pro-signed/build-release.yml)](https://github.com/AxoNex/lineageos-kernelsu-pixel8pro-signed/actions)
  [![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/AxoNex/lineageos-kernelsu-pixel8pro-signed/total)](https://github.com/AxoNex/lineageos-kernelsu-pixel8pro-signed/releases)
  [![License](https://img.shields.io/github/license/AxoNex/lineageos-kernelsu-pixel8pro-signed)](LICENSE)

  中文 · [English](README.en.md)
</div>

基于 **LineageOS 官方构建 + blu_spark 内核**，用 [avbroot](https://github.com/chenxiaolong/avbroot) 在**免费版 GitHub runner** 上完成「解包 → 修改 → 重打包 → 自签名」，产出**线刷包 + OTA 包 + 自定义更新源**，并生成**设备硬件信任根**以支持 bootloader 回锁。

## 功能

- 自定义信任根，支持 Bootloader 重新锁定
- 替换原版内核，使用 [blu_spark](https://github.com/engstk/gs) 内核，以 GKI 形式使用 KernelSU
- 自定义更新源，系统内部更新器接收来自本仓库的更新
- 保持最新，每周自动同步上游版本

## 推荐安装流程

1. 下载 [GrapheneOS](https://grapheneos.org/releases#husky) 的最新安装包，并 `flash-all`
2. 下载本仓库 [Releases](https://github.com/AxoNex/lineageos-kernelsu-pixel8pro-signed/releases) 中最新构建的 `fastboot` 包，并 `flash-all`
3. 重启到恢复模式并格式化 `data` 分区
4. 重启到 bootloader 然后执行 `flashing lock` （警告！推荐保持允许 OEM 解锁开关打开，以免意外修改系统文件后设备变砖。建议使用模块 [OEMUnlockOnBoot](https://github.com/chenxiaolong/OEMUnlockOnBoot/releases) 来确保此开关打开）
5. 安装 [KSU mod](https://github.com/engstk/KernelSU/releases) 来使用 `KernelSU`
6. 谨慎选择模块避免系统文件修改

## 额外信息

关于此项目源代码的详细说明，请见 [PROJECT.md](PROJECT.md)

## 许可

本项目采用 [Apache License 2.0](LICENSE)。blu_spark 内核与 LineageOS 为各自项目所有，本工具仅下载引用、不二次分发其源码。
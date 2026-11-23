# Pixel 8 Pro (husky) bootloader 回锁指引

> 回锁 bootloader 依赖「硬件信任根」：把自建的 AVB 公钥刷入 `avb_custom_key` 分区，
> bootloader 回锁后即以该公钥为信任根验证启动链（vbmeta → boot/init_boot/system/…）。

## 前置条件（务必逐条确认）

1. 设备当前 bootloader 为**已解锁**状态（`fastboot getvar unlocked` 应为 `yes`）。
2. 已用本工具的自签名系统（线刷或 OTA）刷入，且**能正常开机**。
3. **开发者选项 → OEM 解锁（OEM unlocking）已开启** —— 这是回锁后唯一能再次解锁的保命开关，务必回锁前最后确认。
4. 已拿到 `avb_custom_key.bin`（位于工具输出目录 `avb/` 下，与签名用的 `avb.pk8` 私钥配对）。

## 步骤

```bash
# 1. 进入 bootloader
adb reboot bootloader

# 2. 刷入硬件信任根（自定义 AVB 公钥）
fastboot flash avb_custom_key avb_custom_key.bin

# 3. 回锁 bootloader
fastboot flashing lock
```

回锁后设备会重启并开始以自建密钥验证。首次回锁会触发一次用户数据清除。

## 回锁后的屏幕状态

| 状态 | 含义 |
|------|------|
| 正常开机 | 全部镜像签名与信任根匹配 |
| 橙色/黄色「自编译系统」提示 | 信任根为自定义密钥时的正常提示 |
| 「Your device is corrupt」无法启动 | 某分区签名不匹配，需按下方自救 |

## 软砖自救

```bash
# 前提：回锁前已开启「OEM 解锁」，否则可能无法再次解锁
fastboot flashing unlock   # 会清空用户数据
```

## 重要警告

- **回锁会清空用户数据**，请提前备份。
- 回锁后若镜像签名与信任根不匹配，设备将无法启动。
- 一旦回锁且未开启 OEM 解锁，设备将**永久锁死**，无法再解锁刷机。
- `avb.pk8` 私钥必须妥善保存（离线备份）：丢失后无法再签发与已刷入公钥匹配的镜像，也无法正常更新。

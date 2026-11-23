# 04 · AVB 硬件信任根与 bootloader 回锁

## 原理

Pixel bootloader 支持「自定义信任根」：解锁状态下可向 `avb_custom_key` 分区刷入一个自定义 AVB 公钥；回锁后，bootloader 不再使用 Google 出厂密钥，而是以该公钥作为信任根，校验 vbmeta 及其链式分区（boot / init_boot / vendor_boot / system / vendor / …）的签名。

因此：**用哪把私钥签 vbmeta，就必须把配对的公钥刷入 `avb_custom_key`**。

## 密钥对

| 文件 | 用途 |
|------|------|
| `avb.pk8` | 私钥，构建时（`WITH_AVB := true`）用于签名 vbmeta |
| `avb_custom_key.bin` | 公钥，刷入设备的 `avb_custom_key` 分区 |

两者由 `keys.sh` 一并生成（脚本 `00-init-keys.sh` 会校验存在）。

## 制作产物

`06-avb-custom-key.sh` 会把 `avb_custom_key.bin` 复制到输出目录 `avb/`，并生成回锁指引。

## 回锁步骤

```bash
adb reboot bootloader
fastboot flash avb_custom_key avb_custom_key.bin
fastboot flashing lock
```

## 回锁后状态

| 现象 | 含义 |
|------|------|
| 正常开机 | 签名匹配 |
| 橙色/yellow「自编译系统」提示 | 自定义信任根正常状态 |
| 「Your device is corrupt」无法启动 | 签名不匹配（软砖） |

## 自救

```bash
fastboot flashing unlock   # 清空用户数据
```

## 关键风险（务必阅读）

1. **回锁前必须开启「OEM 解锁」**，否则回锁后无法再次解锁，设备永久锁死。
2. **回锁会清空用户数据**。
3. **必须先验证**：解锁状态下完整刷入本套自签名系统并确认能正常开机后，再回锁。
4. Tensor 设备（Pixel 6+）存在 `pvmfw` 等额外分区，务必确认这些分区也已纳入 AVB 链并用自建密钥签名；LineageOS 的构建在 `WITH_AVB := true` 下会统一处理。
5. **保存好 `avb.pk8`**，丢失后无法签发后续 OTA（回锁设备将无法更新）。

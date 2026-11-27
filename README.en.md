<div align="center">
  <h1>Modified LineageOS for Pixel 8 Pro</h1>
  <p>A complete KernelSU + custom trust root solution based on official LineageOS builds</p>

  [![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/AxoNex/lineageos-kernelsu-pixel8pro-signed/build-release.yml)](https://github.com/AxoNex/lineageos-kernelsu-pixel8pro-signed/actions)
  [![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/AxoNex/lineageos-kernelsu-pixel8pro-signed/total)](https://github.com/AxoNex/lineageos-kernelsu-pixel8pro-signed/releases)
  [![License](https://img.shields.io/github/license/AxoNex/lineageos-kernelsu-pixel8pro-signed)](LICENSE)

  English · [中文](README.md)
</div>

Based on **official LineageOS builds + the blu_spark kernel**, this project uses [avbroot](https://github.com/chenxiaolong/avbroot) to perform the full "unpack → modify → repack → self-sign" workflow on **free GitHub runners**. It produces a **fastboot package + OTA package + custom update source**, and generates a **device hardware trust root** to support bootloader relocking.

## Features

- Custom trust root, supporting bootloader relocking
- Replaces the stock kernel with the [blu_spark](https://github.com/engstk/gs) kernel, using KernelSU in GKI form
- Custom update source; the in-system updater receives updates from this repository
- Stays up to date, automatically syncing upstream every week

## Recommended Installation Flow

1. Download the latest [GrapheneOS](https://grapheneos.org/releases#husky) release and run `flash-all`
2. Download the latest `fastboot` package from this repository's [Releases](https://github.com/AxoNex/lineageos-kernelsu-pixel8pro-signed/releases) and run `flash-all`
3. Reboot into recovery and format the `data` partition
4. Reboot to the bootloader and run `flashing lock` (Warning! It is recommended to keep the "Allow OEM unlocking" toggle enabled to avoid bricking the device if system files are accidentally modified. Using the [OEMUnlockOnBoot](https://github.com/chenxiaolong/OEMUnlockOnBoot/releases) module is recommended to ensure this toggle stays enabled)
5. Install the [KSU mod](https://github.com/engstk/KernelSU/releases) to use `KernelSU`
6. Choose modules carefully to avoid modifying system files

> [!NOTE]
> **About OTA Updates**
> As of the last update to this document, when using the built-in system updater to update the system, only the `streaming online update` mode can be used. Disabling this feature or importing a local OTA package will cause the update to fail.

## Additional Information

For a detailed description of this project's source code, please see [PROJECT.md](PROJECT.md).

## License

This project is licensed under the [Apache License 2.0](LICENSE). The blu_spark kernel and LineageOS are owned by their respective projects. This tool only downloads and references them and does not redistribute their source code.
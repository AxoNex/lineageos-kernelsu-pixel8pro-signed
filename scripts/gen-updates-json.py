#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  gen-updates-json.py —— 生成 LineageOS 24.0 更新源 updates.json
#
#  ⚠️ LineageOS 24.0 的 Updater API 已变更：
#      - 响应体是【裸 JSON 数组】，不再是 {"response": [...]}
#      - 每个元素: { datetime, files:[{filename, sha256, size, url,
#                    os_patch_level?, os_sdk_level?, ota_property_files?}],
#                    type, version }
#      - downloadId = sha256（必须为 OTA zip 真实 SHA256）
#      - ota_property_files 用于 AB 流式安装（可选，缺省回退整包下载安装）
#
#  用法:
#     python3 gen-updates-json.py \
#       --ota ota.zip --url https://.../ota.zip \
#       --version 24.0-20251123-UNOFFICIAL-husky --type UNOFFICIAL \
#       [--os-patch-level 2025-11-05] [--os-sdk-level 36] \
#       --out updates.json
# ============================================================================
import argparse
import hashlib
import json
import os
import sys
import time
import zipfile

# zip 局部文件头固定长度（与 LineageOS Updater Utils.getZipEntryOffset 一致）
FIXED_HEADER_SIZE = 30
# 需要计算 offset:size 的条目（与 Updater Constants.AB_PAYLOAD_*_PATH 一致）
AB_PATHS = ("payload_metadata.bin", "payload.bin", "payload_properties.txt")


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ota_property_files(ota_path: str):
    """返回 (value, source)。

    优先直接读 OTA 内 META-INF/com/android/metadata 的 `ota-property-files=`
    行——这个值由打包器（avbroot / ota_from_target_files）按真实 zip 布局算出，
    与官方 LineageOS 服务器下发的 ota_property_files 完全一致。自行累计偏移
    极易算错，见下方 _property_files_from_zip 的注释。

    返回 (None, None) 表示两种方式都失败（此时省略该字段，Updater 回退
    整包下载安装）。
    """
    from_meta = _property_files_from_metadata(ota_path)
    if from_meta:
        return from_meta, "META-INF/com/android/metadata"
    computed = _property_files_from_zip(ota_path)
    if computed:
        return computed, "自行扫描 zip 本地头"
    return None, None


def _property_files_from_metadata(ota_path: str):
    try:
        with zipfile.ZipFile(ota_path) as zf:
            raw = zf.read("META-INF/com/android/metadata")
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"[WARN] 读取 META-INF/com/android/metadata 失败: {exc}\n")
        return None
    for line in raw.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if line.startswith("ota-property-files="):
            value = line.split("=", 1)[1].strip()
            return value or None
    return None


def _property_files_from_zip(ota_path: str):
    """回退方案：自行累计每个条目的数据偏移。

    ⚠️ 逐条累加时**必须计入条目之后的 16 字节 data descriptor**
    （`PK\\x07\\x08` + crc + csize + usize）。avbroot 即使在
    `--zip-mode seekable` 下也仍会写这些描述符（只是把本地头 flags 清零），
    漏算就会出现「真实 3250 被算成 3218」的偏差，设备更新器照着读会拿到
    全零，报 `invalid delta magic: 00000000` /
    `kDownloadInvalidMetadataMagicString (21)`。
    """
    tokens = []
    try:
        with zipfile.ZipFile(ota_path) as zf, open(ota_path, "rb") as fh:
            offset = 0
            for info in zf.infolist():
                name_len = len(info.filename.encode("utf-8"))
                extra_len = len(info.extra) if info.extra else 0
                offset += FIXED_HEADER_SIZE + name_len + extra_len
                if info.filename in AB_PATHS:
                    tokens.append(f"{info.filename}:{offset}:{info.compress_size}")
                offset += info.compress_size
                if info.flag_bits & 0x08:
                    offset += 16
                else:
                    fh.seek(offset)
                    if fh.read(4) == b"PK\x07\x08":
                        offset += 16
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"[WARN] 无法计算 ota_property_files: {exc}\n")
        return None
    return ",".join(tokens) if tokens else None


def verify_payload_offset(ota_path: str, opf: str) -> bool:
    """确认 ota_property_files 里 payload.bin 的偏移处确实是 CrAU 魔数。

    这是「设备更新器不会读到全零」的唯一可靠判据——不通过就直接让构建失败，
    绝不放行一个装不上的包。
    """
    for token in opf.split(","):
        parts = token.split(":")
        if len(parts) != 3 or parts[0] != "payload.bin":
            continue
        try:
            off = int(parts[1])
        except ValueError:
            continue
        with open(ota_path, "rb") as f:
            f.seek(off)
            magic = f.read(4)
        if magic != b"CrAU":
            sys.stderr.write(
                f"[ERROR] ota_property_files 声明 payload.bin 位于偏移 {off}，"
                f"但该处是 {magic!r}（应为 b'CrAU'）。\n"
                f"        设备更新器会读到错误数据，报 "
                f"kDownloadInvalidMetadataMagicString (21)。\n"
            )
            return False
        return True
    return True


def main() -> None:
    ap = argparse.ArgumentParser(description="生成 LineageOS 24.0 updates.json（裸数组格式）")
    ap.add_argument("--ota", required=True, help="OTA zip 路径")
    ap.add_argument("--url", required=True, help="OTA 对外下载地址")
    ap.add_argument("--version", required=True, help="版本号（建议 = ro.lineage.version）")
    ap.add_argument("--type", default="UNOFFICIAL", help="版本类型（ro.lineage.releasetype）")
    ap.add_argument("--os-patch-level", default=None, help="安全补丁日期 YYYY-MM-DD（可选）")
    ap.add_argument("--os-sdk-level", type=int, default=None, help="SDK 版本整数（可选）")
    ap.add_argument("--datetime", type=int, default=None, help="Unix 秒级时间戳（默认当前时间）")
    ap.add_argument("--out", required=True, help="输出 updates.json 路径")
    args = ap.parse_args()

    if not os.path.isfile(args.ota):
        sys.stderr.write(f"[ERROR] OTA 不存在: {args.ota}\n")
        sys.exit(1)

    size = os.path.getsize(args.ota)
    digest = sha256_of(args.ota)
    dt = args.datetime if args.datetime else int(time.time())
    opf, opf_source = ota_property_files(args.ota)
    if opf and not verify_payload_offset(args.ota, opf):
        sys.exit(1)

    file_entry = {
        "filename": os.path.basename(args.ota),
        "sha256": digest,
        "size": size,
        "url": args.url,
    }
    if args.os_patch_level:
        file_entry["os_patch_level"] = args.os_patch_level
    if args.os_sdk_level is not None:
        file_entry["os_sdk_level"] = args.os_sdk_level
    if opf:
        file_entry["ota_property_files"] = opf

    payload = [
        {
            "datetime": dt,
            "files": [file_entry],
            "type": args.type,
            "version": args.version,
        }
    ]

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"[ OK ] updates.json -> {args.out}")
    print(f"       version={args.version}  type={args.type}")
    print(f"       size={size}  sha256={digest}")
    if opf:
        print(f"       ota_property_files ({opf_source}) = {opf}")
    else:
        print("       (未生成 ota_property_files，Updater 将整包下载安装)")


if __name__ == "__main__":
    main()

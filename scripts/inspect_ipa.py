"""Reject simulator, encrypted, malformed or wrongly packaged IPAs before delivery."""
import argparse
import json
from pathlib import Path
import plistlib
import struct
import zipfile


def inspect_macho(data: bytes) -> dict:
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin little-endian 64-bit Mach-O executable")
    _, cpu, _, filetype, commands, _, _, _ = struct.unpack_from("<8I", data)
    if cpu != 0x0100000C or filetype != 2:
        raise ValueError("IPA main binary must be an arm64 executable")
    offset = 32
    device = False
    for _ in range(commands):
        if offset + 8 > len(data):
            raise ValueError("Truncated Mach-O load commands")
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command == 0x32:  # LC_BUILD_VERSION; platform 2 = iOS device, 7 = simulator
            if size < 24:
                raise ValueError("Invalid LC_BUILD_VERSION")
            target_platform = struct.unpack_from("<I", data, offset + 8)[0]
            if target_platform != 2:
                raise ValueError(f"Expected iOS device binary; platform={target_platform}")
            device = True
        if command == 0x25:  # LC_VERSION_MIN_IPHONEOS, pre-LC_BUILD_VERSION arm64 device
            device = True
        if command in (0x21, 0x2C):  # LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64
            if size < 20:
                raise ValueError("Invalid encryption command")
            if struct.unpack_from("<I", data, offset + 16)[0] != 0:
                raise ValueError("Executable is encrypted; it cannot be re-signed as a source build")
        offset += size
    if not device:
        raise ValueError("Mach-O is missing an iOS device platform command")
    return {"architecture": "arm64", "platform": "iOS device", "encrypted": False}


def inspect(path: Path) -> dict:
    with zipfile.ZipFile(path) as archive:
        infos = [name for name in archive.namelist()
                 if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
        if len(infos) != 1:
            raise ValueError("Expected exactly one Payload/*.app/Info.plist")
        app_root = infos[0].rsplit("/", 1)[0]
        info = plistlib.loads(archive.read(infos[0]))
        executable = info.get("CFBundleExecutable", "")
        if not executable or "/" in executable or executable in (".", ".."):
            raise ValueError("Invalid CFBundleExecutable")
        result = inspect_macho(archive.read(app_root + "/" + executable))
        result.update(bundle_id=info.get("CFBundleIdentifier"), minimum_ios=info.get("MinimumOSVersion"))
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.ipa), indent=2))

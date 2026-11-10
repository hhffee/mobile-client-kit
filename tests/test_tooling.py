import importlib.util
import plistlib
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


config = module("make_config")
ipa = module("inspect_ipa")
prepare = module("prepare")


def macho(platform=2, encrypted=False):
    commands = struct.pack("<6I", 0x32, 24, platform, 0, 0, 0)
    commands += struct.pack("<6I", 0x2C, 24, 0, 0, int(encrypted), 0)
    return struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 2, len(commands), 0, 0) + commands


class ToolingTests(unittest.TestCase):
    def test_config_rejects_missing_or_malformed_credentials(self):
        for env in ({}, {"TELEGRAM_API_ID": "0"}, {"TELEGRAM_API_ID": "5", "TELEGRAM_API_HASH": "bad"}):
            with self.assertRaises(ValueError):
                config.configuration(env)

    def test_config_rejects_starlark_injection(self):
        env = {"TELEGRAM_API_ID": "12345", "TELEGRAM_API_HASH": "a" * 32}
        for key, value in (("AYU_BUNDLE_ID", 'org.test.ayu"\nprint("secret")'), ("APPLE_TEAM_ID", 'bad"team')):
            with self.assertRaises(ValueError):
                config.configuration(dict(env, **{key: value}))
        self.assertEqual(config.configuration(env)["app_specific_url_scheme"], "ayupersonal")

    def test_device_macho_accepted(self):
        self.assertEqual(ipa.inspect_macho(macho())["platform"], "iOS device")

    def test_simulator_and_encrypted_binaries_rejected(self):
        for binary in (macho(platform=7), macho(encrypted=True), b"bad", macho()[:38]):
            with self.assertRaises(ValueError):
                ipa.inspect_macho(binary)

    def test_ipa_structure_and_duplicate_apps(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "test.ipa"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Payload/Ayu.app/Info.plist", plistlib.dumps({
                    "CFBundleExecutable": "Ayu", "CFBundleIdentifier": "org.test.ayu", "MinimumOSVersion": "15.0"}))
                archive.writestr("Payload/Ayu.app/Ayu", macho())
            self.assertEqual(ipa.inspect(path)["bundle_id"], "org.test.ayu")
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr("Payload/Other.app/Info.plist", plistlib.dumps({}))
            with self.assertRaises(ValueError):
                ipa.inspect(path)

    def test_patch_anchor_fails_on_ambiguity(self):
        for text in ("missing", "anchor anchor"):
            with self.assertRaises(ValueError):
                prepare.replacement(text, "anchor", "changed", "test")


if __name__ == "__main__":
    unittest.main()

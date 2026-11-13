"""Build arm64 device IPA on macOS. No signing certificates are imported."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(args, cwd=None, env=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, check=True)


def configure_unsigned_packaging(source):
    # Pinned rules_apple embeds the device profile in a separate partial even when
    # legacy signing is disabled. Skip that partial only for the explicit unsigned
    # feature; normal signed device builds retain their required profile checks.
    path = source / "build-system/bazel-rules/rules_apple/apple/internal/ios_rules.bzl"
    text = path.read_text(encoding="utf-8")
    old = "    if platform_prerequisites.platform.is_device:\n        processor_partials.append(\n            partials.provisioning_profile_partial("
    new = old.replace(".is_device:", '.is_device and "disable_legacy_signing" not in features:')
    if text.count(new) == 6 and text.count(old) == 0:
        return
    if text.count(old) != 6:
        raise SystemExit("Unexpected rules_apple profile embedding sites; refusing an unverified patch")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "upstream/Telegram-iOS")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("IPA compilation requires macOS and Xcode. This Windows host cannot compile it.")
    lock = json.loads((ROOT / "upstream.lock.json").read_text())
    xcode = subprocess.check_output(["xcodebuild", "-version"], text=True).splitlines()[0]
    if xcode != f"Xcode {lock['xcode']}":
        raise SystemExit(f"Required Xcode {lock['xcode']}; selected: {xcode}. Select the matching installed Xcode with xcode-select.")
    # Validate API credentials before downloading the large upstream checkout.
    config = ROOT / ".local/configuration.json"
    run([sys.executable, ROOT / "scripts/make_config.py", config])
    source = args.source.resolve()
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "init", source])
        run(["git", "-C", source, "remote", "add", "origin", lock["repository"]])
        run(["git", "-C", source, "fetch", "--depth=1", "origin", lock["commit"]])
        run(["git", "-C", source, "checkout", "--detach", "FETCH_HEAD"])
    head = subprocess.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip()
    if head != lock["commit"]:
        raise SystemExit("Existing source checkout differs from upstream.lock.json; use a fresh --source directory.")
    sparse = subprocess.run(["git", "-C", source, "config", "--get", "core.sparseCheckout"], capture_output=True, text=True)
    if sparse.stdout.strip() == "true":
        run(["git", "-C", source, "sparse-checkout", "disable"])
    run(["git", "-C", source, "submodule", "update", "--init", "--recursive", "--jobs", "4"])
    marker = source / ".ayu-overlay.json"
    if marker.exists():
        overlay = json.loads(marker.read_text())
        if overlay != {"upstream": head, "unsigned": True}:
            raise SystemExit("Existing overlay is incompatible; use a fresh --source directory.")
    else:
        run([sys.executable, ROOT / "scripts/prepare.py", source, "--unsigned"])
    configure_unsigned_packaging(source)
    build_number = os.environ.get("GITHUB_RUN_NUMBER", "1")
    if not build_number.isdigit():
        raise SystemExit("Build number must be numeric")
    # Xcode-managed configuration supplies empty APS environment without needing fake
    # profiles. The overlay explicitly disables profiles, extensions and legacy signing.
    run([sys.executable, "build-system/Make/Make.py", "build",
         f"--configurationPath={config}", "--xcodeManagedCodesigning",
         f"--buildNumber={build_number}", "--configuration=release_arm64"], cwd=source)
    artifact = source / "bazel-bin/Telegram/Telegram.ipa"
    if not artifact.is_file():
        raise SystemExit("Build returned success but no device IPA exists")
    destination = ROOT / "dist/AyuPersonal-unsigned.ipa"
    destination.parent.mkdir(exist_ok=True)
    shutil.copyfile(artifact, destination)
    run([sys.executable, ROOT / "scripts/inspect_ipa.py", destination])
    print(f"Device IPA built for subsequent signing: {destination}")


if __name__ == "__main__":
    main()

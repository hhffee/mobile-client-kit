"""Package only project sources and a reviewable upstream patch; never include private config."""
import difflib
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / "upstream/Telegram-iOS"


def main():
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    patch = subprocess.check_output(["git", "-C", str(UPSTREAM), "-c", "core.autocrlf=false", "diff", "--binary"], text=True, encoding="utf-8")
    added = [
        "submodules/TelegramCore/Sources/AyuSettings.swift",
        "submodules/TelegramCore/Sources/AyuHistoryStore.swift",
        "submodules/TelegramCore/Sources/AyuHistoryBridge.swift",
        "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/AyuSettingsController.swift",
    ]
    for name in added:
        contents = (UPSTREAM / name).read_text(encoding="utf-8")
        patch += f"diff --git a/{name} b/{name}\nnew file mode 100644\n"
        patch += "".join(difflib.unified_diff([], contents.splitlines(keepends=True), fromfile="/dev/null", tofile="b/" + name))
    (output / "telegram-ios-overlay.patch").write_text(patch, encoding="utf-8", newline="\n")
    files = [ROOT / name for name in ["README.md", "FEATURES.md", "VALIDATION.md", "upstream.lock.json", ".gitignore"]]
    for directory in ("Sources", "scripts", "tests", ".github"):
        files.extend(path for path in (ROOT / directory).rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc")
    bundle = output / "AyuPersonal-source.zip"
    with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            archive.write(path, path.relative_to(ROOT).as_posix())
        archive.write(output / "telegram-ios-overlay.patch", "telegram-ios-overlay.patch")
    print(f"Source bundle: {bundle}")
    print(f"Reviewable patch: {output / 'telegram-ios-overlay.patch'}")


if __name__ == "__main__":
    main()

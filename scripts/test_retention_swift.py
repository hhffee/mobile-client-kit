"""Exercise the real retention source against an in-memory Postbox boundary."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parts = []
    for name in ("tests/swift/retention-fixtures.swift", "Sources/AyuSettings.swift",
                 "Sources/AyuMessageRetention.swift", "tests/swift/retention-main.swift"):
        text = (ROOT / name).read_text(encoding="utf-8")
        parts.append(text.replace("import Postbox\n", "").replace("import SwiftSignalKit\n", ""))
    with tempfile.TemporaryDirectory(prefix="karigram-retention-") as temporary:
        source = Path(temporary) / "main.swift"
        source.write_text("\n".join(parts), encoding="utf-8")
        binary = Path(temporary) / "retention-checks"
        subprocess.run(["swiftc", "-warnings-as-errors", str(source), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()


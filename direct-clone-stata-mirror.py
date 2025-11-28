"""
Mirror Stata package sources by cloning their remote folders verbatim.

For each entry in `stata_requirements.txt` (headers: `packagename,url`), this script:
- Wipes the existing local mirror folder for that package inside `C:\\admin\\stata_mirror`.
- Recursively downloads everything reachable from the provided URL into that folder using `wget`.

The layout on disk mirrors the upstream site exactly—no `stata.trk` is generated and files are
not rearranged into lettered subdirectories. Stata installers should point directly at each
package's mirrored folder when installing.

Requirements:
- Windows host with `wget` available in `PATH`.
- `stata_requirements.txt` saved in this repository's root with a header row: `packagename,url`.
"""

import csv
import os
import shutil
import subprocess
import sys
from typing import Iterable, Tuple

MIRROR_ROOT = r"C:\\admin\\stata_mirror"
REQ_FILE = "stata_requirements.txt"


def _read_requirements(path: str) -> Iterable[Tuple[str, str]]:
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            pkg = (row.get("packagename") or "").strip()
            url = (row.get("url") or "").strip()
            if not pkg or not url:
                continue
            yield pkg, url


def _ensure_wget_available() -> None:
    if shutil.which("wget"):
        return
    sys.exit("wget is required on PATH to mirror Stata packages.")


def _mirror_package(pkg: str, url: str) -> None:
    dest = os.path.join(MIRROR_ROOT, pkg)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest, exist_ok=True)

    print(f"Mirroring {pkg} from {url} → {dest}")
    cmd = [
        "wget",
        "--mirror",  # enable recursion with timestamping
        "--no-parent",  # don't ascend to parent directories
        "--no-host-directories",  # avoid creating host-based directory layers
        "--directory-prefix",
        dest,
        url,
    ]

    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"Failed to mirror {pkg} from {url}: {exc}")


if __name__ == "__main__":
    if not os.path.exists(REQ_FILE):
        sys.exit(f"Missing requirements file: {REQ_FILE}")

    _ensure_wget_available()
    os.makedirs(MIRROR_ROOT, exist_ok=True)

    any_rows = False
    for package, source_url in _read_requirements(REQ_FILE):
        any_rows = True
        _mirror_package(package, source_url)

    if not any_rows:
        print("No packages listed; nothing mirrored.")

#!/usr/bin/env python3
"""Download Stata packages from SSC into a local mirror.

Usage (from the project root):

    python build-stata-mirror.py

Packages are read from ``stata_requirements.txt`` (one package name per line),
with blank lines and comments (lines starting with ``#``) ignored. Packages are
mirrored into ``C:/admin/stata_mirror`` using the same letter-based directory
layout that SSC uses. For example, package ``reghdfe`` is mirrored to
``C:/admin/stata_mirror/r/reghdfe.zip``.
"""

from __future__ import annotations

import pathlib
import sys
import urllib.error
import urllib.request
from typing import Iterable, List

DEFAULT_REQUIREMENTS = pathlib.Path(__file__).resolve().parent / "stata_requirements.txt"
DEFAULT_DESTINATION = pathlib.Path("C:/admin/stata_mirror")
SSC_BASE = "http://fmwww.bc.edu/repec/bocode"


def read_requirements(path: pathlib.Path) -> List[str]:
    if not path.exists():
        raise FileNotFoundError(f"Missing requirements file at: {path}")

    lines = path.read_text(encoding="utf-8").splitlines()
    cleaned = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        cleaned.append(stripped)
    return cleaned


def mirror_package(package: str, destination: pathlib.Path) -> pathlib.Path:
    first_letter = package[0].lower()
    package_url = f"{SSC_BASE}/{first_letter}/{package}.zip"
    package_dir = destination / first_letter
    package_dir.mkdir(parents=True, exist_ok=True)
    target_path = package_dir / f"{package}.zip"

    request = urllib.request.Request(package_url, headers={"User-Agent": "package-management-mirror/1.0"})
    try:
        with urllib.request.urlopen(request) as response, target_path.open("wb") as output:
            output.write(response.read())
    except urllib.error.HTTPError as exc:  # pragma: no cover - network error handling
        raise RuntimeError(f"Failed to download {package} from {package_url}: {exc}") from exc

    return target_path


def mirror_packages(packages: Iterable[str], destination: pathlib.Path) -> None:
    if not packages:
        print("No packages listed; nothing to mirror.")
        return

    destination.mkdir(parents=True, exist_ok=True)

    for package in packages:
        print(f"Mirroring {package}...")
        mirrored_path = mirror_package(package, destination)
        print(f"  saved to {mirrored_path}")


def main() -> int:
    try:
        packages = read_requirements(DEFAULT_REQUIREMENTS)
    except FileNotFoundError as exc:
        print(exc)
        return 1

    mirror_packages(packages, DEFAULT_DESTINATION)
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Report packages present in a new list but missing from requirements.

Usage (from the project root)::

    python find-new-packages.py

The script reads a ``new.txt`` file (one package name per line, no versions)
and compares it against ``python_requirements.txt``. It prints any packages
that are present in the new list but absent from the requirements. Package
names are compared case-insensitively and with hyphens and underscores treated
as equivalent for basic normalization.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable


def extract_package_names(lines: Iterable[str]) -> set[str]:
    """Normalize package identifiers from requirement-style file contents."""

    names: set[str] = set()
    for raw_line in lines:
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue

        if line.startswith("-e") or line.startswith("--editable"):
            _, _, line = line.partition("=")
            line = line.strip().removeprefix("-e").strip()

        base = re.split(r"[<>=!~\s]", line, maxsplit=1)[0]
        base = base.split("[", 1)[0]

        if base:
            names.add(base.replace("_", "-").lower())

    return names


def find_missing_packages(new_path: Path, requirements_path: Path) -> set[str]:
    """Return packages present in ``new_path`` but absent from ``requirements_path``."""

    new_packages = extract_package_names(new_path.read_text(encoding="utf-8").splitlines())
    existing_packages = extract_package_names(
        requirements_path.read_text(encoding="utf-8").splitlines()
    )

    return new_packages - existing_packages


def main() -> None:
    new_path = Path("new.txt")
    requirements_path = Path("python_requirements.txt")

    missing = find_missing_packages(new_path, requirements_path)
    if not missing:
        print("No new packages detected.")
        return

    print("New packages not present in requirements:")
    for package in sorted(missing):
        print(f"- {package}")


if __name__ == "__main__":
    main()

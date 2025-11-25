"""Emit a tab-separated report from python_requirements.txt using pip show."""

from __future__ import annotations

import csv
import re
import subprocess
from pathlib import Path

DEFAULT_REQS = Path(__file__).with_name("python_requirements.txt")
FIELDS = ["Name", "Version", "Summary", "Home-page", "Location"]
CONSTANTS = ["PyPi", "reviewer", "installer"]


def parse_requirements(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    return [re.split(r"[<>=!~\s]", line.split("#", 1)[0].strip(), 1)[0]
            for line in text.splitlines() if line.strip() and not line.lstrip().startswith(("-e", "-r"))]


def pip_show(name: str) -> dict[str, str]:
    try:
        out = subprocess.check_output(["python", "-m", "pip", "show", name], text=True)
    except subprocess.CalledProcessError:
        return {field: "" for field in FIELDS}
    rows = dict(line.split(": ", 1) for line in out.splitlines() if ": " in line)
    return {field: rows.get(field, "") for field in FIELDS}


def main() -> None:
    reqs = parse_requirements(DEFAULT_REQS)
    writer = csv.writer(__import__("sys").stdout, delimiter="\t", lineterminator="\n")
    writer.writerow(["name", "version", *CONSTANTS, "summary", "url", "location"])
    for name in reqs:
        info = pip_show(name)
        writer.writerow([info["Name"] or name, info["Version"], *CONSTANTS, info["Summary"], info["Home-page"], info["Location"]])


if __name__ == "__main__":
    main()

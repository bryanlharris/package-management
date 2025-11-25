"""Emit a tab-separated report from python_requirements.txt using pip show."""

from __future__ import annotations

import csv
import io
import re
import subprocess
import sys
from pathlib import Path
from typing import TextIO

DEFAULT_REQS = Path(__file__).with_name("python_requirements.txt")
FIELDS = ["Name", "Version", "Summary", "Home-page", "Location"]
CONSTANTS = ["PyPi", "reviewer", "installer"]


def parse_requirements(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    return [re.split(r"[<>=!~\s]", line.split("#", 1)[0].strip(), maxsplit=1)[0]
            for line in text.splitlines() if line.strip() and not line.lstrip().startswith(("-e", "-r"))]


def pip_show(name: str) -> dict[str, str]:
    try:
        out = subprocess.check_output(
            ["python", "-m", "pip", "show", name], text=True, encoding="utf-8", errors="replace"
        )
    except subprocess.CalledProcessError:
        return {field: "" for field in FIELDS}
    rows = dict(line.split(": ", 1) for line in out.splitlines() if ": " in line)
    return {field: rows.get(field, "") for field in FIELDS}


def strip_non_ascii(text: str) -> str:
    return text.encode("ascii", "ignore").decode("ascii")


def configure_stdout(stream: TextIO) -> TextIO:
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        return stream
    except AttributeError:
        # Python versions before 3.7 do not support reconfigure.
        return io.TextIOWrapper(stream.buffer, encoding="utf-8", errors="replace")


def main() -> None:
    reqs = parse_requirements(DEFAULT_REQS)
    stdout = configure_stdout(sys.stdout)
    writer = csv.writer(stdout, delimiter="\t", lineterminator="\n")
    writer.writerow(["name", "version", *CONSTANTS, "summary", "url", "location"])
    for name in reqs:
        info = pip_show(name)
        row = [info["Name"] or name, info["Version"], *CONSTANTS, info["Summary"], info["Home-page"], info["Location"]]
        writer.writerow([strip_non_ascii(value) for value in row])


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Emit a tab-separated report for Stata packages listed in stata_requirements.txt.

The output mirrors the column order used by the Python and R inventory scripts
and appends SSC lookup details: package name, version, source, reviewer,
installer, summary, URL, install location, SSC presence, and SSC URL.
Metadata is derived from the shared ado tree when available.
"""

import argparse
import csv
import os
import requests
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

DEFAULT_REQUIREMENTS = Path(__file__).resolve().parent / "stata_requirements.txt"
DEFAULT_SHARED_ADO = Path(r"C:/Program Files/Stata18/shared_ado")
SUMMARY_LINE_LIMIT = 30


def ensure_windows() -> None:
    """Abort if the host platform is not Windows."""

    if os.name != "nt":
        raise SystemExit("This script is intended to run on Windows hosts only.")


def read_requirements(path: Path) -> List[Dict[str, str]]:
    """Load requirement entries from a CSV with headers packagename,url."""

    if not path.exists():
        raise SystemExit(f"Missing requirements file at: {path}")

    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = [
            {"packagename": (row.get("packagename") or "").strip(), "url": (row.get("url") or "").strip()}
            for row in reader
            if row
        ]

    rows = [row for row in rows if row["packagename"] and row["url"]]

    if not rows:
        raise SystemExit(f"No valid rows found in {path}. Expected headers packagename,url.")

    return rows


def scan_ado_files(base_path: Path) -> Iterable[Path]:
    """Yield all .ado file paths under the shared ado directory."""

    for root, _, files in os.walk(base_path):
        for filename in files:
            if filename.lower().endswith(".ado"):
                yield Path(root) / filename


def find_ado_file(base_path: Path, package: str) -> Optional[Path]:
    """Return the first ado file matching the package name within the shared tree."""

    target = f"{package.lower()}.ado"

    for ado_file in scan_ado_files(base_path):
        if ado_file.name.lower() == target:
            return ado_file

    return None


def extract_local_metadata(filepath: Path) -> Dict[str, Optional[str]]:
    """Extract version and description metadata from the ado header comments."""

    metadata: Dict[str, Optional[str]] = {"version": None, "description": None}

    try:
        with filepath.open("r", encoding="latin-1", errors="ignore") as handle:
            lines = handle.readlines()[:SUMMARY_LINE_LIMIT]
    except OSError:
        return metadata

    for line in lines:
        stripped = line.strip()
        lower = stripped.lower()

        if stripped.startswith("*") and not metadata["description"]:
            metadata["description"] = stripped.lstrip("*").strip()

        if "version" in lower and not stripped.startswith("*"):
            parts = lower.split()
            for idx, token in enumerate(parts):
                if token == "version" and idx + 1 < len(parts):
                    metadata["version"] = parts[idx + 1]
                    break

        if metadata["version"] and metadata["description"]:
            break

    return metadata


def query_ssc(package: str, timeout: float = 5.0) -> Tuple[str, str]:
    """Return SSC presence and URL for the given package, falling back to blanks on error."""

    url = (
        "https://ideas.repec.org/cgi-bin/htsearch?cmd=Search%21&form=extended&m=all&sp=1&wm=wrd&q="
        f"{package}"
    )

    try:
        response = requests.get(url, timeout=timeout)
    except (OSError, requests.RequestException):
        return "", ""

    if response.status_code != 200:
        return "", ""

    found = package.lower() in response.text.lower()
    return ("true" if found else "false"), url


def format_row(
    package: str,
    version: str,
    description: str,
    url: str,
    location: Path,
    ssc_found: str,
    ssc_url: str,
    source: str = "Stata",
) -> str:
    """Format a TSV row using the shared column order."""

    columns = [
        package,
        version,
        source,
        "Reviewer",
        "Installer",
        description,
        url,
        str(location),
        ssc_found,
        ssc_url,
    ]
    return "\t".join(columns)


def resolve_location(shared_root: Path, ado_path: Optional[Path]) -> Path:
    """Choose the best install location for reporting."""

    if ado_path is not None:
        return ado_path.parent

    return shared_root


def print_report(requirements_path: Path, shared_root: Path) -> None:
    ensure_windows()

    requirements = read_requirements(requirements_path)

    if not shared_root.exists():
        raise SystemExit(
            f"Shared ado directory not found at {shared_root}. Run install-stata-baseline.do first."
        )

    for entry in requirements:
        name = entry["packagename"]
        url = entry["url"]

        ado_path = find_ado_file(shared_root, name)
        meta = extract_local_metadata(ado_path) if ado_path else {"version": None, "description": None}

        ssc_found, ssc_url = query_ssc(name)

        version = meta.get("version") or ""
        description = meta.get("description") or ""
        location = resolve_location(shared_root, ado_path)

        print(format_row(name, version, description, url, location, ssc_found, ssc_url))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Print Stata package metadata as TSV")
    parser.add_argument(
        "--requirements",
        type=Path,
        default=DEFAULT_REQUIREMENTS,
        help="Path to stata_requirements.txt",
    )
    parser.add_argument(
        "--shared-ado",
        type=Path,
        default=DEFAULT_SHARED_ADO,
        help="Root of the shared ado directory",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    print_report(args.requirements, args.shared_ado)

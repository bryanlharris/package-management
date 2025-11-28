#!/usr/bin/env python3
"""
Emit a tab-separated report for every Stata package found in the shared ado tree.

The output mirrors the column order used by the Python and R inventory scripts
and appends blank placeholders for SSC presence and URLs alongside package name,
version, source, reviewer, installer, summary, URL, and install location.
Metadata is derived from the shared ado tree when available.
"""

import os
from pathlib import Path
from typing import Dict, Iterable, Optional

DEFAULT_SHARED_ADO = Path(r"C:/Program Files/Stata18/shared_ado")
SUMMARY_LINE_LIMIT = 30


def ensure_windows() -> None:
    """Abort if the host platform is not Windows."""

    if os.name != "nt":
        raise SystemExit("This script is intended to run on Windows hosts only.")


def scan_ado_files(base_path: Path) -> Iterable[Path]:
    """Yield all .ado file paths under the shared ado directory."""

    for root, _, files in os.walk(base_path):
        for filename in files:
            if filename.lower().endswith(".ado"):
                yield Path(root) / filename


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

    def sanitize(field: object) -> str:
        """Coerce fields to strings and strip embedded tabs."""

        return str(field).replace("\t", " ")

    columns = [
        package,
        version,
        source,
        "Reviewer",
        "Installer",
        description,
        url,
        location,
        ssc_found,
        ssc_url,
    ]
    return "\t".join(sanitize(field) for field in columns)


def resolve_location(shared_root: Path, ado_path: Optional[Path]) -> Path:
    """Choose the best install location for reporting."""

    if ado_path is not None:
        return ado_path.parent

    return shared_root


def print_report(shared_root: Path) -> None:
    ensure_windows()

    if not shared_root.exists():
        raise SystemExit(
            f"Shared ado directory not found at {shared_root}. Run install-stata-baseline.do first."
        )

    for ado_path in scan_ado_files(shared_root):
        name = ado_path.stem
        meta = extract_local_metadata(ado_path)

        version = meta.get("version") or ""
        description = meta.get("description") or ""
        location = resolve_location(shared_root, ado_path)

        print(format_row(name, version, description, "", location, "", ""))

if __name__ == "__main__":
    print_report(DEFAULT_SHARED_ADO)

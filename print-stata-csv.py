#!/usr/bin/env python3
"""
Emit a tab-separated report for every Stata package found in the shared ado tree.

The output mirrors the column order used by the Python and R inventory scripts
and appends SSC lookup details: package name, version, source, reviewer,
installer, summary, URL, install location, SSC presence, and SSC URL.
Metadata is sourced from `ssc describe` output for each ado package.
"""

import io
import os
from contextlib import redirect_stdout
from pathlib import Path
from typing import Dict, Iterable, Optional

from pystata import config, stata

DEFAULT_SHARED_ADO = Path(r"C:/Program Files/Stata18/shared_ado")
STATA_EXECUTABLE = Path(r"C:/Program Files/Stata18/StataMP-64.exe")


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


def init_pystata() -> None:
    """Configure pystata to use the Stata MP executable."""

    config.init(executable=str(STATA_EXECUTABLE))


def run_ssc_describe(package: str) -> str:
    """Run `ssc describe` for a package and capture the resulting log."""

    buffer = io.StringIO()
    try:
        with redirect_stdout(buffer):
            stata.run(f"capture noisily ssc describe {package}", echo=False, quietly=True)
    except Exception:
        return ""

    return buffer.getvalue()


def parse_ssc_log(log: str) -> Dict[str, Optional[str]]:
    """Extract metadata fields from `ssc describe` output."""

    metadata: Dict[str, Optional[str]] = {
        "version": None,
        "description": None,
        "url": None,
        "ssc_found": None,
        "ssc_url": None,
    }

    lines = [line.strip() for line in log.splitlines() if line.strip()]

    for line in lines:
        if " from http" in line.lower() and "package" in line.lower():
            parts = line.split(" from ", maxsplit=1)
            if len(parts) == 2:
                metadata["ssc_url"] = parts[1].strip()
                metadata["ssc_found"] = "true"
        if line.lower().startswith("distribution-date"):
            metadata["version"] = line.split(":", maxsplit=1)[-1].strip()

    if metadata["description"] is None:
        for idx, line in enumerate(lines):
            if line.upper() == "TITLE" and idx + 1 < len(lines):
                metadata["description"] = lines[idx + 1].strip()
                break

    if metadata["ssc_url"]:
        metadata["url"] = metadata["ssc_url"]

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

        return str(field).replace("\t", " ").strip()

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
    init_pystata()

    if not shared_root.exists():
        raise SystemExit(
            f"Shared ado directory not found at {shared_root}. Run install-stata-baseline.do first."
        )

    for ado_path in scan_ado_files(shared_root):
        name = ado_path.stem
        log = run_ssc_describe(name)
        meta = parse_ssc_log(log) if log else {}

        version = (meta.get("version") or "") if meta else ""
        description = (meta.get("description") or "") if meta else ""
        url = (meta.get("url") or "") if meta else ""
        ssc_found = (meta.get("ssc_found") or "") if meta else ""
        ssc_url = (meta.get("ssc_url") or "") if meta else ""
        location = resolve_location(shared_root, ado_path)

        print(format_row(name, version, description, url, location, ssc_found, ssc_url))

if __name__ == "__main__":
    print_report(DEFAULT_SHARED_ADO)

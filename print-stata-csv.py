#!/usr/bin/env python3
"""
Emit a tab-separated package report for Stata add-ons installed in the managed
shared ado tree (C:\\Program Files\\Stata18\\shared_ado). The output mirrors
other language exporters with the columns:

    name, version, source, reviewer, installer, summary, URL, location

The script scans the per-letter subfolders created by install-stata-baseline.do,
locates .pkg manifests, and extracts minimal metadata from the manifest and any
associated .ado files. Missing metadata fields are emitted as empty strings.

The script is intentionally dependency-free so it can run on Windows hosts
without additional installations.
"""
from __future__ import annotations

import os
import re
from typing import Dict, Iterable, Tuple

DEFAULT_SHARED_ROOT = r"C:\\Program Files\\Stata18\\shared_ado"
VERSION_PATTERN = re.compile(r"^\*!\s*version\s+(.+)$", re.IGNORECASE)
URL_PATTERN = re.compile(r"https?://\S+")


def normalize(path: str) -> str:
    return os.path.normpath(path)


def read_lines(path: str) -> Iterable[str]:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                yield line.rstrip("\n")
    except FileNotFoundError:
        return []


def version_from_ado(path: str) -> str:
    for line in read_lines(path):
        match = VERSION_PATTERN.match(line.strip())
        if match:
            return match.group(1).strip()
    return ""


def discover_version(package_dir: str, base_name: str) -> str:
    primary = os.path.join(package_dir, f"{base_name}.ado")
    version = version_from_ado(primary)
    if version:
        return version

    for root, _, files in os.walk(package_dir):
        for filename in files:
            if not filename.lower().endswith(".ado"):
                continue
            version = version_from_ado(os.path.join(root, filename))
            if version:
                return version
    return ""


def parse_pkg(path: str) -> Tuple[str, str]:
    summary = ""
    url = ""
    for raw_line in read_lines(path):
        line = raw_line.strip()
        if not summary and line.lower().startswith("d"):
            content = line[1:].strip()
            if content.startswith('"') and content.endswith('"') and len(content) >= 2:
                content = content[1:-1]
            summary = content.strip()
        if not url:
            match = URL_PATTERN.search(raw_line)
            if match:
                url = match.group(0)
        if summary and url:
            break
    return summary.replace("\t", " "), url


def letter_directories(root: str) -> Iterable[str]:
    if not os.path.isdir(root):
        return []
    for name in os.listdir(root):
        candidate = os.path.join(root, name)
        if os.path.isdir(candidate) and (len(name) == 1 or name == "_"):
            yield candidate


def collect_packages(shared_root: str) -> Dict[str, Dict[str, str]]:
    packages: Dict[str, Dict[str, str]] = {}
    for letter_dir in letter_directories(shared_root):
        for current_dir, _, files in os.walk(letter_dir):
            for filename in files:
                if not filename.lower().endswith(".pkg"):
                    continue
                name = os.path.splitext(filename)[0]
                if name in packages:
                    continue
                pkg_path = os.path.join(current_dir, filename)
                summary, url = parse_pkg(pkg_path)
                version = discover_version(current_dir, name)
                packages[name] = {
                    "version": version,
                    "source": "Stata",
                    "reviewer": "Reviewer",
                    "installer": "Installer",
                    "summary": summary,
                    "url": url,
                    "location": normalize(current_dir),
                }
    return packages


def emit(packages: Dict[str, Dict[str, str]]) -> None:
    for name, meta in sorted(packages.items()):
        fields = [
            name,
            meta.get("version", ""),
            meta.get("source", ""),
            meta.get("reviewer", ""),
            meta.get("installer", ""),
            meta.get("summary", ""),
            meta.get("url", ""),
            meta.get("location", ""),
        ]
        print("\t".join(fields))


def main() -> int:
    shared_root = DEFAULT_SHARED_ROOT
    packages = collect_packages(shared_root)
    if not packages:
        return 0
    emit(packages)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

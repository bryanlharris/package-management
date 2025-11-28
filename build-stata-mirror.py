"""
Mirror Stata package sources by resolving the files listed in each package's ``.pkg`` manifest.

For each entry in `stata_requirements.txt` (headers: `packagename,url`), this script:
- Locates the package's `.pkg` file (either the supplied URL or `{base}/{pkgname}.pkg`).
- Parses the manifest's `from` and `file` directives to learn which files belong to the
  package.
- Downloads the manifest and each referenced payload directly into `C:\\admin\\stata_mirror`,
  preserving the upstream folder layout instead of creating per-package subdirectories.
- Skips a package when the manifest cannot be fetched or parsed.

Requirements:
- Windows host.
- Python libraries `requests` and `beautifulsoup4` (installable via pip).
- `stata_requirements.txt` saved in this repository's root with a header row: `packagename,url`.
"""

import csv
import os
import sys
from typing import Iterable, List, Tuple
from urllib.parse import urljoin, urlparse

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


def _ensure_requests_stack_available() -> None:
    try:
        import requests  # noqa: F401
        from bs4 import BeautifulSoup  # noqa: F401
    except ImportError as exc:  # pragma: no cover - dependency check
        sys.exit(
            "Python download crawler requires the 'requests' and 'beautifulsoup4' libraries. "
            "Install them via: python -m pip install requests beautifulsoup4"
        )


def _relative_path(url: str, base_parts) -> str:
    parsed = urlparse(url)
    path = parsed.path
    if path.startswith(base_parts.path):
        path = path[len(base_parts.path) :]
    path = path.lstrip("/")
    return path


def _save_response_content(url: str, dest: str, base_parts, response, is_html: bool) -> None:
    rel_path = _relative_path(url, base_parts)
    if not rel_path:
        rel_path = "index.html" if is_html else os.path.basename(base_parts.path.rstrip("/")) or "downloaded"
    if rel_path.endswith("/"):
        rel_path = os.path.join(rel_path, "index.html") if is_html else rel_path.rstrip("/")

    full_path = os.path.join(dest, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    mode = "wb"
    with open(full_path, mode) as handle:
        handle.write(response.content)


def _resolve_pkg_url(pkg: str, url: str) -> Tuple[str, str]:
    """
    Identify the manifest URL for a package.

    If the provided URL already points at a ``.pkg`` file we reuse it. Otherwise we assume
    the conventional ``{base}/{pkgname}.pkg`` layout that Stata package repositories use
    and append the filename to the supplied base URL.
    """

    parsed = urlparse(url)
    if parsed.path.lower().endswith(".pkg"):
        pkg_url = url
    else:
        base_url = url if url.endswith("/") else f"{url}/"
        pkg_url = urljoin(base_url, f"{pkg}.pkg")

    # urljoin(..., ".") returns the manifest's directory with a trailing slash, which we
    # then reuse when resolving referenced files.
    return pkg_url, urljoin(pkg_url, ".")


def _parse_pkg_manifest(manifest_text: str) -> List[str]:
    """
    Parse a Stata ``.pkg`` file and extract referenced files.

    The .pkg syntax we expect mirrors the common format used by SSC packages::

        * comments start with an asterisk
        from . using mypkg.ado mypkg.sthlp
        file manual.pdf

    "from" lines list relative files after an optional ``using`` token and typically point
    back to the same directory that hosted the ``.pkg`` file. "file" entries explicitly
    list downloadable payloads. Both directives are treated as relative paths, and the
    downloader resolves them against the manifest's directory.
    """

    files: List[str] = []
    for line in manifest_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("*"):
            continue

        tokens = stripped.split()
        directive = tokens[0].lower()
        if directive not in {"from", "file"}:
            continue

        for token in tokens[1:]:
            if token.lower() == "using":
                continue
            files.append(token)

    return files


def _fetch_pkg_and_files(pkg: str, url: str, dest: str) -> None:
    _ensure_requests_stack_available()
    pkg_url, base_url = _resolve_pkg_url(pkg, url)
    base_parts = urlparse(base_url)

    try:
        import requests
    except ImportError:
        _ensure_requests_stack_available()
        import requests

    try:
        pkg_response = requests.get(pkg_url)
        pkg_response.raise_for_status()
    except Exception as exc:
        print(f"Error fetching {pkg} manifest at {pkg_url}: {exc}")
        return

    _save_response_content(pkg_url, dest, base_parts, pkg_response, is_html=False)

    try:
        manifest_files = _parse_pkg_manifest(pkg_response.text)
    except Exception as exc:
        print(f"Error parsing {pkg} manifest at {pkg_url}: {exc}")
        return

    if not manifest_files:
        print(f"Error parsing {pkg} manifest at {pkg_url}: no file entries found")
        return

    for rel_path in manifest_files:
        file_url = urljoin(base_url, rel_path)
        try:
            response = requests.get(file_url)
            response.raise_for_status()
        except Exception as exc:
            print(f"Error downloading {pkg} file {file_url}: {exc}")
            continue

        content_type = (response.headers.get("Content-Type") or "").lower()
        is_html = "text/html" in content_type
        _save_response_content(file_url, dest, base_parts, response, is_html)


def _mirror_package(pkg: str, url: str) -> None:
    if not os.path.isdir(MIRROR_ROOT):
        os.makedirs(MIRROR_ROOT, exist_ok=True)

    # Keep files directly under MIRROR_ROOT; Stata will reference the same relative
    # hierarchy as the upstream host rather than an extra per-package subfolder.
    _fetch_pkg_and_files(pkg, url, MIRROR_ROOT)


if __name__ == "__main__":
    if not os.path.exists(REQ_FILE):
        sys.exit(f"Missing requirements file: {REQ_FILE}")

    os.makedirs(MIRROR_ROOT, exist_ok=True)

    any_rows = False
    for package, source_url in _read_requirements(REQ_FILE):
        any_rows = True
        _mirror_package(package, source_url)

    if not any_rows:
        print("No packages listed; nothing mirrored.")

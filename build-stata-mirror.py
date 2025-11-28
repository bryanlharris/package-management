"""
Mirror Stata package sources by cloning their remote folders verbatim using a Python crawler.

For each entry in `stata_requirements.txt` (headers: `packagename,url`), this script:
- Wipes the existing local mirror folder for that package inside `C:\\admin\\stata_mirror`.
- Recursively downloads everything reachable from the provided URL into that folder using
  Python's `requests` and `beautifulsoup4` libraries.

The layout on disk mirrors the upstream site exactly—no `stata.trk` is generated and files are
not rearranged into lettered subdirectories. Stata installers should point directly at each
package's mirrored folder when installing.

Requirements:
- Windows host.
- Python libraries `requests` and `beautifulsoup4` (installable via pip).
- `stata_requirements.txt` saved in this repository's root with a header row: `packagename,url`.
"""

import csv
import os
import shutil
import sys
from typing import Iterable, Tuple
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


def _should_follow_link(target: str, base_parts) -> bool:
    parsed = urlparse(target)
    if parsed.scheme and parsed.scheme not in {"http", "https"}:
        return False
    netloc = parsed.netloc or base_parts.netloc
    path = parsed.path or "/"
    if netloc != base_parts.netloc:
        return False
    return path.startswith(base_parts.path)


def _crawl_and_download(url: str, base_parts, dest: str, visited: set) -> None:
    if url in visited:
        return
    visited.add(url)

    try:
        import requests
        from bs4 import BeautifulSoup
    except ImportError:
        _ensure_requests_stack_available()
        import requests
        from bs4 import BeautifulSoup

    try:
        response = requests.get(url)
        response.raise_for_status()
    except Exception as exc:
        raise SystemExit(f"Failed to mirror content from {url}: {exc}")

    content_type = (response.headers.get("Content-Type") or "").lower()
    is_html = "text/html" in content_type
    _save_response_content(url, dest, base_parts, response, is_html)

    if not is_html:
        return

    soup = BeautifulSoup(response.text, "html.parser")
    for link in soup.find_all("a"):
        href = link.get("href")
        if not href:
            continue
        target = urljoin(url, href)
        if not _should_follow_link(target, base_parts):
            continue
        _crawl_and_download(target, base_parts, dest, visited)


def _download_with_requests(pkg: str, url: str, dest: str) -> None:
    _ensure_requests_stack_available()
    base_url = url if url.endswith("/") else f"{url}/"
    base_parts = urlparse(base_url)
    print(f"Mirroring {pkg} from {base_url} → {dest} using Python crawler")
    _crawl_and_download(base_url, base_parts, dest, set())


def _mirror_package(pkg: str, url: str) -> None:
    dest = os.path.join(MIRROR_ROOT, pkg)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest, exist_ok=True)

    _download_with_requests(pkg, url, dest)


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

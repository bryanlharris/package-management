#!/usr/bin/env python3
"""Quick experiment to scrape SSC search results for a package homepage and description.

The script is intentionally minimal and focuses on the package name requested in
this investigation (``ashell``). It fetches the Ideas/RePEc SSC search page,
finds the first package result, follows it, and attempts to extract a homepage
link and a description from the package detail page.
"""

from __future__ import annotations

import sys
from typing import Dict, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

SEARCH_TEMPLATE = (
    "https://ideas.repec.org/cgi-bin/htsearch?cmd=Search!&form=extended&m=all&sp=1&wm=wrd&q="
    "{package}"
)


def fetch_html(url: str, timeout: float = 10.0) -> str:
    """Return the response text for ``url`` or raise ``requests.HTTPError`` on failure."""

    response = requests.get(url, timeout=timeout)
    response.raise_for_status()
    return response.text


def parse_first_result(search_html: str, base_url: str) -> Optional[str]:
    """Return the absolute URL of the first SSC result link in the search HTML."""

    soup = BeautifulSoup(search_html, "html.parser")
    result_link = soup.find("a", href=lambda href: href and href.startswith("/c/"))
    if not result_link:
        return None

    return urljoin(base_url, result_link.get("href"))


def extract_details(package_html: str, package_url: str) -> Dict[str, Optional[str]]:
    """Attempt to pull a homepage URL and human-readable description from the package page."""

    soup = BeautifulSoup(package_html, "html.parser")

    homepage = None
    for link in soup.find_all("a", href=True):
        text = (link.get_text() or "").strip().lower()
        if "home" in text or "url" in text:
            homepage = urljoin(package_url, link.get("href"))
            break

    description = None
    meta_desc = soup.find("meta", attrs={"name": "description"})
    if meta_desc and meta_desc.get("content"):
        description = meta_desc["content"].strip()

    if not description:
        # Fall back to the first paragraph on the page if no meta description exists.
        first_para = soup.find("p")
        if first_para:
            description = first_para.get_text(strip=True)

    return {"homepage": homepage, "description": description}


def probe_package(package: str) -> Dict[str, Optional[str]]:
    """End-to-end lookup for the given package name."""

    search_url = SEARCH_TEMPLATE.format(package=package)
    result: Dict[str, Optional[str]] = {"search_url": search_url, "package_url": None, "homepage": None, "description": None}

    try:
        search_html = fetch_html(search_url)
    except requests.RequestException as exc:  # pragma: no cover - diagnostic path
        result["error"] = f"search request failed: {exc}"
        return result

    package_url = parse_first_result(search_html, search_url)
    result["package_url"] = package_url

    if not package_url:
        result["error"] = "no results found"
        return result

    try:
        package_html = fetch_html(package_url)
    except requests.RequestException as exc:  # pragma: no cover - diagnostic path
        result["error"] = f"package page fetch failed: {exc}"
        return result

    details = extract_details(package_html, package_url)
    result.update(details)
    return result


def main(argv: list[str]) -> int:
    package = argv[1] if len(argv) > 1 else "ashell"
    details = probe_package(package)

    for key, value in details.items():
        print(f"{key}: {value}")

    if details.get("error"):
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

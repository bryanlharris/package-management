import os
import csv
import requests
from urllib.parse import urljoin

BASE = r"C:\\admin\\stata_mirror"
REQ = "stata_requirements.txt"

os.makedirs(BASE, exist_ok=True)

trk_lines = [
    "SITE LocalStataMirror",
    f"URL file:///{BASE.replace('\\','/')}"
]

def fetch(url, path, binary=False):
    r = requests.get(url)
    r.raise_for_status()
    with open(path, "wb" if binary else "w", encoding=None if binary else "utf-8") as f:
        f.write(r.content if binary else r.text)

with open(REQ) as f:
    reader = csv.DictReader(f)
    for row in reader:
        pkg = row["packagename"].strip()
        url = row["url"].rstrip("/") + "/"

        letter = pkg[0].lower()
        folder = os.path.join(BASE, letter)
        os.makedirs(folder, exist_ok=True)

        toc_url = urljoin(url, "stata.toc")
        toc_path = os.path.join(folder, "stata.toc")
        if not os.path.exists(toc_path):
            fetch(toc_url, toc_path)

        pkg_url = urljoin(url, f"{pkg}.pkg")
        pkg_path = os.path.join(folder, f"{pkg}.pkg")
        fetch(pkg_url, pkg_path)

        with open(pkg_path) as f2:
            for line in f2:
                line = line.strip()
                if line.startswith("F "):
                    fname = line[2:].strip()
                    file_url = urljoin(url, fname)
                    file_path = os.path.join(folder, fname)
                    fetch(file_url, file_path, binary=True)

        if letter not in trk_lines:
            trk_lines.append(f"{letter} {letter}")

with open(os.path.join(BASE, "stata.trk"), "w") as trk:
    trk.write("\n".join(trk_lines))

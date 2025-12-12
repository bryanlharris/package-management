import os
import re
from pathlib import Path
from collections import defaultdict

packages_dir = Path('C:/admin/pip_mirror')
keep_versions = 3

# Pattern to extract package name and version from wheel filename
# Example: numpy-1.24.3-cp313-cp313-win_amd64.whl
wheel_pattern = re.compile(r'^(.+?)-(\d+\.\d+\.\d+.*?)-(cp\d+|py\d+|py2\.py3)-.+\.whl$')

# Group files by (package name, python version)
packages = defaultdict(list)

for file in packages_dir.glob('*.whl'):
    match = wheel_pattern.match(file.name)
    if match:
        pkg_name = match.group(1)
        pkg_version = match.group(2)
        py_version = match.group(3)
        # Group by both package name AND Python version
        key = (pkg_name, py_version)
        packages[key].append((pkg_version, file))

# Process each package-python combination
total = len(packages)
for index, ((pkg_name, py_version), files) in enumerate(packages.items(), 1):
    print(f'[{index}/{total}] Processing {pkg_name} ({py_version})...')

    # Sort by package version (newest first)
    sorted_files = sorted(files, key=lambda x: x[0], reverse=True)

    # Keep only the newest package versions
    for version, file_path in sorted_files[keep_versions:]:
        print(f'  Deleting {file_path.name}')
        file_path.unlink()

print('Cleanup complete.')

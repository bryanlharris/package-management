import os
import re
from pathlib import Path
from collections import defaultdict

packages_dir = Path('C:/admin/pip_mirror')
keep_versions = 3

# Pattern to extract package name and version from wheel filename
# Example: numpy-1.24.3-cp313-cp313-win_amd64.whl
wheel_pattern = re.compile(r'^(.+?)-(\d+\.\d+\.\d+.*?)-(cp\d+|py\d+|py2\.py3)-.+\.whl$')

# Group files by package name
packages = defaultdict(list)

for file in packages_dir.glob('*.whl'):
    match = wheel_pattern.match(file.name)
    if match:
        pkg_name = match.group(1)
        version = match.group(2)
        packages[pkg_name].append((version, file))

# Process each package
total = len(packages)
for index, (pkg_name, files) in enumerate(packages.items(), 1):
    print(f'[{index}/{total}] Processing {pkg_name}...')

    # Sort by version (newest first)
    sorted_files = sorted(files, key=lambda x: x[0], reverse=True)

    # Keep only the newest versions
    for version, file_path in sorted_files[keep_versions:]:
        print(f'  Deleting {file_path.name}')
        file_path.unlink()

print('Cleanup complete.')

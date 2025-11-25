# Package Management Utilities
This repository contains helper scripts for managing Python package requirements in restricted environments. Use them to capture
and mirror dependencies alongside your code.

## Files
- `freeze_packages.py` — save frozen dependencies to `python_requirements.txt`.
- `build-local-mirror.py` — mirror packages from `python_requirements.txt` into `C:\admin\python_mirror` on Windows.

## Usage
Run the mirror initialization from the repository root on Windows hosts:

```powershell
python build-local-mirror.py
```

After the packages are mirrored, restore a requirements snapshot if needed:

```powershell
python freeze_packages.py
```

# Package Management Utilities
This repository contains helper scripts for managing Python package requirements in restricted environments. Use them to capture
and mirror dependencies alongside your code.

## Files
- `freeze_packages.py` — save frozen dependencies to `python_requirements.txt`.
- `build-local-mirror.py` — mirror packages from `python_requirements.txt` into `C:\admin\python_mirror` on Windows.
- `find-new-packages.py` — list packages in a new list that are missing from `python_requirements.txt`.

## Usage
Run the mirror initialization from the repository root on Windows hosts:

```powershell
python build-local-mirror.py
```

After the packages are mirrored, restore a requirements snapshot if needed:

```powershell
python freeze_packages.py
```

Check for any packages in `new.txt` (one package name per line) that are not already captured in `python_requirements.txt`:

```powershell
python find-new-packages.py
```

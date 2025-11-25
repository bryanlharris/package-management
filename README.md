# Package Management Utilities
This repository contains helper scripts for managing Python package requirements in restricted environments. Use them to capture
and mirror dependencies alongside your code.

## Files
- `freeze-python-packages.py` — save frozen dependencies to `python_requirements.txt`.
- `build-python-mirror.py` — mirror packages from `python_requirements.txt` into `C:\\admin\\python_mirror` on Windows.
- `find-new-python-packages.py` — list packages in a new list that are missing from `python_requirements.txt`.
- `install-python-baseline.py` — install packages from `python_requirements.txt` using the `C:\\admin\\python_mirror` baseline.

## Usage
Run the mirror initialization from the repository root on Windows hosts:

```powershell
python build-python-mirror.py
```

After the packages are mirrored, restore a requirements snapshot if needed:

```powershell
python freeze-python-packages.py
```

Install the baseline requirements from the local mirror (requires an elevated shell):

```powershell
python install-python-baseline.py
```

Check for any packages in `new.txt` (one package name per line) that are not already captured in `python_requirements.txt`:

```powershell
python find-new-python-packages.py
```

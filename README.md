# Package Management Utilities
This repository contains helper scripts for managing Python and R package requirements in restricted environments. Use them to capture
and mirror dependencies alongside your code.

## Files
- `freeze-python-packages.py` — save frozen dependencies to `python_requirements.txt`.
- `build-python-mirror.py` — mirror packages from `python_requirements.txt` into `C:\\admin\\python_mirror` on Windows.
- `build-r-mirror.R` — mirror Windows binary packages from `r_requirements.txt` into `C:\\admin\\r_mirror` on Windows.
- `install-stata-baseline.do` — install Stata packages from `stata_requirements.txt` into the shared ado directory on Windows.
- `find-new-python-packages.py` — list packages in a new list that are missing from `python_requirements.txt`.
- `install-python-baseline.py` — install packages from `python_requirements.txt` using the `C:\\admin\\python_mirror` baseline.
- `install-r-baseline.R` — install packages from `r_requirements.txt` using the `C:\\admin\\r_mirror` baseline.
- `print-python-csv.ps1` — emit a tab-separated report from `python_requirements.txt`.
- `print-r-csv.R` — emit a tab-separated report from `r_requirements.txt` using the local R mirror.

## Usage
Run the mirror initialization from the repository root on Windows hosts:

```powershell
python build-python-mirror.py
Rscript build-r-mirror.R
# Run install-stata-baseline.do in Stata (right-click and choose "Do" on Windows)
```

> The Stata requirements file (`stata_requirements.txt`) must be a CSV with a header row that names
> each column. Use `packagename` and `url` as the headers so that the Stata script can identify the
> package names and their download URLs (the script now explicitly reads the first line as headers
> with `varnames(1)`), for example:
>
> ```csv
> packagename,url
> mypackage,https://example.org/stata/
> ```
>
> If Stata still reports `v1`/`v2` column names, ensure the file is saved as a plain CSV
> (comma-separated, no extra leading rows or UTF-8 BOM) and that the first line exactly matches
> `packagename,url`.

After the packages are mirrored, restore a requirements snapshot if needed:

```powershell
python freeze-python-packages.py
```

Install the baseline requirements from the local mirror (requires an elevated shell):

```powershell
python install-python-baseline.py
Rscript install-r-baseline.R
```

Check for any packages in `new.txt` (one package name per line) that are not already captured in `python_requirements.txt`:

```powershell
python find-new-python-packages.py
```

Export a tab-separated report for the packages listed in `python_requirements.txt`:

```powershell
./print-python-csv.ps1 > report.tsv
```

Export a tab-separated report for the packages listed in `r_requirements.txt` using the local mirror metadata:

```powershell
Rscript print-r-csv.R > r-report.tsv
```

### Pip mirror maintenance
Use the pip-specific maintenance scripts when you need to refresh or prune the Windows Python wheel mirror at `C:\\admin\\pip_mirror`:

- Pull wheels for all requirements across supported Python versions:

  ```powershell
  # Downloads wheels for the requirements listed in pip_requirements_multi_version.txt
  # Optionally scope downloads to a specific interpreter version (for example, -PythonVersion 3.9)
  ./pip-download-packages.ps1
  ./pip-download-packages.ps1 -PythonVersion 3.9
  ```

  `pip-download-packages.ps1` temporarily disables the local `pip.ini` to allow upstream downloads and writes the wheels into `C:\\admin\\pip_mirror`.

- Prune older wheels so only the newest N versions per package and Python ABI remain:

  ```powershell
  python ./pip-cleanup-versions.py
  ```

  The script walks `C:\\admin\\pip_mirror` and keeps only the most recent versions you configure.

- Re-enable pip lockdown to point clients at the local mirror after downloads complete:

  ```powershell
  ./pip-client-lockdown.ps1
  ```

  This restores `pip.ini` with `--no-index` and `--find-links` settings aimed at `C:\\admin\\pip_mirror`.

- Install compiler and SDK prerequisites for packages that need local builds:

  ```powershell
  ./pip-install-build-tools.ps1
  ```

  Run this before installing wheels that must compile native extensions so Windows build toolchains are present alongside the mirror.

## Alignment with FedRAMP/NIST-style controls
These utilities support common control objectives often found in FedRAMP and NIST guidance:

- **Configuration baselines (e.g., CM-2, CM-6):** `python_requirements.txt` and `r_requirements.txt` capture explicit dependency baselines, with scripts to regenerate frozen environments from real installs.
- **Least functionality / allowlisting (e.g., CM-7, SI-7(10)):** Installation scripts only pull from locally mirrored artifacts (Windows `C:\\admin\\python_mirror` and `C:\\admin\\r_mirror`) and require Windows hosts (with admin elevation for Python), constraining software sources and scope.
- **Supply chain risk management / software integrity (e.g., NIST SP 800-161r1, NIST SP 800-218):** Mirror-building downloads vetted versions into organization-controlled directories for offline installs, reducing exposure to tampered upstream artifacts and ensuring content matches the specified baseline.
- **Change control and auditability (e.g., CM-3, SA-10):** `find-new-python-packages.py` normalizes and records new dependencies into the baseline file rather than permitting ad-hoc installs, creating a reviewable change point.
- **Asset reporting / inventory (e.g., CM-8, SI-4(14)):** `print-python-csv.ps1` and `print-r-csv.R` generate inventories (package, version, source URL, install location) from the mirrored content to feed review or inventory processes.

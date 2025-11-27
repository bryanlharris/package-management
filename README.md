# Package Management Utilities
This repository contains helper scripts for managing Python and R package requirements in restricted environments. Use them to capture
and mirror dependencies alongside your code.

## Files
- `freeze-python-packages.py` — save frozen dependencies to `python_requirements.txt`.
- `build-python-mirror.py` — mirror packages from `python_requirements.txt` into `C:\\admin\\python_mirror` on Windows.
- `build-r-mirror.R` — mirror Windows binary packages from `r_requirements.txt` into `C:\\admin\\r_mirror` on Windows.
- `build-stata-mirror.do` — mirror Stata packages from `stata_requirements.txt` into `C:\admin\stata_mirror` on Windows using `net install`.
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
stata-se -b do build-stata-mirror.do
```

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

## Alignment with FedRAMP/NIST-style controls
These utilities support common control objectives often found in FedRAMP and NIST guidance:

- **Configuration baselines (e.g., CM-2, CM-6):** `python_requirements.txt` and `r_requirements.txt` capture explicit dependency baselines, with scripts to regenerate frozen environments from real installs.
- **Least functionality / allowlisting (e.g., CM-7, SI-7(10)):** Installation scripts only pull from locally mirrored artifacts (Windows `C:\\admin\\python_mirror` and `C:\\admin\\r_mirror`) and require Windows hosts (with admin elevation for Python), constraining software sources and scope.
- **Supply chain risk management / software integrity (e.g., NIST SP 800-161r1, NIST SP 800-218):** Mirror-building downloads vetted versions into organization-controlled directories for offline installs, reducing exposure to tampered upstream artifacts and ensuring content matches the specified baseline.
- **Change control and auditability (e.g., CM-3, SA-10):** `find-new-python-packages.py` normalizes and records new dependencies into the baseline file rather than permitting ad-hoc installs, creating a reviewable change point.
- **Asset reporting / inventory (e.g., CM-8, SI-4(14)):** `print-python-csv.ps1` and `print-r-csv.R` generate inventories (package, version, source URL, install location) from the mirrored content to feed review or inventory processes.

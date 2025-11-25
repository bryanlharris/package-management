# Package Management Utilities

This repository contains a small helper script to capture the Python packages installed in the environment. Use it to generate a reproducible requirements snapshot that can be committed alongside your code.

## Files

- `freeze_packages.py` — runs `pip freeze` using the detected Python launcher and saves the results to `python_requirements.txt`.
- `python_requirements.txt` — generated dependency snapshot (not present until you run the script).

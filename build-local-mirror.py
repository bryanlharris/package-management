"""Prepare a local pip download mirror on Windows systems.

Usage (from the project root)::

    python build-local-mirror.py

The script is tailored for Windows Server environments. It temporarily removes
``PIP_NO_INDEX`` from the current environment and downloads all packages listed
in ``python_requirements.txt`` into ``C:\\admin\\python_mirror`` using ``py -m pip``
with the local Python launcher.
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from event_log import log_event

DEFAULT_REQUIREMENTS = Path(__file__).resolve().parent / "python_requirements.txt"
DEFAULT_DESTINATION = Path(r"C:\\admin\\python_mirror")


def run_command(
    command: list[str], description: str, *, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a command, surfacing errors with helpful context."""

    result = subprocess.run(command, check=False, env=env, text=True)
    if result.returncode != 0:
        raise SystemExit(f"Failed to {description}: exited with {result.returncode}")
    return result


def ensure_windows() -> None:
    """Abort execution when not on a Windows host."""

    if platform.system() != "Windows":
        raise SystemExit("This script is intended to run on Windows hosts only.")


def initialize_local_mirror(requirements_path: Path, destination: Path) -> None:
    """Perform the environment tweaks and download the package mirror."""

    ensure_windows()

    launcher = shutil.which("py") or sys.executable
    env = dict(os.environ)
    env.pop("PIP_NO_INDEX", None)

    download_command = [
        launcher,
        "-m",
        "pip",
        "download",
        "-r",
        str(requirements_path),
        "-d",
        str(destination),
    ]
    result = run_command(
        download_command, "download packages into the local mirror", env=env
    )
    if result.returncode == 0:
        log_event(
            f"package-management: built local pip mirror at {destination} using {requirements_path.name}",
        )


def main() -> None:
    initialize_local_mirror(DEFAULT_REQUIREMENTS, DEFAULT_DESTINATION)


if __name__ == "__main__":
    main()

New-Item -Path "C:\admin\package-management\pip-mirror" -ItemType Directory -Force
Set-Location "C:\admin\package-management\pip-mirror"

# Temporarily disable pip.ini to allow PyPI access
Rename-Item "C:\ProgramData\pip\pip.ini" "C:\ProgramData\pip\pip.ini.disabled" -ErrorAction SilentlyContinue

pip install pip-tools devpi-server devpi-web devpi-client
Copy-Item "C:\admin\package-management\pip_requirements_multi_version.txt" -Destination "C:\admin\package-management\pip-mirror\requirements.txt"
(Get-Content "C:\admin\package-management\pip-mirror\requirements.txt" | Measure-Object -Line).Lines

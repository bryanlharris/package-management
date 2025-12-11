New-Item -Path "C:\admin\pip_mirror" -ItemType Directory -Force
Set-Location "C:\admin\pip_mirror"

# Disable pip.ini temporarily
Rename-Item "C:\ProgramData\pip\pip.ini" "C:\ProgramData\pip\pip.ini.disabled" -ErrorAction SilentlyContinue

Copy-Item "C:\admin\package-management\pip_requirements_multi_version.txt" -Destination "C:\admin\pip_mirror\requirements.txt"

(Get-Content "C:\admin\pip_mirror\requirements.txt" | Measure-Object -Line).Lines

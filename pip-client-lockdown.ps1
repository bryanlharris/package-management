Set-Location "C:\admin\pip_mirror"

# Ensure pip folder exists in ProgramData
if (-not (Test-Path "C:\ProgramData\pip")) {
    New-Item -ItemType Directory -Path "C:\ProgramData\pip" -Force | Out-Null
}

Rename-Item "C:\ProgramData\pip\pip.ini.disabled" "C:\ProgramData\pip\pip.ini" -ErrorAction SilentlyContinue

$pipConfig = @"
[global]
find-links = file:///C:/admin/pip_mirror
no-index = true
"@
[System.IO.File]::WriteAllText("C:\ProgramData\pip\pip.ini", $pipConfig)

Set-Location "C:\admin\package-management"

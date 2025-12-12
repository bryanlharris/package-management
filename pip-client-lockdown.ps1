Set-Location "C:\admin\pip_mirror"

Rename-Item "C:\ProgramData\pip\pip.ini.disabled" "C:\ProgramData\pip\pip.ini" -ErrorAction SilentlyContinue

$pipConfig = @"
[global]
find-links = file:///C:/admin/pip_mirror
no-index = true
"@
[System.IO.File]::WriteAllText("C:\ProgramData\pip\pip.ini", $pipConfig)

Set-Location "C:\admin\package-management"

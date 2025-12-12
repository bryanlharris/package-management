Set-Location "C:\admin\pip_mirror"
New-Item -Path "C:\admin\pip_mirror\packages" -ItemType Directory -Force
$outputDir = "C:\admin\pip_mirror\packages"
$requirementsFile = "C:\admin\package-management\pip_requirements_multi_version.txt"
$packages = Get-Content $requirementsFile
$maxJobs = 15
$total = $packages.Count
$current = 0

foreach ($pkg in $packages) {
    while ((Get-Job -State Running).Count -ge $maxJobs) {
        Start-Sleep -Milliseconds 200
    }

    $current++
    Start-Job -ScriptBlock {
        param($package, $output)
        pip download $package -d $output --platform win_amd64 --python-version 313 --only-binary=:all: 2>&1
    } -ArgumentList $pkg, $outputDir | Out-Null

    $running = (Get-Job -State Running).Count
    Write-Host "[$current/$total] Queued: $pkg (Active: $running)"
}

Write-Host "`nWaiting for downloads to complete..."
Get-Job | Wait-Job | Receive-Job
Get-Job | Remove-Job
Write-Host "Download process complete."

Set-Location "C:\admin\package-management"

# Disable pip.ini temporarily
Remove-Item "C:\ProgramData\pip\pip.ini.disabled" -Force -ErrorAction SilentlyContinue
Rename-Item "C:\ProgramData\pip\pip.ini" "C:\ProgramData\pip\pip.ini.disabled" -ErrorAction SilentlyContinue

New-Item -Path "C:\admin\pip_mirror" -ItemType Directory -Force
Set-Location "C:\admin\pip_mirror"
$outputDir = "C:\admin\pip_mirror"
$requirementsFile = "C:\admin\package-management\pip_requirements_multi_version.txt"
$packages = Get-Content $requirementsFile
$maxJobs = 15
$total = $packages.Count
$current = 0

$builtFromSource = @()

foreach ($pkg in $packages) {
    while ((Get-Job -State Running).Count -ge $maxJobs) {
        Start-Sleep -Milliseconds 200
    }

    $current++
    Start-Job -ScriptBlock {
        param($package, $output)

        # Try binary-only first
        $binaryResult = pip download $package -d $output --platform win_amd64 --python-version 313 --only-binary=:all: 2>&1

        if ($LASTEXITCODE -ne 0) {
            # Binary download failed, try allowing source builds
            Write-Output "Binary download failed for $package, attempting source build..."
            $sourceResult = pip download $package -d $output --platform win_amd64 --python-version 313 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Output "SUCCESS_SOURCE:$package"
            } else {
                Write-Output $sourceResult
            }
        } else {
            Write-Output $binaryResult
        }
    } -ArgumentList $pkg, $outputDir | Out-Null

    $running = (Get-Job -State Running).Count
    Write-Host "[$current/$total] Queued: $pkg (Active: $running)"
}

Write-Host "`nWaiting for downloads to complete..."
$jobResults = Get-Job | Wait-Job | Receive-Job

# Track packages that were built from source
foreach ($line in $jobResults) {
    if ($line -match "^SUCCESS_SOURCE:(.+)$") {
        $builtFromSource += $Matches[1]
    } else {
        Write-Output $line
    }
}

Get-Job | Remove-Job

Write-Host "`nDownload process complete."
if ($builtFromSource.Count -gt 0) {
    Write-Host "`nPackages built from source:"
    $builtFromSource | ForEach-Object { Write-Host "  - $_" }
}

Set-Location "C:\admin\package-management"

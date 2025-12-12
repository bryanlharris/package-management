# Function to check if a package already exists in the mirror
function Test-PackageExists {
    param($packageSpec, $outputDir)

    # Extract package name and version from spec (e.g., "numpy==1.26.0" -> "numpy", "1.26.0")
    if ($packageSpec -match '^([a-zA-Z0-9_\-\.]+)(==|>=|<=|~=|!=)(.+)$') {
        $pkgName = $matches[1]
        $pkgVersion = $matches[3]

        # Normalize package name (PyPI uses lowercase with hyphens/underscores interchangeable)
        $normalizedName = $pkgName.ToLower() -replace '_', '-'

        # Check for wheel files: packagename-version-*.whl
        $wheelPattern = "$normalizedName-$pkgVersion-*.whl"
        $wheels = Get-ChildItem -Path $outputDir -Filter $wheelPattern -ErrorAction SilentlyContinue

        if ($wheels) {
            return $true
        }

        # Check for source distributions: packagename-version.tar.gz or .zip
        $sourcePatterns = @(
            "$normalizedName-$pkgVersion.tar.gz",
            "$normalizedName-$pkgVersion.zip"
        )

        foreach ($pattern in $sourcePatterns) {
            $sources = Get-ChildItem -Path $outputDir -Filter $pattern -ErrorAction SilentlyContinue
            if ($sources) {
                return $true
            }
        }
    }

    return $false
}

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
$skipped = 0

# Track jobs and their associated packages
$jobPackages = @{}

Write-Host "Checking existing packages in mirror...`n"

# Filter out packages that already exist
$packagesToDownload = @()
foreach ($pkg in $packages) {
    if (Test-PackageExists -packageSpec $pkg -outputDir $outputDir) {
        $skipped++
        Write-Host "[SKIP] $pkg (already exists)" -ForegroundColor Gray
    } else {
        $packagesToDownload += $pkg
    }
}

Write-Host "`nPackages to download: $($packagesToDownload.Count)"
Write-Host "Packages skipped: $skipped"
Write-Host "`nPhase 1: Downloading binary wheels...`n"

$total = $packagesToDownload.Count
$current = 0

foreach ($pkg in $packagesToDownload) {
    while ((Get-Job -State Running).Count -ge $maxJobs) {
        Start-Sleep -Milliseconds 200
    }

    $current++
    $job = Start-Job -ScriptBlock {
        param($package, $output)
        $result = pip download $package -d $output --platform win_amd64 --python-version 313 --only-binary=:all: 2>&1
        return @{
            ExitCode = $LASTEXITCODE
            Output = $result
        }
    } -ArgumentList $pkg, $outputDir

    $jobPackages[$job.Id] = $pkg

    $running = (Get-Job -State Running).Count
    Write-Host "[$current/$total] Queued: $pkg (Active: $running)"
}

Write-Host "`nWaiting for binary downloads to complete..."
Get-Job | Wait-Job | Out-Null

# Collect results and identify failures
$failedPackages = @()
foreach ($job in Get-Job) {
    $package = $jobPackages[$job.Id]
    $result = Receive-Job $job

    # Check if download failed (non-zero exit code or error indicators in output)
    if ($result.ExitCode -ne 0 -or $result.Output -match "ERROR|Could not find|No matching distribution") {
        $failedPackages += $package
        Write-Host "Binary download failed: $package" -ForegroundColor Yellow
    }
}

Get-Job | Remove-Job

# Phase 2: Retry failures with source builds allowed
if ($failedPackages.Count -gt 0) {
    Write-Host "`nPhase 2: Checking which failed packages need source builds...`n"

    # Filter failed packages that might have been downloaded as source in the meantime
    $packagesToRetry = @()
    $alreadyHaveSource = 0

    foreach ($pkg in $failedPackages) {
        if (Test-PackageExists -packageSpec $pkg -outputDir $outputDir) {
            $alreadyHaveSource++
            Write-Host "[SKIP] $pkg (source already exists)" -ForegroundColor Gray
        } else {
            $packagesToRetry += $pkg
        }
    }

    Write-Host "`nPackages needing source builds: $($packagesToRetry.Count)"
    Write-Host "Already have source: $alreadyHaveSource`n"

    if ($packagesToRetry.Count -gt 0) {
        $current = 0
        $retryTotal = $packagesToRetry.Count

        foreach ($pkg in $packagesToRetry) {
            while ((Get-Job -State Running).Count -ge $maxJobs) {
                Start-Sleep -Milliseconds 200
            }

            $current++
            Start-Job -ScriptBlock {
                param($package, $output)
                # Remove platform constraints and allow source builds as fallback
                # Source distributions are platform-independent, so no need for --platform/--python-version
                pip download $package -d $output 2>&1
            } -ArgumentList $pkg, $outputDir | Out-Null

            $running = (Get-Job -State Running).Count
            Write-Host "[$current/$retryTotal] Retrying with source: $pkg (Active: $running)"
        }

        Write-Host "`nWaiting for source build downloads to complete..."
        Get-Job | Wait-Job | Receive-Job
        Get-Job | Remove-Job
    }
} else {
    Write-Host "`nAll packages downloaded successfully with binary wheels!" -ForegroundColor Green
}

Write-Host "Download process complete."

Set-Location "C:\admin\package-management"

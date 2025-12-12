param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('3.7', '3.8', '3.9', '3.10', '3.11', '3.12', '3.13')]
    [string]$PythonVersion
)

# Ensure py.exe is available
if (-not (Get-Command py.exe -ErrorAction SilentlyContinue)) {
    Write-Error "py.exe not found. Please ensure Python Launcher for Windows is installed."
    exit 1
}

# Function to discover the latest installed Python 3.x version
function Get-LatestPython3Version {
    $pyList = & py --list 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to run 'py --list'. Ensure Python Launcher is properly installed."
        exit 1
    }

    # Parse py --list output to find Python 3.x versions
    # Example output:
    #  -3.13-64 *
    #  -3.12-64
    #  -3.11-64
    $python3Versions = $pyList | Where-Object { $_ -match '-3\.(\d+)' } | ForEach-Object {
        if ($_ -match '-3\.(\d+)') {
            [PSCustomObject]@{
                Major = 3
                Minor = [int]$matches[1]
                FullVersion = "3.$($matches[1])"
            }
        }
    }

    if (-not $python3Versions -or $python3Versions.Count -eq 0) {
        Write-Error "No Python 3.x interpreters found. Please install Python 3.x."
        exit 1
    }

    # Sort by minor version and get the highest
    $latest = $python3Versions | Sort-Object -Property Minor -Descending | Select-Object -First 1
    return $latest.FullVersion
}

# Function to convert version to py selector format (e.g., "3.10" -> "-3.10")
function Get-PySelector {
    param([string]$version)
    return "-$version"
}

# Function to convert version to pip --python-version format (e.g., "3.10" -> "310")
function Get-PipPythonVersion {
    param([string]$version)
    return $version.Replace('.', '')
}

# Determine which Python version to use
if ($PythonVersion) {
    Write-Host "Using specified Python version: $PythonVersion"
    $selectedVersion = $PythonVersion

    # Verify the specified version is installed
    $pySelector = Get-PySelector $selectedVersion
    $testResult = & py $pySelector --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Python $selectedVersion is not installed. Please install it or choose a different version."
        exit 1
    }
} else {
    Write-Host "No Python version specified. Detecting latest installed version..."
    $selectedVersion = Get-LatestPython3Version
    Write-Host "Using latest installed Python version: $selectedVersion"
}

# Prepare version formats for use
$pySelector = Get-PySelector $selectedVersion
$pipPythonVersion = Get-PipPythonVersion $selectedVersion

Write-Host "Python selector: py $pySelector -m pip"
Write-Host "Pip python-version: $pipPythonVersion`n"

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

# Track jobs and their associated packages
$jobPackages = @{}

Write-Host "Phase 1: Downloading binary wheels...`n"

foreach ($pkg in $packages) {
    while ((Get-Job -State Running).Count -ge $maxJobs) {
        Start-Sleep -Milliseconds 200
    }

    $current++
    $job = Start-Job -ScriptBlock {
        param($package, $output, $selector, $pipPythonVersion)
        $result = & py $selector -m pip download $package -d $output --platform win_amd64 --python-version $pipPythonVersion --only-binary=:all: 2>&1
        return @{
            ExitCode = $LASTEXITCODE
            Output = $result
        }
    } -ArgumentList $pkg, $outputDir, $pySelector, $pipPythonVersion

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
    Write-Host "`nPhase 2: Retrying $($failedPackages.Count) failed package(s) with source builds allowed...`n"

    $current = 0
    $retryTotal = $failedPackages.Count

    foreach ($pkg in $failedPackages) {
        while ((Get-Job -State Running).Count -ge $maxJobs) {
            Start-Sleep -Milliseconds 200
        }

        $current++
        Start-Job -ScriptBlock {
            param($package, $output, $selector)
            # Remove platform constraints and allow source builds as fallback
            # Source distributions are platform-independent, so no need for --platform/--python-version
            & py $selector -m pip download $package -d $output 2>&1
        } -ArgumentList $pkg, $outputDir, $pySelector | Out-Null

        $running = (Get-Job -State Running).Count
        Write-Host "[$current/$retryTotal] Retrying with source: $pkg (Active: $running)"
    }

    Write-Host "`nWaiting for source build downloads to complete..."
    Get-Job | Wait-Job | Receive-Job
    Get-Job | Remove-Job
} else {
    Write-Host "`nAll packages downloaded successfully with binary wheels!" -ForegroundColor Green
}

Write-Host "Download process complete."

Set-Location "C:\admin\package-management"

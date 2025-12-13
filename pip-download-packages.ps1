param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('3.7', '3.8', '3.9', '3.10', '3.11', '3.12', '3.13')]
    [string]$PythonVersion
)

$originalLocation = Get-Location

function Exit-WithCleanup {
    param([string]$message)

    if ($message) { Write-Error $message }
    Set-Location $originalLocation
    exit 1
}

function Ensure-PyLauncher {
    if (Get-Command py.exe -ErrorAction SilentlyContinue) { return }

    Exit-WithCleanup "py.exe not found. Please ensure Python Launcher for Windows is installed."
}

function Get-LatestPython3Version {
    $pyList = & py --list 2>&1
    if ($LASTEXITCODE -ne 0) {
        Exit-WithCleanup "Failed to run 'py --list'. Ensure Python Launcher is properly installed."
    }

    $python3Versions = foreach ($line in $pyList) {
        if ($line -match '3\.(\d+)') {
            "3.$($matches[1])"
        }
    }

    $sortedVersions = $python3Versions | Sort-Object {[version]$_} -Descending -Unique
    if (-not $sortedVersions) {
        Exit-WithCleanup "No Python 3.x interpreters found. Please install Python 3.x."
    }

    $sampleVersions = @('3.7', '3.10', '3.13', '3.9')
    $sampleSorted = $sampleVersions | Sort-Object {[version]$_} -Descending
    Write-Verbose "Example numeric ordering for detected 3.x versions: $($sampleVersions -join ', ') -> $($sampleSorted -join ', ') (selects $($sampleSorted[0]))"

    return $sortedVersions | Select-Object -First 1
}

function Get-PySelector {
    param([string]$version)
    "-$version"
}

function Get-PipPythonVersion {
    param([string]$version)
    $version.Replace('.', '')
}

function Normalize-PackageName {
    param([string]$name)
    $name.ToLower() -replace '[-_.]+', '-'
}

function Get-PackageArtifacts {
    param(
        [string]$Name,
        [string]$Version,
        [string]$Directory
    )

    $normalizedName = Normalize-PackageName $Name
    $files = Get-ChildItem -Path $Directory -File -ErrorAction SilentlyContinue
    $matching = foreach ($file in $files) {
        if ($file.Name -notmatch '^(.+)-([0-9].+?)\.(tar\.gz|zip|whl)$') { continue }

        $fileName = $matches[1]
        $fileVersion = $matches[2]
        $normalizedFileName = Normalize-PackageName $fileName

        if ($normalizedFileName -eq $normalizedName -and $fileVersion -eq $Version) {
            $file
        }
    }

    $matching | Sort-Object -Property Name
}

function Invoke-DownloadPhase {
    param(
        [string[]]$Packages,
        [ScriptBlock]$DownloadScript,
        [int]$MaxJobs,
        [string]$PhaseLabel
    )

    Write-Host "`n$PhaseLabel`n"

    $jobs = @()
    $total = $Packages.Count
    $index = 0

    foreach ($pkg in $Packages) {
        $index++

        while ((Get-Job -State Running).Count -ge $MaxJobs) {
            Start-Sleep -Milliseconds 200
        }

        $job = Start-Job -ScriptBlock $DownloadScript -ArgumentList $pkg
        $job | Add-Member -NotePropertyName Package -NotePropertyValue $pkg
        $jobs += $job

        Write-Host "[$index/$total] Queued: $pkg (Active: $((Get-Job -State Running).Count))"
    }

    Write-Host "`nWaiting for downloads to complete..."
    Get-Job | Wait-Job | Out-Null

    $failures = @()
    foreach ($job in $jobs) {
        $result = Receive-Job $job
        if ($result.ExitCode -ne 0 -or $result.Output -match "ERROR|Could not find|No matching distribution") {
            $failures += $job.Package
            Write-Host "Download failed: $($job.Package)" -ForegroundColor Yellow
        }
    }

    Get-Job | Remove-Job
    return $failures
}

Ensure-PyLauncher

$selectedVersion = if ($PythonVersion) {
    Write-Host "Using specified Python version: $PythonVersion"
    $pySelector = Get-PySelector $PythonVersion
    & py $pySelector --version 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Exit-WithCleanup "Python $PythonVersion is not installed. Please install it or choose a different version."
    }
    $PythonVersion
} else {
    Write-Host "No Python version specified. Detecting latest installed version..."
    Get-LatestPython3Version
}

Write-Host "Using Python version: $selectedVersion"

# Prepare version formats for use
$pySelector = Get-PySelector $selectedVersion
$pipPythonVersion = Get-PipPythonVersion $selectedVersion

Write-Host "Python selector: py $pySelector -m pip"
Write-Host "Pip python-version: $pipPythonVersion`n"

# Disable pip.ini temporarily
Remove-Item "C:\ProgramData\pip\pip.ini.disabled" -Force -ErrorAction SilentlyContinue
Rename-Item "C:\ProgramData\pip\pip.ini" "C:\ProgramData\pip\pip.ini.disabled" -ErrorAction SilentlyContinue

New-Item -Path "C:\admin\pip_mirror" -ItemType Directory -Force | Out-Null
Set-Location "C:\admin\pip_mirror"
$outputDir = "C:\admin\pip_mirror"
$requirementsFile = "C:\admin\package-management\pip_requirements_multi_version.txt"
$packages = Get-Content $requirementsFile
$maxJobs = 15

$downloadJob = {
    param($package)
    $result = & py $using:pySelector -m pip download $package `
        -d $using:outputDir `
        --platform win_amd64 `
        --python-version $using:pipPythonVersion `
        --only-binary=:all: `
        --exists-action i 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = $result }
}

$failedPackages = Invoke-DownloadPhase -Packages $packages -DownloadScript $downloadJob -MaxJobs $maxJobs -PhaseLabel "Phase 1: Downloading binary wheels..."

$retryFailures = @()
if ($failedPackages.Count -gt 0) {
    $sourceJob = {
        param($package)
        & py $using:pySelector -m pip download $package -d $using:outputDir --exists-action i 2>&1 | Out-Null
        return @{ ExitCode = $LASTEXITCODE; Output = "" }
    }

    $retryFailures = Invoke-DownloadPhase -Packages $failedPackages -DownloadScript $sourceJob -MaxJobs $maxJobs -PhaseLabel "Phase 2: Retrying failed packages with source builds allowed..."
} else {
    Write-Host "`nAll packages downloaded successfully with binary wheels!" -ForegroundColor Green
}

function Get-NormalizedPackageName {
    param([string]$name)

    return ($name.ToLower() -replace '[_\.]+', '-')
}

function Get-PackageNameFromRequirement {
    param([string]$requirementLine)

    $trimmed = ($requirementLine -split ';')[0].Trim()
    if (-not $trimmed) { return $null }

    if ($trimmed.StartsWith('-')) { return $null }

    if ($trimmed -match '^([A-Za-z0-9_.-]+)') {
        return Get-NormalizedPackageName $matches[1]
    }

    return $null
}

if (-not (Test-Path $requirementsFile)) {
    Exit-WithCleanup "Requirements file not found at $requirementsFile"
}

$artifactNames = Get-ChildItem $outputDir -File | ForEach-Object {
    $base = ($_.Name -split '-')[0]
    Get-NormalizedPackageName $base
} | Sort-Object -Unique

$requirementEntries = Get-Content $requirementsFile | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }
$missingPackages = @()
foreach ($entry in $requirementEntries) {
    $normalizedName = Get-PackageNameFromRequirement $entry
    if (-not $normalizedName) { continue }

    if (-not ($artifactNames -contains $normalizedName)) {
        $missingPackages += $entry
    }
}

if ($retryFailures.Count -gt 0 -or $missingPackages.Count -gt 0) {
    if ($retryFailures.Count -gt 0) {
        Write-Error "Some packages failed to download after retry: $($retryFailures -join ', ')"
    }

    if ($missingPackages.Count -gt 0) {
        Write-Error "Missing downloaded artifacts for: $($missingPackages -join ', ')"
        Write-Host "Packages without artifacts:" -ForegroundColor Yellow
        $missingPackages | ForEach-Object { Write-Host " - $_" }
    }

    Exit-WithCleanup $null
}

Write-Host "All packages downloaded and verified."

Write-Host "Download process complete."

Set-Location "C:\admin\package-management"

$lockFile = "C:\admin\package-management\pip_requirements_multi_version.lock"

Write-Host "Generating lock file: $lockFile"

$rawRequirements = Get-Content $requirementsFile | ForEach-Object { $_.Trim() }
$requirements = $rawRequirements | Where-Object { $_ -and -not $_.StartsWith('#') }

$lockEntries = @()
foreach ($req in $requirements) {
    if ($req -notmatch '^(?<name>[^=<>!~\s]+?)(?:\[.*\])?==(?<version>[^\s;]+)') {
        Exit-WithCleanup "Invalid requirement format: $req"
    }

    $name = $matches['name']
    $version = $matches['version']
    $artifacts = Get-PackageArtifacts -Name $name -Version $version -Directory $outputDir

    if (-not $artifacts -or $artifacts.Count -eq 0) {
        Exit-WithCleanup "No artifacts found for $name==$version in $outputDir."
    }

    $hashParts = foreach ($artifact in $artifacts) {
        $hash = Get-FileHash -Path $artifact.FullName -Algorithm SHA256
        if (-not $hash.Hash) {
            Exit-WithCleanup "Failed to compute hash for $($artifact.Name)"
        }

        "--hash=sha256:$($hash.Hash.ToLower())"
    }

    $lockEntries += "$req " + ($hashParts -join ' ')
}

if ($lockEntries.Count -eq 0) {
    Exit-WithCleanup "No requirements found to lock."
}

Set-Content -Path $lockFile -Value $lockEntries
Write-Host "Lock file written to $lockFile" -ForegroundColor Green
Set-Location $originalLocation

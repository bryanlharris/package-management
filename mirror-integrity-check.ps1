<#
.SYNOPSIS
    Generate or verify integrity baselines for offline package mirrors.

.DESCRIPTION
    This script walks a single mirror root directory and records file integrity information
    (size, modified time, SHA-256 hash) in a JSON manifest. Baseline mode produces the
    manifest, while verify mode re-computes hashes and reports missing files, unexpected
    files, and hash mismatches. Results are written to the console and the Windows event log.

.PARAMETER MirrorRoot
    Mirror root directory to process. Defaults to C:\admin\pip_mirror.

.PARAMETER Mode
    Operation mode: 'baseline' to create a manifest; 'verify' to compare against an
    existing manifest.

.PARAMETER ManifestPath
    Location of the JSON manifest to write or read. Defaults to
    <MirrorRoot>\integrity-baseline.json. Must reside inside the mirror root.

.EXAMPLE
    # Create a baseline manifest for the default mirror
    .\mirror-integrity-check.ps1 -Mode baseline

.EXAMPLE
    # Verify the mirror against an existing baseline manifest
    .\mirror-integrity-check.ps1 -Mode verify
#>

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[string]$MirrorRoot = "C:\\admin\\pip_mirror",

    [Parameter(Mandatory = $false)]
    [ValidateSet('baseline', 'verify')]
    [string]$Mode = 'baseline',

[Parameter(Mandatory = $false)]
[string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

$logName = 'Application'
$eventSource = 'MirrorIntegrityCheck'
$informationEventId = 12000
$errorEventId = 12001

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $color = switch ($Level) {
        'INFO' { 'Gray' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Ensure-EventLogSource {
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        New-EventLog -LogName $logName -Source $eventSource
    }
}

function Write-EventLogEntry {
    param(
        [string]$Message,
        [ValidateSet('Information', 'Error')]
        [string]$EntryType = 'Information'
    )

    Ensure-EventLogSource

    $eventId = if ($EntryType -eq 'Information') { $informationEventId } else { $errorEventId }
    Write-EventLog -LogName $logName -Source $eventSource -EntryType $EntryType -EventId $eventId -Message $Message
}

function Resolve-AbsolutePath {
    param([string]$Path)
    [System.IO.Path]::GetFullPath($Path)
}

function Validate-Parameters {
    if (-not $MirrorRoot) {
        throw 'A mirror root must be specified.'
    }

    $absoluteRoot = Resolve-AbsolutePath $MirrorRoot
    if (-not (Test-Path -Path $absoluteRoot -PathType Container)) {
        throw "Mirror root does not exist or is not a directory: $absoluteRoot"
    }

    $script:MirrorRoot = $absoluteRoot

    if (-not $ManifestPath) {
        $script:ManifestPath = Join-Path -Path $script:MirrorRoot -ChildPath 'integrity-baseline.json'
    }

    $resolvedManifest = Resolve-AbsolutePath $script:ManifestPath
    $script:ManifestPath = $resolvedManifest

    $rootPrefix = $script:MirrorRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedManifest.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "ManifestPath must be located inside the mirror root: $script:MirrorRoot"
    }

    if ($Mode -eq 'verify' -and -not (Test-Path -Path $script:ManifestPath -PathType Leaf)) {
        throw "Manifest not found for verification: $script:ManifestPath"
    }
}

function Get-ExcludedPaths {
    $excluded = New-Object System.Collections.Generic.HashSet[string]

    if ($script:ManifestPath) {
        $excluded.Add((Resolve-AbsolutePath $script:ManifestPath)) | Out-Null
    }

    $excluded
}

function Get-FileRecords {
    param(
        [string]$RootPath,
        [System.Collections.Generic.HashSet[string]]$ExcludedPaths
    )

    $files = Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction Stop
    $records = foreach ($file in $files) {
        if ($ExcludedPaths.Contains($file.FullName)) { continue }
        if ($file.Extension -match '\.(tmp|log|bak)$') { continue }

        $relativePath = [System.IO.Path]::GetRelativePath($RootPath, $file.FullName)
        $hash = Get-FileHash -Algorithm SHA256 -Path $file.FullName

        [PSCustomObject]@{
            RootPath        = $RootPath
            RelativePath    = $relativePath
            FullPath        = $file.FullName
            SizeBytes       = $file.Length
            LastWriteTimeUtc= $file.LastWriteTimeUtc.ToString('o')
            Hash            = $hash.Hash
        }
    }

    $records
}

function Build-Baseline {
    $excluded = Get-ExcludedPaths

    Write-Log "Building baseline for $script:MirrorRoot" 'INFO'
    $files = Get-FileRecords -RootPath $script:MirrorRoot -ExcludedPaths $excluded

    $manifest = [PSCustomObject]@{
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Mode           = 'baseline'
        Mirror         = [PSCustomObject]@{
            RootPath  = $script:MirrorRoot
            FileCount = $files.Count
            Files     = $files | Sort-Object RelativePath
        }
    }

    $manifest | ConvertTo-Json -Depth 6 | Out-File -FilePath $script:ManifestPath -Encoding UTF8
    Write-Log "Baseline written to $script:ManifestPath" 'INFO'
}

function Verify-Baseline {
    $excluded = Get-ExcludedPaths
    $manifest = Get-Content -Path $script:ManifestPath -Raw | ConvertFrom-Json -Depth 6

    $discrepancies = @()

    $expected = $manifest.Mirror
    if (-not $expected -or $expected.RootPath -ne $script:MirrorRoot) {
        $message = "Manifest mirror root does not match the requested mirror root: $script:MirrorRoot"
        Write-Log $message 'WARN'
        $discrepancies += [PSCustomObject]@{ RootPath = $script:MirrorRoot; Issue = 'MissingManifestEntry'; Detail = $message }
    }
    else {
        Write-Log "Verifying mirror $script:MirrorRoot" 'INFO'

        $expectedFiles = @{}
        foreach ($item in $expected.Files) { $expectedFiles[$item.RelativePath] = $item }

        $actualRecords = Get-FileRecords -RootPath $script:MirrorRoot -ExcludedPaths $excluded
        $actualFiles = @{}
        foreach ($record in $actualRecords) { $actualFiles[$record.RelativePath] = $record }

        $missing = $expectedFiles.Keys | Where-Object { -not $actualFiles.ContainsKey($_) }
        $unexpected = $actualFiles.Keys | Where-Object { -not $expectedFiles.ContainsKey($_) }

        foreach ($rel in $missing) {
            $discrepancies += [PSCustomObject]@{ RootPath = $script:MirrorRoot; Issue = 'MissingFile'; Detail = $rel }
            Write-Log "Missing: $rel" 'ERROR'
            Write-EventLogEntry -Message "Missing file: $rel" -EntryType 'Error'
        }

        foreach ($rel in $unexpected) {
            $discrepancies += [PSCustomObject]@{ RootPath = $script:MirrorRoot; Issue = 'UnexpectedFile'; Detail = $rel }
            Write-Log "Unexpected: $rel" 'WARN'
            Write-EventLogEntry -Message "Unexpected file: $rel" -EntryType 'Error'
        }

        $shared = $expectedFiles.Keys | Where-Object { $actualFiles.ContainsKey($_) }
        foreach ($rel in $shared) {
            $expectedItem = $expectedFiles[$rel]
            $actualItem = $actualFiles[$rel]
            if ($expectedItem.Hash -ne $actualItem.Hash) {
                $discrepancies += [PSCustomObject]@{ RootPath = $script:MirrorRoot; Issue = 'HashMismatch'; Detail = $rel }
                Write-Log "Hash mismatch: $rel" 'ERROR'
                Write-EventLogEntry -Message "Hash mismatch: $rel" -EntryType 'Error'
            }
        }

        Write-Log "Verification complete for $script:MirrorRoot. Missing: $($missing.Count), Unexpected: $($unexpected.Count), Hash mismatches: $((($shared | Where-Object { $expectedFiles[$_].Hash -ne $actualFiles[$_].Hash }).Count))" 'INFO'
    }

    if ($discrepancies.Count -gt 0) {
        $summary = "Mirror integrity verification FAILED with $($discrepancies.Count) issue(s)."
        Write-Log $summary 'ERROR'
        Write-EventLogEntry -Message $summary -EntryType 'Error'
        return @{ Success = $false; Issues = $discrepancies }
    }

    $successMessage = 'Mirror integrity verification succeeded with no discrepancies.'
    Write-Log $successMessage 'INFO'
    Write-EventLogEntry -Message $successMessage -EntryType 'Information'
    return @{ Success = $true; Issues = @() }
}

function Run-MirrorIntegrityCheck {
    Validate-Parameters

    if ($Mode -eq 'baseline') {
        Build-Baseline
        $message = "Mirror integrity baseline created at $script:ManifestPath"
        Write-EventLogEntry -Message $message -EntryType 'Information'
        return 0
    }
    else {
        $result = Verify-Baseline
        if (-not $result.Success) { return 1 }
        return 0
    }
}

exit (Run-MirrorIntegrityCheck)

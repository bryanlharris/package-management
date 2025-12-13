#!/usr/bin/env pwsh
<##
Emit a tab-separated report for every Stata package found in the shared ado tree.

The output mirrors the column order used by the Python and R inventory scripts
and appends blank placeholders for SSC presence and URLs alongside package name,
version, source, reviewer, installer, summary, URL, and install location.
Metadata is derived from the shared ado tree when available.
##>

param(
    [string]$SharedAdo = "C:/Program Files/Stata18/shared_ado"
)

$SummaryLineLimit = 30

function Ensure-Windows {
    $isWindowsPlatform = $IsWindows

    if (-not $isWindowsPlatform -and $PSVersionTable.Platform) {
        $isWindowsPlatform = $PSVersionTable.Platform -eq 'Win32NT'
    }

    if (-not $isWindowsPlatform -and $env:OS) {
        $isWindowsPlatform = $env:OS -like 'Windows*'
    }

    if (-not $isWindowsPlatform) {
        Write-Error "This script is intended to run on Windows hosts only."
        exit 1
    }
}

function Get-AdoFiles {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    Get-ChildItem -Path $BasePath -Filter *.ado -Recurse -File -ErrorAction SilentlyContinue
}

function Get-LocalMetadata {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File
    )

    $metadata = @{ version = $null; description = $null }

    try {
        $lines = Get-Content -LiteralPath $File.FullName -Encoding Latin1 -TotalCount $SummaryLineLimit -ErrorAction Stop
    }
    catch {
        return $metadata
    }

    foreach ($line in $lines) {
        $stripped = $line.Trim()
        $lower = $stripped.ToLowerInvariant()

        if ($stripped.StartsWith('*') -and -not $metadata.description) {
            $metadata.description = $stripped.TrimStart('*').Trim()
        }

        if ($lower.Contains('version') -and -not $stripped.StartsWith('*')) {
            $parts = $lower -split '\s+'
            for ($i = 0; $i -lt $parts.Length; $i++) {
                if ($parts[$i] -eq 'version' -and $i + 1 -lt $parts.Length) {
                    $metadata.version = $parts[$i + 1]
                    break
                }
            }
        }

        if ($metadata.version -and $metadata.description) {
            break
        }
    }

    return $metadata
}

function Resolve-Location {
    param(
        [string]$SharedRoot,
        [System.IO.FileInfo]$AdoPath
    )

    if ($null -ne $AdoPath) {
        return (Split-Path -Path $AdoPath.FullName -Parent)
    }

    return $SharedRoot
}

function Format-Row {
    param(
        [string]$Package,
        [string]$Version = "",
        [string]$Description = "",
        [string]$Location = "",
        [string]$Url = "",
        [string]$SscFound = "",
        [string]$SscUrl = ""
    )

    function Sanitize($field) {
        if ($null -eq $field) {
            return ""
        }

        return $field.ToString().Replace("`t", " ")
    }

    $packageValue = if ([string]::IsNullOrWhiteSpace($Package)) { "unknown" } else { $Package }
    $versionValue = if ($null -eq $Version) { "" } else { $Version }
    $descriptionValue = if ($null -eq $Description) { "" } else { $Description }
    $locationValue = if ([string]::IsNullOrWhiteSpace($Location)) { "unknown" } else { $Location }

    $columns = @(
        $packageValue,
        $versionValue,
        'Stata',
        'Reviewer',
        'Installer',
        $descriptionValue,
        $Url,
        $locationValue,
        $SscFound,
        $SscUrl
    )

    return ($columns | ForEach-Object { Sanitize $_ }) -join "`t"
}

Ensure-Windows

if (-not (Test-Path -LiteralPath $SharedAdo)) {
    Write-Error "Shared ado directory not found at $SharedAdo. Run stata-install-baseline.do first."
    exit 1
}

foreach ($ado in Get-AdoFiles -BasePath $SharedAdo) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($ado.Name)
    $meta = Get-LocalMetadata -File $ado

    $version = if ($meta.version) { $meta.version } else { "" }
    $description = if ($meta.description) { $meta.description } else { "" }
    $location = Resolve-Location -SharedRoot $SharedAdo -AdoPath $ado

    Write-Output (Format-Row -Package $name -Version $version -Description $description -Location $location)
}

# Load the System.IO.Compression assembly for ZipArchive
Add-Type -AssemblyName System.IO.Compression.FileSystem

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

function ConvertFrom-JsonCompat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Json
    )

    begin {
        $jsonFragments = New-Object System.Collections.Generic.List[string]
    }

    process {
        $jsonFragments.Add($Json)
    }

    end {
        $combinedJson = if ($jsonFragments.Count -eq 1) { $jsonFragments[0] } else { [string]::Join([Environment]::NewLine, $jsonFragments) }

        $supportsDepth = $PSVersionTable.PSVersion.Major -ge 6 -or (Get-Command ConvertFrom-Json).Parameters.ContainsKey('Depth')

        if ($supportsDepth) {
            try {
                return $combinedJson | ConvertFrom-Json -Depth 6 -ErrorAction Stop
            }
            catch {
            }
        }

        try {
            return $combinedJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Add-Type -AssemblyName System.Web.Extensions
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $serializer.MaxJsonLength = [int]::MaxValue
            return $serializer.DeserializeObject($combinedJson)
        }
    }
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $psObject = $Object.PSObject

    if ($psObject -and $psObject.Methods['ContainsKey']) {
        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
    }
    elseif ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
    }
    elseif ($psObject -and $psObject.Properties[$Name]) {
        return $Object.$Name
    }

    return $null
}

# Sanity check: baseline dictionaries produced by integrity-check.ps1 on
# Windows PowerShell 5.x expose ContainsKey but not Contains, so make sure we
# access them without emitting warnings.
if ($PSVersionTable.PSEdition -eq 'Desktop' -and $PSVersionTable.PSVersion.Major -lt 6) {
    $sanityBaseline = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $sanityMirror = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $sanityBaseline['Mirror'] = $sanityMirror
    $sanityMirror['Files'] = @()

    Get-PropertyValue -Object $sanityBaseline -Name 'Mirror' | Out-Null
}

Ensure-Windows

$pipMirrorPath = "C:\admin\pip_mirror"
$integrityBaselinePath = Join-Path -Path $pipMirrorPath -ChildPath "integrity-baseline.json"
$approvedPackagesRepo = "C:\admin\approved-packages"
$requirementsHistoryFile = "pip_requirements_multi_version.txt"

function Normalize-PipPackageKey {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    $normalized = $Name.Trim().ToLowerInvariant()
    $normalized = [regex]::Replace($normalized, '[-_.]+', '-')
    return $normalized
}

function Get-PipHistoryKeysFromRequirements {
    param(
        [string]$Content
    )

    $keys = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($Content)) {
        return $keys
    }

    $lines = $Content -split "`r?`n"

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        if ($trimmed.StartsWith('-')) {
            continue
        }

        $candidate = ($trimmed -split '\s+')[0]
        if (-not $candidate) {
            continue
        }

        $candidate = ($candidate -split ';')[0]
        $candidate = ($candidate -split '\[')[0]
        $candidate = ($candidate -split '(?i)(===|==|~=|!=|<=|>=|<|>|@)')[0]

        $key = Normalize-PipPackageKey -Name $candidate
        if ($key) {
            $keys.Add($key)
        }
    }

    return $keys
}

function Get-FirstUseByPackageKey {
    param(
        [string]$RepoPath,
        [string]$RequirementsFile,
        [ScriptBlock]$ExtractKeys
    )

    $firstUse = @{}

    if (-not (Test-Path -LiteralPath $RepoPath)) {
        return $firstUse
    }

    try {
        $commitLines = git -C $RepoPath log --reverse --format="%H|%cs" -- $RequirementsFile 2>$null
    }
    catch {
        return $firstUse
    }

    foreach ($commitLine in $commitLines) {
        if (-not $commitLine) {
            continue
        }

        $parts = $commitLine -split '\|', 2
        if ($parts.Count -ne 2) {
            continue
        }

        $commitHash = $parts[0]
        $commitDate = $parts[1]

        $content = $null
        try {
            $content = git -C $RepoPath show "$commitHash`:$RequirementsFile" 2>$null | Out-String
        }
        catch {
            continue
        }

        $keys = & $ExtractKeys $content
        foreach ($key in $keys) {
            if ($key -and -not $firstUse.ContainsKey($key)) {
                $firstUse[$key] = $commitDate
            }
        }
    }

    return $firstUse
}

function ConvertFrom-WheelMetadata {
    param(
        [System.IO.FileInfo]$File,
        [string]$Hash
    )

    $whlFile = $File.FullName

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($whlFile)
        $metadataEntry = $zip.Entries | Where-Object {
            $_.FullName -match '\.dist-info/METADATA$'
        } | Select-Object -First 1

        if (-not $metadataEntry) {
            $zip.Dispose()
            return $null
        }

        $stream = $metadataEntry.Open()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $content = $reader.ReadToEnd()
        $reader.Close()
        $stream.Close()
        $zip.Dispose()

        $name = ""
        $version = ""
        $requiresPython = ""
        $summary = ""
        $homepage = ""

        $content -split "`n" | ForEach-Object {
            $line = $_
            if ($line -match "^Name:\s*(.+)$") {
                $name = $Matches[1].Trim()
            }
            elseif ($line -match "^Version:\s*(.+)$") {
                $version = $Matches[1].Trim()
            }
            elseif ($line -match "^Requires-Python:\s*(.+)$") {
                $requiresPython = $Matches[1].Trim()
            }
            elseif ($line -match "^Summary:\s*(.+)$") {
                $summary = $Matches[1].Trim()
            }
            elseif ($line -match "^Home-page:\s*(.+)$") {
                $homepage = $Matches[1].Trim()
            }
        }

        if (-not $name -or -not $version) {
            return $null
        }

        return [PSCustomObject]@{
            Name = $name
            Version = $version
            RequiresPython = $requiresPython
            Summary = $summary
            Homepage = $homepage
            Hash = $Hash
        }
    }
    catch {
        Write-Error "Failed to process $whlFile : $_"
        return $null
    }
}

function ConvertFrom-SourceArchiveName {
    param(
        [System.IO.FileInfo]$File,
        [string]$Hash
    )

    $archiveName = $File.Name
    $baseName = $File.BaseName

    if ($archiveName -like '*.tar.gz') {
        $baseName = $archiveName.Substring(0, $archiveName.Length - 7)
    }
    elseif ($archiveName -like '*.tar.bz2') {
        $baseName = $archiveName.Substring(0, $archiveName.Length - 8)
    }
    elseif ($archiveName -like '*.tar.xz') {
        $baseName = $archiveName.Substring(0, $archiveName.Length - 7)
    }

    if ($baseName -notmatch '^(?<name>.+)-(?<version>\d[^\s]*)$') {
        return $null
    }

    return [PSCustomObject]@{
        Name = $Matches['name']
        Version = $Matches['version']
        RequiresPython = ""
        Summary = ""
        Homepage = ""
        Hash = $Hash
    }
}

if (-not (Test-Path $pipMirrorPath)) {
    Write-Error "Pip mirror directory not found: $pipMirrorPath"
    exit 1
}

# Optional SHA-256 hash lookup sourced from integrity-check.ps1 output
$hashByFilename = @{}
if (Test-Path $integrityBaselinePath) {
    try {
        $baseline = Get-Content -Path $integrityBaselinePath -Raw | ConvertFrom-JsonCompat
        $mirror = Get-PropertyValue -Object $baseline -Name 'Mirror'
        $files = Get-PropertyValue -Object $mirror -Name 'Files'

        if ($files) {
            foreach ($file in $files) {
                $relativePath = Get-PropertyValue -Object $file -Name 'RelativePath'
                $hashValue = Get-PropertyValue -Object $file -Name 'Hash'
                $name = if ($relativePath) { [System.IO.Path]::GetFileName($relativePath) } else { $null }

                if ($name -and -not $hashByFilename.ContainsKey($name)) {
                    $hashByFilename[$name] = $hashValue
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to parse integrity baseline at $integrityBaselinePath : $_"
    }
}

$firstUseByKey = Get-FirstUseByPackageKey -RepoPath $approvedPackagesRepo -RequirementsFile $requirementsHistoryFile -ExtractKeys ${function:Get-PipHistoryKeysFromRequirements}

$wheelRows = Get-ChildItem -Path $pipMirrorPath -Filter "*.whl" -File | ForEach-Object {
    $hash = $hashByFilename[$_.Name]
    ConvertFrom-WheelMetadata -File $_ -Hash $hash
}

$sourceRows = Get-ChildItem -Path $pipMirrorPath -File | Where-Object {
    $_.Name -match '\.(tar\.gz|tar\.bz2|tar\.xz|tgz|zip)$' -and $_.Extension -ne '.whl'
} | ForEach-Object {
    $hash = $hashByFilename[$_.Name]
    ConvertFrom-SourceArchiveName -File $_ -Hash $hash
}

$packageInfo = @($wheelRows + $sourceRows) | Where-Object { $_ } | ForEach-Object {
    $name = $_.Name
    $version = $_.Version
    $packageKey = Normalize-PipPackageKey -Name $name
    $dateWhenFirstUsed = if ($packageKey -and $firstUseByKey.ContainsKey($packageKey)) { $firstUseByKey[$packageKey] } else { "" }
    $requiresPython = $_.RequiresPython
    $summary = $_.Summary
    $homepage = $_.Homepage
    $hash = $_.Hash
    $location = $pipMirrorPath

    # Output format: Name, Version, DateWhenPackageFirstUsed, Requires-Python, Source, Reviewer, Installer, Summary, Home-page, Location, Hash
    "$name`t$version`t$dateWhenFirstUsed`t$requiresPython`tPyPi`tReviewer`tInstaller`t$summary`t$homepage`t$location`t$hash"
}

if ($packageInfo) {
    ($packageInfo -join "`r`n") | clip.exe

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Copied pip mirror package list to clipboard" -ForegroundColor Yellow
    }
}

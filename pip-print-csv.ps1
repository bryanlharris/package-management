# Load the System.IO.Compression assembly for ZipArchive
Add-Type -AssemblyName System.IO.Compression.FileSystem

$pipMirrorPath = "C:\admin\pip_mirror"
$integrityBaselinePath = Join-Path -Path $pipMirrorPath -ChildPath "integrity-baseline.json"

if (-not (Test-Path $pipMirrorPath)) {
    Write-Error "Pip mirror directory not found: $pipMirrorPath"
    exit 1
}

# Optional SHA-256 hash lookup sourced from mirror-integrity-check.ps1 output
$hashByFilename = @{}
if (Test-Path $integrityBaselinePath) {
    try {
        $baseline = Get-Content -Path $integrityBaselinePath -Raw | ConvertFrom-Json -Depth 6
        if ($baseline.Mirror -and $baseline.Mirror.Files) {
            foreach ($file in $baseline.Mirror.Files) {
                $name = [System.IO.Path]::GetFileName($file.RelativePath)
                if ($name -and -not $hashByFilename.ContainsKey($name)) {
                    $hashByFilename[$name] = $file.Hash
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to parse integrity baseline at $integrityBaselinePath : $_"
    }
}

$packageInfo = Get-ChildItem -Path $pipMirrorPath -Filter "*.whl" | ForEach-Object {
    $whlFile = $_.FullName
    $filename = $_.BaseName
    $hash = $hashByFilename[$_.Name]

    try {
        # Open the wheel file directly as a ZIP archive
        $zip = [System.IO.Compression.ZipFile]::OpenRead($whlFile)

        # Find the METADATA file inside the *.dist-info directory
        $metadataEntry = $zip.Entries | Where-Object {
            $_.FullName -match '\.dist-info/METADATA$'
        } | Select-Object -First 1

        if ($metadataEntry) {
            # Read the METADATA file content directly from the archive
            $stream = $metadataEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $content = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()

            # Initialize metadata fields
            $name = ""
            $version = ""
            $summary = ""
            $homepage = ""

            # Parse the METADATA content
            $content -split "`n" | ForEach-Object {
                $line = $_
                if ($line -match "^Name:\s*(.+)$") {
                    $name = $Matches[1].Trim()
                }
                elseif ($line -match "^Version:\s*(.+)$") {
                    $version = $Matches[1].Trim()
                }
                elseif ($line -match "^Summary:\s*(.+)$") {
                    $summary = $Matches[1].Trim()
                }
                elseif ($line -match "^Home-page:\s*(.+)$") {
                    $homepage = $Matches[1].Trim()
                }
            }

            if ($name -and $version) {
                $location = $pipMirrorPath
                # Output format: Name, Version, Source, Reviewer, Installer, Summary, Home-page, Location, Hash
                "$name`t$version`tPyPi`tReviewer`tInstaller`t$summary`t$homepage`t$location`t$hash"
            }
        }

        $zip.Dispose()
    }
    catch {
        Write-Error "Failed to process $whlFile : $_"
    }
}

if ($packageInfo) {
    ($packageInfo -join "`r`n") | clip.exe

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Copied pip mirror package list to clipboard" -ForegroundColor Yellow
    }
}

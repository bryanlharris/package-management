# Load the System.IO.Compression assembly for ZipArchive
Add-Type -AssemblyName System.IO.Compression.FileSystem

$pipMirrorPath = "C:\admin\pip_mirror"

if (-not (Test-Path $pipMirrorPath)) {
    Write-Error "Pip mirror directory not found: $pipMirrorPath"
    exit 1
}

Get-ChildItem -Path $pipMirrorPath -Filter "*.whl" | ForEach-Object {
    $whlFile = $_.FullName
    $filename = $_.BaseName

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
                # Output format: Name, Version, Source, Reviewer, Installer, Summary, Home-page, Location
                "$name`t$version`tPyPi`tReviewer`tInstaller`t$summary`t$homepage`t$location"
            }
        }

        $zip.Dispose()
    }
    catch {
        Write-Error "Failed to process $whlFile : $_"
    }
}

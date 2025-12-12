$pipMirrorPath = "C:\admin\pip_mirror"

if (-not (Test-Path $pipMirrorPath)) {
    Write-Error "Pip mirror directory not found: $pipMirrorPath"
    exit 1
}

Get-ChildItem -Path $pipMirrorPath -Filter "*.whl" | ForEach-Object {
    $whlFile = $_.FullName
    $filename = $_.BaseName

    # Create a temporary extraction directory
    $tempDir = Join-Path $env:TEMP ("whl_extract_" + [System.Guid]::NewGuid().ToString())

    try {
        # Extract the wheel file (it's a ZIP archive)
        Expand-Archive -Path $whlFile -DestinationPath $tempDir -Force

        # Find the .dist-info directory
        $distInfoDir = Get-ChildItem -Path $tempDir -Directory -Filter "*.dist-info" | Select-Object -First 1

        if ($distInfoDir) {
            $metadataFile = Join-Path $distInfoDir.FullName "METADATA"

            # Initialize metadata fields
            $name = ""
            $version = ""
            $summary = ""
            $homepage = ""

            if (Test-Path $metadataFile) {
                # Read and parse the METADATA file
                $content = Get-Content $metadataFile -Encoding UTF8

                foreach ($line in $content) {
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
            }

            if ($name -and $version) {
                $location = $pipMirrorPath
                # Output format: Name, Version, Source, Reviewer, Installer, Summary, Home-page, Location
                "$name`t$version`tPyPi`tReviewer`tInstaller`t$summary`t$homepage`t$location"
            }
        }
    }
    finally {
        # Clean up the temporary extraction directory
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

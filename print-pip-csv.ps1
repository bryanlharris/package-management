$pipMirrorPath = "C:\admin\pip_mirror"

if (-not (Test-Path $pipMirrorPath)) {
    Write-Error "Pip mirror directory not found: $pipMirrorPath"
    exit 1
}

Get-ChildItem -Path $pipMirrorPath -Filter "*.whl" | ForEach-Object {
    $filename = $_.BaseName

    # Parse wheel filename format: {distribution}-{version}(-{build})?-{python}-{abi}-{platform}
    # We need to split on '-' but package names can contain hyphens
    # Strategy: Split and find where the version starts (first part matching version pattern)
    $parts = $filename -split '-'

    $name = ""
    $version = ""
    $foundVersion = $false

    for ($i = 0; $i -lt $parts.Length; $i++) {
        # Check if this part looks like a version (starts with digit)
        if (-not $foundVersion -and $parts[$i] -match '^\d') {
            $version = $parts[$i]
            $foundVersion = $true
            # Join all previous parts as the package name
            if ($i -gt 0) {
                $name = ($parts[0..($i-1)] -join '-')
            }
            break
        }
    }

    if ($name -and $version) {
        $location = $pipMirrorPath
        # Output format: Name, Version, Source, Reviewer, Installer, Summary, Home-page, Location
        "$name`t$version`tPyPi`tReviewer`tInstaller`t`t`t$location"
    }
}

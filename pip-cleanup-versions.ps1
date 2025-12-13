$packagesDir = "C:/admin/pip_mirror"
$keepVersions = 3

# Pattern to extract package name and version from wheel filename
# Example: numpy-1.24.3-cp313-cp313-win_amd64.whl
$wheelPattern = '^(.+?)-(\d+\.\d+\.\d+.*?)-(cp\d+|py\d+|py2\.py3)-.+\.whl$'

# Pattern to extract package name and version from source distribution filename
# Examples:
#   numpy-1.24.3.tar.gz
#   numpy-1.24.3.zip
$sdistPattern = '^(.+?)-(\d+\.\d+\.\d+.*?)\.(tar\.gz|tar\.bz2|zip)$'

# Group files by (package name, python version)
$packages = @{}

Get-ChildItem -Path $packagesDir -Filter '*.whl' | ForEach-Object {
    if ($_.Name -match $wheelPattern) {
        $pkgName = $Matches[1]
        $pkgVersion = $Matches[2]
        $pyVersion = $Matches[3]
        $key = "$pkgName|$pyVersion"

        if (-not $packages.ContainsKey($key)) {
            $packages[$key] = @()
        }

        $packages[$key] += [PSCustomObject]@{
            Package = $pkgName
            PythonVersion = $pyVersion
            Version = $pkgVersion
            File = $_
        }
    }
}

# Group source distributions by package name only
$sdistPackages = @{}

Get-ChildItem -Path $packagesDir -Include '*.tar.gz', '*.tar.bz2', '*.zip' -File | ForEach-Object {
    if ($_.Name -match $sdistPattern) {
        $pkgName = $Matches[1]
        $pkgVersion = $Matches[2]

        if (-not $sdistPackages.ContainsKey($pkgName)) {
            $sdistPackages[$pkgName] = @()
        }

        $sdistPackages[$pkgName] += [PSCustomObject]@{
            Package = $pkgName
            Version = $pkgVersion
            File = $_
        }
    }
}

# Process each package-python combination
$total = $packages.Keys.Count
$index = 0
foreach ($key in $packages.Keys) {
    $index++
    $parts = $key -split '\|'
    $pkgName = $parts[0]
    $pyVersion = $parts[1]
    Write-Host "[$index/$total] Processing $pkgName ($pyVersion)..."

    $sortedFiles = $packages[$key] | Sort-Object -Property Version -Descending

    $sortedFiles | Select-Object -Skip $keepVersions | ForEach-Object {
        Write-Host "  Deleting $($_.File.Name)"
        Remove-Item -LiteralPath $_.File.FullName
    }
}

Write-Host 'Wheel cleanup complete.'

# Process source distributions
$totalSdist = $sdistPackages.Keys.Count
$sdistIndex = 0
foreach ($pkgName in $sdistPackages.Keys) {
    $sdistIndex++
    Write-Host "[$sdistIndex/$totalSdist] Processing source distributions for $pkgName..."

    $sortedFiles = $sdistPackages[$pkgName] | Sort-Object -Property Version -Descending

    $sortedFiles | Select-Object -Skip $keepVersions | ForEach-Object {
        Write-Host "  Deleting $($_.File.Name)"
        Remove-Item -LiteralPath $_.File.FullName
    }
}

Write-Host 'Source distribution cleanup complete.'

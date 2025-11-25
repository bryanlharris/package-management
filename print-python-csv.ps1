$requirementsPath = Join-Path $PSScriptRoot 'python_requirements.txt'

Get-Content $requirementsPath | ForEach-Object {
    if ($_ -match "([^=]+)==(.+)") {
        $info = py -m pip show $Matches[1] 2>$null

        if ($info) {
            $name = ($info | findstr /B "Name:") -replace "Name: ", ""
            $ver  = ($info | findstr /B "Version:") -replace "Version: ", ""
            $sum  = ($info | findstr /B "Summary:") -replace "Summary: ", ""
            $url  = ($info | findstr /B "Home-page:") -replace "Home-page: ", ""
            $loc  = ($info | findstr /B "Location:") -replace "Location: ", ""

            "$name`t$ver`tPyPi`tReviewer`tInstaller`t$sum`t$url`t$loc"
        }
    }
}

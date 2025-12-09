Get-ChildItem C:\admin\conda_channel -Recurse -File -Include *.tar.bz2, *.conda |
ForEach-Object {
    $pkg = $_.BaseName
    $name, $ver, $build = $pkg.Split("-")

    $meta = "$($_.DirectoryName)\info\index.json"
    $sum  = ""
    $url  = ""

    if (Test-Path $meta) {
        $j = Get-Content $meta | ConvertFrom-Json
        $sum = $j.summary
        $url = $j.home
    }

    "$name`t$ver`t$_.FullName`tREVIEWER`tINSTALLER`t$sum`t$url`tC:\admin\conda_channel"
}

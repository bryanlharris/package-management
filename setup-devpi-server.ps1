Set-Location "C:\admin\package-management\pip-mirror"
Stop-Process -Name "devpi-server" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\admin\package-management\pip-mirror\devpi-server" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\admin\package-management\pip-mirror\packages" -Recurse -Force -ErrorAction SilentlyContinue

$env:DEVPI_SERVERDIR = "C:\admin\package-management\pip-mirror\devpi-server"
devpi-init --serverdir "C:\admin\package-management\pip-mirror\devpi-server"
devpi-server --serverdir "C:\admin\package-management\pip-mirror\devpi-server" --host=0.0.0.0 --port=3141

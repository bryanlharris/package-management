# Invoke the R report script and copy its tab-separated output to the clipboard.
# Windows-only expectations; ensures the R script's exit code is preserved.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rScriptPath = Join-Path $scriptDir "r-print-csv.R"
$rExitCode = 0

# Run the R script and capture its exit code while piping output to clip.exe
& {
    & Rscript $rScriptPath
    $script:rExitCode = $LASTEXITCODE
} | clip.exe
$clipExitCode = $LASTEXITCODE
$rExitCode = $script:rExitCode

if ($clipExitCode -ne 0) {
    Write-Host "clip.exe returned exit code $clipExitCode while copying the report" -ForegroundColor Yellow 1>&2
}

Write-Host "Copied R package report to clipboard" -ForegroundColor Yellow 1>&2
exit $rExitCode

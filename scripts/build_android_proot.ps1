$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}

if (-not $python) {
    throw "Python is required to run scripts/build_android_proot.py"
}

& $python.Source (Join-Path $projectRoot "scripts/build_android_proot.py")
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

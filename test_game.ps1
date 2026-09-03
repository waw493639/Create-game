$ErrorActionPreference = "Stop"

$projectPath = $PSScriptRoot
$godotExe = "D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if (-not (Test-Path -LiteralPath $godotExe)) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Godot 4 was not found."
    }
    $godotExe = $command.Source
}

& $godotExe `
    --headless `
    --path $projectPath `
    --log-file (Join-Path $projectPath "godot-test.log") `
    --script res://tests/test_runner.gd

exit $LASTEXITCODE


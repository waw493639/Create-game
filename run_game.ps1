$ErrorActionPreference = "Stop"

$projectPath = $PSScriptRoot
$godotExe = "D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if (-not (Test-Path -LiteralPath $godotExe)) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Godot 4 was not found. Import project.godot from the Godot project manager."
    }
    $godotExe = $command.Source
}

Start-Process -FilePath $godotExe -ArgumentList @(
    "--path", ('"{0}"' -f $projectPath)
)


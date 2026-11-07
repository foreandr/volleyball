$ErrorActionPreference = 'Stop'
$enginePath = Join-Path $PSScriptRoot '..\game\tools\Godot_v4.6-stable_win64.exe'
if (!(Test-Path -LiteralPath $enginePath)) { throw 'Godot 4.6 is missing from the shared game tools.' }
Start-Process -FilePath $enginePath -ArgumentList @('--path',('"'+$PSScriptRoot+'"'),'--maximized')

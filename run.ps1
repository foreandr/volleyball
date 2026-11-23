param([switch]$Cinematic)
$ErrorActionPreference = 'Stop'
$enginePath = Join-Path $PSScriptRoot '..\game\tools\Godot_v4.6-stable_win64.exe'
if (!(Test-Path -LiteralPath $enginePath)) { throw 'Godot 4.6 is missing from the shared game tools.' }
$gameArgs = @('--path',('"'+$PSScriptRoot+'"'),'--maximized')

if ($Cinematic) { $gameArgs += @('--rendering-method','forward_plus') }
Start-Process -FilePath $enginePath -ArgumentList $gameArgs

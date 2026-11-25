param([switch]$Cinematic)
$ErrorActionPreference = 'Stop'
$enginePath = Join-Path $PSScriptRoot '..\game\tools\Godot_v4.6-stable_win64.exe'
if (!(Test-Path -LiteralPath $enginePath)) { throw 'Godot 4.6 is missing from the shared game tools.' }
$gameArgs = @('--path',('"'+$PSScriptRoot+'"'),'--maximized')

if ($Cinematic) { $gameArgs += @('--rendering-method','forward_plus') }
# Give Windows a stable, game-specific audio session when running from source.
$runtimeDir = Join-Path $PSScriptRoot '.godot\runtime'
$null = New-Item -ItemType Directory -Path $runtimeDir -Force
$runtime = Join-Path $runtimeDir 'AndreForemanVolleyball.exe'
if (!(Test-Path -LiteralPath $runtime) -or (Get-FileHash -LiteralPath $runtime).Hash -ne (Get-FileHash -LiteralPath $enginePath).Hash) {
    Copy-Item -LiteralPath $enginePath -Destination $runtime -Force
}
Start-Process -FilePath $runtime -ArgumentList $gameArgs -WorkingDirectory $PSScriptRoot

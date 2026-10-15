param(
    [Parameter(Mandatory=$true)][string]$GameRoot,
    [ValidateSet('HOST','JOINER')][Parameter(Mandatory=$true)][string]$Role,
    [string]$OutputDirectory = (Join-Path $env:USERPROFILE 'Desktop')
)
$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath $GameRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $game 'bin/x64/Cyberpunk2077.exe'))) { throw 'Select the Cyberpunk game root' }
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$out = Join-Path $OutputDirectory "CP2077-movement-$Role-$stamp"
New-Item -ItemType Directory -Path $out | Out-Null
$paths = @(
    'red4ext/plugins/CP2077Coop/session.log',
    'bin/x64/plugins/cyber_engine_tweaks/mods/CP2077Coop/CP2077Coop.log',
    'bin/x64/plugins/cyber_engine_tweaks/mods/CP2077MovementDiagnostics/CP2077MovementDiagnostics.log',
    'bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.log',
    'r6/logs/redscript_rCURRENT.log'
)
$missing = @()
foreach ($name in @('BUILD.txt', 'package-manifest.json')) {
    $source = Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $out }
}
foreach ($relative in $paths) {
    $source = Join-Path $game $relative
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $out }
    else { $missing += $relative }
}
@{role=$Role; collected_utc=$stamp; missing_logs=$missing; note='Read-only capture. No connection settings or access key collected. Logs may contain network addresses; review before sharing publicly.'} |
    ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $out 'capture.json') -Encoding UTF8
Get-ChildItem -LiteralPath $out -File | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash,$_.Name
} | Set-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt')
Compress-Archive -LiteralPath $out -DestinationPath "$out.zip"
Write-Output "Logs only: $out.zip"

param(
    [string]$Server = '127.0.0.1',
    [ValidateRange(1,65535)][int]$Port = 11779,
    [ValidatePattern('^[a-zA-Z0-9_-]{1,31}$')][string]$Session = 'first-test',
    [string]$AccessKeyFile = '',
    [ValidateRange(1,60)][int]$SnapshotRate = 60,
    [string]$BuildDirectory = 'build/windows'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ip = $null
if (-not [System.Net.IPAddress]::TryParse($Server, [ref]$ip) -or $ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { throw 'Server must be IPv4' }
$dll = Join-Path $root "$BuildDirectory/CoopPlugin/Release/CP2077Coop.dll"
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build the typed Release plugin first' }
$cache = Get-Content -LiteralPath (Join-Path $root "$BuildDirectory/CMakeCache.txt") -Raw
if ($cache -notmatch 'COOP_LEGACY_PLUGIN:BOOL=OFF') { throw 'Packaging requires a verified typed plugin build directory' }
if ($AccessKeyFile) { $key = (Get-Content -LiteralPath $AccessKeyFile -Raw).Trim() }
else {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes); $rng.Dispose()
    $key = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
if ($key -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid access key file' }
$out = Join-Path $root ('artifacts/session-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $out | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($role in @('HOST','JOINER')) {
    $base = Join-Path $out $role
    $plugin = Join-Path $base 'red4ext/plugins/CP2077Coop'
    $cet = Join-Path $base 'bin/x64/plugins/cyber_engine_tweaks/mods/CP2077Coop'
    $reds = Join-Path $base 'r6/scripts/CP2077Coop'
    New-Item -ItemType Directory -Path $plugin,$cet,$reds -Force | Out-Null
    Copy-Item -LiteralPath $dll -Destination $plugin
    Get-ChildItem -LiteralPath "$root/runtime/session/cet/CP2077Coop" -Filter '*.lua' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $cet
    }
    Copy-Item -LiteralPath "$root/runtime/session/redscript/CP2077Coop/natives.reds","$root/runtime/session/redscript/CP2077Coop/remote.reds" -Destination $reds
    # Replace the prior combat bridge explicitly if a future installer overlays files.
    [IO.File]::WriteAllText((Join-Path $reds 'combat.reds'), '// Combat hooks disabled in session foundation; legacy sentinel hooks must not run.' + "`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $plugin 'access.key'), $key + "`n", $utf8)
    $config = @"
role=$role
server_ip=$Server
server_port=$Port
session=$Session
access_key_file=access.key
player_snapshot_rate=$SnapshotRate
vehicle_snapshot_rate=$SnapshotRate
npc_snapshot_rate=20
max_npcs=128
bubble_radius=100
interpolation_ms=100
extrapolation_ms=100
snap_distance=6
max_extrapolation_speed=30
"@
    [IO.File]::WriteAllText((Join-Path $plugin 'session.ini'), $config.Replace("`r`n","`n") + "`n", $utf8)
}
$debian = Join-Path $out 'debian'
New-Item -ItemType Directory -Path $debian | Out-Null
foreach ($name in @('server.ini','install.sh','cp2077-coop.service')) {
    $text = (Get-Content -LiteralPath "$root/deploy/debian/$name" -Raw).Replace("`r`n","`n")
    if ($name -eq 'server.ini') { $text = $text.Replace('port=11779',"port=$Port").Replace('snapshot_rate=60',"snapshot_rate=$SnapshotRate"); $text = $text.Replace('distant_rate=15', ('distant_rate=' + [Math]::Min(15,$SnapshotRate))) }
    [IO.File]::WriteAllText((Join-Path $debian $name), $text, $utf8)
}
[IO.File]::WriteAllText((Join-Path $debian 'access.key'), $key + "`n", $utf8)
[IO.File]::WriteAllText((Join-Path $out 'STATUS.txt'), @"
Foundation package only. No installation performed and no in-game milestone certified.
Requires matched RED4ext, CET, REDscript and Codeware. REDscript compilation/engine behavior is unverified.
HOST and JOINER contain the same protocol build with role-specific configuration.
The Debian directory contains deployment inputs and a private generated key, not a Linux executable.
Build the executable on Debian with bash scripts/build.sh. Use a private trusted network.
Do not mix old combat.reds/natives.reds/init.lua with this DLL. Save the complete old mod package before any future cutover.
Rollback source: COOP_LEGACY_PLUGIN=ON and the frozen runtime/ baseline; never load both DLL variants.
NPC AI/world reactions/combat sync are unsupported and deliberately not enabled.
"@, $utf8)
Get-ChildItem -LiteralPath $out -Recurse -File | ForEach-Object {
    $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
    '{0}  {1}' -f $hash.Hash, $_.FullName.Substring($out.Length + 1)
} | Set-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt') -Encoding UTF8
Write-Output "Prepared (not installed): $out"

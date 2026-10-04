param(
    [switch]$CoreOnly,
    [string]$SdkSource = '',
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $repoRoot 'build/windows'
$plugin = if ($CoreOnly) { 'OFF' } else { 'ON' }
$legacy = if ($CoreOnly) { 'OFF' } else { 'ON' }
& cmake -S $repoRoot -B $buildDir -A x64 "-DCOOP_BUILD_PLUGIN=$plugin" "-DCOOP_BUILD_LEGACY_SERVER=$legacy" "-DCOOP_RED4EXT_SOURCE=$SdkSource"
if ($LASTEXITCODE -ne 0) { throw 'Configure failed' }
& cmake --build $buildDir --config $Configuration --parallel
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
& ctest --test-dir $buildDir -C $Configuration --output-on-failure
if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }

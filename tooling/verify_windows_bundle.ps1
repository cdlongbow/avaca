[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('server', 'avaca')]
    [string]$Role,
    [Parameter(Mandatory = $true)]
    [string]$BundlePath
)

$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
$files = Get-ChildItem -LiteralPath $bundle -File -Recurse
$names = @($files | ForEach-Object { $_.Name.ToLowerInvariant() })

function Get-BundleFile([string]$Name) {
    $match = $files | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($null -eq $match) {
        throw "WINDOWS_BUNDLE_MISSING_FILE: $Name"
    }
    return $match.FullName
}

foreach ($requiredPath in @(
    (Join-Path $bundle 'flutter_windows.dll'),
    (Join-Path $bundle 'data/flutter_assets'),
    (Get-BundleFile 'msquic.dll'),
    (Get-BundleFile 'avaca_remote_quic.dll'),
    (Get-BundleFile 'avaca-msquic-provenance.json')
)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "WINDOWS_BUNDLE_MISSING_QUIC_CLOSURE: $requiredPath"
    }
}

$provenancePath = Get-BundleFile 'avaca-msquic-provenance.json'
try {
    $provenance = Get-Content -Raw -LiteralPath $provenancePath | ConvertFrom-Json
} catch {
    throw "WINDOWS_BUNDLE_INVALID_MSQUIC_PROVENANCE: $provenancePath"
}
foreach ($entry in @{
    repository = 'https://github.com/microsoft/msquic.git'
    tag = 'v2.6.0'
    commit = 'e7e7a114e20a55ec2d5f723cf6bdf3bfb7b0b24a'
    configuration = 'Release'
    architecture = 'x64'
    tls = 'schannel'
}.GetEnumerator()) {
    if ([string]$provenance.($entry.Key) -ne $entry.Value) {
        throw "WINDOWS_BUNDLE_MSQUIC_PROVENANCE_MISMATCH: $($entry.Key)"
    }
}
$msquicPath = Get-BundleFile 'msquic.dll'
$actualMsquicHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $msquicPath).Hash.ToLowerInvariant()
if ([string]$provenance.sha256.ToLowerInvariant() -ne $actualMsquicHash) {
    throw "WINDOWS_BUNDLE_MSQUIC_HASH_MISMATCH: expected=$($provenance.sha256) actual=$actualMsquicHash"
}

if ($Role -eq 'server') {
    $forbidden = @(
        'libmpv-2.dll',
        'libegl.dll',
        'libglesv2.dll',
        'avaca_player_native.dll',
        'avaca_player_native_plugin.dll'
    )
    $found = $forbidden | Where-Object { $names -contains $_ }
    if ($found) { throw "SERVER_BUNDLE_CONTAINS_PLAYER_RUNTIME: $($found -join ', ')" }
    if (-not ($names -contains 'avaca_server.exe')) { throw 'SERVER_BUNDLE_MISSING_AVACA_SERVER_EXE' }
    if ($names -contains 'avaca.exe') { throw 'SERVER_BUNDLE_CONTAINS_AVACA_CLIENT_EXE' }
    if ($names | Where-Object { $_ -like 'avaca_player_native*.dll' }) {
        throw 'SERVER_BUNDLE_CONTAINS_PLAYER_NATIVE_RUNTIME'
    }
}
else {
    if (-not ($names -contains 'avaca.exe')) { throw 'AVACA_BUNDLE_MISSING_AVACA_EXE' }
    if (-not ($names -contains 'libmpv-2.dll')) { throw 'AVACA_BUNDLE_MISSING_PLAYER_RUNTIME' }
    foreach ($requiredPlayerRuntime in @(
        'libegl.dll',
        'libglesv2.dll',
        'd3dcompiler_47.dll',
        'vk_swiftshader.dll',
        'vulkan-1.dll'
    )) {
        if (-not ($names -contains $requiredPlayerRuntime)) {
            throw "AVACA_BUNDLE_MISSING_PLAYER_RUNTIME: $requiredPlayerRuntime"
        }
    }
    if ($names -contains 'avaca_server.exe') {
        throw 'AVACA_BUNDLE_CONTAINS_SERVER_EXE'
    }
}

Write-Output "WINDOWS_BUNDLE_CHECK_PASS role=$Role path=$bundle"

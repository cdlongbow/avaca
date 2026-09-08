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
}
else {
    if (-not ($names -contains 'avaca.exe')) { throw 'AVACA_BUNDLE_MISSING_AVACA_EXE' }
    if (-not ($names -contains 'libmpv-2.dll')) { throw 'AVACA_BUNDLE_MISSING_PLAYER_RUNTIME' }
}

Write-Output "WINDOWS_BUNDLE_CHECK_PASS role=$Role path=$bundle"

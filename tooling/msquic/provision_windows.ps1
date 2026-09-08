[CmdletBinding()]
param(
    [string]$ExternalRoot = 'D:\william\APP\DevTools\msquic\v2.6.0-e7e7a114',
    [string]$Repository = 'https://github.com/microsoft/msquic.git',
    [string]$Commit = 'e7e7a114e20a55ec2d5f723cf6bdf3bfb7b0b24a',
    [string]$Tag = 'v2.6.0',
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64',
    [ValidateSet('schannel')]
    [string]$Tls = 'schannel'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required to provision pinned MsQuic.'
}

$parent = Split-Path -Parent $ExternalRoot
New-Item -ItemType Directory -Force -Path $parent | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $ExternalRoot '.git'))) {
    Invoke-Checked git @('clone', '--recurse-submodules', '--branch', $Tag, '--depth', '1', $Repository, $ExternalRoot)
}

Push-Location $ExternalRoot
try {
    # Keep the pinned dependency fetch scoped to the MsQuic superproject. Some
    # developer Git configurations enable fetch.recurseSubmodules globally;
    # that causes an unrelated upstream submodule tag sweep and can fail on
    # historical refs that are not needed for this pinned checkout.
    $tagRef = "refs/tags/${Tag}:refs/tags/${Tag}"
    Invoke-Checked git @('-c', 'fetch.recurseSubmodules=false', 'fetch', '--no-tags', '--force', 'origin', $tagRef)
    Invoke-Checked git @('checkout', '--detach', $Commit)
    Invoke-Checked git @('-c', 'fetch.recurseSubmodules=false', 'submodule', 'update', '--init', '--recursive')

    $head = (& git rev-parse HEAD).Trim()
    if ($head -ne $Commit) {
        throw "Pinned MsQuic HEAD mismatch. Expected $Commit, got $head."
    }
    $tagCommit = (& git rev-list -n 1 $Tag).Trim()
    if ($tagCommit -ne $Commit) {
        throw "Pinned MsQuic tag mismatch. Expected $Commit, got $tagCommit."
    }

    $buildScript = Join-Path $ExternalRoot 'scripts\build.ps1'
    if (-not (Test-Path -LiteralPath $buildScript)) {
        throw "MsQuic build script not found: $buildScript"
    }
    # The Visual Studio installation can provide CMake without registering it
    # on PATH (as on the clean Windows build host used for Gate I). Resolve it
    # explicitly so the upstream build script's Start-Process invocation can
    # still launch the pinned toolchain.
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        $vsRoot = Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio'
        $vsCmake = Get-ChildItem -LiteralPath $vsRoot -Filter 'cmake.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $vsCmake) {
            throw 'CMake is required to build pinned MsQuic, but no cmake.exe was found on PATH or in Visual Studio.'
        }
        $env:Path = "$(Split-Path -Parent $vsCmake.FullName);$env:Path"
    }
    & $buildScript -Config $Configuration -Arch $Architecture -Platform windows -Tls $Tls
    if ($LASTEXITCODE -ne 0) {
        throw "MsQuic build failed ($LASTEXITCODE)."
    }

    $dll = Get-ChildItem -LiteralPath $ExternalRoot -Filter 'msquic.dll' -File -Recurse |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if ($null -eq $dll) {
        throw 'MsQuic build completed without producing msquic.dll.'
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dll.FullName).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        repository = $Repository
        tag = $Tag
        commit = $Commit
        configuration = $Configuration
        architecture = $Architecture
        tls = $Tls
        dll = $dll.FullName
        sha256 = $hash
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $manifestPath = Join-Path $ExternalRoot 'avaca-msquic-provenance.json'
    $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
    Write-Output "AVACA_MSQUIC_ROOT=$ExternalRoot"
    Write-Output "AVACA_MSQUIC_DLL=$($dll.FullName)"
    Write-Output "AVACA_MSQUIC_SHA256=$hash"
    Write-Output "AVACA_MSQUIC_PROVENANCE=$manifestPath"
}
finally {
    Pop-Location
}

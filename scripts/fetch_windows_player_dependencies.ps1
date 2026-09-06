[CmdletBinding()]
param(
  [string]$DependencyRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DependencyRoot)) {
  $DependencyRoot = Join-Path $repoRoot 'windows\engine'
}

$assetName = 'mpv-dev-lgpl-x86_64-20260827-git-182fa6ca49.7z'
$assetUrl = "https://github.com/zhongfly/mpv-winbuild/releases/download/2026-08-27-182fa6ca49/$assetName"
$expectedArchiveSha256 = '16CD542F7386BF1E68339B90618FE5446171FA555DAA0C6D07D59BE43BB903EA'
$expectedLibmpvSha256 = '63FED593A9E1B3C7E170BB38FCDF73722FA3D73B7C068F303BF2985EEEC75367'

$requiredAdjacentFiles = @(
  'libEGL.dll',
  'libGLESv2.dll',
  'd3dcompiler_47.dll',
  'vk_swiftshader.dll',
  'vulkan-1.dll'
)

foreach ($fileName in $requiredAdjacentFiles) {
  $path = Join-Path $DependencyRoot $fileName
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Pinned AVACA engine dependency is missing: $path"
  }
}

New-Item -ItemType Directory -Force -Path $DependencyRoot | Out-Null
$downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'avaca-player-dependencies'
$downloadRoot = Join-Path $downloadRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
$archivePath = Join-Path $downloadRoot $assetName
$extractRoot = Join-Path $downloadRoot 'extracted'
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

try {
  Write-Host "Downloading pinned LGPL libmpv asset: $assetName"
  Invoke-WebRequest -Uri $assetUrl -OutFile $archivePath

  $archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
  if ($archiveHash -ne $expectedArchiveSha256) {
    throw "libmpv archive SHA-256 mismatch: expected $expectedArchiveSha256, got $archiveHash"
  }

  $sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
  if ($null -ne $sevenZip) {
    & $sevenZip.Source x $archivePath "-o$extractRoot" -y | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "7z failed with exit code $LASTEXITCODE"
    }
  } else {
    tar -xf $archivePath -C $extractRoot
    if ($LASTEXITCODE -ne 0) {
      throw "tar failed with exit code $LASTEXITCODE"
    }
  }

  $libmpv = Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter 'libmpv-2.dll' |
    Select-Object -First 1
  if ($null -eq $libmpv) {
    throw 'The pinned libmpv archive did not contain libmpv-2.dll'
  }

  $libmpvHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $libmpv.FullName).Hash
  if ($libmpvHash -ne $expectedLibmpvSha256) {
    throw "libmpv SHA-256 mismatch: expected $expectedLibmpvSha256, got $libmpvHash"
  }

  Copy-Item -LiteralPath $libmpv.FullName -Destination (Join-Path $DependencyRoot 'libmpv-2.dll') -Force
  $copiedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $DependencyRoot 'libmpv-2.dll')).Hash
  if ($copiedHash -ne $expectedLibmpvSha256) {
    throw "Copied libmpv SHA-256 mismatch: expected $expectedLibmpvSha256, got $copiedHash"
  }

  Write-Host "Pinned Windows player dependencies are ready in $DependencyRoot"
  Get-ChildItem -LiteralPath $DependencyRoot -File |
    Where-Object { $_.Name -in ($requiredAdjacentFiles + 'libmpv-2.dll') } |
    Sort-Object Name |
    ForEach-Object {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
      Write-Host ("{0} {1}" -f $_.Name, $hash)
    }
} finally {
  if (Test-Path -LiteralPath $downloadRoot) {
    Remove-Item -LiteralPath $downloadRoot -Recurse -Force
  }
}

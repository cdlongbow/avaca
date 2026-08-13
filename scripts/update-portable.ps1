[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [ValidatePattern('^(latest|v?\d+\.\d+\.\d+)$')]
    [string]$Version = 'latest',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository = 'william12233/avaca',

    [Parameter()]
    [string]$InstallRoot,

    [Parameter()]
    [string]$ArchivePath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# PowerShell launched by cmd.exe with -NoProfile may not auto-load the utility
# module. Import it explicitly because checksum verification depends on
# Get-FileHash.
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

function Stop-Avaca {
    $processes = @(Get-Process -Name 'avaca' -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        if ($process.MainWindowHandle -ne 0) {
            $null = $process.CloseMainWindow()
            $null = $process.WaitForExit(5000)
        }

        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }

    Start-Sleep -Milliseconds 500
    if (Get-Process -Name 'avaca' -ErrorAction SilentlyContinue) {
        throw 'AVACA is still running. Close it and run the updater again.'
    }
}

function Get-PortableRoot {
    if ($InstallRoot) {
        return [IO.Path]::GetFullPath($InstallRoot)
    }

    $portableRoot = [IO.Path]::GetFullPath($PSScriptRoot)
    if (Test-Path -LiteralPath (Join-Path $portableRoot 'avaca.exe')) {
        return $portableRoot
    }

    throw 'Run update.cmd from an extracted AVACA portable folder, or pass -InstallRoot explicitly.'
}

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $separators = [char[]]@(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    return ([IO.Path]::GetFullPath($Path)).TrimEnd($separators)
}

function Test-PathOverlap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,

        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $leftPath = Get-NormalizedPath $Left
    $rightPath = Get-NormalizedPath $Right
    $separator = [IO.Path]::DirectorySeparatorChar

    return (
        [string]::Equals($leftPath, $rightPath, [StringComparison]::OrdinalIgnoreCase) -or
        $leftPath.StartsWith("$rightPath$separator", [StringComparison]::OrdinalIgnoreCase) -or
        $rightPath.StartsWith("$leftPath$separator", [StringComparison]::OrdinalIgnoreCase)
    )
}

function ConvertTo-ProcessArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $escaped = $Value -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Get-Release {
    param(
        [string]$Repo,
        [string]$RequestedVersion
    )

    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'avaca-portable-updater'
    }

    $releaseUri = if ($RequestedVersion -eq 'latest') {
        "https://api.github.com/repos/$Repo/releases/latest"
    } else {
        $requestedTag = if ($RequestedVersion.StartsWith('v')) {
            $RequestedVersion
        } else {
            "v$RequestedVersion"
        }
        "https://api.github.com/repos/$Repo/releases/tags/$requestedTag"
    }

    try {
        return Invoke-RestMethod -Uri $releaseUri -Headers $headers
    } catch {
        throw "Unable to read GitHub Release metadata from $releaseUri. $($_.Exception.Message)"
    }
}

function Assert-SafeArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $destination = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $totalUncompressed = [int64]0

    try {
        foreach ($entry in $archive.Entries) {
            $entryName = $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            if ([IO.Path]::IsPathRooted($entryName) -or
                $entryName -match '^[A-Za-z]:') {
                throw "The ZIP contains an absolute path: $($entry.FullName)"
            }
            if ($entryName -match '(^|[\\/])\.\.([\\/]|$)') {
                throw "The ZIP contains a path traversal entry: $($entry.FullName)"
            }

            $candidate = [IO.Path]::GetFullPath((Join-Path $DestinationRoot $entryName))
            if (-not $candidate.StartsWith($destination, [StringComparison]::OrdinalIgnoreCase)) {
                throw "The ZIP entry escapes the staging directory: $($entry.FullName)"
            }
            if (-not $seen.Add($entryName)) {
                throw "The ZIP contains a duplicate path: $($entry.FullName)"
            }

            $totalUncompressed += $entry.Length
            if ($totalUncompressed -gt 4GB) {
                throw 'The ZIP uncompressed size exceeds the supported limit.'
            }

            $unixMode = ($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($unixMode -eq 0xA000) {
                throw "The ZIP contains a symbolic link: $($entry.FullName)"
            }
        }
    } finally {
        $archive.Dispose()
    }
}

function New-ApplyScript {
    param(
        [string]$Path
    )

    $content = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,

    [Parameter(Mandatory = $true)]
    [string]$StageRoot,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$TempRoot,

    [Parameter(Mandatory = $true)]
    [string]$BackupRoot,

    [Parameter(Mandatory = $true)]
    [string]$StartupMarker,

    [Parameter(Mandatory = $true)]
    [int]$ParentPid
)

$ErrorActionPreference = 'Stop'
$appPath = Join-Path $InstallRoot 'avaca.exe'
$child = $null
$replacementStarted = $false

try {
    if (Test-Path -LiteralPath $BackupRoot) {
        throw "The backup directory already exists: $BackupRoot"
    }
    if (-not (Test-Path -LiteralPath $StageRoot -PathType Container)) {
        throw "The same-volume staging directory does not exist: $StageRoot"
    }

    $parent = $null
    $parentDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $parentDeadline) {
        $parent = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
        if ($null -eq $parent -or $parent.HasExited) {
            break
        }
        Start-Sleep -Milliseconds 200
    }
    if ($null -ne $parent -and -not $parent.HasExited) {
        throw 'The updater parent process did not exit before replacement.'
    }

    Remove-Item -LiteralPath $StartupMarker -Force -ErrorAction SilentlyContinue
    Rename-Item -LiteralPath $InstallRoot -NewName (Split-Path $BackupRoot -Leaf)
    $replacementStarted = $true
    Rename-Item -LiteralPath $StageRoot -NewName (Split-Path $InstallRoot -Leaf)

    if (-not (Test-Path -LiteralPath $appPath)) {
        throw 'The staged package did not install avaca.exe.'
    }

    $installedVersionPath = Join-Path $InstallRoot 'version.txt'
    if (-not (Test-Path -LiteralPath $installedVersionPath)) {
        throw 'The staged package did not install version.txt.'
    }

    $installedVersion = (Get-Content -LiteralPath $installedVersionPath -Raw).Trim()
    if ($installedVersion -ne $Version) {
        throw "Installed package version $installedVersion does not match $Version."
    }

    $child = Start-Process -FilePath $appPath -WorkingDirectory $InstallRoot -PassThru
    if ($null -eq $child -or $child.Id -le 0) {
        throw 'The updated AVACA process could not be started.'
    }
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $StartupMarker -PathType Leaf) -and
        (Get-Date) -lt $deadline) {
        if ($child.HasExited) {
            throw 'The updated AVACA process exited before startup completed.'
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Path -LiteralPath $StartupMarker -PathType Leaf)) {
        throw 'The updated AVACA process did not report a successful startup.'
    }
    Remove-Item -LiteralPath $StartupMarker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $BackupRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Warning "AVACA update failed: $($_.Exception.Message)"

    if ($null -ne $child -and -not $child.HasExited) {
        Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
    }

    if ($replacementStarted) {
        try {
            $failedRoot = "$InstallRoot.failed-$([Guid]::NewGuid().ToString('N'))"
            if (Test-Path -LiteralPath $InstallRoot) {
                Rename-Item -LiteralPath $InstallRoot -NewName (Split-Path $failedRoot -Leaf)
            }
            if (Test-Path -LiteralPath $BackupRoot) {
                Rename-Item -LiteralPath $BackupRoot -NewName (Split-Path $InstallRoot -Leaf)
            }
            Remove-Item -LiteralPath $failedRoot -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "AVACA rollback also failed: $($_.Exception.Message)"
        }
    }

    Remove-Item -LiteralPath $StartupMarker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
'@

    Set-Content -LiteralPath $Path -Value $content -Encoding utf8
}

$portableRoot = Get-PortableRoot
if ($ArchivePath) {
    $ArchivePath = [IO.Path]::GetFullPath($ArchivePath)
}
# Do not keep the portable directory as this process's current directory while
# the detached helper renames it during the handoff.
Set-Location -LiteralPath ([IO.Path]::GetTempPath())
$protectedDataRoot = Get-NormalizedPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AVACA')
if (Test-PathOverlap -Left $portableRoot -Right $protectedDataRoot) {
    throw "The install directory overlaps protected data directory $protectedDataRoot."
}
if (-not (Test-Path -LiteralPath $portableRoot -PathType Container)) {
    throw "Portable directory does not exist: $portableRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $portableRoot 'avaca.exe') -PathType Leaf)) {
    throw "Portable directory must contain avaca.exe: $portableRoot"
}

$release = Get-Release -Repo $Repository -RequestedVersion $Version
if ($release.draft -or $release.prerelease) {
    throw "Release $($release.tag_name) is not a stable release."
}

$tag = [string]$release.tag_name
if ($tag -notmatch '^v(\d+\.\d+\.\d+)$') {
    throw "Release tag is not a supported semantic version: $tag"
}
$releaseVersion = $Matches[1]

if ($Version -ne 'latest') {
    $requestedVersion = $Version.TrimStart('v')
    if ($requestedVersion -ne $releaseVersion) {
        throw "Requested version $requestedVersion does not match release tag $tag."
    }
}

$assetName = "avaca-$releaseVersion.zip"
$assetMatches = @($release.assets | Where-Object { $_.name -eq $assetName })
if ($assetMatches.Count -ne 1) {
    throw "Release $tag does not contain the expected asset $assetName."
}
$asset = $assetMatches[0]

$checksumName = "$assetName.sha256"
$checksumMatches = @($release.assets | Where-Object { $_.name -eq $checksumName })
if ($checksumMatches.Count -ne 1) {
    throw "Release $tag does not contain the expected checksum asset $checksumName."
}
$checksumAsset = $checksumMatches[0]

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("avaca-update-" + [Guid]::NewGuid().ToString('N'))
    $downloadPath = if ($ArchivePath) {
        [IO.Path]::GetFullPath($ArchivePath)
    } else {
        Join-Path $tempRoot $assetName
    }
    $checksumPath = Join-Path $tempRoot $checksumName
$extractRoot = Join-Path $tempRoot 'extract'
$applyScriptPath = Join-Path $tempRoot 'apply-update.ps1'
$portableParent = Split-Path $portableRoot -Parent
$handoffStageRoot = Join-Path $portableParent ('.avaca-update-' + [Guid]::NewGuid().ToString('N'))
$handoffBackupRoot = Join-Path $portableParent ('.avaca-backup-' + [Guid]::NewGuid().ToString('N'))
$startupMarker = Join-Path $portableRoot 'update-startup-success.marker'
$handoff = $false

try {
    New-Item -ItemType Directory -Force -Path $tempRoot, $extractRoot | Out-Null
    $headers = @{
        Accept = 'application/octet-stream'
        'User-Agent' = 'avaca-portable-updater'
    }
    if (-not $ArchivePath) {
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $downloadPath
    } elseif (-not (Test-Path -LiteralPath $downloadPath -PathType Leaf)) {
        throw "The supplied archive does not exist: $downloadPath"
    }
    Invoke-WebRequest -Uri $checksumAsset.browser_download_url -Headers $headers -OutFile $checksumPath
    $expectedHash = (Get-Content -LiteralPath $checksumPath -Raw).Trim().Split([char[]]@(' ', [char]9))[0].ToLowerInvariant()
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw "Checksum asset $checksumName is malformed."
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Downloaded ZIP checksum does not match $checksumName."
    }
    if ((Get-Item -LiteralPath $downloadPath).Length -gt 1GB) {
        throw 'The downloaded ZIP exceeds the supported size limit.'
    }
    Assert-SafeArchive -ArchivePath $downloadPath -DestinationRoot $extractRoot
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractRoot -Force

    $stagedExe = Get-ChildItem -LiteralPath $extractRoot -Filter 'avaca.exe' -File -Recurse | Select-Object -First 1
    if ($null -eq $stagedExe) {
        throw 'The downloaded ZIP does not contain avaca.exe.'
    }
    $stageRoot = $stagedExe.Directory.FullName

    $stagedVersionPath = Join-Path $stageRoot 'version.txt'
    if (-not (Test-Path -LiteralPath $stagedVersionPath)) {
        throw 'The downloaded ZIP does not contain version.txt.'
    }
    $stagedVersion = (Get-Content -LiteralPath $stagedVersionPath -Raw).Trim()
    if ($stagedVersion -ne $releaseVersion) {
        throw "ZIP version $stagedVersion does not match release tag $tag."
    }

    Write-Host "Found AVACA $releaseVersion at $assetName"
    Write-Host "Install directory: $portableRoot"
    Write-Host 'Persistent data stays in %LOCALAPPDATA%\AVACA.'

    if ($WhatIfPreference) {
        Write-Host 'WhatIf: download, ZIP structure, executable, and version checks passed.'
        return
    }

    New-Item -ItemType Directory -Force -Path $handoffStageRoot | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $stageRoot -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $handoffStageRoot -Recurse -Force
    }

    Stop-Avaca
    Remove-Item -LiteralPath $startupMarker -Force -ErrorAction SilentlyContinue
    New-ApplyScript -Path $applyScriptPath
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        (ConvertTo-ProcessArgument $applyScriptPath)
        '-InstallRoot'
        (ConvertTo-ProcessArgument $portableRoot)
        '-StageRoot'
        (ConvertTo-ProcessArgument $handoffStageRoot)
        '-Version'
        $releaseVersion
        '-TempRoot'
        (ConvertTo-ProcessArgument $tempRoot)
        '-BackupRoot'
        (ConvertTo-ProcessArgument $handoffBackupRoot)
        '-StartupMarker'
        (ConvertTo-ProcessArgument $startupMarker)
        '-ParentPid'
        $PID
    )
    $child = Start-Process -FilePath $powershell -ArgumentList $arguments -WorkingDirectory ([IO.Path]::GetTempPath()) -WindowStyle Hidden -PassThru
    if ($null -eq $child -or $child.Id -le 0) {
        throw 'Unable to start the portable update helper.'
    }
    $handoff = $true
    Write-Host 'Update staged. The portable app will restart after replacement.'
} finally {
    if (-not $handoff -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not $handoff -and (Test-Path -LiteralPath $handoffStageRoot)) {
        Remove-Item -LiteralPath $handoffStageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

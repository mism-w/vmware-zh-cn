#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Install', 'Restore')]
    [string]$Action = 'Install',

    [Parameter(Mandatory = $true)]
    [string]$VmwareRoot,

    [string]$SourceLocalePath,

    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
}

function Assert-VmwareRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = Resolve-FullPath $Root
    $vmwareExe = Join-Path $resolvedRoot 'vmware.exe'
    if (-not (Test-Path -LiteralPath $vmwareExe -PathType Leaf)) {
        throw "未找到 vmware.exe：$resolvedRoot"
    }
    return $resolvedRoot
}

function Assert-VmwareStopped {
    $processNames = @('vmware', 'vmware-vmx', 'vmware-remotemks', 'mksSandbox')
    $running = Get-Process -Name $processNames -ErrorAction SilentlyContinue
    if ($running) {
        $names = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        throw "请先退出 VMware 及所有正在运行的虚拟机进程：$names"
    }
}

function Assert-LocaleSource {
    param([Parameter(Mandatory = $true)][string]$Source)

    $requiredFiles = @('vmappsdk-zh_CN.dll', 'vmui-zh_CN.dll', 'vmware.vmsg')
    foreach ($file in $requiredFiles) {
        $path = Join-Path $Source $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "中文资源缺失：$path"
        }
    }
}

function Get-PreferencePath {
    return Join-Path (Join-Path $env:APPDATA 'VMware') 'preferences.ini'
}

function Get-DefaultBackupRoot {
    return Join-Path (Join-Path $env:APPDATA 'VMware') 'zh-cn-backups'
}

function Get-LatestBackup {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "未找到备份目录：$Root"
    }

    $latest = Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) {
        throw "备份目录为空：$Root"
    }
    return $latest.FullName
}

function Install-Locale {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Source
    )

    Assert-VmwareStopped
    Assert-LocaleSource $Source

    $messagesPath = Join-Path $Root 'messages'
    $targetLocalePath = Join-Path $messagesPath 'zh_CN'
    $preferencePath = Get-PreferencePath
    $backupRoot = Get-DefaultBackupRoot
    $backupPathLocal = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    $backupLocalePath = Join-Path $backupPathLocal 'messages\zh_CN'
    $backupPreferencePath = Join-Path $backupPathLocal 'preferences.ini'
    $metadataPath = Join-Path $backupPathLocal 'metadata.json'

    $preferenceContent = if (Test-Path -LiteralPath $preferencePath -PathType Leaf) {
        [System.IO.File]::ReadAllText($preferencePath)
    } else {
        ''
    }
    $localeMatch = [regex]::Match($preferenceContent, '(?m)^\s*pref\.locale\s*=\s*"([^"]*)"\s*$')

    if ($PSCmdlet.ShouldProcess($backupPathLocal, '创建 VMware 中文补丁备份')) {
        New-Item -ItemType Directory -Path $backupPathLocal -Force | Out-Null
        $metadata = [ordered]@{
            localeExisted = Test-Path -LiteralPath $targetLocalePath -PathType Container
            preferencesExisted = Test-Path -LiteralPath $preferencePath -PathType Leaf
            previousLocale = if ($localeMatch.Success) { $localeMatch.Groups[1].Value } else { $null }
            createdAt = (Get-Date).ToString('o')
            vmwareRoot = $Root
        }
        if ($metadata.localeExisted) {
            New-Item -ItemType Directory -Path (Split-Path $backupLocalePath -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $targetLocalePath -Destination $backupLocalePath -Recurse -Force
        }
        if ($metadata.preferencesExisted) {
            Copy-Item -LiteralPath $preferencePath -Destination $backupPreferencePath -Force
        }
        Write-Utf8NoBom $metadataPath (($metadata | ConvertTo-Json) + [Environment]::NewLine)
    }

    if ($PSCmdlet.ShouldProcess($targetLocalePath, '安装中文资源')) {
        New-Item -ItemType Directory -Path $messagesPath -Force | Out-Null
        if (Test-Path -LiteralPath $targetLocalePath) {
            Remove-Item -LiteralPath $targetLocalePath -Recurse -Force
        }
        Copy-Item -LiteralPath $Source -Destination $targetLocalePath -Recurse -Force
    }

    if ($PSCmdlet.ShouldProcess($preferencePath, '设置 VMware 中文区域')) {
        $preferenceDirectory = Split-Path $preferencePath -Parent
        New-Item -ItemType Directory -Path $preferenceDirectory -Force | Out-Null
        $content = $preferenceContent
        if ($content -match '(?m)^\s*pref\.locale\s*=') {
            $content = [regex]::Replace($content, '(?m)^\s*pref\.locale\s*=.*$', 'pref.locale = "zh_CN"')
        } else {
            if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
                $content += [Environment]::NewLine
            }
            $content += 'pref.locale = "zh_CN"' + [Environment]::NewLine
        }
        Write-Utf8NoBom $preferencePath $content
    }

    Write-Output "安装完成。备份目录：$backupPathLocal"
}

function Restore-Locale {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$RequestedBackupPath
    )

    Assert-VmwareStopped

    $backupRoot = Get-DefaultBackupRoot
    $restorePath = if ($RequestedBackupPath) { Resolve-FullPath $RequestedBackupPath } else { Get-LatestBackup $backupRoot }
    $metadataPath = Join-Path $restorePath 'metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "备份元数据不存在：$metadataPath"
    }

    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $targetLocalePath = Join-Path $Root 'messages\zh_CN'
    $preferencePath = Get-PreferencePath
    $backupLocalePath = Join-Path $restorePath 'messages\zh_CN'
    $backupPreferencePath = Join-Path $restorePath 'preferences.ini'

    if ($PSCmdlet.ShouldProcess($targetLocalePath, '恢复 VMware 原始语言资源')) {
        if (Test-Path -LiteralPath $targetLocalePath) {
            Remove-Item -LiteralPath $targetLocalePath -Recurse -Force
        }
        if ([bool]$metadata.localeExisted) {
            Copy-Item -LiteralPath $backupLocalePath -Destination $targetLocalePath -Recurse -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($preferencePath, '恢复 VMware 用户语言设置')) {
        $content = if (Test-Path -LiteralPath $preferencePath -PathType Leaf) {
            [System.IO.File]::ReadAllText($preferencePath)
        } else {
            ''
        }
        $hasPreviousLocale = $metadata.PSObject.Properties.Name -contains 'previousLocale'
        if ($hasPreviousLocale -and $null -ne $metadata.previousLocale) {
            if ($content -match '(?m)^\s*pref\.locale\s*=') {
                $content = [regex]::Replace($content, '(?m)^\s*pref\.locale\s*=.*$', ('pref.locale = "' + $metadata.previousLocale + '"'))
            } else {
                if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
                    $content += [Environment]::NewLine
                }
                $content += 'pref.locale = "' + $metadata.previousLocale + '"' + [Environment]::NewLine
            }
        } elseif ($hasPreviousLocale) {
            $content = [regex]::Replace($content, '(?m)^\s*pref\.locale\s*=.*(?:\r?\n|$)', '')
        } elseif ([bool]$metadata.preferencesExisted -and (Test-Path -LiteralPath $backupPreferencePath -PathType Leaf)) {
            Copy-Item -LiteralPath $backupPreferencePath -Destination $preferencePath -Force
            $content = $null
        }

        if ($null -ne $content) {
            if ([string]::IsNullOrWhiteSpace($content)) {
                if (Test-Path -LiteralPath $preferencePath) {
                    Remove-Item -LiteralPath $preferencePath -Force
                }
            } else {
                Write-Utf8NoBom $preferencePath $content
            }
        }
    }

    Write-Output "恢复完成。使用备份：$restorePath"
}

$resolvedVmwareRoot = Assert-VmwareRoot $VmwareRoot
if (-not $SourceLocalePath) {
    $SourceLocalePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'resources\zh_CN'
}
$resolvedSource = Resolve-FullPath $SourceLocalePath

if ($Action -eq 'Install') {
    Install-Locale -Root $resolvedVmwareRoot -Source $resolvedSource
} else {
    Restore-Locale -Root $resolvedVmwareRoot -RequestedBackupPath $BackupPath
}

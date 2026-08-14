#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Install', 'Restore')]
    [string]$Action = 'Install',

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

function Add-VmwareCandidate {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Candidates,
        [AllowEmptyString()][string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return
    }

    $candidatePath = $Candidate.Trim().Trim('"')
    if ($candidatePath -match '^\s*"([^"]+)"') {
        $candidatePath = $Matches[1]
    }

    try {
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            if ([System.IO.Path]::GetFileName($candidatePath) -ieq 'vmware.exe') {
                $candidatePath = Split-Path -LiteralPath $candidatePath -Parent
            }
        }

        $resolvedCandidate = Resolve-FullPath $candidatePath
        $vmwareExe = Join-Path $resolvedCandidate 'vmware.exe'
        if (-not (Test-Path -LiteralPath $vmwareExe -PathType Leaf)) {
            return
        }

        foreach ($existing in $Candidates) {
            if ([string]::Equals($existing, $resolvedCandidate, [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }
        }
        $Candidates.Add($resolvedCandidate)
    } catch {
        return
    }
}

function Find-VmwareRoot {
    $candidates = New-Object 'System.Collections.Generic.List[string]'

    foreach ($basePath in @(
        [Environment]::GetEnvironmentVariable('ProgramW6432'),
        [Environment]::GetEnvironmentVariable('ProgramFiles'),
        [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($basePath)) {
            Add-VmwareCandidate -Candidates $candidates -Candidate (Join-Path $basePath 'VMware\VMware Workstation')
        }
    }

    $registryLocations = @(
        'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
        'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'
    )
    foreach ($registryLocation in $registryLocations) {
        try {
            $registryItem = Get-ItemProperty -LiteralPath $registryLocation -ErrorAction Stop
            foreach ($propertyName in @('InstallPath', 'InstallDir', 'Path')) {
                $property = $registryItem.PSObject.Properties[$propertyName]
                if ($null -ne $property) {
                    Add-VmwareCandidate -Candidates $candidates -Candidate ([string]$property.Value)
                }
            }
        } catch {
            continue
        }
    }

    $appPathLocations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\vmware.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\vmware.exe'
    )
    foreach ($appPathLocation in $appPathLocations) {
        try {
            $registryItem = Get-Item -LiteralPath $appPathLocation -ErrorAction Stop
            Add-VmwareCandidate -Candidates $candidates -Candidate ([string]$registryItem.GetValue(''))
        } catch {
            continue
        }
    }

    foreach ($uninstallRoot in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        try {
            foreach ($entry in Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction Stop) {
                try {
                    $uninstallItem = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction Stop
                    $displayNameProperty = $uninstallItem.PSObject.Properties['DisplayName']
                    $installLocationProperty = $uninstallItem.PSObject.Properties['InstallLocation']
                    if ($null -ne $displayNameProperty -and $null -ne $installLocationProperty -and
                        ([string]$displayNameProperty.Value) -like 'VMware Workstation*') {
                        Add-VmwareCandidate -Candidates $candidates -Candidate ([string]$installLocationProperty.Value)
                    }
                } catch {
                    continue
                }
            }
        } catch {
            continue
        }
    }

    try {
        $command = Get-Command -Name 'vmware.exe' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $commandPathProperty = $command.PSObject.Properties['Path']
            $commandPath = if ($null -ne $commandPathProperty) { $commandPathProperty.Value } else { $command.Source }
            Add-VmwareCandidate -Candidates $candidates -Candidate ([string]$commandPath)
        }
    } catch {
        # PATH 查询失败时继续使用其他公开安装位置。
    }

    return $candidates | Select-Object -First 1
}

function Assert-VmwareRoot {
    param([AllowEmptyString()][string]$Root)

    $resolvedRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
        Find-VmwareRoot
    } else {
        Resolve-FullPath $Root
    }

    if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
        throw '未找到 VMware Workstation 安装目录。请确认 VMware 已安装，或使用 -VmwareRoot 指定包含 vmware.exe 的目录。'
    }

    $vmwareExe = Join-Path $resolvedRoot 'vmware.exe'
    if (-not (Test-Path -LiteralPath $vmwareExe -PathType Leaf)) {
        if ([string]::IsNullOrWhiteSpace($Root)) {
            throw "未找到 VMware Workstation 安装目录。请确认 VMware 已安装，或使用 -VmwareRoot 指定包含 vmware.exe 的目录。自动发现路径：$resolvedRoot"
        }
        throw "未找到 vmware.exe：$resolvedRoot。请将 -VmwareRoot 指向包含 vmware.exe 的目录。"
    }
    return $resolvedRoot
}

function Assert-LocalePathsDistinct {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $resolvedSource = Resolve-FullPath $Source
    $resolvedTarget = Resolve-FullPath $Target
    $sourceWithSeparator = $resolvedSource.TrimEnd('\') + '\'
    $targetWithSeparator = $resolvedTarget.TrimEnd('\') + '\'
    $samePath = [string]::Equals($resolvedSource, $resolvedTarget, [System.StringComparison]::OrdinalIgnoreCase)
    $sourceContainsTarget = $resolvedTarget.StartsWith($sourceWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
    $targetContainsSource = $resolvedSource.StartsWith($targetWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)

    if ($samePath -or $sourceContainsTarget -or $targetContainsSource) {
        throw "拒绝安装：中文资源来源目录与 VMware 目标目录相同或相互嵌套，可能导致误删。来源：$resolvedSource；目标：$resolvedTarget"
    }
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

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "未找到中文资源目录：$Source。请将与当前 VMware 版本匹配的资源放入仓库 resources\zh_CN，或使用 -SourceLocalePath 指定目录。"
    }

    $requiredFiles = @('vmappsdk-zh_CN.dll', 'vmui-zh_CN.dll', 'vmware.vmsg')
    foreach ($file in $requiredFiles) {
        $path = Join-Path $Source $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "中文资源缺失：$path。请将 vmappsdk-zh_CN.dll、vmui-zh_CN.dll 和 vmware.vmsg 放入资源目录。"
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

    $messagesPath = Join-Path $Root 'messages'
    $targetLocalePath = Join-Path $messagesPath 'zh_CN'
    Assert-LocalePathsDistinct -Source $Source -Target $targetLocalePath
    Assert-LocaleSource $Source

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

    if ($WhatIfPreference) {
        Write-Output '预演完成，未修改任何文件。'
    } else {
        Write-Output "安装完成。备份目录：$backupPathLocal"
    }
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

try {
    $resolvedVmwareRoot = Assert-VmwareRoot $VmwareRoot

    if ($Action -eq 'Install') {
        if (-not $SourceLocalePath) {
            $SourceLocalePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'resources\zh_CN'
        }
        $resolvedSource = Resolve-FullPath $SourceLocalePath
        Install-Locale -Root $resolvedVmwareRoot -Source $resolvedSource
    } else {
        Restore-Locale -Root $resolvedVmwareRoot -RequestedBackupPath $BackupPath
    }
} catch {
    [Console]::Error.WriteLine(('错误：{0}' -f $_.Exception.Message))
    exit 1
}

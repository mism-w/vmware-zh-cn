# VMware Workstation 中文界面方案

一个面向 Windows 的 VMware Workstation 简体中文界面安装辅助方案。

项目结构参考了常见的桌面软件中文补丁项目，但本仓库只提供安装、备份、恢复脚本和操作说明，不包含 VMware 官方安装包、厂商 DLL/VMSG 资源、虚拟机磁盘或任何个人信息。

## 支持范围

- Windows 上的 VMware Workstation 26.x
- 简体中文资源目录：`messages\zh_CN`
- VMware 用户配置：`%APPDATA%\VMware\preferences.ini`
- 安装前自动备份，支持恢复原始文件

本地验证环境为 VMware Workstation `26.0.0 build-25388281`。不同版本的资源文件可能不兼容，请使用与本机版本匹配的资源包。

## 准备资源

将合法取得的中文资源放入项目目录下的 `resources\zh_CN`：

```text
resources\zh_CN\vmappsdk-zh_CN.dll
resources\zh_CN\vmui-zh_CN.dll
resources\zh_CN\vmware.vmsg
```

资源文件不会被 Git 跟踪，具体说明见 [resources/README.md](resources/README.md)。

## 安装

先完全退出 VMware Workstation 及正在运行的虚拟机，然后在 PowerShell 中执行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Set-VmwareZhCn.ps1 `
  -Action Install `
  -VmwareRoot "C:\Program Files (x86)\VMware\VMware Workstation" `
  -SourceLocalePath ".\resources\zh_CN"
```

如果 VMware 安装在自定义目录，请将 `-VmwareRoot` 改为包含 `vmware.exe` 的目录。

建议先执行预览，不会修改文件：

```powershell
.\scripts\Set-VmwareZhCn.ps1 `
  -Action Install `
  -VmwareRoot "C:\Program Files (x86)\VMware\VMware Workstation" `
  -SourceLocalePath ".\resources\zh_CN" `
  -WhatIf
```

安装脚本会：

- 检查 VMware 进程是否已经退出
- 校验三个中文资源文件是否齐全
- 将原有 `messages\zh_CN` 和用户配置备份到 `%APPDATA%\VMware\zh-cn-backups`
- 安装中文资源
- 将 `pref.locale` 设置为 `zh_CN`

完成后重新打开 VMware Workstation。如果界面没有切换，先退出 VMware，再重新运行安装脚本或检查资源包版本。

## 恢复原状

恢复最近一次备份：

```powershell
.\scripts\Set-VmwareZhCn.ps1 `
  -Action Restore `
  -VmwareRoot "C:\Program Files (x86)\VMware\VMware Workstation"
```

也可以通过 `-BackupPath` 指定某个备份目录。恢复前同样需要退出 VMware Workstation。

## 桥接网络与 VPN 说明

如果虚拟机需要使用当前局域网地址，可以在 VMware 的虚拟机设置中选择：

`Network Adapter` → `Bridged` → `Replicate physical network connection state`

桥接应选择实际联网的物理网卡。仅在主机上运行的三层 VPN 通常不会自动把 VPN 路由继承给桥接虚拟机；如果虚拟机必须经过该 VPN，优先考虑在虚拟机内运行 VPN，或使用明确支持局域网转发的主机代理/路由方案。不要在公开文档中写入真实 IP、用户名、密码或私有密钥。

## 注意事项

- VMware 更新可能覆盖 `messages\zh_CN` 或改变资源格式，更新后需要重新验证资源包。
- 不要混用不同 VMware 主版本的中文 DLL/VMSG 文件。
- 本项目不修改 VMware 服务端数据，也不包含 VMware 官方软件。
- VMware 是 Broadcom Inc. 的商标。本项目与 VMware/Broadcom 无关联。

## 目录说明

```text
resources/README.md              中文资源放置说明
scripts/Set-VmwareZhCn.ps1      安装、备份、恢复脚本
docs/bridge-network-vpn.md      桥接网络与 VPN 注意事项
```

## 开源许可

本仓库中的脚本和说明以 MIT License 发布。VMware 官方软件及其资源文件不属于本仓库的授权范围。


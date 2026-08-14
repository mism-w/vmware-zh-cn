# VMware Workstation 中文界面安装辅助

本仓库提供 VMware Workstation 中文界面的本地安装、备份和恢复脚本。仓库不包含 VMware 官方安装包、厂商 DLL/VMSG 资源、虚拟机文件或任何个人信息。

> 本项目由 OpenAI Codex 协助完成。

## 最快安装：双击 BAT

先准备与当前 VMware Workstation 主版本匹配、且你已合法取得或获授权使用的中文资源包，将以下文件放入仓库的 `resources\zh_CN`：

```text
resources\zh_CN\vmappsdk-zh_CN.dll
resources\zh_CN\vmui-zh_CN.dll
resources\zh_CN\vmware.vmsg
```

然后双击 `install-windows.bat`：

- 脚本会自动请求管理员权限；在 Windows 用户账户控制提示中选择“是”。
- 脚本会自动发现 VMware Workstation 安装目录，不要求修改脚本中的个人路径。
- 安装前会检查 VMware 相关进程；如果 VMware 或虚拟机仍在运行，脚本会给出错误并退出，不会自动关闭任何进程。
- 原有 `messages\zh_CN` 和用户语言配置会备份到 `%APPDATA%\VMware\zh-cn-backups`。

如果缺少资源文件或找不到 VMware，脚本会显示具体原因并以非零退出码结束。资源文件不会由本仓库自动下载或生成，也不应提交到公共仓库。

## 预演安装

在命令提示符中运行：

```bat
install-windows.bat /dry-run
```

`/dry-run` 会执行 VMware、进程和资源检查，并显示 PowerShell 的 `WhatIf` 预演信息，但不会创建备份、删除目录、复制资源或修改 `preferences.ini`。它同样会执行管理员权限检查，以便尽早发现实际安装权限问题。

## 高级 PowerShell 用法

在已提升权限的 Windows PowerShell 5.1 窗口中运行：

```powershell
.\scripts\Set-VmwareZhCn.ps1 -Action Install
```

不传 `-VmwareRoot` 时，脚本会从公开的 Program Files 目录、Windows 注册表和 `PATH` 自动发现包含 `vmware.exe` 的 VMware Workstation 目录。不传 `-SourceLocalePath` 时，脚本使用仓库中的 `resources\zh_CN`。显式参数仍然兼容：

```powershell
.\scripts\Set-VmwareZhCn.ps1 `
  -Action Install `
  -VmwareRoot "C:\Program Files (x86)\VMware\VMware Workstation" `
  -SourceLocalePath ".\resources\zh_CN"
```

直接使用 PowerShell 预演：

```powershell
.\scripts\Set-VmwareZhCn.ps1 -Action Install -WhatIf
```

恢复最近一次备份：

```powershell
.\scripts\Set-VmwareZhCn.ps1 -Action Restore
```

也可以使用 `-BackupPath` 指定备份目录。恢复前同样需要退出 VMware Workstation 和正在运行的虚拟机。

## 版本和安全注意事项

- 资源文件必须与 VMware Workstation 主版本匹配，不要混用不同版本的 DLL 或 VMSG 文件。
- VMware 更新后可能覆盖 `messages\zh_CN`，需要重新验证并安装匹配的资源包。
- 本项目不修改 VMware 服务端数据，也不包含个人凭据或第三方宣传内容。
- VMware 是 Broadcom Inc. 的商标。本项目与 VMware/Broadcom 无关联。

## 目录说明

```text
install-windows.bat          双击安装入口和管理员提权
resources/README.md          中文资源放置说明
scripts/Set-VmwareZhCn.ps1  安装、备份、恢复脚本
```

## 开源许可

本仓库中的脚本和说明以 MIT License 发布。VMware 官方软件及其资源文件不属于本仓库的授权范围。

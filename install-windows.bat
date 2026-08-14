@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
chcp 65001 >nul

if /I "%~1"=="/?" goto :usage
if /I "%~1"=="-?" goto :usage
if /I "%~1"=="/help" goto :usage
if not "%~1"=="" if /I not "%~1"=="/dry-run" goto :invalid
if not "%~2"=="" goto :invalid

if not exist "%~dp0scripts\Set-VmwareZhCn.ps1" (
    echo [错误] 找不到安装脚本：scripts\Set-VmwareZhCn.ps1
    goto :failure
)

set "VMWARE_ZH_CN_DIR=%~dp0"
set "VMWARE_ZH_CN_BAT=%~f0"
set "VMWARE_ZH_CN_ARGS="
set "DRY_RUN_OPTION="
if /I "%~1"=="/dry-run" (
    set "VMWARE_ZH_CN_ARGS= /dry-run"
    set "DRY_RUN_OPTION=-WhatIf"
)

"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if errorlevel 1 (
    echo 正在请求管理员权限...
    powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$command = '/d /c ""' + $env:VMWARE_ZH_CN_BAT + '"' + $env:VMWARE_ZH_CN_ARGS + '"'; $process = Start-Process -FilePath $env:ComSpec -ArgumentList $command -Verb RunAs -WorkingDirectory $env:VMWARE_ZH_CN_DIR -Wait -PassThru; exit $process.ExitCode"
    set "ELEVATED_EXIT=%ERRORLEVEL%"
    if not "%ELEVATED_EXIT%"=="0" (
        echo [错误] 管理员权限启动失败，退出码：%ELEVATED_EXIT%
        pause
        exit /b %ELEVATED_EXIT%
    )
    exit /b 0
)

echo 正在运行 VMware 中文界面安装脚本...
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\Set-VmwareZhCn.ps1" -Action Install %DRY_RUN_OPTION%
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" (
    if /I "%~1"=="/dry-run" (
        echo 预演完成，未修改任何文件。
    ) else (
        echo 安装完成。
    )
) else (
    echo [错误] 安装失败，退出码：%EXIT_CODE%
)
pause
exit /b %EXIT_CODE%

:invalid
echo [错误] 只支持可选参数 /dry-run。
goto :failure

:failure
pause
exit /b 1

:usage
echo VMware Workstation 中文界面安装
echo.
echo 双击本文件即可自动请求管理员权限并安装。
echo.
echo 用法：
echo   install-windows.bat
echo   install-windows.bat /dry-run
echo.
echo /dry-run 仅执行检查和预演，不修改文件。
exit /b 0

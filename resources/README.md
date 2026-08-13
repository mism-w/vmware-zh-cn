# 本地语言资源

本目录不包含 VMware 官方安装包或厂商资源文件。请从你合法拥有或获授权使用的、与当前 VMware Workstation 版本匹配的中文资源包中，复制以下文件到 `resources/zh_CN/`：

```text
vmappsdk-zh_CN.dll
vmui-zh_CN.dll
vmware.vmsg
```

这些文件只作为本地安装脚本的输入，不应提交到公共仓库。仓库的 `.gitignore` 已默认忽略它们。

资源版本必须与 VMware Workstation 主版本匹配。不要混用不同版本的 DLL 或消息文件。


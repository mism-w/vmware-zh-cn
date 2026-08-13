# VMware 桥接网络与 VPN

## 桥接模式

在虚拟机设置中打开 `Network Adapter`，选择 `Bridged`，并在 `Configure Adapters` 中指定实际联网的物理网卡。这样虚拟机通常会从同一局域网 DHCP 获取独立地址。

VMX 配置的核心形式如下：

```ini
ethernet0.connectionType = "bridged"
ethernet0.startConnected = "TRUE"
```

`bridgeName` 应填写当前主机实际使用的物理网卡标识，不要把示例值直接复制到其他电脑。

## VPN 路由限制

主机 VPN 如果只是创建了一个三层隧道，桥接虚拟机不会自然继承主机的 VPN 路由。此时可以选择：

- 在虚拟机内安装并连接同一个 VPN
- 在主机上配置明确允许局域网客户端转发的 VPN/代理方案
- 使用 VMware NAT，并在主机上配置对应的路由或代理

切换网络模式后，在虚拟机内检查：

```bash
ip addr
ip route
curl -I https://example.com
```

不要把真实 IP、网关、VPN 配置、用户名、密码或密钥提交到公开仓库。


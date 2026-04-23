#!/bin/bash

# =================================================================
# AWS EC2 Tailscale Exit Node 自动部署与网络优化脚本
# =================================================================

# 1. 安装 Tailscale
echo "正在安装 Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# 2. 开启内核 IP 转发（Exit Node 必需）
echo "配置内核参数..."
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 3. 自动检测网卡名称并优化 UDP 性能 (GRO)
# 获取默认网卡名称 (如 ens5, eth0)
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

echo "正在优化网卡 $IFACE 的 UDP 性能..."
sudo apt update && sudo apt install -y ethtool
sudo ethtool -K $IFACE rx-udp-gro-forwarding on rx-gro-list on

# 4. 持久化网卡优化设置（防止重启失效）
echo "创建持久化网络优化脚本..."
sudo mkdir -p /etc/networkd-dispatcher/routable.d/
cat <<EOF | sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale
#!/sh
/usr/sbin/ethtool -K $IFACE rx-udp-gro-forwarding on rx-gro-list on
EOF
sudo chmod +x /etc/networkd-dispatcher/routable.d/50-tailscale

# 5. 启动 Tailscale 并通告为出口节点
echo "====================================================="
echo "请点击下方的链接完成登录授权："
echo "====================================================="
sudo tailscale up --advertise-exit-node
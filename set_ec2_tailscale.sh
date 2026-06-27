#!/bin/bash

# =================================================================
# AWS EC2 Tailscale Exit Node 自动部署与深度网络优化脚本 (Ubuntu 26.04 完美适配版)
# =================================================================

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本"
  exit 1
fi

# 1. 安装 Tailscale
echo "正在安装 Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# 2. 开启内核 IP 转发 与 谷歌 BBR 拥塞控制算法
echo "配置内核参数 (IP转发 + BBR加速)..."
sudo sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sudo sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
sudo sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

cat <<EOF | sudo tee -a /etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sudo sysctl -p

# 3. 自动检测网卡名称并优化 UDP 性能 (GRO)
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$IFACE" ]; then
    echo "❌ 未检测到默认网卡，跳过 UDP GRO 优化"
else
    echo "正在优化网卡 $IFACE 的 UDP 性能..."
    sudo apt update && sudo apt install -y ethtool
    sudo ethtool -K $IFACE rx-udp-gro-forwarding on rx-gro-list on

    # 4. 【针对 Ubuntu 26.04 优化】使用 Systemd 替代旧版 networkd-dispatcher 实现持久化
    echo "创建 Systemd 持久化网络优化服务..."
    
    # 动态写入一个通用的网络优化脚本
    cat << 'EOF' | sudo tee /usr/local/bin/tailscale-network-optimize.sh
#!/bin/sh
CURRENT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -n "$CURRENT_IFACE" ] && [ -x /usr/sbin/ethtool ]; then
    /usr/sbin/ethtool -K $CURRENT_IFACE rx-udp-gro-forwarding on rx-gro-list on
fi
EOF
    sudo chmod +x /usr/local/bin/tailscale-network-optimize.sh

    # 创建 Systemd 服务配置文件
    cat << EOF | sudo tee /etc/systemd/system/tailscale-network-optimize.service
[Unit]
Description=Tailscale UDP GRO Network Optimization
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tailscale-network-optimize.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载并启用服务，确保重启后自动运行
    sudo systemctl daemon-reload
    sudo systemctl enable tailscale-network-optimize.service
fi

# 5. UFW 防火墙冲突预防策略
if command -v ufw > /dev/null; then
    echo "检测到系统启用了 ufw 防火墙，正在配置放行与转发规则..."
    sudo ufw allow in on tailscale0
    sudo ufw allow 41641/udp
    sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
    sudo ufw reload
fi

# 6. 启动 Tailscale 并通告为出口节点
echo "====================================================="
echo " 脚本执行完毕！请点击下方的链接完成登录授权："
echo "====================================================="
sudo tailscale up --advertise-exit-node

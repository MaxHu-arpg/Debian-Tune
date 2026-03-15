#!/bin/bash

# 确保以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 权限运行此脚本"
   exit 1
fi

echo "开始优化系统性能..."

# ----------------------------------------------------------------
# 1. 提升系统资源限制 (File Descriptors & Processes)
# ----------------------------------------------------------------
echo ">>> 正在优化资源限制..."
cat << EOF > /etc/security/limits.d/99-myperformance.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc unlimited
* hard nproc unlimited
root soft nofile 1048576
root hard nofile 1048576
EOF

# 修改 Systemd 限制
sed -i 's/#DefaultLimitNOFILE=/DefaultLimitNOFILE=1048576/g' /etc/systemd/system.conf
sed -i 's/#DefaultLimitNPROC=/DefaultLimitNPROC=1048576/g' /etc/systemd/system.conf

# ----------------------------------------------------------------
# 2. 内核参数调优 (Network & Virtual Memory)
# ----------------------------------------------------------------
echo ">>> 正在写入内核参数 (sysctl)..."
cat << EOF > /etc/sysctl.d/99-mytune.conf
# 开启 BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 提升网络缓冲区 (16MB)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 提升连接队列深度
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 8192

# 快速回收与重用端口
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15

# 内存与交换优化
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50

# 防止过载时丢弃数据包
net.ipv4.tcp_slow_start_after_idle = 0
EOF

sysctl -p /etc/sysctl.d/99-tuning.conf

# ----------------------------------------------------------------
# 3. 磁盘 I/O 优化
# ----------------------------------------------------------------
echo ">>> 正在设置磁盘调度算法 (SSD/NVMe 优化)..."
# 自动为非机械硬盘设置 none 或 mq-deadline
for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
    if [ -d "$disk" ]; then
        # 如果是固态硬盘 (rotaion=0)
        if [ "$(cat $disk/queue/rotational)" == "0" ]; then
            echo "none" > "$disk/queue/scheduler" 2>/dev/null || echo "mq-deadline" > "$disk/queue/scheduler" 2>/dev/null
        fi
    fi
done

# ----------------------------------------------------------------
# 4. 文件系统优化 (挂载参数)
# ----------------------------------------------------------------
echo ">>> 正在优化文件系统挂载选项 (noatime)..."
# 实时重挂载根目录以应用 noatime
mount -o remount,noatime /

# 修改 fstab 以便重启生效
sed -i 's/errors=remount-ro/errors=remount-ro,noatime/g' /etc/fstab

# ----------------------------------------------------------------
# 5. CPU 性能模式
# ----------------------------------------------------------------
echo ">>> 正在设置 CPU 模式为 Performance..."
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
fi

echo "---"
echo "✅ 系统优化完成！"
echo "提示：部分资源限制修改需要重新登录或重启生效。"

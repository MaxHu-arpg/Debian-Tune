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
# 解释：^#? 匹配开头可能有也可能没有的 # 号
# .*$ 匹配该行剩下的所有字符并替换掉
sed -i 's/^#\?DefaultLimitNOFILE=.*$/DefaultLimitNOFILE=1048576/g' /etc/systemd/system.conf
sed -i 's/^#\?DefaultLimitNPROC=.*$/DefaultLimitNPROC=1048576/g' /etc/systemd/system.conf

# ----------------------------------------------------------------
# 2. 内核参数调优 (Network & Virtual Memory)
# ----------------------------------------------------------------
echo ">>> 正在写入内核参数 (sysctl)..."
cat << EOF > /etc/sysctl.d/98-mytune.conf
# 提高系统全局文件句柄限制 (200万)
fs.file-max = 2097152
fs.nr_open = 2097152

# 提升网络缓冲区 (16MB)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 提升连接队列深度
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 8192

# TCP 快速回收与重用 (注意：在 NAT 环境下小心开启)
#net.ipv4.tcp_tw_reuse = 1
#net.ipv4.ip_local_port_range = 1024 65535
#net.ipv4.tcp_fin_timeout = 15

net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_synack_retries = 4
# 表示系统同时保持TIME_WAIT的最大数量  
net.ipv4.tcp_max_tw_buckets = 16384
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
#net.ipv4.tcp_mtu_probing = 1
# 不建议开启tcp fast open功能 https://vpsgongyi.com/p/2237/
#net.ipv4.tcp_fastopen = 3

net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2

net.ipv4.neigh.default.gc_stale_time = 120

# 满足nf_conntrack_max=4*nf_conntrack_buckets
# 比如，对64G内存的机器，推荐配置nf_conntrack_max=4194304，nf_conntrack_buckets=1048576
net.netfilter.nf_conntrack_max=524288
net.netfilter.nf_conntrack_buckets=131072

# 内存与交换优化
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.vfs_cache_pressure = 50
#vm.overcommit_memory = 1
vm.min_free_kbytes = 40960

EOF

sysctl -p /etc/sysctl.d/98-mytune.conf

# # ----------------------------------------------------------------
# # 3. 磁盘 I/O 优化
# # ----------------------------------------------------------------
# echo ">>> 正在设置磁盘调度算法 (SSD/NVMe 优化)..."
# # 自动为非机械硬盘设置 none 或 mq-deadline
# for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
#     if [ -d "$disk" ]; then
#         # 如果是固态硬盘 (rotaion=0)
#         if [ "$(cat $disk/queue/rotational)" == "0" ]; then
#             echo "none" > "$disk/queue/scheduler" 2>/dev/null || echo "mq-deadline" > "$disk/queue/scheduler" 2>/dev/null
#         fi
#     fi
# done

# # ----------------------------------------------------------------
# # 4. 文件系统优化 (挂载参数)
# # ----------------------------------------------------------------
# echo ">>> 正在优化文件系统挂载选项 (noatime)..."
# # 实时重挂载根目录以应用 noatime
# mount -o remount,noatime /

# # 修改 fstab 以便重启生效
# sed -i 's/errors=remount-ro/errors=remount-ro,noatime/g' /etc/fstab

# # ----------------------------------------------------------------
# # 5. CPU 性能模式
# # ----------------------------------------------------------------
# echo ">>> 正在设置 CPU 模式为 Performance..."
# if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
#     echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
# fi

echo "---"
echo "✅ 系统优化完成！"
echo "提示：部分资源限制修改需要重新登录或重启生效。"

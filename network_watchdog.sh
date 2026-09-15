#!/bin/sh

# 1. 获取默认网关 IP（优先自动获取，失败时回退到静态 IP）
GATEWAY=$(ip route show | awk '/default/ {print $3; exit}')
: "${GATEWAY:=10.7.246.33}"

# 2. 快速检测：只要 ping 通 1 包即说明网络正常，立即退出 (降低耗时和 CPU 占用)
if ping -c 1 -W 2 "$GATEWAY" > /dev/null 2>&1; then
    exit 0
fi

# 3. 第一次失败后，二次确认（防止因偶尔的网络丢包导致误重启网卡）
sleep 2
if ! ping -c 2 -W 2 "$GATEWAY" > /dev/null 2>&1; then
    # 4. 确认不通，记录日志并重启网卡
    LOG_FILE="/var/log/network_watchdog.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [异常] 网关 $GATEWAY 无法连通，开始重启 eth0..." >> "$LOG_FILE"

    ifdown eth0 && ifup eth0

    # 5. 重启后再次验证并在日志记录结果
    sleep 3
    if ping -c 1 -W 2 "$GATEWAY" > /dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [恢复] eth0 重启成功，网关已恢复连通。" >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [错误] eth0 重启后依然无法连通网关！" >> "$LOG_FILE"
    fi
fi
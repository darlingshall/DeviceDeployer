#!/bin/sh

# 0. 补全 PATH 环境变量，防止 cron 执行时找不到系统命令
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# 2. 设置需要通过网关才能连通的外网/跨网段目标 IP（请根据实际环境修改，如 223.5.5.5 或 114.114.114.114）
TARGET_IP="8.8.8.8"

# 2. 快速检测：只要 ping 通 1 包即说明网络正常，立即退出 (降低耗时和 CPU 占用)
if ping -c 1 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
    exit 0
fi

# 3. 第
# 一次失败后，二次确认（防止因偶尔的网络丢包导致误重启网卡）
sleep 2
if ! ping -c 2 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
    # 4. 确认不通，记录日志并重启网卡
    LOG_FILE="/var/log/network_watchdog.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [异常] 目标 $TARGET_IP 无法连通，开始重启 eth0..." >> "$LOG_FILE"

    ifdown eth0 && ifup eth0

    # 5. 重启后再次验证并在日志记录结果
    sleep 3
    if ping -c 1 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [恢复] eth0 重启成功，网关已恢复连通。" >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [错误] eth0 重启后依然无法连通网关！" >> "$LOG_FILE"
    fi
#    # 6. 【防爆盘机制】限制日志只保留最新 300 行
#    if [ -f "$LOG_FILE" ]; then
#        tail -n 300 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
#    fi
fi
#!/bin/sh

# 0. 补全 PATH 环境变量，防止 cron 执行时找不到系统命令
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# 2. 设置需要通过网关才能连通的外网/跨网段目标 IP（请根据实际环境修改，如 223.5.5.5 或 114.114.114.114）
TARGET_IP="8.8.8.8"

# 3. 快速检测：只要 ping 通 1 包即说明网络正常，立即退出 (降低耗时和 CPU 占用)
if ping -c 1 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
    exit 0
fi

# 4. 第一次失败后，二次确认（防止因偶尔的网络丢包导致误重启网卡）
sleep 2
if ! ping -c 2 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
    # 5. 不通，则需要记录日志并重启网卡
    LOG_FILE="/var/log/network_watchdog.log"
    # 6. 【核心防死机机制】检测网线物理链路状态
    # 读取 carrier 文件，若为 0 说明网线已被拔出，绝不执行 ifdown/ifup！
    CARRIER=$(cat /sys/class/net/eth0/carrier 2>/dev/null)
    if [ "$CARRIER" != "1" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [警告] 无法连通 $TARGET_IP，但检测到 eth0 网线已拔出(Link Down)，跳过网卡重启以防系统异常。" >> "$LOG_FILE"
        exit 0
    fi

    # 7. 确认网线插着、但网络不通（说明是路由丢失或网络服务卡死），此时才安全重启网卡
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [异常] 网线已连接但目标 $TARGET_IP 无法连通，开始重启 eth0..." >> "$LOG_FILE"

    ifdown eth0 && ifup eth0 || ifup eth0

    # 8. 重启后再次验证并在日志记录结果
    sleep 5
    if ping -c 1 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [恢复] eth0 重启成功，网关已恢复连通。" >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [错误] eth0 重启后依然无法连通网关！" >> "$LOG_FILE"
    fi
   # 9. 【防爆盘机制】限制日志只保留最新 300 行
    if [ -f "$LOG_FILE" ]; then
        tail -n 300 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
fi
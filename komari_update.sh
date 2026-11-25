#!/bin/sh
set -e

HTTP_URL="$1"
AUTO_KEY="$2"

if [ -z "$HTTP_URL" ] || [ -z "$AUTO_KEY" ]; then
    echo "[ERROR] 用法: $0 <httpurl> <autokey>" >&2
    exit 1
fi

TARGET_FILE="/usr/sbin/komari-agent"
TEMP_FILE="/usr/sbin/komari-agent.tmp"
DOWNLOAD_URL="https://github.com/xtlspace/komari-zig-agent/releases/latest/download/komari-agent-linux-amd64"

# 判断是否为 Alpine 系统
is_alpine() {
    if [ -f /etc/alpine-release ]; then
        return 0
    elif [ -f /etc/os-release ] && grep -qi '^ID=alpine' /proc/os-release; then
        return 0
    fi
    return 1
}

# 判断是否为 Debian 系统
is_debian() {
    if [ -f /etc/debian_version ]; then
        return 0
    elif [ -f /etc/os-release ] && grep -qi '^ID=debian' /proc/os-release; then
        return 0
    fi
    return 1
}

# 清理旧的 nezha-agent 服务及检查定时任务
cleanup_nezha() {
    if is_alpine; then
        echo "[INFO] 检查 Alpine 下 nezha-agent 服务状态..."
        if rc-service nezha-agent status 2>/dev/null | grep -q 'started'; then
            echo "[INFO] 检测到 nezha-agent 正在运行，正在移除自启并停止服务..."
            rc-update del nezha-agent >/dev/null 2>&1 || true
            rc-service nezha-agent stop || true
        fi

        if [ -f /etc/crontabs/root ] && grep -q 'nezha-agent' /etc/crontabs/root; then
            echo "[WARN] 检测到 /etc/crontabs/root 中包含 nezha-agent 相关配置，请手动检查清理："
            grep -n 'nezha-agent' /etc/crontabs/root || true
        fi
    elif is_debian; then
        echo "[INFO] 检查 Debian 下 nezha-agent.service 状态..."
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nezha-agent.service 2>/dev/null; then
            echo "[INFO] 检测到 nezha-agent.service 正在运行，正在停止服务并取消开机自启..."
            systemctl stop nezha-agent.service || true
            systemctl disable nezha-agent.service || true
        elif command -v systemctl >/dev/null 2>&1 && systemctl is-enabled --quiet nezha-agent.service 2>/dev/null; then
            echo "[INFO] 检测到 nezha-agent.service 已设置自启，正在取消开机自启..."
            systemctl disable nezha-agent.service || true
        fi

        if [ -f /etc/crontab ] && grep -q 'nezha-agent' /etc/crontab; then
            echo "[WARN] 检测到 /etc/crontab 中包含 nezha-agent 相关配置，请手动检查清理："
            grep -n 'nezha-agent' /etc/crontab || true
        fi
    fi
}

cleanup_nezha

# 校验系统是否为 x86_64 架构
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "[ERROR] 当前系统架构为 $ARCH，仅支持 x86_64。" >&2
    exit 1
fi

mkdir -p /usr/sbin

# 下载到临时文件，避免直接写入运行中的文件导致 "Text file busy"
echo "[INFO] 正在下载最新版本 ($DOWNLOAD_URL)..."
if command -v curl >/dev/null 2>&1; then
    curl -fL "$DOWNLOAD_URL" -o "$TEMP_FILE"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$TEMP_FILE" "$DOWNLOAD_URL"
else
    echo "[ERROR] 未检测到 curl 或 wget，请先安装下载工具。" >&2
    exit 1
fi

chmod +x "$TEMP_FILE"

echo "[INFO] 正在移动到 $TARGET_FILE..."
mv -f "$TEMP_FILE" "$TARGET_FILE"

if is_alpine; then
    echo "[INFO] 检测到 Alpine 系统，正在更新 /etc/init.d/komari-agent..."
    cat << EOF > /etc/init.d/komari-agent
#!/sbin/openrc-run

name="komari-agent"
command="/usr/sbin/komari-agent"
command_args="--endpoint ${HTTP_URL}  --auto-discovery  ${AUTO_KEY} -i 6 --include-nics eth0 -month-rotate 1 --disable-auto-update"
command_user="root:root" #执行用户和用户组


supervisor="supervise-daemon"
rc_ulimit="-n 65535"
retry="SIGTERM/5/SIGKILL/5"
respawn_delay="5"
respawn_max="0"

start_pre() {
    pkill -9 -f "\${command}.*\${command_args}" >/dev/null 2>&1 || true
}
stop_post() {
    pkill -9 -f "\${command}.*\${command_args}" >/dev/null 2>&1 || true
}

#在网络启动后启动服务，二进制程序一般无需改动
depend() {
        after net dns
        use net
}
EOF
    chmod +x /etc/init.d/komari-agent
    rc-update add komari-agent default >/dev/null 2>&1 || true

    echo "[INFO] 正在重启 komari-agent 服务..."
    rc-service komari-agent restart
    echo "[SUCCESS] 二进制更新及 Alpine 服务重启完成！"
elif is_debian; then
    echo "[INFO] 检测到 Debian 系统，正在更新 /etc/systemd/system/komari-agent.service..."
    mkdir -p /etc/systemd/system
    cat << EOF > /etc/systemd/system/komari-agent.service
[Unit]
After=rc-local.service
[Service]
Type=simple
ExecStart=/usr/sbin/komari-agent --endpoint ${HTTP_URL}  --auto-discovery  ${AUTO_KEY} -i 6 --include-nics eth0 -month-rotate 1 --disable-auto-update
Restart=always
LimitNOFILE=51200
StartLimitBurst=0
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable komari-agent
    systemctl restart komari-agent
    echo "[SUCCESS] 二进制更新及 Debian 服务重启完成！"
else
    echo "[INFO] 未检测到 Alpine 或 Debian 系统，跳过服务配置与重启。"
    echo "[SUCCESS] 二进制文件更新完成！"
fi
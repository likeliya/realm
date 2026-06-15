#!/bin/bash

# ==========================================
# Realm 一键转发脚本 v3.1.3
# 更新日志:
# 1. 新增输入错误计数器
# 2. 连续输错 2 次自动返回主菜单
# 3. 添加 ipv4 和 ipv6 入口选择
# 4. 增加对 Alpine Linux (OpenRC) 的原生支持
# 5. 针对 Alpine 自动配置伪装 systemctl 修复面板状态抓取
# ==========================================

# --- 基础配置 ---
sh_ver="3.1.3"
panel_ver="v3.1.3.1"

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 路径定义
REALM_DIR="/root/realm"
REALM_BIN="${REALM_DIR}/realm"
CONFIG_DIR="/root/.realm"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
SERVICE_FILE_SYSTEMD="/etc/systemd/system/realm.service"
SERVICE_FILE_OPENRC="/etc/init.d/realm"
PANEL_DIR="${REALM_DIR}/web"
PANEL_BIN="${PANEL_DIR}/realm_web"

# === 核心修改：请将下方链接替换为你真实的 GitHub 脚本 Raw 直链 ===
SYSTEMCTL_PROXY_URL="https://raw.githubusercontent.com/likeliya/realm/refs/heads/main/systemctl"

# --- 系统初始化系统检测 ---
check_init_sys() {
    # 1. 最高优先级：直接检测是否为 Alpine Linux
    if [ -f "/etc/alpine-release" ]; then
        INIT_SYS="openrc"
    # 2. 严谨检测 systemd：判断 systemd 目录是否作为 init 真正挂载运行
    elif [ -d "/run/systemd/system" ]; then
        INIT_SYS="systemd"
    # 3. 降级备用检测：常规命令判断
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYS="openrc"
    elif command -v systemctl >/dev/null 2>&1; then
        INIT_SYS="systemd"
    else
        echo -e "${RED}无法识别当前系统的 init 管理器 (不支持 systemd 和 openrc)。${PLAIN}"
        exit 1
    fi
}

# --- 状态检测函数 ---

get_status() {
    if [ "$INIT_SYS" == "systemd" ]; then
        if systemctl is-active --quiet realm; then
            echo -e "${GREEN}运行中${PLAIN}"
        else
            echo -e "${RED}未运行${PLAIN}"
        fi
    elif [ "$INIT_SYS" == "openrc" ]; then
        if rc-service realm status 2>/dev/null | grep -q "started"; then
            echo -e "${GREEN}运行中${PLAIN}"
        else
            echo -e "${RED}未运行${PLAIN}"
        fi
    fi
}

get_panel_status() {
    if [ ! -f "$PANEL_BIN" ]; then
        echo -e "${RED}未安装${PLAIN}"
    elif [ "$INIT_SYS" == "systemd" ]; then
        if systemctl is-active --quiet realm-panel; then
            echo -e "${GREEN}运行中${PLAIN}"
        else
            echo -e "${YELLOW}已安装但未启动${PLAIN}"
        fi
    elif [ "$INIT_SYS" == "openrc" ]; then
        if rc-service realm-panel status 2>/dev/null | grep -q "started"; then
            echo -e "${GREEN}运行中${PLAIN}"
        else
            echo -e "${YELLOW}已安装但未启动${PLAIN}"
        fi
    fi
}

# --- 核心校验函数 ---

validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        echo -e "${RED}错误: 端口必须是 1-65535 之间的数字。${PLAIN}"
        return 1
    fi
}

validate_ip() {
    local ip=$1
    if [[ -z "$ip" ]]; then
        echo -e "${RED}错误: 地址不能为空。${PLAIN}"
        return 1
    fi
    if [[ "$ip" =~ ^[a-zA-Z0-9\.\:\-]+$ ]]; then
        return 0
    else
        echo -e "${RED}错误: 无效的 IP 或域名格式。${PLAIN}"
        return 1
    fi
}

check_port_available() {
    local port=$1
    if command -v ss >/dev/null; then
        if ss -tulpn | grep -q ":${port} " | grep -v "realm"; then
            echo -e "${RED}错误: 本机端口 ${port} 已被其他程序占用。${PLAIN}"
            return 1
        fi
    fi
    return 0
}

check_rule_exists() {
    local port=$1
    if [ -f "$CONFIG_FILE" ]; then
        # 兼容旧 of 0.0.0.0 格式和新的 [::] 格式检测
        if grep -q "listen = \"0.0.0.0:${port}\"" "$CONFIG_FILE" || grep -q "listen = \"\[::\]:${port}\"" "$CONFIG_FILE"; then
            echo -e "${RED}错误: 端口 ${port} 的规则已存在。${PLAIN}"
            return 0
        fi
    fi
    return 1
}

# --- 基础功能 ---

init_env() {
    mkdir -p "$REALM_DIR"
    mkdir -p "$CONFIG_DIR"
    [ ! -f "$CONFIG_FILE" ] && write_config_header
}

write_config_header() {
    cat <<EOF > "$CONFIG_FILE"
[network]
no_tcp = false
use_udp = true

EOF
}

check_dependencies() {
    local dependencies=("wget" "tar" "sed" "grep" "curl" "unzip")
    local missing=()
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then missing+=("$dep"); fi
    done
    
    local need_iproute=false
    if ! command -v ss >/dev/null 2>&1 || ! command -v ip >/dev/null 2>&1; then
        need_iproute=true
    fi

    if [ ${#missing[@]} -gt 0 ] || [ "$need_iproute" = true ]; then
        local msg="${missing[*]}"
        [ "$need_iproute" = true ] && msg="$msg iproute2"
        echo -e "${YELLOW}安装缺失依赖: $msg ...${PLAIN}"
        
        if [ -x "$(command -v apt-get)" ]; then
            apt-get update -y >/dev/null 2>&1
            [ ${#missing[@]} -gt 0 ] && apt-get install -y "${missing[@]}"
            [ "$need_iproute" = true ] && apt-get install -y iproute2
        elif [ -x "$(command -v yum)" ]; then
            [ ${#missing[@]} -gt 0 ] && yum install -y "${missing[@]}"
            [ "$need_iproute" = true ] && yum install -y iproute
        elif [ -x "$(command -v apk)" ]; then
            apk update >/dev/null 2>&1
            [ ${#missing[@]} -gt 0 ] && apk add "${missing[@]}"
            [ "$need_iproute" = true ] && apk add iproute2
        else
            echo -e "${RED}请手动安装依赖。${PLAIN}"; exit 1
        fi
    fi
}

install_realm() {
    echo -e "${GREEN}> 部署 Realm...${PLAIN}"
    check_dependencies; init_env
    local version=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -z "$version" ] && version="v2.6.0"
    
    local libc="gnu"
    if [ -f "/etc/alpine-release" ]; then
        libc="musl"
    fi
    
    local arch=$(uname -m)
    local filename=""
    case "$arch" in
        x86_64) filename="realm-x86_64-unknown-linux-${libc}.tar.gz" ;;
        aarch64|arm64) filename="realm-aarch64-unknown-linux-${libc}.tar.gz" ;;
        *) echo -e "${RED}不支持架构: $arch${PLAIN}"; return 1 ;;
    esac

    wget -O "realm.tar.gz" "https://github.com/zhboner/realm/releases/download/${version}/${filename}" || { echo -e "${RED}下载失败${PLAIN}"; return 1; }
    tar -xvf realm.tar.gz -C "$REALM_DIR" && rm -f realm.tar.gz
    chmod +x "$REALM_BIN"

    if [ "$INIT_SYS" == "systemd" ]; then
        cat <<EOF > "$SERVICE_FILE_SYSTEMD"
[Unit]
Description=Realm Forwarding Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
WorkingDirectory=${REALM_DIR}
ExecStart=${REALM_BIN} -c ${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable realm; systemctl restart realm
    elif [ "$INIT_SYS" == "openrc" ]; then
        cat <<EOF > "$SERVICE_FILE_OPENRC"
#!/sbin/openrc-run

name="realm"
description="Realm Forwarding Service"
command="${REALM_BIN}"
command_args="-c ${CONFIG_FILE}"
command_background=true
pidfile="/var/run/realm.pid"
output_log="/var/log/realm.log"
error_log="/var/log/realm.err"
directory="${REALM_DIR}"

depend() {
    need net
}
EOF
        chmod +x "$SERVICE_FILE_OPENRC"
        rc-update add realm default
        rc-service realm restart
    fi
    echo -e "${GREEN}安装完成${PLAIN}"
}

uninstall_realm() {
    read -p "确定卸载 Realm? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    
    if [ "$INIT_SYS" == "systemd" ]; then
        systemctl stop realm; systemctl disable realm
        rm -f "$SERVICE_FILE_SYSTEMD"; systemctl daemon-reload
    elif [ "$INIT_SYS" == "openrc" ]; then
        rc-service realm stop
        rc-update del realm default
        rm -f "$SERVICE_FILE_OPENRC"
    fi
    
    rm -rf "$REALM_DIR"
    read -p "删除配置? [y/N]: " del_conf
    [[ "$del_conf" == "y" || "$del_conf" == "Y" ]] && rm -rf "$CONFIG_DIR"
    echo -e "${GREEN}已卸载${PLAIN}"
}

# --- 服务控制 ---
stop_service() { 
    if [ "$INIT_SYS" == "systemd" ]; then
        systemctl stop realm >/dev/null 2>&1
    elif [ "$INIT_SYS" == "openrc" ]; then
        rc-service realm stop >/dev/null 2>&1
    fi
    echo "已停止" 
}

# --- 转发管理 ---

add_forward() {
    echo -e "${YELLOW}>>> 添加转发 (连续错误2次自动返回)${PLAIN}"
    
    local attempt=0
    local listen_ip="0.0.0.0"
    while true; do
        read -e -p "选择本机入口类型 (1: IPv4 [0.0.0.0], 2: IPv6/双栈 [::] 默认1): " l_type
        if [[ -z "$l_type" || "$l_type" == "1" ]]; then
            listen_ip="0.0.0.0"
            break
        elif [[ "$l_type" == "2" ]]; then
            listen_ip="[::]"
            break
        else
            ((attempt++)); [ $attempt -ge 2 ] && { echo -e "${RED}错误过多，返回主菜单${PLAIN}"; return; }
            echo -e "${RED}输入错误，请输入 1 或 2。${PLAIN}"
        fi
    done

    attempt=0
    while true; do
        read -e -p "本机端口: " lp
        if ! validate_port "$lp"; then
            ((attempt++)); [ $attempt -ge 2 ] && { echo -e "${RED}错误过多，返回主菜单${PLAIN}"; return; }
            continue
        fi
        if ! check_port_available "$lp"; then
            ((attempt++)); [ $attempt -ge 2 ] && { echo -e "${RED}错误过多，返回主菜单${PLAIN}"; return; }
            continue
        fi
        if check_rule_exists "$lp"; then
            ((attempt++)); [ $attempt -ge 2 ] && { echo -e "${RED}错误过多，返回主菜单${PLAIN}"; return; }
            continue
        fi
        break
    done

    attempt=0
    while true; do
        read -e -p "落地IP/域名: " rip
        if ! validate_ip "$rip"; then
             ((attempt++)); [ $attempt -ge 2 ] && { echo -e "${RED}错误过多，返回主菜单${PLAIN}"; return; }
             continue
        fi
        break
    done

    attempt=0
    while true; do
        read -e -p "落地端口: " rp
        if ! validate_port "$rp"; then
            ((attempt++)); [ $attempt -ge 2 ] && { echo -e "${RED}错误过多，返回主菜单${PLAIN}"; return; }
            continue
        fi
        break
    done

    local formatted_rip="$rip"
    if [[ "$rip" =~ ":" ]]; then
        formatted_rip="[${rip}]"
    fi

    cat <<EOF >> "$CONFIG_FILE"

[[endpoints]]
listen = "${listen_ip}:$lp"
remote = "${formatted_rip}:$rp"
EOF
    restart_service
}

add_range_forward() {
    echo -e "${YELLOW}>>> 端口段转发 (连续错误2次自动返回)${PLAIN}"
    local attempt=0
    
    local listen_ip="0.0.0.0"
    while true; do
        read -e -p "选择本机入口类型 (1: IPv4 [0.0.0.0], 2: IPv6/双栈 [::] 默认1): " l_type
        if [[ -z "$l_type" || "$l_type" == "1" ]]; then
            listen_ip="0.0.0.0"
            break
        elif [[ "$l_type" == "2" ]]; then
            listen_ip="[::]"
            break
        else
            ((attempt++)); [ $attempt -ge 2 ] && { echo -e "${RED}错误过多，返回主菜单${PLAIN}"; return; }
            echo -e "${RED}输入错误，请输入 1 或 2。${PLAIN}"
        fi
    done

    attempt=0; while true; do read -e -p "落地IP: " rip; validate_ip "$rip" && break; ((attempt++)); [ $attempt -ge 2 ] && return; done
    attempt=0; while true; do read -e -p "起始端口: " sp; validate_port "$sp" && break; ((attempt++)); [ $attempt -ge 2 ] && return; done
    attempt=0; while true; do read -e -p "结束端口: " ep; validate_port "$ep" && break; ((attempt++)); [ $attempt -ge 2 ] && return; done
    attempt=0; while true; do read -e -p "落地基准端口: " rbp; validate_port "$rbp" && break; ((attempt++)); [ $attempt -ge 2 ] && return; done

    [ "$sp" -ge "$ep" ] && { echo -e "${RED}起始必须小于结束${PLAIN}"; return; }

    local formatted_rip="$rip"
    if [[ "$rip" =~ ":" ]]; then
        formatted_rip="[${rip}]"
    fi

    echo "生成中..."
    local rp=$rbp
    for ((p=$sp; p<=$ep; p++)); do
        if ! grep -q "listen = \"\[::\]:$p\"" "$CONFIG_FILE" && ! grep -q "listen = \"0.0.0.0:$p\"" "$CONFIG_FILE"; then
            cat <<EOF >> "$CONFIG_FILE"

[[endpoints]]
listen = "${listen_ip}:$p"
remote = "${formatted_rip}:$rp"
EOF
        fi
        ((rp++))
    done
    restart_service
}

delete_forward() {
    [ ! -f "$CONFIG_FILE" ] && return
    local listens=($(grep "listen =" "$CONFIG_FILE" | awk -F'"' '{print $2}'))
    local remotes=($(grep "remote =" "$CONFIG_FILE" | awk -F'"' '{print $2}'))
    [ ${#listens[@]} -eq 0 ] && { echo "无规则"; return; }

    echo "==============="
    for ((i=0; i<${#listens[@]}; i++)); do
        echo -e "${GREEN}$((i+1)).${PLAIN} ${listens[i]} -> ${remotes[i]}"
    done
    echo "==============="
    read -p "删除序号(0取消): " c
    [[ "$c" == "0" || -z "$c" ]] && return
    
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"; write_config_header
    local del_idx=$((c-1))
    for ((i=0; i<${#listens[@]}; i++)); do
        if [ $i -ne $del_idx ]; then
            cat <<EOF >> "$CONFIG_FILE"

[[endpoints]]
listen = "${listens[i]}"
remote = "${remotes[i]}"
EOF
        fi
    done
    restart_service
}

# --- 服务控制 ---
start_service() { 
    if [ "$INIT_SYS" == "systemd" ]; then
        systemctl start realm
    elif [ "$INIT_SYS" == "openrc" ]; then
        rc-service realm start
    fi
    echo "已启动" 
}

stop_service() { 
    if [ "$INIT_SYS" == "systemd" ]; then
        systemctl stop realm
    elif [ "$INIT_SYS" == "openrc" ]; then
        rc-service realm stop
    fi
    echo "已停止" 
}

restart_service() { 
    if [ "$INIT_SYS" == "systemd" ]; then
        systemctl daemon-reload; systemctl restart realm; sleep 1
        systemctl is-active --quiet realm && echo -e "${GREEN}重启成功${PLAIN}" || echo -e "${RED}重启失败${PLAIN}"
    elif [ "$INIT_SYS" == "openrc" ]; then
        rc-service realm restart; sleep 1
        rc-service realm status 2>/dev/null | grep -q "started" && echo -e "${GREEN}重启成功${PLAIN}" || echo -e "${RED}重启失败${PLAIN}"
    fi
}

# --- 面板管理 ---
panel_management() {
    while true; do
        clear
        echo "=== Realm 面板管理 ($panel_ver) ==="
        echo -e "面板状态: $(get_panel_status)"
        echo "============================="
        echo "1. 安装面板"
        echo "2. 启动面板"
        echo "3. 停止面板"
        echo "4. 卸载面板"
        echo "0. 返回上级"
        read -p "选择: " pc
        case $pc in
            1) install_panel ;;
            2) 
               if [ "$INIT_SYS" == "systemd" ]; then systemctl start realm-panel; else rc-service realm-panel start; fi
               echo "尝试启动..." 
               ;;
            3) 
               if [ "$INIT_SYS" == "systemd" ]; then systemctl stop realm-panel; else rc-service realm-panel stop; fi
               echo "已停止" 
               ;;
            4) uninstall_panel ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
        read -p "按回车继续..."
    done
}

install_panel() {
    check_dependencies
    local arch=$(uname -m)
    local p_file=""
    case "$arch" in
        x86_64) p_file="realm-panel-linux-amd64.zip" ;;
        aarch64|arm64) p_file="realm-panel-linux-arm64.zip" ;;
        *) echo "不支持架构: $arch"; return ;;
    esac

    mkdir -p "$PANEL_DIR"
    local url="https://github.com/likeliya/realm/releases/download/${panel_ver}/${p_file}"
    if wget -O "$p_file" "$url"; then
        unzip -o "$p_file" -d "$PANEL_DIR" && chmod +x "$PANEL_BIN" && rm -f "$p_file"
        
        if [ "$INIT_SYS" == "systemd" ]; then
            cat <<EOF > /etc/systemd/system/realm-panel.service
[Unit]
Description=Realm Web Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${PANEL_DIR}
ExecStart=${PANEL_BIN}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload; systemctl enable realm-panel; systemctl start realm-panel
        elif [ "$INIT_SYS" == "openrc" ]; then
            cat <<EOF > /etc/init.d/realm-panel
#!/sbin/openrc-run

name="realm-panel"
description="Realm Web Panel"
command="${PANEL_BIN}"
command_background=true
pidfile="/var/run/realm-panel.pid"
directory="${PANEL_DIR}"

depend() {
    need net
}
EOF
            chmod +x /etc/init.d/realm-panel
            rc-update add realm-panel default
            rc-service realm-panel start

            # === 核心增加：自动在 Alpine 系统下配置伪装的 systemctl ===
            echo -e "${YELLOW}> 检测到 Alpine Linux，开始配置伪装 systemctl 以支撑面板状态抓取...${PLAIN}"
            if wget -qO /bin/systemctl "$SYSTEMCTL_PROXY_URL"; then
                chmod +x /bin/systemctl
                ln -sf /bin/systemctl /usr/bin/systemctl
                echo -e "${GREEN}伪装 systemctl 自动化部署并链接成功！${PLAIN}"
            else
                echo -e "${RED}警告: 伪装 systemctl 脚本下载失败，请检查 URL 是否有效。${PLAIN}"
            fi
        fi
        echo -e "${GREEN}面板安装成功!${PLAIN}"
    else
        echo -e "${RED}下载失败${PLAIN}"
    fi
}

uninstall_panel() {
    if [ "$INIT_SYS" == "systemd" ]; then
        systemctl stop realm-panel; systemctl disable realm-panel
        rm -f /etc/systemd/system/realm-panel.service; systemctl daemon-reload
    elif [ "$INIT_SYS" == "openrc" ]; then
        rc-service realm-panel stop
        rc-update del realm-panel default
        rm -f /etc/init.d/realm-panel

        # === 核心增加：卸载面板时顺手清理伪装脚本与软链接 ===
        echo -e "${YELLOW}> 正在清理 Alpine 专属伪装环境...${PLAIN}"
        rm -f /bin/systemctl
        rm -f /usr/bin/systemctl
    fi
    rm -rf "$PANEL_DIR"
    echo "已卸载"
}

# --- 脚本更新 ---
Update_Shell() {
    local url="https://raw.githubusercontent.com/wcwq98/realm/main/realm.sh"
    local new_ver=$(wget -qO- "$url" | grep 'sh_ver="' | awk -F "=" '{print $NF}' | tr -d '"' | head -1)
    [[ -z "$new_ver" ]] && { echo -e "${RED}检测失败${PLAIN}"; return; }
    [[ "$new_ver" == "$sh_ver" ]] && { echo "已是最新"; return; }
    read -p "更新到 $new_ver? [y/N]: " yn
    [[ "$yn" =~ ^[Yy]$ ]] && wget -N --no-check-certificate "$url" -O realm.sh && chmod +x realm.sh && echo "已更新" && exit 0
}

# --- 主菜单 ---
show_menu() {
    clear
    echo "################################################"
    echo "#        Realm 一键转发脚本 (v${sh_ver})         #"
    echo "################################################"
    echo -e " Realm 状态: $(get_status)"
    echo -e " 面板 状态: $(get_panel_status)"
    echo -e " 当前管理器: ${GREEN}${INIT_SYS}${PLAIN}"
    echo "------------------------------------------------"
    echo "  1. 安装 / 重置 Realm"
    echo "  2. 卸载 Realm"
    echo "------------------------------------------------"
    echo "  3. 添加转发规则"
    echo "  4. 添加端口段转发"
    echo "  5. 删除转发规则"
    echo "  6. 查看当前配置"
    echo "------------------------------------------------"
    echo "  7. 启动服务"
    echo "  8. 停止服务"
    echo "  9. 重启服务"
    echo "------------------------------------------------"
    echo "  10. 更新脚本"
    echo "  11. 面板管理"
    echo "  0. 退出脚本"
    echo "################################################"
}

main() {
    check_init_sys
    check_dependencies; init_env
    while true; do
        show_menu
        read -p "选择 [0-11]: " opt
        case $opt in
            1) install_realm ;;
            2) uninstall_realm ;;
            3) add_forward ;;
            4) add_range_forward ;;
            5) delete_forward ;;
            6) cat "$CONFIG_FILE" ;;
            7) start_service ;;
            8) stop_service ;;
            9) restart_service ;;
            10) Update_Shell ;;
            11) panel_management ;;
            0) exit 0 ;;
            *) echo "无效" ;;
        esac
        [ "$opt" != "0" ] && read -p "按回车返回..."
    done
}

main

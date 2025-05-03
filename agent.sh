#!/bin/sh

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
SCREEN_NAME="nezha_agent"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

info() {
    printf "${yellow}%s${plain}\n" "$*"
}

sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "错误：系统中未安装sudo，无法继续操作。"
            exit 1
        fi
    else
        "$@"
    fi
}

deps_check() {
    deps="wget unzip grep"
    set -- "$api_list"
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            err "未找到 $dep，请先安装它。"
            exit 1
        fi
    done

    # 检查screen并安装（如果未找到）
    if ! command -v screen >/dev/null 2>&1; then
        info "未安装screen，正在尝试安装..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y screen
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y screen
        elif command -v apk >/dev/null 2>&1; then
            sudo apk add screen
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm screen
        else
            err "无法自动安装screen。请手动安装screen。"
            exit 1
        fi
        
        if ! command -v screen >/dev/null 2>&1; then
            err "安装screen失败。请手动安装。"
            exit 1
        else
            success "screen安装成功。"
        fi
    fi
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://developers.cloudflare.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    set -- "$api_list"
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s "$url")"
        endpoint="$(echo "$text" | sed -n 's/.*h=\([^ ]*\).*/\1/p')"
        if echo "$text" | grep -qw 'CN'; then
            isCN=true
            break
        elif echo "$url" | grep -q "$endpoint"; then
            break
        fi
    done
}

env_check() {
    mach=$(uname -m)
    case "$mach" in
        amd64|x86_64)
            os_arch="amd64"
            ;;
        i386|i686)
            os_arch="386"
            ;;
        aarch64|arm64)
            os_arch="arm64"
            ;;
        *arm*)
            os_arch="arm"
            ;;
        s390x)
            os_arch="s390x"
            ;;
        riscv64)
            os_arch="riscv64"
            ;;
        mips)
            os_arch="mips"
            ;;
        mipsel|mipsle)
            os_arch="mipsle"
            ;;
        *)
            err "未知架构：$mach"
            exit 1
            ;;
    esac

    system=$(uname)
    case "$system" in
        *Linux*)
            os="linux"
            ;;
        *Darwin*)
            os="darwin"
            ;;
        *FreeBSD*)
            os="freebsd"
            ;;
        *)
            err "未知操作系统：$system"
            exit 1
            ;;
    esac
}

init() {
    deps_check
    env_check

    ## 中国IP检测
    if [ -z "$CN" ]; then
        geo_check
        if [ -n "$isCN" ]; then
            CN=true
        fi
    fi

    if [ -z "$CN" ]; then
        GITHUB_URL="github.com"
    else
        GITHUB_URL="gitee.com"
    fi
}

stop_agent() {
    # 检查screen会话是否存在并终止它
    if screen -list | grep -q "$SCREEN_NAME"; then
        screen -S "$SCREEN_NAME" -X quit
        info "已停止哪吒探针screen会话。"
    fi
}

install() {
    echo "正在安装..."

    if [ -z "$CN" ]; then
        NZ_AGENT_URL="https://${GITHUB_URL}/nezhahq/agent/releases/latest/download/nezha-agent_${os}_${os_arch}.zip"
    else
        _version=$(curl -m 10 -sL "https://gitee.com/api/v5/repos/naibahq/agent/releases/latest" | awk -F '"' '{for(i=1;i<=NF;i++){if($i=="tag_name"){print $(i+2)}}}')
        NZ_AGENT_URL="https://${GITHUB_URL}/naibahq/agent/releases/download/${_version}/nezha-agent_${os}_${os_arch}.zip"
    fi

    _cmd="wget -T 60 -O /tmp/nezha-agent_${os}_${os_arch}.zip $NZ_AGENT_URL >/dev/null 2>&1"
    if ! eval "$_cmd"; then
        err "下载哪吒探针失败，请检查网络连接"
        exit 1
    fi

    sudo mkdir -p $NZ_AGENT_PATH

    sudo unzip -qo /tmp/nezha-agent_${os}_${os_arch}.zip -d $NZ_AGENT_PATH &&
        sudo rm -rf /tmp/nezha-agent_${os}_${os_arch}.zip

    path="$NZ_AGENT_PATH/config.yml"
    if [ -f "$path" ]; then
        random=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 5)
        path=$(printf "%s" "$NZ_AGENT_PATH/config-$random.yml")
    fi

    if [ -z "$NZ_SERVER" ]; then
        err "NZ_SERVER 不能为空"
        exit 1
    fi

    if [ -z "$NZ_CLIENT_SECRET" ]; then
        err "NZ_CLIENT_SECRET 不能为空"
        exit 1
    fi

    # 如果正在运行，停止现有的探针
    stop_agent

    # 创建配置文件
    cat > "$path" << EOF
debug: false
server: "${NZ_SERVER}"
secret: "${NZ_CLIENT_SECRET}"
tls: ${NZ_TLS:-false}
disable_auto_update: ${NZ_DISABLE_AUTO_UPDATE:-false}
disable_force_update: ${DISABLE_FORCE_UPDATE:-false}
disable_command_execute: ${NZ_DISABLE_COMMAND_EXECUTE:-false}
skip_conn: ${NZ_SKIP_CONNECTION_COUNT:-false}
EOF

    chmod +x "$NZ_AGENT_PATH/nezha-agent"

    # 创建启动脚本
    startup_script="$NZ_AGENT_PATH/start-agent.sh"
    cat > "$startup_script" << EOF
#!/bin/sh
cd "$NZ_AGENT_PATH"
./nezha-agent -c "$path"
EOF
    chmod +x "$startup_script"

    # 在screen会话中启动探针
    screen -dmS "$SCREEN_NAME" "$startup_script"
    
    if screen -list | grep -q "$SCREEN_NAME"; then
        success "哪吒探针安装成功并在screen会话'$SCREEN_NAME'中运行"
        info "查看探针状态，请使用: screen -r $SCREEN_NAME"
        info "从screen会话中分离，请按 Ctrl+A 然后按 D"
    else
        err "在screen会话中启动哪吒探针失败"
        exit 1
    fi
}

uninstall() {
    stop_agent
    
    if [ -d "$NZ_AGENT_PATH" ]; then
        sudo rm -rf "$NZ_AGENT_PATH"
        success "卸载完成。"
    else
        info "未找到探针目录，无需卸载。"
    fi
}

status() {
    if screen -list | grep -q "$SCREEN_NAME"; then
        success "哪吒探针正在screen会话'$SCREEN_NAME'中运行"
    else
        err "哪吒探针未运行"
    fi
}

restart() {
    stop_agent
    info "正在启动哪吒探针..."
    
    # 查找最新的配置文件
    config_file=$(find "$NZ_AGENT_PATH" -type f -name "config*.yml" | sort -r | head -n 1)
    
    if [ -z "$config_file" ]; then
        err "未找到配置文件，请重新安装。"
        exit 1
    fi
    
    # 在screen会话中启动探针
    startup_script="$NZ_AGENT_PATH/start-agent.sh"
    cat > "$startup_script" << EOF
#!/bin/sh
cd "$NZ_AGENT_PATH"
./nezha-agent -c "$config_file"
EOF
    chmod +x "$startup_script"
    
    screen -dmS "$SCREEN_NAME" "$startup_script"
    
    if screen -list | grep -q "$SCREEN_NAME"; then
        success "哪吒探针重启成功"
    else
        err "重启哪吒探针失败"
        exit 1
    fi
}

case "$1" in
    uninstall)
        uninstall
        exit
        ;;
    status)
        status
        exit
        ;;
    restart)
        restart
        exit
        ;;
    stop)
        stop_agent
        exit
        ;;
esac

init
install

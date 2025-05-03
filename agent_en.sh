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
            err "ERROR: sudo is not installed on the system, the action cannot be proceeded."
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
            err "$dep not found, please install it first."
            exit 1
        fi
    done

    # Check screen and install if not found
    if ! command -v screen >/dev/null 2>&1; then
        info "Screen is not installed, trying to install..."
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
            err "Could not install screen automatically. Please install screen manually."
            exit 1
        fi
        
        if ! command -v screen >/dev/null 2>&1; then
            err "Failed to install screen. Please install it manually."
            exit 1
        else
            success "Screen installed successfully."
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
            err "Unknown architecture: $mach"
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
            err "Unknown operating system: $system"
            exit 1
            ;;
    esac
}

init() {
    deps_check
    env_check

    ## China_IP
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
    # Check if screen session exists and kill it
    if screen -list | grep -q "$SCREEN_NAME"; then
        screen -S "$SCREEN_NAME" -X quit
        info "Stopped nezha-agent screen session."
    fi
}

install() {
    echo "Installing..."

    if [ -z "$CN" ]; then
        NZ_AGENT_URL="https://${GITHUB_URL}/nezhahq/agent/releases/latest/download/nezha-agent_${os}_${os_arch}.zip"
    else
        _version=$(curl -m 10 -sL "https://gitee.com/api/v5/repos/naibahq/agent/releases/latest" | awk -F '"' '{for(i=1;i<=NF;i++){if($i=="tag_name"){print $(i+2)}}}')
        NZ_AGENT_URL="https://${GITHUB_URL}/naibahq/agent/releases/download/${_version}/nezha-agent_${os}_${os_arch}.zip"
    fi

    _cmd="wget -T 60 -O /tmp/nezha-agent_${os}_${os_arch}.zip $NZ_AGENT_URL >/dev/null 2>&1"
    if ! eval "$_cmd"; then
        err "Download nezha-agent release failed, check your network connectivity"
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
        err "NZ_SERVER should not be empty"
        exit 1
    fi

    if [ -z "$NZ_CLIENT_SECRET" ]; then
        err "NZ_CLIENT_SECRET should not be empty"
        exit 1
    fi

    # Stop existing agent if running
    stop_agent

    # Create config file
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

    # Create a startup script
    startup_script="$NZ_AGENT_PATH/start-agent.sh"
    cat > "$startup_script" << EOF
#!/bin/sh
cd "$NZ_AGENT_PATH"
./nezha-agent -c "$path"
EOF
    chmod +x "$startup_script"

    # Start the agent in a screen session
    screen -dmS "$SCREEN_NAME" "$startup_script"
    
    if screen -list | grep -q "$SCREEN_NAME"; then
        success "nezha-agent successfully installed and running in screen session '$SCREEN_NAME'"
        info "To check agent status, use: screen -r $SCREEN_NAME"
        info "To detach from screen session, press Ctrl+A then D"
    else
        err "Failed to start nezha-agent in screen session"
        exit 1
    fi
}

uninstall() {
    stop_agent
    
    if [ -d "$NZ_AGENT_PATH" ]; then
        sudo rm -rf "$NZ_AGENT_PATH"
        success "Uninstallation completed."
    else
        info "Agent directory not found. Nothing to uninstall."
    fi
}

status() {
    if screen -list | grep -q "$SCREEN_NAME"; then
        success "nezha-agent is running in screen session '$SCREEN_NAME'"
    else
        err "nezha-agent is not running"
    fi
}

restart() {
    stop_agent
    info "Starting nezha-agent..."
    
    # Find the latest config file
    config_file=$(find "$NZ_AGENT_PATH" -type f -name "config*.yml" | sort -r | head -n 1)
    
    if [ -z "$config_file" ]; then
        err "No configuration file found. Please reinstall."
        exit 1
    fi
    
    # Start the agent in a screen session
    startup_script="$NZ_AGENT_PATH/start-agent.sh"
    cat > "$startup_script" << EOF
#!/bin/sh
cd "$NZ_AGENT_PATH"
./nezha-agent -c "$config_file"
EOF
    chmod +x "$startup_script"
    
    screen -dmS "$SCREEN_NAME" "$startup_script"
    
    if screen -list | grep -q "$SCREEN_NAME"; then
        success "nezha-agent restarted successfully"
    else
        err "Failed to restart nezha-agent"
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

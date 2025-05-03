#!/bin/sh

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
SCREEN_SESSION_NAME="nezha_agent"

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

detect_pkg_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    else
        err "Unable to determine package manager. Please install screen manually."
        exit 1
    fi
}

install_screen() {
    info "Installing screen using $PKG_MANAGER..."
    case "$PKG_MANAGER" in
        apt)
            if ! sudo apt update && sudo apt install -y screen; then
                err "Failed to install screen via apt"
                exit 1
            fi
            ;;
        apk)
            if ! sudo apk add screen; then
                err "Failed to install screen via apk"
                exit 1
            fi
            ;;
        yum)
            if ! sudo yum install -y screen; then
                err "Failed to install screen via yum"
                exit 1
            fi
            ;;
        dnf)
            if ! sudo dnf install -y screen; then
                err "Failed to install screen via dnf"
                exit 1
            fi
            ;;
        *)
            err "Unsupported package manager: $PKG_MANAGER"
            exit 1
            ;;
    esac
    success "screen installed successfully"
}

deps_check() {
    deps="wget unzip grep screen"
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            if [ "$dep" = "screen" ]; then
                info "screen not found, attempting to install..."
                detect_pkg_manager
                install_screen
            else
                err "$dep not found, please install it first."
                exit 1
            fi
        fi
    done
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://developers.cloudflare.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    set -- "$api_list"
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s "$url")"
        endpoint="$(echo "$text" | grep -o 'h=[^ ]*' | cut -d= -f2 | head -1)"
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
            err "Unknown system: $system"
            exit 1
            ;;
    esac
}

init() {
    deps_check
    env_check

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

install() {
    echo "Installing..."

    if [ -z "$CN" ]; then
        NZ_AGENT_URL="https://${GITHUB_URL}/nezhahq/agent/releases/latest/download/nezha-agent_${os}_${os_arch}.zip"
    else
        _version=$(curl -m 10 -sL "https://gitee.com/api/v5/repos/naibahq/agent/releases/latest" | awk -F '"' '/tag_name/ {print substr($4,2)}')
        NZ_AGENT_URL="https://${GITHUB_URL}/naibahq/agent/releases/download/${_version}/nezha-agent_${os}_${os_arch}.zip"
    fi

    _cmd="wget -T 60 -O /tmp/nezha-agent_${os}_${os_arch}.zip $NZ_AGENT_URL 2>&1 | tee /tmp/wget.log"
    if ! eval "$_cmd"; then
        err "Download failed. Log:"
        cat /tmp/wget.log
        exit 1
    fi
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

    start_cmd="env NZ_UUID=$NZ_UUID NZ_SERVER=$NZ_SERVER NZ_CLIENT_SECRET=$NZ_CLIENT_SECRET NZ_TLS=$NZ_TLS NZ_DISABLE_AUTO_UPDATE=$NZ_DISABLE_AUTO_UPDATE NZ_DISABLE_FORCE_UPDATE=$NZ_DISABLE_FORCE_UPDATE NZ_DISABLE_COMMAND_EXECUTE=$NZ_DISABLE_COMMAND_EXECUTE NZ_SKIP_CONNECTION_COUNT=$NZ_SKIP_CONNECTION_COUNT ${NZ_AGENT_PATH}/nezha-agent"

    if screen -ls | grep -q "$SCREEN_SESSION_NAME"; then
        info "Found existing screen session, killing it..."
        screen -S "$SCREEN_SESSION_NAME" -X quit
        sleep 1
    fi

    info "Starting nezha-agent in screen session..."
    if ! screen -dmS "$SCREEN_SESSION_NAME" $start_cmd; then
        err "Failed to start screen session"
        exit 1
    fi

    sleep 2
    if pgrep -f "nezha-agent" > /dev/null; then
        success "nezha-agent successfully installed and running in screen session."
        info "Attach to the session with: ${green}screen -r $SCREEN_SESSION_NAME${plain}"
    else
        err "Failed to start nezha-agent"
        exit 1
    fi
}

uninstall() {
    if screen -ls | grep -q "$SCREEN_SESSION_NAME"; then
        info "Stopping screen session..."
        screen -S "$SCREEN_SESSION_NAME" -X quit
    fi
    
    sudo rm -rf "$NZ_AGENT_PATH"
    info "Uninstallation completed."
}

if [ "$1" = "uninstall" ]; then
    uninstall
    exit
fi

init
install

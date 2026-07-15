#!/bin/bash
# Optimized Homebrew Install Script V2.1.0 | P0 Full Optimized
# Support: macOS Intel/M1/M2/M3 | Linux / WSL
set -eo pipefail

########################### 全局常量 & 初始化 ###########################
SCRIPT_VERSION="2.1.0"
SCRIPT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
TMP_DIR="$HOME/.brew_install_tmp"
LOG_FILE="$HOME/.brew_install.log"
TAG_MARKER="#brew-mirror-auto"
LOCK_FILE="/tmp/brew_install.lock"
NETWORK_TIMEOUT=3
NETWORK_RETRY_TIMES=2

# ========== 国内镜像源配置 ==========
MIRROR_GIT_TUNA="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew"
MIRROR_GIT_GITEE="https://gitee.com/mirrors/homebrew-install"
MIRROR_BOTTLE_ALI="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
MIRROR_BOTTLE_TUNA="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
MIRROR_BOTTLE_USTC="https://mirrors.ustc.edu.cn/homebrew-bottles"
MIRROR_BOTTLE_TENCENT="https://mirrors.cloud.tencent.com/homebrew-bottles"

# API域名独立配置
MIRROR_API_TUNA="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
MIRROR_API_ALI="https://mirrors.aliyun.com/homebrew/homebrew-bottles/api"

# Pip镜像同步对应
PIP_ALI="http://mirrors.aliyun.com/pypi/simple"
PIP_TUNA="https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_USTC="https://pypi.mirrors.ustc.edu.cn/simple"
PIP_TENCENT="https://mirrors.cloud.tencent.com/pypi/simple"

# ========== 海外官方源配置 ==========
OFFICIAL_GIT_BASE="https://github.com/Homebrew"
OFFICIAL_API_DOMAIN="https://formulae.brew.sh/api"

# 系统标识
OS=$(uname)
UNAME_MACHINE=$(uname -m)
HOMEBREW_ON_MAC=0
HOMEBREW_ON_LINUX=0

# Mac 路径
HB_ARM_PREFIX="/opt/homebrew"
HB_X86_PREFIX="/usr/local/Homebrew"

# 运行时变量
HB_PREFIX=""
HB_REPO=""
HB_CACHE=""
HB_LOGS=""
SHELL_PROFILE=""
USER_GIT_MIRROR=""
USER_BOTTLE_MIRROR=""
USER_API_DOMAIN=""
USER_PIP_INDEX=""
IS_OVERSEAS=0
NO_COLOR=0
RUN_UNINSTALL=0
RUN_SWITCH_ONLY=0

# 验证结果统计
VERIFY_ERRORS=0
VERIFY_WARNINGS=0

########################### 彩色日志工具函数 ###########################
tty_support() { [[ -t 1 ]]; }

ESC_RESET="\033[0m"
ESC_RED="\033[31m"
ESC_GREEN="\033[32m"
ESC_YELLOW="\033[33m"
ESC_BLUE="\033[34m"
ESC_CYAN="\033[36m"

_log_raw() {
    echo "[$SCRIPT_TIME] $*" >> "$LOG_FILE"
}

log_info() {
    _log_raw "[INFO] $*"
    if [[ $NO_COLOR -eq 1 ]] || ! tty_support; then
        echo "[INFO] $*"
    else
        echo -e "${ESC_BLUE}[INFO] $*${ESC_RESET}"
    fi
}

log_success() {
    _log_raw "[SUCCESS] $*"
    if [[ $NO_COLOR -eq 1 ]] || ! tty_support; then
        echo "[SUCCESS] $*"
    else
        echo -e "${ESC_GREEN}[SUCCESS] $*${ESC_RESET}"
    fi
}

log_warn() {
    _log_raw "[WARN] $*"
    VERIFY_WARNINGS=$((VERIFY_WARNINGS+1))
    if [[ $NO_COLOR -eq 1 ]] || ! tty_support; then
        echo "[WARN] $*"
    else
        echo -e "${ESC_YELLOW}[WARN] $*${ESC_RESET}"
    fi
}

log_error() {
    _log_raw "[ERROR] $*"
    VERIFY_ERRORS=$((VERIFY_ERRORS+1))
    if [[ $NO_COLOR -eq 1 ]] || ! tty_support; then
        echo "[ERROR] $*"
    else
        echo -e "${ESC_RED}[ERROR] $*${ESC_RESET}"
    fi
}

check_exec() {
    local msg="$1"
    shift
    if "$@"; then
        log_success "$msg"
    else
        log_error "$msg 执行失败"
        return 1
    fi
}

########################### P0：锁文件 + 信号捕获自动清理 ###########################
remove_lock() {
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
}

create_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        log_error "检测到脚本正在运行，锁文件：$LOCK_FILE，如需强制执行请手动删除锁文件"
        exit 1
    fi
    trap remove_lock EXIT INT TERM
    touch "$LOCK_FILE"
}

########################### P0：sudo 后台保活 ###########################
sudo_keep_alive() {
    log_info "启动sudo权限后台保活进程"
    while true; do
        sudo -n true 2>/dev/null || sudo -v
        sleep 60
    done &
    SUDO_KEEP_PID=$!
}

stop_sudo_keep_alive() {
    [[ -n "$SUDO_KEEP_PID" ]] && kill "$SUDO_KEEP_PID" 2>/dev/null || true
}

########################### P2：磁盘空间检测 ###########################
check_disk_space() {
    log_info "检测磁盘剩余空间..."
    local free_gb
    if [[ $HOMEBREW_ON_MAC -eq 1 ]]; then
        free_gb=$(df -g ~ | awk 'NR==2{print $4}')
    else
        free_gb=$(df -BG ~ | awk 'NR==2{gsub(/G/,"",$4);print $4}')
    fi
    
    if [[ $free_gb -lt 5 ]]; then
        log_warn "当前磁盘剩余空间小于5GB，安装可能失败"
        read -p "是否继续执行？(y/N): " sp_confirm
        if [[ ! "$sp_confirm" =~ [Yy] ]]; then
            exit 0
        fi
    else
        log_info "磁盘空间充足，剩余 ${free_gb}GB"
    fi
}

########################### P2：系统架构&版本拦截 ###########################
check_os_arch_support() {
    log_info "校验系统架构兼容性"
    if [[ "$UNAME_MACHINE" == "armv7l" || "$UNAME_MACHINE" == "armv6l" ]]; then
        log_error "不支持32位ARM架构，仅支持arm64/x86_64"
        exit 1
    fi
    
    if [[ $HOMEBREW_ON_MAC -eq 1 ]]; then
        mac_ver=$(sw_vers -productVersion)
        major_ver=${mac_ver%%.*}
        if [[ $major_ver -lt 12 ]]; then
            log_warn "macOS $mac_ver 版本过旧，Homebrew最低支持macOS 12"
            read -p "是否强制继续？(y/N): " force_continue
            if [[ ! "$force_continue" =~ [Yy] ]]; then
                exit 0
            fi
        fi
    fi
}

########################### P0：网络区域检测 ###########################
check_overseas_network() {
    log_info "正在检测当前网络区域..."
    
    if [[ -n "$HTTP_PROXY" || -n "$HTTPS_PROXY" || -n "$ALL_PROXY" ]]; then
        IS_OVERSEAS=1
        log_success "检测到系统代理环境变量，自动判定境外网络，使用GitHub官方源"
        return
    fi

    local github_accessible=0
    local retry=0
    while [[ $retry -le $NETWORK_RETRY_TIMES ]]; do
        if curl -sI --connect-timeout ${NETWORK_TIMEOUT} \
            "https://github.com/Homebrew/brew" >/dev/null 2>&1; then
            github_accessible=1
            break
        fi
        retry=$((retry+1))
        sleep 1
    done

    if [[ $github_accessible -eq 1 ]]; then
        IS_OVERSEAS=1
        log_success "GitHub直连畅通，判定为境外网络，使用官方源"
    else
        log_warn "GitHub访问受限，判定为境内网络"
        read -p "请手动确认：1=境内(国内镜像) 2=境外(官方源) [1]: " net_opt
        net_opt=${net_opt:-1}
        if [[ "$net_opt" == "2" ]]; then
            IS_OVERSEAS=1
            log_info "手动选择境外模式，使用官方源"
        else
            IS_OVERSEAS=0
            log_info "使用国内镜像加速"
        fi
    fi
}

########################### P0：境内镜像测速 ###########################
get_timestamp_ms() {
    if [[ "$OS" == "Darwin" ]]; then
        perl -MTime::HiRes=time -e 'printf "%d\n", time*1000' 2>/dev/null || echo "0"
    else
        date +%s%3N
    fi
}

test_mirror_speed() {
    log_info "开始测速国内Git与Bottle镜像..."
    local git_mirrors=(
        "$MIRROR_GIT_TUNA|清华Git"
        "$MIRROR_GIT_GITEE|Gitee Git"
    )
    local bottle_mirrors=(
        "$MIRROR_BOTTLE_ALI|阿里Bottle"
        "$MIRROR_BOTTLE_TUNA|清华Bottle"
        "$MIRROR_BOTTLE_USTC|中科大Bottle"
        "$MIRROR_BOTTLE_TENCENT|腾讯Bottle"
    )
    
    echo -e "${ESC_CYAN}==== Git镜像测速 ====${ESC_RESET}"
    for item in "${git_mirrors[@]}"; do
        IFS='|' read -r url name <<< "$item"
        local start=$(get_timestamp_ms)
        curl -s --connect-timeout 2 "$url" >/dev/null 2>&1 || true
        local end=$(get_timestamp_ms)
        local cost=$((end-start))
        if [[ $cost -lt 0 || $cost -gt 30000 ]]; then cost="超时"; fi
        echo "$name 延迟: ${cost}ms"
    done
    
    echo -e "${ESC_CYAN}==== Bottle镜像测速 ====${ESC_RESET}"
    for item in "${bottle_mirrors[@]}"; do
        IFS='|' read -r url name <<< "$item"
        local start=$(get_timestamp_ms)
        curl -s --connect-timeout 2 "$url" >/dev/null 2>&1 || true
        local end=$(get_timestamp_ms)
        local cost=$((end-start))
        if [[ $cost -lt 0 || $cost -gt 30000 ]]; then cost="超时"; fi
        echo "$name 延迟: ${cost}ms"
    done
    log_info "测速完成，延迟越低速度越快"
}

########################### 系统环境初始化 ###########################
init_os_env() {
    log_info "正在识别系统与硬件架构"
    if [[ "${OS}" == "Darwin" ]]; then
        HOMEBREW_ON_MAC=1
        if [[ "${UNAME_MACHINE}" == "arm64" ]]; then
            HB_PREFIX="${HB_ARM_PREFIX}"
        else
            HB_PREFIX="/usr/local"
        fi
        HB_REPO="${HB_PREFIX}"
        HB_CACHE="${HOME}/Library/Caches/Homebrew"
        HB_LOGS="${HOME}/Library/Logs/Homebrew"
    elif [[ "${OS}" == "Linux" ]]; then
        HOMEBREW_ON_LINUX=1
        HB_PREFIX="/home/linuxbrew/.linuxbrew"
        HB_REPO="${HB_PREFIX}/Homebrew"
        HB_CACHE="${HOME}/.cache/Homebrew"
        HB_LOGS="${HOME}/.logs/Homebrew"
    else
        log_error "仅支持 macOS / Linux，当前系统不兼容"
        exit 1
    fi
    log_info "系统识别完成 | Prefix: ${HB_PREFIX}"
}

detect_shell_profile() {
    if [[ ${HOMEBREW_ON_LINUX} -eq 1 ]]; then
        SHELL_PROFILE="/etc/profile"
        return
    fi
    case "$SHELL" in
        */zsh*) SHELL_PROFILE="${HOME}/.zprofile" ;;
        */bash*)
            [[ -f "${HOME}/.bash_profile" ]] && SHELL_PROFILE="${HOME}/.bash_profile" || SHELL_PROFILE="${HOME}/.profile"
            ;;
        *) SHELL_PROFILE="${HOME}/.profile" ;;
    esac
    touch "${SHELL_PROFILE}"
    log_info "检测到配置文件: ${SHELL_PROFILE}"
}

########################### 前置依赖检查 ###########################
check_deps() {
    log_info "校验基础依赖 git curl"
    
    if ! command -v git &>/dev/null; then
        log_warn "未检测到 git，开始自动安装"
        if [[ ${HOMEBREW_ON_MAC} -eq 1 ]]; then
            xcode-select --install
            log_info "请在弹出窗口安装命令行工具"
            until xcode-select -p &>/dev/null; do
                sleep 5
            done
            log_success "命令行工具安装完成"
        else
            if command -v apt &>/dev/null; then
                sudo apt update && sudo apt install -y git curl
            elif command -v yum &>/dev/null; then
                sudo yum install -y git curl
            elif command -v pacman &>/dev/null; then
                sudo pacman -Sy --noconfirm git curl
            else
                log_error "无法自动安装git，请手动安装"
                exit 1
            fi
        fi
    fi
    
    if ! command -v curl &>/dev/null; then
        log_warn "未检测到 curl，自动安装"
        if [[ ${HOMEBREW_ON_LINUX} -eq 1 ]]; then
            if command -v apt &>/dev/null; then sudo apt install -y curl
            elif command -v yum &>/dev/null; then sudo yum install -y curl
            fi
        fi
    fi
    log_success "依赖校验通过"
}

clear_git_proxy() {
    local hp=$(git config --global http.proxy || true)
    local hps=$(git config --global https.proxy || true)
    if [[ -n "${hp}" || -n "${hps}" ]]; then
        log_warn "检测到全局Git代理: http=${hp} https=${hps}"
        log_info "临时禁用代理进行Homebrew安装（不删除配置）"
        export GIT_HTTP_PROXY=""
        export GIT_HTTPS_PROXY=""
    fi
}

########################### 旧环境备份清理 ###########################
backup_and_remove_old_brew() {
    local target="$1"
    if [[ ! -d "${target}" ]]; then return; fi
    
    if [[ ! -f "${target}/bin/brew" && ! -d "${target}/Homebrew" ]]; then
        log_warn "${target} 不是标准Homebrew目录，跳过备份"
        return
    fi
    
    local backup_root="${HOME}/Desktop/Old_Homebrew_Backup/${SCRIPT_TIME// /_}"
    log_warn "发现旧Homebrew目录 ${target}，自动备份至 ${backup_root}"
    mkdir -p "${backup_root}"
    cp -a "${target}" "${backup_root}/" || sudo cp -a "${target}" "${backup_root}/"
    rm -rf "${target}" || sudo rm -rf "${target}"
    log_success "旧目录备份并删除完成"
}

clean_all_old_brew() {
    backup_and_remove_old_brew "${HB_ARM_PREFIX}"
    backup_and_remove_old_brew "${HB_X86_PREFIX}"
    [[ -d "${HB_CACHE}" ]] && rm -rf "${HB_CACHE}"/*
    [[ -d "${HB_LOGS}" ]] && rm -rf "${HB_LOGS}"/*
}

########################### P1：一键卸载功能 ###########################
uninstall_brew() {
    log_warn "即将完整卸载Homebrew，所有软件、缓存、配置都会清理"
    read -p "确认卸载？(Y/n): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ [Yy] ]]; then
        log_info "取消卸载"
        exit 0
    fi
    
    clean_all_old_brew
    
    detect_shell_profile
    if [[ ${HOMEBREW_ON_LINUX} -eq 1 ]]; then
        sed -i "/${TAG_MARKER}/d" "${SHELL_PROFILE}"
    else
        sed -i '' "/${TAG_MARKER}/d" "${SHELL_PROFILE}"
    fi
    
    log_success "Homebrew 卸载完成，重启终端生效"
    exit 0
}

########################### 镜像源交互式选择 ###########################
select_git_mirror() {
    if [[ ${IS_OVERSEAS} -eq 1 ]]; then
        USER_GIT_MIRROR="${OFFICIAL_GIT_BASE}"
        log_info "境外模式：自动使用官方GitHub源码仓库 ${USER_GIT_MIRROR}"
        return 0
    fi
    
    test_mirror_speed
    echo -e "${ESC_CYAN}===== 选择Homebrew源码下载镜像 =====${ESC_RESET}"
    echo "1) 清华大学镜像(推荐) ${MIRROR_GIT_TUNA}"
    echo "2) Gitee镜像 ${MIRROR_GIT_GITEE}"
    echo "3) 已安装brew，仅配置镜像不重装"
    echo "4) 仅修改现有brew远程地址(清华)"
    echo "5) 仅修改现有brew远程地址(Gitee)"
    read -p "请输入序号(默认1): " opt
    opt=${opt:-1}
    case "${opt}" in
        1) USER_GIT_MIRROR="${MIRROR_GIT_TUNA}"; return 0 ;;
        2) USER_GIT_MIRROR="${MIRROR_GIT_GITEE}"; return 0 ;;
        3) return 1 ;;
        4) USER_GIT_MIRROR="${MIRROR_GIT_TUNA}"; return 2 ;;
        5) USER_GIT_MIRROR="${MIRROR_GIT_GITEE}"; return 2 ;;
        *) log_warn "输入错误，默认使用清华源"; USER_GIT_MIRROR="${MIRROR_GIT_TUNA}"; return 0 ;;
    esac
}

select_bottle_mirror() {
    if [[ ${IS_OVERSEAS} -eq 1 ]]; then
        USER_BOTTLE_MIRROR="${OFFICIAL_BOTTLE_DOMAIN}"
        USER_API_DOMAIN="${OFFICIAL_API_DOMAIN}"
        USER_PIP_INDEX=""
        log_info "境外模式：不配置国内Bottle镜像，使用官方默认CDN"
        return
    fi
    
    echo -e "${ESC_CYAN}===== 选择二进制包下载源(brew install) =====${ESC_RESET}"
    echo "1) 中科大"
    echo "2) 清华大学"
    echo "3) 腾讯云"
    echo "4) 阿里云(强烈推荐)"
    read -p "输入序号(默认4): " opt
    opt=${opt:-4}
    case "${opt}" in
        1) 
            USER_BOTTLE_MIRROR="${MIRROR_BOTTLE_USTC}"
            USER_API_DOMAIN="${MIRROR_BOTTLE_USTC}/api"
            USER_PIP_INDEX="${PIP_USTC}"
            ;;
        2) 
            USER_BOTTLE_MIRROR="${MIRROR_BOTTLE_TUNA}"
            USER_API_DOMAIN="${MIRROR_API_TUNA}"
            USER_PIP_INDEX="${PIP_TUNA}"
            ;;
        3) 
            USER_BOTTLE_MIRROR="${MIRROR_BOTTLE_TENCENT}"
            USER_API_DOMAIN="${MIRROR_BOTTLE_TENCENT}/api"
            USER_PIP_INDEX="${PIP_TENCENT}"
            ;;
        4) 
            USER_BOTTLE_MIRROR="${MIRROR_BOTTLE_ALI}"
            USER_API_DOMAIN="${MIRROR_API_ALI}"
            USER_PIP_INDEX="${PIP_ALI}"
            ;;
        *) 
            log_warn "输入错误，使用阿里云"
            USER_BOTTLE_MIRROR="${MIRROR_BOTTLE_ALI}"
            USER_API_DOMAIN="${MIRROR_API_ALI}"
            USER_PIP_INDEX="${PIP_ALI}"
            ;;
    esac
}

########################### P1：Gitee/清华镜像仓库互备兜底克隆 ###########################
safe_clone_install_repo() {
    local target_dir="$1"
    local base_url="$2"
    log_info "尝试克隆安装脚本仓库: $base_url/install.git"
    
    if git clone --depth=1 "$base_url/install.git" "$target_dir" 2>/dev/null; then
        return 0
    fi
    
    log_warn "当前仓库克隆失败，切换备用镜像重试"
    if [[ "$base_url" == "$MIRROR_GIT_TUNA" ]]; then
        base_url="$MIRROR_GIT_GITEE"
    else
        base_url="$MIRROR_GIT_TUNA"
    fi
    
    check_exec "备用镜像克隆" git clone --depth=1 "$base_url/install.git" "$target_dir"
}

########################### 安装核心流程 ###########################
install_brew_full() {
    log_info "完整安装流程启动"
    sudo -v
    
    read -p "是否备份并删除旧版Homebrew? (Y/n): " del_old
    del_old=${del_old:-Y}
    if [[ "${del_old}" =~ [Yy] ]]; then clean_all_old_brew; fi

    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"
    cd "${TMP_DIR}"

    if [[ ${IS_OVERSEAS} -eq 1 ]]; then
        check_exec "克隆官方安装脚本仓库" \
            git clone --depth=1 "${USER_GIT_MIRROR}/install.git" install-repo
    else
        safe_clone_install_repo "install-repo" "${USER_GIT_MIRROR}"
    fi
    cd install-repo

    if [[ ${IS_OVERSEAS} -eq 0 ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            sed -i '' "s|https://github.com/Homebrew|${USER_GIT_MIRROR}|g" install.sh
            sed -i '' "1i\\
export HOMEBREW_BOTTLE_DOMAIN=${USER_BOTTLE_MIRROR}" install.sh
        else
            sed -i "s|https://github.com/Homebrew|${USER_GIT_MIRROR}|g" install.sh
            sed -i "1i export HOMEBREW_BOTTLE_DOMAIN=${USER_BOTTLE_MIRROR}" install.sh
        fi
    fi

    log_info "执行官方安装脚本，请按提示回车确认"
    /bin/bash install.sh
    cd ~
    rm -rf "${TMP_DIR}"
    log_success "Homebrew主体安装完成"
}

patch_exist_brew_remote() {
    if ! command -v brew &>/dev/null; then
        log_error "未检测到brew，请先安装再执行此选项"
        exit 1
    fi
    
    local brew_bin
    brew_bin=$(which brew)
    local brew_root
    brew_root=$(dirname "$(realpath "${brew_bin}")")
    
    if [[ ! -d "${brew_root}/.git" ]]; then
        log_error "${brew_root} 不是有效的git仓库"
        exit 1
    fi
    
    cd "${brew_root}"
    git remote set-url origin "${USER_GIT_MIRROR}/brew"
    check_exec "更新brew远程地址" git remote -v
}

write_mirror_env() {
    detect_shell_profile
    
    if [[ ${HOMEBREW_ON_LINUX} -eq 1 ]]; then
        sed -i "/${TAG_MARKER}/d" "${SHELL_PROFILE}"
    else
        sed -i '' "/${TAG_MARKER}/d" "${SHELL_PROFILE}"
    fi

    if [[ ${IS_OVERSEAS} -eq 1 ]]; then
        cat >> "${SHELL_PROFILE}" <<EOF
# ${TAG_MARKER} 自动镜像配置 - ${SCRIPT_TIME} (Overseas Official Source)
eval \$(${HB_REPO}/bin/brew shellenv)
EOF
    else
        cat >> "${SHELL_PROFILE}" <<EOF
# ${TAG_MARKER} 自动镜像配置 - ${SCRIPT_TIME} (China Mirror)
export HOMEBREW_BOTTLE_DOMAIN=${USER_BOTTLE_MIRROR}
export HOMEBREW_API_DOMAIN=${USER_API_DOMAIN}
export HOMEBREW_PIP_INDEX_URL=${USER_PIP_INDEX}
eval \$(${HB_REPO}/bin/brew shellenv)
EOF
    fi
    log_success "镜像环境变量已写入 ${SHELL_PROFILE}"
    
    if ! source "${SHELL_PROFILE}" 2>/dev/null; then
        log_warn "source临时加载失败，请手动执行: source ${SHELL_PROFILE}"
    fi
}

brew_auto_fix() {
    log_info "执行brew doctor 检测环境异常"
    brew doctor || true
    
    local problem_dirs
    problem_dirs=$(brew doctor 2>&1 | grep -E "permission|Permission" | awk '{print $NF}' | grep -E "^/" || true)
    
    if [[ -n "$problem_dirs" ]]; then
        echo "$problem_dirs" | while read -r dir; do
            if [[ -d "$dir" ]]; then
                log_info "修复权限: $dir"
                if [[ $HOMEBREW_ON_MAC -eq 1 ]]; then
                    sudo chown -R "$USER":admin "$dir"
                else
                    sudo chown -R "$USER:$(id -gn)" "$dir"
                fi
            fi
        done
    fi
    log_success "自动修复Homebrew目录权限完成"
}

########################### 安装后验证功能（新增） ###########################

# 验证核心目录结构
verify_directory_structure() {
    log_info "验证核心目录结构..."
    local required_dirs=(
        "${HB_PREFIX}/bin"
        "${HB_PREFIX}/Cellar"
        "${HB_PREFIX}/Homebrew"
        "${HB_PREFIX}/opt"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "缺失核心目录: $dir"
        else
            log_success "目录存在: $dir"
        fi
    done
}

# 验证brew命令可用性
verify_brew_command() {
    log_info "验证brew命令..."
    
    if ! command -v brew &>/dev/null; then
        log_warn "brew命令未找到，尝试修复PATH"
        export PATH="${HB_PREFIX}/bin:$PATH"
        
        if ! command -v brew &>/dev/null; then
            log_error "brew命令仍不可用，安装可能失败"
            return 1
        fi
    fi
    
    local brew_version
    brew_version=$(brew --version | head -n1)
    log_success "brew命令可用: $brew_version"
    return 0
}

# 验证Git仓库状态
verify_git_repo() {
    log_info "验证Homebrew Git仓库..."
    local brew_repo="${HB_REPO}/Homebrew"
    
    if [[ ! -d "$brew_repo/.git" ]]; then
        log_error "Homebrew仓库Git初始化失败: $brew_repo"
        return 1
    fi
    
    cd "$brew_repo"
    
    # 检查远程地址
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || true)
    if [[ -z "$remote_url" ]]; then
        log_error "Git远程地址未配置"
    else
        log_info "Git远程地址: $remote_url"
    fi
    
    # 检查仓库完整性
    if ! git fsck --quiet 2>/dev/null; then
        log_warn "Git仓库可能存在损坏"
    else
        log_success "Git仓库状态正常"
    fi
}

# 验证权限配置
verify_permissions() {
    log_info "验证目录权限..."
    local test_dirs=(
        "${HB_PREFIX}/Cellar"
        "${HB_PREFIX}/bin"
    )
    
    for dir in "${test_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            continue
        fi
        
        if [[ -w "$dir" ]]; then
            log_success "目录可写: $dir"
        else
            log_error "目录不可写: $dir (可能导致安装失败)"
        fi
    done
}

# 验证镜像配置
verify_mirror_config() {
    log_info "验证镜像配置..."
    
    if [[ "$IS_OVERSEAS" -eq 1 ]]; then
        if [[ -n "$HOMEBREW_BOTTLE_DOMAIN" ]]; then
            log_warn "境外模式不应配置BOTTLE_DOMAIN"
        else
            log_success "境外模式配置正确"
        fi
        return
    fi
    
    # 境内模式检查
    if [[ -z "$HOMEBREW_BOTTLE_DOMAIN" ]]; then
        log_error "境内模式未配置BOTTLE_DOMAIN"
    else
        log_success "BOTTLE_DOMAIN: $HOMEBREW_BOTTLE_DOMAIN"
    fi
    
    if [[ -z "$HOMEBREW_API_DOMAIN" ]]; then
        log_warn "未配置API_DOMAIN"
    else
        log_success "API_DOMAIN: $HOMEBREW_API_DOMAIN"
    fi
}

# 验证网络连通性
verify_network() {
    log_info "验证网络连通性..."
    
    local test_url
    if [[ "$IS_OVERSEAS" -eq 1 ]]; then
        test_url="https://github.com"
    else
        test_url="$USER_BOTTLE_MIRROR"
    fi
    
    if curl -sI --connect-timeout 5 "$test_url" >/dev/null 2>&1; then
        log_success "镜像源可访问: $test_url"
    else
        log_error "镜像源不可访问: $test_url"
    fi
}

# 验证安装测试包
verify_install_test() {
    log_info "验证安装功能（安装测试包hello）..."
    
    if brew install hello 2>/dev/null; then
        log_success "测试包安装成功"
        
        if command -v hello &>/dev/null; then
            log_success "测试包可执行"
        else
            log_warn "测试包安装但未找到命令"
        fi
        
        # 清理测试包
        if brew uninstall hello 2>/dev/null; then
            log_info "测试包已清理"
        fi
    else
        log_error "测试包安装失败，Homebrew可能存在问题"
    fi
}

# 验证更新功能
verify_update_function() {
    log_info "验证更新功能..."
    
    if brew update 2>/dev/null; then
        log_success "brew update 执行成功"
    else
        log_warn "brew update 执行失败（可能是网络问题）"
    fi
}

# 生成验证报告
generate_verify_report() {
    echo ""
    echo -e "${ESC_CYAN}========== 安装验证报告 ==========${ESC_RESET}"
    
    if [[ $VERIFY_ERRORS -eq 0 && $VERIFY_WARNINGS -eq 0 ]]; then
        echo -e "${ESC_GREEN}✓ 所有验证通过，Homebrew安装成功！${ESC_RESET}"
    elif [[ $VERIFY_ERRORS -eq 0 ]]; then
        echo -e "${ESC_YELLOW}⚠ 安装成功，但有 $VERIFY_WARNINGS 个警告${ESC_RESET}"
    else
        echo -e "${ESC_RED}✗ 安装验证失败，发现 $VERIFY_ERRORS 个错误${ESC_RESET}"
    fi
    
    echo ""
    echo "详细日志: $LOG_FILE"
    echo "常见问题排查:"
    echo "  1. 如果权限错误，尝试: sudo chown -R $(whoami) $HB_PREFIX"
    echo "  2. 如果网络错误，检查镜像源配置或切换网络"
    echo "  3. 如果Git错误，尝试: brew update-reset"
    echo ""
}

# 主验证函数
verify_installation() {
    log_info "开始安装后验证..."
    echo -e "${ESC_CYAN}========== 安装后验证 ==========${ESC_RESET}"
    
    # 重置计数器
    VERIFY_ERRORS=0
    VERIFY_WARNINGS=0
    
    # 执行各项验证
    verify_directory_structure
    verify_brew_command
    verify_git_repo
    verify_permissions
    verify_mirror_config
    verify_network
    verify_update_function
    verify_install_test
    
    # 生成报告
    generate_verify_report
    
    # 根据错误数返回状态
    if [[ $VERIFY_ERRORS -gt 0 ]]; then
        return 1
    fi
    return 0
}

########################### 主流程函数 ###########################
brew_post_check() {
    log_info "开始brew自检"
    if ! command -v brew &>/dev/null; then
        log_warn "未识别brew命令，尝试修复环境"
        export PATH="${HB_REPO}/bin:$PATH"
    fi
    
    check_exec "brew版本校验" brew -v
    log_info "执行brew update-reset 修复仓库"
    brew update-reset || true
    brew update || true
    brew_auto_fix
    log_success "Homebrew全部配置完成！"
}

switch_mirror_only() {
    log_info "仅执行镜像切换，不重装Homebrew"
    check_overseas_network
    select_git_mirror
    local mode=$?
    case "${mode}" in
        2) patch_exist_brew_remote ;;
        *) log_info "跳过远程地址修改" ;;
    esac
    select_bottle_mirror
    write_mirror_env
    brew_post_check
    exit 0
}

########################### 参数解析 ###########################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-color) NO_COLOR=1; shift ;;
            --uninstall) RUN_UNINSTALL=1; shift ;;
            --switch-mirror) RUN_SWITCH_ONLY=1; shift ;;
            *) log_error "未知参数 $1"; echo "支持参数：--no-color --uninstall --switch-mirror"; exit 1 ;;
        esac
    done
}

########################### 主入口 ###########################
main() {
    create_lock
    parse_args "$@"
    echo "Homebrew 一键安装脚本 V$SCRIPT_VERSION [P0优化完整版]"
    log_info "脚本启动，版本 V$SCRIPT_VERSION"

    init_os_env
    check_os_arch_support
    check_disk_space
    check_deps
    clear_git_proxy
    sudo_keep_alive

    if [[ $RUN_UNINSTALL -eq 1 ]]; then
        uninstall_brew
    fi
    if [[ $RUN_SWITCH_ONLY -eq 1 ]]; then
        switch_mirror_only
    fi

    check_overseas_network
    select_git_mirror
    local mode=$?
    case "${mode}" in
        0) install_brew_full ;;
        1) log_info "跳过安装，直接配置镜像" ;;
        2) patch_exist_brew_remote ;;
    esac

    select_bottle_mirror
    write_mirror_env
    brew_post_check

    # 新增：执行安装后验证
    if ! verify_installation; then
        log_error "安装验证未通过，请检查上述错误"
        echo -e "\n${ESC_YELLOW}建议操作："
        echo "1. 查看详细日志: tail -n 100 $LOG_FILE"
        echo "2. 重新运行脚本: bash $0"
        echo "3. 手动修复后验证: brew doctor${ESC_RESET}"
        stop_sudo_keep_alive
        remove_lock
        exit 1
    fi

    echo -e "\n${ESC_GREEN}========== 安装完成 ==========${ESC_RESET}"
    if [[ ${IS_OVERSEAS} -eq 1 ]]; then
        echo "当前使用：GitHub 官方源（境外网络）"
    else
        echo "当前使用：国内加速镜像（境内网络）"
    fi
    echo "1. 立即生效：source ${SHELL_PROFILE}"
    echo "2. 永久生效：关闭终端重新打开"
    echo "常用命令："
    echo "  brew -v          查看版本"
    echo "  brew install xxx 安装软件"
    echo "  brew search xxx  搜索软件"
    echo "  brew update      更新Homebrew"
    echo "问题排查：brew doctor"

    stop_sudo_keep_alive
    remove_lock
}

main "$@"

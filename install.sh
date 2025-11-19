#!/usr/bin/env bash

set -e

# ----------------------------------------------------------------------
#  日志和错误处理
# ----------------------------------------------------------------------
LOG_FILE="$HOME/.one-for-terminal-install.log"
BACKUP_DIR="$HOME/.one-for-terminal-backup-$(date +%Y%m%d_%H%M%S)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    local msg="[信息] $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${msg}" >> "$LOG_FILE"
}

log_success() {
    local msg="[成功] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${msg}" >> "$LOG_FILE"
}

log_warn() {
    local msg="[警告] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${msg}" >> "$LOG_FILE"
}

log_error() {
    local msg="[错误] $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${msg}" >> "$LOG_FILE"
}

# 错误处理函数
error_exit() {
    log_error "$1"
    log_error "安装失败，请查看日志文件: $LOG_FILE"
    exit 1
}

# 用户确认函数
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        prompt="${prompt} [Y/n]: "
    else
        prompt="${prompt} [y/N]: "
    fi

    echo -n -e "${YELLOW}${prompt}${NC}"
    read -r response

    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

    if [[ "$default" == "y" ]]; then
        [[ -z "$response" || "$response" == "y" || "$response" == "yes" ]]
    else
        [[ "$response" == "y" || "$response" == "yes" ]]
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 备份文件
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "$BACKUP_DIR/"
        log_success "已备份文件: $file -> $BACKUP_DIR/$(basename "$file")"
    fi
}

# ----------------------------------------------------------------------
#  检测操作系统
# ----------------------------------------------------------------------
detect_os() {
    log_info "正在检测操作系统..."
    case "$(uname -s)" in
        Linux*)     OS="linux" ;;
        Darwin*)    OS="macos" ;;
        *)          error_exit "不支持的操作系统: $(uname -s)" ;;
    esac
    log_success "检测到操作系统: $OS"
}

# ----------------------------------------------------------------------
#  权限检查
# ----------------------------------------------------------------------
check_sudo() {
    log_info "正在检查管理员权限..."

    # 测试 sudo 是否可用
    if sudo -n true 2>/dev/null; then
        log_success "已获得管理员权限"
        return 0
    fi

    log_warn "需要管理员权限来安装系统软件包"
    echo -e "${YELLOW}请输入您的密码以继续安装:${NC}"

    if sudo -v; then
        log_success "管理员权限验证成功"
        # 保持 sudo 会话活跃
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        return 0
    else
        error_exit "无法获取管理员权限，安装终止"
    fi
}

# ----------------------------------------------------------------------
#  安装软件包
# ----------------------------------------------------------------------
install_pkgs() {
    log_info "开始检查并安装必需的软件包..."

    # 定义需要安装的软件包列表
    local packages=(zsh git fzf eza tig neofetch lolcat cowsay)
    local missing_packages=()

    # 检查哪些包还未安装
    log_info "正在检测已安装的软件包..."
    for pkg in "${packages[@]}"; do
        if command_exists "$pkg"; then
            log_success "✓ $pkg 已安装"
        else
            log_warn "✗ $pkg 未安装"
            missing_packages+=("$pkg")
        fi
    done

    # 如果所有包都已安装,跳过安装步骤
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_success "所有必需软件包已安装,跳过安装步骤"
    else
        log_info "需要安装 ${#missing_packages[@]} 个软件包: ${missing_packages[*]}"

        if [[ "$OS" == "macos" ]]; then
            # 检查并安装 Homebrew
            if ! command_exists brew; then
                log_warn "未检测到 Homebrew，正在安装..."
                if confirm "是否安装 Homebrew (macOS 包管理器)?"; then
                    log_info "正在下载并安装 Homebrew..."
                    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
                        log_success "Homebrew 安装成功"
                    else
                        error_exit "Homebrew 安装失败"
                    fi
                else
                    error_exit "用户取消安装 Homebrew，无法继续"
                fi
            else
                log_success "检测到 Homebrew 已安装"
            fi

            log_info "正在安装缺失的软件包: ${missing_packages[*]}"
            if brew install "${missing_packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "软件包安装成功"
            else
                log_error "部分软件包安装失败，但继续执行"
            fi

        elif [[ "$OS" == "linux" ]]; then
            # 检测包管理器
            PKG_MANAGER=""
            if command_exists apt; then
                PKG_MANAGER="apt"
            elif command_exists dnf; then
                PKG_MANAGER="dnf"
            elif command_exists pacman; then
                PKG_MANAGER="pacman"
            fi

            if [[ -z "$PKG_MANAGER" ]]; then
                error_exit "不支持的 Linux 包管理器，仅支持 apt/dnf/pacman"
            fi

            log_success "检测到包管理器: $PKG_MANAGER"

            # 检查 sudo 权限
            check_sudo

            case $PKG_MANAGER in
                apt)
                    log_info "正在更新软件源..."
                    if sudo apt update 2>&1 | tee -a "$LOG_FILE"; then
                        log_success "软件源更新成功"
                    else
                        log_warn "软件源更新失败，但继续执行"
                    fi

                    log_info "正在安装缺失的软件包..."
                    if sudo apt install -y "${missing_packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
                        log_success "软件包安装成功"
                    else
                        error_exit "软件包安装失败"
                    fi
                    ;;
                dnf)
                    log_info "正在安装缺失的软件包..."
                    if sudo dnf install -y "${missing_packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
                        log_success "软件包安装成功"
                    else
                        error_exit "软件包安装失败"
                    fi
                    ;;
                pacman)
                    log_info "正在同步软件源并安装缺失的软件包..."
                    if sudo pacman -Sy --noconfirm "${missing_packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
                        log_success "软件包安装成功"
                    else
                        error_exit "软件包安装失败"
                    fi
                    ;;
            esac
        fi
    fi

    # 安装字体 (macOS)
    if [[ "$OS" == "macos" ]]; then
        log_info "正在检查 Nerd Font 字体..."
        if brew list --cask font-hack-nerd-font &>/dev/null; then
            log_success "Hack Nerd Font 字体已安装"
        else
            log_info "正在安装 Hack Nerd Font 字体..."
            if brew install --cask font-hack-nerd-font 2>&1 | tee -a "$LOG_FILE"; then
                log_success "字体安装成功"
            else
                log_warn "字体安装失败，请手动从 https://www.nerdfonts.com 下载"
            fi
        fi
    else
        log_warn "请自行下载并安装 Nerd Font 字体: https://www.nerdfonts.com/font-downloads"
    fi
}

# ----------------------------------------------------------------------
#  安装 oh-my-zsh
# ----------------------------------------------------------------------
install_omz() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_success "检测到 oh-my-zsh 已安装"
        return 0
    fi

    log_info "正在安装 oh-my-zsh..."

    # 备份现有的 .zshrc
    backup_file "$HOME/.zshrc"

    if CHSH=no RUNZSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "oh-my-zsh 安装成功"
    else
        error_exit "oh-my-zsh 安装失败"
    fi
}

# ----------------------------------------------------------------------
#  设置默认 Shell
# ----------------------------------------------------------------------
set_default_shell() {
    log_info "正在检查默认 Shell 设置..."

    local zsh_path
    zsh_path="$(command -v zsh)"

    if [[ "$SHELL" == "$zsh_path" ]]; then
        log_success "zsh 已经是默认 Shell"
        return 0
    fi

    log_warn "当前默认 Shell 是: $SHELL"
    if confirm "是否将 zsh 设置为默认 Shell?" "y"; then
        log_info "正在设置 zsh 为默认 Shell..."
        echo -e "${YELLOW}可能需要输入密码...${NC}"

        if chsh -s "$zsh_path" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "默认 Shell 已设置为 zsh"
            log_info "需要重新登录或重启终端才能生效"
        else
            log_error "设置默认 Shell 失败，您可以稍后手动执行: chsh -s $zsh_path"
        fi
    else
        log_warn "跳过设置默认 Shell"
    fi
}

# ----------------------------------------------------------------------
#  安装 zsh 插件
# ----------------------------------------------------------------------
install_zsh_plugins() {
    log_info "正在安装 zsh 插件..."

    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    # 安装 autosuggestions 插件
    if [[ ! -d "$zsh_custom/plugins/zsh-autosuggestions" ]]; then
        log_info "正在安装 zsh-autosuggestions 插件..."
        if git clone https://github.com/zsh-users/zsh-autosuggestions \
            "$zsh_custom/plugins/zsh-autosuggestions" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "zsh-autosuggestions 插件安装成功"
        else
            log_error "zsh-autosuggestions 插件安装失败"
        fi
    else
        log_success "zsh-autosuggestions 插件已存在"
    fi

    # 安装 syntax highlighting 插件
    if [[ ! -d "$zsh_custom/plugins/zsh-syntax-highlighting" ]]; then
        log_info "正在安装 zsh-syntax-highlighting 插件..."
        if git clone https://github.com/zsh-users/zsh-syntax-highlighting \
            "$zsh_custom/plugins/zsh-syntax-highlighting" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "zsh-syntax-highlighting 插件安装成功"
        else
            log_error "zsh-syntax-highlighting 插件安装失败"
        fi
    else
        log_success "zsh-syntax-highlighting 插件已存在"
    fi

    # 更新 .zshrc 配置
    if ! grep -q "zsh-autosuggestions" ~/.zshrc; then
        log_info "正在更新 .zshrc 配置以启用插件..."
        backup_file "$HOME/.zshrc"

        # 使用兼容 macOS 和 Linux 的 sed 语法
        if [[ "$OS" == "macos" ]]; then
            sed -i '' 's/plugins=(/plugins=(zsh-autosuggestions zsh-syntax-highlighting /' ~/.zshrc
        else
            sed -i 's/plugins=(/plugins=(zsh-autosuggestions zsh-syntax-highlighting /' ~/.zshrc
        fi

        log_success "插件配置已添加到 .zshrc"
    else
        log_success "插件配置已存在于 .zshrc 中"
    fi
}

# ----------------------------------------------------------------------
#  安装 Starship
# ----------------------------------------------------------------------
install_starship() {
    if command_exists starship; then
        log_success "检测到 Starship 已安装"
    else
        log_info "正在安装 Starship 提示符主题..."
        if curl -sS https://starship.rs/install.sh | sh -s -- -y 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Starship 安装成功"
        else
            error_exit "Starship 安装失败"
        fi
    fi

    mkdir -p ~/.config

    # 配置 Starship
    if [[ -f ~/.config/starship.toml ]]; then
        log_warn "检测到已存在的 Starship 配置文件"
        if ! confirm "是否覆盖现有的 Starship 配置?"; then
            log_warn "跳过 Starship 配置"
        else
            backup_file "$HOME/.config/starship.toml"
            create_starship_config
        fi
    else
        create_starship_config
    fi

    # 添加到 .zshrc
    if ! grep -q "eval \"\$(starship init zsh)\"" ~/.zshrc; then
        log_info "正在添加 Starship 初始化到 .zshrc..."
        backup_file "$HOME/.zshrc"
        echo 'eval "$(starship init zsh)"' >> ~/.zshrc
        log_success "Starship 初始化已添加到 .zshrc"
    else
        log_success "Starship 初始化已存在于 .zshrc 中"
    fi
}

# 创建 Starship 配置
create_starship_config() {
    log_info "正在创建 Starship 配置文件..."
    cat > ~/.config/starship.toml <<'EOF'
# Starship 默认简洁配置
add_newline = false

[character]
success_symbol = "➜"
error_symbol = "✗"

[directory]
truncate_to_repo = false
EOF
    log_success "Starship 配置文件已创建"
}

# ----------------------------------------------------------------------
#  安装 LunarVim
# ----------------------------------------------------------------------
install_lvim() {
    log_warn "LunarVim 会修改您的 Neovim 配置"

    if [[ -d "$HOME/.local/share/lunarvim" ]] || [[ -d "$HOME/.config/lvim" ]]; then
        log_success "检测到 LunarVim 已安装"
        return 0
    fi

    if ! confirm "是否安装 LunarVim (基于 Neovim 的 IDE 配置)?"; then
        log_warn "跳过 LunarVim 安装"
        return 0
    fi

    # 备份现有的 Neovim 配置
    if [[ -d "$HOME/.config/nvim" ]]; then
        log_warn "检测到现有的 Neovim 配置"
        if confirm "是否备份现有的 Neovim 配置?" "y"; then
            local nvim_backup="$HOME/.config/nvim.backup-$(date +%Y%m%d_%H%M%S)"
            mv "$HOME/.config/nvim" "$nvim_backup"
            log_success "Neovim 配置已备份到: $nvim_backup"
        fi
    fi

    log_info "正在安装 LunarVim..."
    LV_BRANCH='release-1.3/neovim-0.10'
    export LV_BRANCH

    if bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --yes 2>&1 | tee -a "$LOG_FILE"; then
        log_success "LunarVim 安装成功"
    else
        log_error "LunarVim 安装失败，但不影响其他功能"
    fi
}

# ----------------------------------------------------------------------
#  主函数
# ----------------------------------------------------------------------
main() {
    echo ""
    echo "======================================"
    echo "  One-For-Terminal 安装脚本"
    echo "======================================"
    echo ""

    log_info "开始安装，日志将保存到: $LOG_FILE"

    # 检测操作系统
    detect_os

    # 安装软件包
    install_pkgs

    # 安装 oh-my-zsh
    install_omz

    # 设置默认 Shell
    set_default_shell

    # 安装 zsh 插件
    install_zsh_plugins

    # 安装 Starship
    install_starship

    # 安装 LunarVim (可选)
    install_lvim

    echo ""
    echo "======================================"
    log_success "安装完成！"
    echo "======================================"
    echo ""
    log_info "请重新打开终端或执行 'source ~/.zshrc' 以应用更改"
    log_info "记得将终端字体切换到 Nerd Font"

    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "配置文件备份位置: $BACKUP_DIR"
    fi

    log_info "完整的安装日志: $LOG_FILE"
    echo ""
}

main "$@"
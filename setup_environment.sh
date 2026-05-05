#!/bin/bash
# =============================================================================
# KOI Development Environment Setup Script
# =============================================================================
# Supports  : macOS (Apple Silicon + Intel), Linux (Ubuntu/Debian/Fedora)
# Version   : 1.0.0
# Usage     : bash setup_environment.sh [--install-android] [--skip-vscode]
#
# Exit codes: 0 = success, 1 = fatal failure
# Idempotent: safe to run multiple times — checks before installing
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="${PWD}/setup.log"
readonly REQUIRED_FLUTTER_MAJOR=3
readonly REQUIRED_FLUTTER_MINOR=19
readonly REQUIRED_NODE_MAJOR=20
readonly REQUIRED_ANDROID_API=34

# Flags (modified by CLI args)
INSTALL_ANDROID=false
SKIP_VSCODE=false

# Track what this run installs so rollback() knows what to remove
INSTALLED_COMPONENTS=()

# =============================================================================
# ANSI COLORS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# LOGGING
# =============================================================================

log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    case "$level" in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        SUCCESS) echo -e "${GREEN}[OK]${NC}    $message" ;;
        *)       echo -e "${BLUE}[INFO]${NC}  $message" ;;
    esac
}

error() {
    log "$1" "ERROR"
    rollback
    exit 1
}

warn()    { log "$1" "WARN"; }
success() { log "$1" "SUCCESS"; }

section() {
    local sep
    sep=$(printf '=%.0s' {1..50})
    log "$sep"
    log "  $1"
    log "$sep"
}

# =============================================================================
# OS DETECTION
# =============================================================================

detect_os() {
    case "$(uname -s)" in
        Darwin)               echo "macos" ;;
        Linux)                echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)                    error "Unsupported OS: $(uname -s). Use setup_environment.ps1 on Windows." ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) echo "arm64" ;;
        x86_64|amd64)  echo "x64" ;;
        *)             echo "unknown" ;;
    esac
}

detect_linux_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

# =============================================================================
# ROLLBACK
# Removes components installed by *this run* if a later step fails.
# Does not touch pre-existing installations.
# =============================================================================

rollback() {
    if [ ${#INSTALLED_COMPONENTS[@]} -eq 0 ]; then
        return 0
    fi

    warn "Rolling back components installed this run: ${INSTALLED_COMPONENTS[*]}"

    for component in "${INSTALLED_COMPONENTS[@]}"; do
        case "$component" in
            flutter)
                local flutter_dir="$HOME/flutter"
                if [ -d "$flutter_dir" ]; then
                    warn "Removing Flutter from $flutter_dir..."
                    rm -rf "$flutter_dir"
                fi
                ;;
            nvm)
                local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
                if [ -d "$nvm_dir" ]; then
                    warn "Removing NVM from $nvm_dir..."
                    rm -rf "$nvm_dir"
                fi
                ;;
            android-cmdline-tools)
                local sdk_root="${ANDROID_HOME:-$HOME/Android/Sdk}"
                warn "Android cmdline-tools were extracted to $sdk_root — remove manually if needed"
                ;;
        esac
    done

    warn "Rollback complete. Check $LOG_FILE for details."
}

# =============================================================================
# UTILITY HELPERS
# =============================================================================

# Returns 0 if version MAJOR1.MINOR1 >= MAJOR2.MINOR2
version_ge() {
    local major1="$1" minor1="$2" major2="$3" minor2="$4"
    if   [ "$major1" -gt "$major2" ]; then return 0
    elif [ "$major1" -eq "$major2" ] && [ "$minor1" -ge "$minor2" ]; then return 0
    else return 1
    fi
}

get_shell_profile() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        bash) echo "$HOME/.bashrc" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

append_to_profile() {
    local profile
    profile=$(get_shell_profile)
    local marker="$1"
    local content="$2"

    if ! grep -qF "$marker" "$profile" 2>/dev/null; then
        {
            echo ""
            echo "# $marker"
            echo "$content"
        } >> "$profile"
        log "Added to $profile: $marker"
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$dest" "$url" || error "Download failed: $url"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$dest" "$url" || error "Download failed: $url"
    else
        error "Neither curl nor wget found. Install one and retry."
    fi
}

# =============================================================================
# FLUTTER
# =============================================================================

check_flutter() {
    log "Checking Flutter SDK..."

    if ! command -v flutter &>/dev/null; then
        # Try the default install location before giving up
        if [ -f "$HOME/flutter/bin/flutter" ]; then
            export PATH="$HOME/flutter/bin:$PATH"
        else
            log "Flutter not found in PATH" "WARN"
            return 1
        fi
    fi

    local full_version
    full_version=$(flutter --version 2>/dev/null | grep -oP 'Flutter \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
    local major minor
    major=$(echo "$full_version" | cut -d. -f1)
    minor=$(echo "$full_version" | cut -d. -f2)

    if version_ge "$major" "$minor" "$REQUIRED_FLUTTER_MAJOR" "$REQUIRED_FLUTTER_MINOR"; then
        success "Flutter $full_version found (>= $REQUIRED_FLUTTER_MAJOR.$REQUIRED_FLUTTER_MINOR required)"
        return 0
    fi

    warn "Flutter $full_version is below required $REQUIRED_FLUTTER_MAJOR.$REQUIRED_FLUTTER_MINOR"
    return 1
}

install_flutter() {
    local os arch
    os=$(detect_os)
    arch=$(detect_arch)

    log "Installing Flutter SDK ($os/$arch)..."

    local flutter_dir="$HOME/flutter"
    local tmpfile
    tmpfile=$(mktemp /tmp/flutter_XXXXXX.tar.xz)

    local flutter_url
    case "$os" in
        macos)
            if [ "$arch" = "arm64" ]; then
                flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_latest.tar.xz"
            else
                flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_latest.tar.xz"
            fi
            ;;
        linux)
            flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_latest.tar.xz"
            ;;
        *)
            error "Auto-install not supported on $os. Install Flutter manually: https://docs.flutter.dev/get-started/install"
            ;;
    esac

    log "Downloading Flutter from official storage..."
    download_file "$flutter_url" "$tmpfile"

    log "Extracting Flutter to $HOME..."
    tar -xf "$tmpfile" -C "$HOME" || error "Extraction failed"
    rm -f "$tmpfile"

    INSTALLED_COMPONENTS+=("flutter")

    export PATH="$flutter_dir/bin:$PATH"
    append_to_profile "Flutter SDK" 'export PATH="$HOME/flutter/bin:$PATH"'

    # Disable telemetry for reproducible CI environments
    flutter config --no-analytics &>/dev/null || true

    success "Flutter $(flutter --version 2>/dev/null | grep -oP 'Flutter \K[0-9.]+' | head -1) installed"
}

# =============================================================================
# NODE.JS  (via NVM — keeps multiple projects on different Node versions)
# =============================================================================

_source_nvm() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -f "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1091
        source "$NVM_DIR/nvm.sh"
        return 0
    fi
    return 1
}

check_node() {
    log "Checking Node.js..."
    _source_nvm || true

    if ! command -v node &>/dev/null; then
        log "Node.js not found in PATH" "WARN"
        return 1
    fi

    local node_full node_major
    node_full=$(node --version 2>/dev/null)
    node_major=$(echo "$node_full" | grep -oP 'v\K[0-9]+')

    if [ "$node_major" = "$REQUIRED_NODE_MAJOR" ]; then
        success "Node.js $node_full found (exactly v$REQUIRED_NODE_MAJOR.x required)"
        return 0
    fi

    warn "Node.js $node_full found but v$REQUIRED_NODE_MAJOR.x required (not $node_major)"
    return 1
}

install_node() {
    log "Installing Node.js v$REQUIRED_NODE_MAJOR LTS via NVM..."

    if [ ! -f "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
        log "Installing NVM..."
        local nvm_install_url="https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh"
        download_file "$nvm_install_url" /tmp/nvm_install.sh
        bash /tmp/nvm_install.sh || error "NVM installation failed"
        rm -f /tmp/nvm_install.sh
        INSTALLED_COMPONENTS+=("nvm")
    fi

    _source_nvm || error "Failed to source NVM after installation"

    nvm install "$REQUIRED_NODE_MAJOR" || error "Failed to install Node.js $REQUIRED_NODE_MAJOR"
    nvm use "$REQUIRED_NODE_MAJOR"     || error "Failed to activate Node.js $REQUIRED_NODE_MAJOR"
    nvm alias default "$REQUIRED_NODE_MAJOR"

    success "Node.js $(node --version) installed and set as default"
}

# =============================================================================
# ANDROID SDK
# =============================================================================

_find_sdk_root() {
    local candidates=(
        "${ANDROID_HOME:-}"
        "${ANDROID_SDK_ROOT:-}"
        "$HOME/Android/Sdk"
        "$HOME/Library/Android/sdk"
        "/opt/android-sdk"
    )
    for p in "${candidates[@]}"; do
        if [ -n "$p" ] && [ -d "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

check_android_sdk() {
    log "Checking Android SDK..."

    local sdk_root
    if ! sdk_root=$(_find_sdk_root); then
        warn "ANDROID_HOME not set and SDK not found in common locations"
        return 1
    fi

    export ANDROID_HOME="$sdk_root"
    export ANDROID_SDK_ROOT="$sdk_root"

    if [ -d "$sdk_root/platforms/android-$REQUIRED_ANDROID_API" ]; then
        success "Android SDK at $sdk_root with API $REQUIRED_ANDROID_API"
        return 0
    fi

    warn "Android SDK found at $sdk_root but API $REQUIRED_ANDROID_API not installed"
    return 1
}

install_android_sdk() {
    local os
    os=$(detect_os)

    local sdk_root
    sdk_root=$(_find_sdk_root 2>/dev/null || echo "")

    if [ -z "$sdk_root" ]; then
        case "$os" in
            macos) sdk_root="$HOME/Library/Android/sdk" ;;
            linux) sdk_root="$HOME/Android/Sdk" ;;
            *)     error "Cannot determine Android SDK location on $os" ;;
        esac
    fi

    export ANDROID_HOME="$sdk_root"
    export ANDROID_SDK_ROOT="$sdk_root"
    mkdir -p "$sdk_root/cmdline-tools"

    local cmdline_tools_dir="$sdk_root/cmdline-tools/latest"
    local sdkmanager="$cmdline_tools_dir/bin/sdkmanager"

    if [ ! -f "$sdkmanager" ]; then
        log "Downloading Android command-line tools..."

        local tools_url
        case "$os" in
            macos) tools_url="https://dl.google.com/android/repository/commandlinetools-mac-latest.zip" ;;
            linux) tools_url="https://dl.google.com/android/repository/commandlinetools-linux-latest.zip" ;;
            *)     error "Android auto-install not supported on $os" ;;
        esac

        local tmpzip
        tmpzip=$(mktemp /tmp/cmdtools_XXXXXX.zip)
        download_file "$tools_url" "$tmpzip"

        unzip -q "$tmpzip" -d "$sdk_root/cmdline-tools/" || error "Extraction failed"
        rm -f "$tmpzip"

        # Google's zip unpacks to "cmdline-tools/", rename to "latest" per SDK convention
        if [ -d "$sdk_root/cmdline-tools/cmdline-tools" ] && [ ! -d "$cmdline_tools_dir" ]; then
            mv "$sdk_root/cmdline-tools/cmdline-tools" "$cmdline_tools_dir"
        fi

        INSTALLED_COMPONENTS+=("android-cmdline-tools")
        export PATH="$cmdline_tools_dir/bin:$sdk_root/platform-tools:$PATH"
    fi

    log "Accepting Android SDK licenses..."
    yes | "$sdkmanager" --licenses > /dev/null 2>&1 || true

    log "Installing Android SDK API $REQUIRED_ANDROID_API, build-tools, and platform-tools..."
    "$sdkmanager" \
        "platforms;android-${REQUIRED_ANDROID_API}" \
        "build-tools;34.0.0" \
        "platform-tools" \
        || error "sdkmanager failed — check network and retry"

    append_to_profile "Android SDK" \
        "export ANDROID_HOME=\"$sdk_root\"
export ANDROID_SDK_ROOT=\"$sdk_root\"
export PATH=\"\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH\""

    success "Android SDK API $REQUIRED_ANDROID_API installed"
}

# =============================================================================
# GIT SSH
# =============================================================================

check_git_ssh() {
    log "Checking Git SSH configuration..."

    if ! command -v git &>/dev/null; then
        warn "Git not found"
        return 1
    fi

    local key_found=false
    for key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
        [ -f "$key" ] && { key_found=true; break; }
    done

    if [ "$key_found" = false ]; then
        warn "No SSH keys in ~/.ssh"
        return 1
    fi

    # Timeout the SSH test so it never hangs the script
    local ssh_out
    ssh_out=$(ssh -T git@github.com \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        2>&1) || true

    if echo "$ssh_out" | grep -q "successfully authenticated"; then
        success "Git SSH to github.com confirmed"
        return 0
    fi

    warn "SSH keys exist but GitHub auth failed: $ssh_out"
    return 1
}

setup_git_ssh() {
    log "Setting up Git SSH..."

    local key_file="$HOME/.ssh/id_ed25519"

    if [ ! -f "$key_file" ]; then
        log "Generating new ED25519 SSH key..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"

        local git_email
        git_email=$(git config --global user.email 2>/dev/null || echo "koi-dev@example.com")

        ssh-keygen -t ed25519 -C "$git_email" -f "$key_file" -N "" \
            || error "ssh-keygen failed"

        chmod 600 "$key_file"
        success "SSH key generated: $key_file"
    fi

    # Start agent and load key
    if ! ssh-add -l &>/dev/null 2>&1; then
        eval "$(ssh-agent -s)" &>/dev/null || warn "Could not start ssh-agent"
    fi
    ssh-add "$key_file" 2>/dev/null || warn "ssh-add failed — agent may not be running"

    warn "============================================================"
    warn "ACTION REQUIRED: Add your public SSH key to GitHub"
    warn "============================================================"
    warn "1. Copy this key:"
    echo ""
    cat "${key_file}.pub"
    echo ""
    warn "2. Open https://github.com/settings/keys"
    warn "3. Click 'New SSH key', paste the key, save."
    warn "============================================================"
}

# =============================================================================
# VS CODE EXTENSIONS
# =============================================================================

check_vscode_extensions() {
    log "Checking VS Code extensions..."

    if ! command -v code &>/dev/null; then
        warn "VS Code CLI ('code') not in PATH — skipping extension check"
        return 1
    fi

    local required=(
        "dart-code.dart-code"
        "dart-code.flutter"
        "dbaeumer.vscode-eslint"
        "esbenp.prettier-vscode"
        "eamodio.gitlens"
        "jsayol.firebase-explorer"
    )

    local installed
    installed=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')

    local missing=0
    for ext in "${required[@]}"; do
        echo "$installed" | grep -q "^${ext}$" || ((missing++))
    done

    if [ "$missing" -eq 0 ]; then
        success "All required VS Code extensions are installed"
        return 0
    fi

    warn "$missing required extensions missing"
    return 1
}

install_vscode_extensions() {
    log "Installing VS Code extensions..."

    if ! command -v code &>/dev/null; then
        warn "VS Code CLI not found — install extensions manually using .vscode/extensions.json"
        return 0
    fi

    local extensions=(
        "dart-code.dart-code"
        "dart-code.flutter"
        "dbaeumer.vscode-eslint"
        "esbenp.prettier-vscode"
        "eamodio.gitlens"
        "jsayol.firebase-explorer"
        "ms-vscode.vscode-typescript-next"
        "bradlc.vscode-tailwindcss"
    )

    for ext in "${extensions[@]}"; do
        log "Installing: $ext"
        if code --install-extension "$ext" --force > /dev/null 2>&1; then
            success "  $ext"
        else
            warn "  $ext (may already be installed or CLI unavailable)"
        fi
    done
}

# =============================================================================
# ENVIRONMENT REPORT
# =============================================================================

generate_report() {
    local report_file="environment_report.md"
    local timestamp os
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    os=$(detect_os)

    log "Generating environment report..."

    local flutter_ver="Not installed"
    command -v flutter &>/dev/null && \
        flutter_ver=$(flutter --version 2>/dev/null | grep -oP 'Flutter \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "Unknown")

    local node_ver="Not installed"
    command -v node &>/dev/null && \
        node_ver=$(node --version 2>/dev/null || echo "Unknown")

    local git_ver="Not installed"
    command -v git &>/dev/null && \
        git_ver=$(git --version 2>/dev/null | grep -oP 'git version \K.+' || echo "Unknown")

    local android_status="✗ Not configured"
    local sdk_root
    sdk_root=$(_find_sdk_root 2>/dev/null || echo "")
    [ -n "$sdk_root" ] && [ -d "$sdk_root/platforms/android-$REQUIRED_ANDROID_API" ] && \
        android_status="✓ API $REQUIRED_ANDROID_API @ $sdk_root"

    local flutter_status="✗"
    local node_status="✗"
    local git_status="✗"
    [ "$flutter_ver" != "Not installed" ] && flutter_status="✓"
    [ "$(echo "$node_ver" | grep -oP 'v\K[0-9]+')" = "$REQUIRED_NODE_MAJOR" ] && node_status="✓"
    [ "$git_ver" != "Not installed" ] && git_status="✓"

    local flutter_doctor_output="Flutter not available"
    command -v flutter &>/dev/null && \
        flutter_doctor_output=$(flutter doctor 2>&1 || true)

    cat > "$report_file" << REPORT
# KOI Development Environment Report

**Generated:** $timestamp
**OS:** $os ($(uname -r))
**Script version:** $SCRIPT_VERSION

## Component Status

| Component | Required | Installed | Status |
|-----------|----------|-----------|--------|
| Flutter | >= $REQUIRED_FLUTTER_MAJOR.$REQUIRED_FLUTTER_MINOR | $flutter_ver | $flutter_status |
| Node.js | = $REQUIRED_NODE_MAJOR.x LTS | $node_ver | $node_status |
| Git | Latest | $git_ver | $git_status |
| Android SDK | API $REQUIRED_ANDROID_API | $android_status | |

## Flutter Doctor Output

\`\`\`
$flutter_doctor_output
\`\`\`

## Environment Variables

| Variable | Value |
|----------|-------|
| ANDROID_HOME | ${ANDROID_HOME:-Not set} |
| ANDROID_SDK_ROOT | ${ANDROID_SDK_ROOT:-Not set} |
| NVM_DIR | ${NVM_DIR:-Not set} |
| FLUTTER_ROOT | ${FLUTTER_ROOT:-Not set} |

## Next Steps

1. Restart your terminal to pick up PATH changes
2. Run \`./validate_environment.sh\` for a detailed check
3. Run \`./test/test_environment_setup.sh\` for automated tests
4. If SSH was prompted, add your public key to GitHub

---
*Generated by KOI setup_environment.sh v$SCRIPT_VERSION*
REPORT

    success "Environment report written to $report_file"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --install-android) INSTALL_ANDROID=true ;;
            --skip-vscode)     SKIP_VSCODE=true ;;
            --help|-h)
                echo "Usage: $0 [--install-android] [--skip-vscode]"
                echo "  --install-android  Attempt to auto-install Android SDK (requires internet)"
                echo "  --skip-vscode      Skip VS Code extension installation"
                exit 0
                ;;
            *) warn "Unknown argument: $arg (ignored)" ;;
        esac
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    parse_args "$@"

    # Ensure log directory is writable
    touch "$LOG_FILE" 2>/dev/null || { echo "Cannot write to $LOG_FILE"; exit 1; }
    echo "" >> "$LOG_FILE"

    # Clean exit on Ctrl+C / SIGTERM
    trap 'log "Script interrupted" "ERROR"; rollback; exit 1' INT TERM

    section "KOI Development Environment Setup v$SCRIPT_VERSION"
    log "Timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
    log "OS        : $(detect_os) / $(detect_arch)"
    log "Shell     : ${SHELL:-unknown}"
    log "Log file  : $LOG_FILE"

    # ---- Flutter ----
    section "Flutter SDK"
    check_flutter || install_flutter

    # ---- Node.js ----
    section "Node.js (via NVM)"
    check_node || install_node

    # ---- Android SDK ----
    section "Android SDK"
    if ! check_android_sdk; then
        if [ "$INSTALL_ANDROID" = true ]; then
            install_android_sdk
        else
            warn "Android SDK not configured."
            warn "Options:"
            warn "  a) Install Android Studio: https://developer.android.com/studio"
            warn "  b) Re-run with flag: bash setup_environment.sh --install-android"
            warn "Note: Android is only required for mobile target — web development works without it."
        fi
    fi

    # ---- Git SSH ----
    section "Git SSH"
    check_git_ssh || setup_git_ssh

    # ---- VS Code Extensions ----
    if [ "$SKIP_VSCODE" = false ]; then
        section "VS Code Extensions"
        check_vscode_extensions || install_vscode_extensions
    fi

    # ---- Report ----
    section "Environment Report"
    generate_report

    section "Setup Complete"
    success "KOI environment setup finished!"
    log "Next: ./validate_environment.sh — detailed validation"
    log "Next: ./test/test_environment_setup.sh — automated tests"
    log "Log:  $LOG_FILE"
    log ""
    warn "Restart your terminal (or run: source $(get_shell_profile)) to apply PATH changes"
}

main "$@"

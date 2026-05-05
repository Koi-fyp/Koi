#!/bin/bash
# =============================================================================
# KOI — Automated Environment Test Suite
# =============================================================================
# Validates that the development environment is correctly configured.
# Each test is independent and provides actionable remediation hints.
#
# Usage   : bash test/test_environment_setup.sh [--verbose]
# Exit    : 0 = min requirements met, 1 = environment not ready
# =============================================================================

set -uo pipefail

# =============================================================================
# COLORS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# STATE
# =============================================================================
TESTS_TOTAL=0
TESTS_PASSED=0
VERBOSE=false

[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# =============================================================================
# HELPERS
# =============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}=========================================="
    echo "  KOI Environment Validation Tests"
    echo -e "==========================================${NC}"
    echo ""
}

# pass <test_number> <description> [detail]
pass() {
    ((TESTS_PASSED++))
    local detail="${3:-}"
    echo -e "  Test $1: $2... ${GREEN}✓ PASS${NC}${detail:+  ($detail)}"
}

# fail <test_number> <description> [detail]
fail() {
    local detail="${3:-}"
    echo -e "  Test $1: $2... ${RED}✗ FAIL${NC}${detail:+  ($detail)}"
}

# skip <test_number> <description> [detail]
skip() {
    ((TESTS_PASSED++))
    local detail="${3:-}"
    echo -e "  Test $1: $2... ${YELLOW}⚠ SKIP${NC}${detail:+  ($detail)}"
}

# warn <test_number> <description> [detail]
warn_test() {
    ((TESTS_PASSED++))
    local detail="${3:-}"
    echo -e "  Test $1: $2... ${YELLOW}⚠ WARNING${NC}${detail:+  ($detail)}"
}

hint() {
    echo -e "    ${BLUE}→${NC} $1"
}

# =============================================================================
# TEST 1 — Flutter SDK version >= 3.19
# =============================================================================
test_flutter_version() {
    ((TESTS_TOTAL++))
    local num=1 label="Flutter SDK >= 3.19"

    if ! command -v flutter &>/dev/null; then
        # Check default install location before giving up
        if [ -f "$HOME/flutter/bin/flutter" ]; then
            export PATH="$HOME/flutter/bin:$PATH"
        else
            fail $num "$label" "Flutter not found in PATH"
            hint "Install Flutter: bash setup_environment.sh"
            hint "Or manually: https://docs.flutter.dev/get-started/install"
            return 1
        fi
    fi

    local full_ver major minor
    full_ver=$(flutter --version 2>/dev/null | grep -oP 'Flutter \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
    major=$(echo "$full_ver" | cut -d. -f1)
    minor=$(echo "$full_ver" | cut -d. -f2)

    if [ "$major" -ge 3 ] && [ "$minor" -ge 19 ]; then
        pass $num "$label" "v$full_ver"
        return 0
    fi

    fail $num "$label" "v$full_ver < 3.19 required"
    hint "Upgrade: flutter upgrade"
    hint "Or reinstall: bash setup_environment.sh"
    return 1
}

# =============================================================================
# TEST 2 — Node.js must be exactly v20.x LTS
# =============================================================================
test_node_version() {
    ((TESTS_TOTAL++))
    local num=2 label="Node.js v20.x LTS"

    # Source NVM if available so 'node' appears in PATH
    if [ -f "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
        # shellcheck disable=SC1091
        source "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
    fi

    if ! command -v node &>/dev/null; then
        fail $num "$label" "Node.js not installed"
        hint "Install NVM then Node 20: bash setup_environment.sh"
        hint "Or: nvm install 20 && nvm use 20"
        return 1
    fi

    local node_full node_major
    node_full=$(node --version 2>/dev/null)
    node_major=$(echo "$node_full" | grep -oP 'v\K[0-9]+')

    if [ "$node_major" = "20" ]; then
        pass $num "$label" "$node_full"
        return 0
    fi

    if [ "$node_major" -lt 20 ]; then
        fail $num "$label" "$node_full is too old"
    else
        fail $num "$label" "$node_full is too new (need exactly v20)"
    fi

    hint "Switch version: nvm install 20 && nvm use 20 && nvm alias default 20"
    hint "If NVM isn't installed: bash setup_environment.sh"
    return 1
}

# =============================================================================
# TEST 3 — Android SDK API 34
# =============================================================================
test_android_sdk() {
    ((TESTS_TOTAL++))
    local num=3 label="Android SDK API 34"

    # Discover SDK root from env or common paths
    local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
    if [ -z "$sdk_root" ]; then
        for p in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/opt/android-sdk"; do
            [ -d "$p" ] && { sdk_root="$p"; break; }
        done
    fi

    if [ -z "$sdk_root" ]; then
        skip $num "$label" "ANDROID_HOME not set — required for Android development only"
        hint "Install Android Studio: https://developer.android.com/studio"
        hint "Or: bash setup_environment.sh --install-android"
        return 0  # Skipped counts as passed — web-only dev can proceed
    fi

    if [ -d "$sdk_root/platforms/android-34" ]; then
        pass $num "$label" "$sdk_root/platforms/android-34"
        return 0
    fi

    fail $num "$label" "android-34 not found in $sdk_root"
    hint "Install: sdkmanager 'platforms;android-34'"
    hint "Or open Android Studio > SDK Manager > Android 14 (API 34)"
    return 1
}

# =============================================================================
# TEST 4 — Git SSH configured and GitHub auth works
# =============================================================================
test_git_ssh() {
    ((TESTS_TOTAL++))
    local num=4 label="Git SSH configured"

    if ! command -v git &>/dev/null; then
        fail $num "$label" "Git not installed"
        hint "Install Git: https://git-scm.com/downloads"
        return 1
    fi

    # Find SSH key
    local key_file=""
    for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
        [ -f "$k" ] && { key_file="$k"; break; }
    done

    if [ -z "$key_file" ]; then
        fail $num "$label" "no SSH key in ~/.ssh"
        hint "Generate: ssh-keygen -t ed25519 -C \"your_email@example.com\""
        hint "Then add to GitHub: https://github.com/settings/keys"
        return 1
    fi

    # Test GitHub connectivity
    local ssh_out
    ssh_out=$(ssh -T git@github.com \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        2>&1) || true

    if echo "$ssh_out" | grep -q "successfully authenticated"; then
        pass $num "$label" "key=$key_file, github.com authenticated"
        return 0
    fi

    # Key exists but auth failed — partial pass (warn)
    warn_test $num "$label" "key found but GitHub auth failed"
    hint "Add key to agent: ssh-add $key_file"
    hint "Add public key to GitHub: https://github.com/settings/keys"
    hint "SSH output: $ssh_out"
    return 0  # Non-fatal: SSH issues don't block all development
}

# =============================================================================
# TEST 5 — Unity 2022.3 LTS  (optional)
# =============================================================================
test_unity() {
    ((TESTS_TOTAL++))
    local num=5 label="Unity 2022.3 LTS"

    local unity_ver=""

    # macOS
    if [ -d "/Applications/Unity/Hub/Editor" ]; then
        unity_ver=$(ls /Applications/Unity/Hub/Editor/ 2>/dev/null | grep "^2022\.3" | sort -V | tail -1)
    fi

    # Linux
    if [ -z "$unity_ver" ] && [ -d "$HOME/Unity/Hub/Editor" ]; then
        unity_ver=$(ls "$HOME/Unity/Hub/Editor/" 2>/dev/null | grep "^2022\.3" | sort -V | tail -1)
    fi

    if [ -n "$unity_ver" ]; then
        pass $num "$label" "$unity_ver"
        return 0
    fi

    skip $num "$label" "not installed — optional until Phase 3 (Avatar System)"
    hint "Download Unity Hub: https://unity.com/download"
    hint "Install Unity 2022.3 LTS via Unity Hub"
    return 0
}

# =============================================================================
# TEST 6 — Required VS Code extensions
# =============================================================================
test_vscode_extensions() {
    ((TESTS_TOTAL++))
    local num=6 label="VS Code extensions (required set)"

    if ! command -v code &>/dev/null; then
        skip $num "$label" "VS Code CLI not in PATH — cannot verify"
        hint "Add VS Code to PATH or install extensions manually from .vscode/extensions.json"
        return 0
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

    local missing=()
    for ext in "${required[@]}"; do
        echo "$installed" | grep -q "^${ext}$" || missing+=("$ext")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        pass $num "$label" "all ${#required[@]} extensions installed"
        return 0
    fi

    fail $num "$label" "${#missing[@]} missing: ${missing[*]}"
    for ext in "${missing[@]}"; do
        hint "Install: code --install-extension $ext"
    done
    hint "Or run: bash setup_environment.sh"
    return 1
}

# =============================================================================
# TEST 7 — Project dependencies installed
# =============================================================================
test_project_dependencies() {
    ((TESTS_TOTAL++))
    local num=7 label="Project dependencies"

    local found_project=false
    local missing_deps=()

    # Flutter project
    if [ -f "pubspec.yaml" ]; then
        found_project=true
        if [ ! -d ".dart_tool" ]; then
            missing_deps+=("Flutter deps (.dart_tool missing)")
        fi
        if [ ! -d ".dart_tool/package_config.json" ] && [ ! -f ".dart_tool/package_config.json" ]; then
            : # Already covered above
        fi
    fi

    # Node project
    if [ -f "package.json" ]; then
        found_project=true
        if [ ! -d "node_modules" ]; then
            missing_deps+=("Node deps (node_modules missing)")
        fi
    fi

    if [ "$found_project" = false ]; then
        skip $num "$label" "not in a project directory — run from project root"
        return 0
    fi

    if [ ${#missing_deps[@]} -eq 0 ]; then
        pass $num "$label" "dependencies installed"
        return 0
    fi

    warn_test $num "$label" "some deps not installed: ${missing_deps[*]}"
    [ -f "pubspec.yaml" ]  && hint "Flutter: flutter pub get"
    [ -f "package.json" ]  && hint "Node.js: npm install"
    return 0  # Warning only — deps are easily fixed on first run
}

# =============================================================================
# SUMMARY & EXIT
# =============================================================================

print_summary() {
    local failed=$((TESTS_TOTAL - TESTS_PASSED))

    echo ""
    echo -e "${BOLD}${BLUE}=========================================="
    printf "Results: %d/%d tests passed\n" "$TESTS_PASSED" "$TESTS_TOTAL"
    echo -e "==========================================${NC}"
    echo ""

    if [ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]; then
        echo -e "${GREEN}${BOLD}✓ Environment is fully configured!${NC}"
        echo "  You're ready to start KOI development."
        return 0
    elif [ "$failed" -le 2 ]; then
        echo -e "${YELLOW}${BOLD}⚠ Environment is partially configured${NC}"
        echo "  Minimum requirements met — some features may be unavailable."
        echo "  Run ./validate_environment.sh for a detailed breakdown."
        return 0
    else
        echo -e "${RED}${BOLD}✗ Environment setup incomplete${NC}"
        echo "  Fix the failing tests above, then re-run."
        echo "  Quick fix: bash setup_environment.sh"
        return 1
    fi
}

# =============================================================================
# ENTRY POINT
# =============================================================================

main() {
    print_header

    test_flutter_version
    test_node_version
    test_android_sdk
    test_git_ssh
    test_unity
    test_vscode_extensions
    test_project_dependencies

    print_summary
    exit $?
}

main "$@"

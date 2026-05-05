#!/bin/bash
# =============================================================================
# KOI Environment Validation Script
# =============================================================================
# Runs comprehensive checks against every KOI development dependency,
# prints a colour-coded status table to stdout, and writes a markdown
# report to environment_report.md.
#
# Exit codes: 0 = all critical checks pass  (warnings allowed)
#             1 = one or more critical checks fail
# =============================================================================

set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly REPORT_FILE="environment_report.md"
readonly REQUIRED_NODE_MAJOR=20
readonly REQUIRED_FLUTTER_MAJOR=3
readonly REQUIRED_FLUTTER_MINOR=19
readonly REQUIRED_ANDROID_API=34

# =============================================================================
# ANSI COLORS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# CHECK REGISTRY
# Tracks every check so we can build the report accurately.
# =============================================================================
declare -A CHECK_STATUS   # PASS | FAIL | WARN | SKIP
declare -A CHECK_DETAIL   # human-readable detail string
declare -A CHECK_CRITICAL # 1 = failure blocks development

TOTAL=0
PASSED=0
FAILED=0
WARNED=0

# =============================================================================
# RESULT RECORDING
# =============================================================================

record() {
    local key="$1"      # unique check identifier
    local status="$2"   # PASS | FAIL | WARN | SKIP
    local detail="${3:-}"
    local critical="${4:-1}"  # 1 = critical, 0 = optional

    ((TOTAL++))
    CHECK_STATUS["$key"]="$status"
    CHECK_DETAIL["$key"]="${detail}"
    CHECK_CRITICAL["$key"]="$critical"

    case "$status" in
        PASS) ((PASSED++)) ;;
        FAIL) ((FAILED++)) ;;
        WARN) ((WARNED++)) ; ((PASSED++)) ;;
        SKIP) ((PASSED++)) ;;
    esac
}

print_check() {
    local key="$1"
    local label="$2"
    local status="${CHECK_STATUS[$key]:-FAIL}"
    local detail="${CHECK_DETAIL[$key]:-}"

    case "$status" in
        PASS) echo -e "  ${GREEN}✓${NC} $label${detail:+  ($detail)}" ;;
        FAIL) echo -e "  ${RED}✗${NC} $label${detail:+  ($detail)}" ;;
        WARN) echo -e "  ${YELLOW}⚠${NC} $label${detail:+  ($detail)}" ;;
        SKIP) echo -e "  ${BLUE}○${NC} $label${detail:+  ($detail)}" ;;
    esac
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}── $1 $( printf '─%.0s' $(seq 1 $((44 - ${#1}))) )${NC}"
}

# =============================================================================
# FLUTTER VALIDATION
# =============================================================================

validate_flutter() {
    print_section "Flutter SDK"

    # Installed?
    if ! command -v flutter &>/dev/null; then
        record "flutter.installed"    "FAIL" "not in PATH — run setup_environment.sh"
        record "flutter.version"      "FAIL" "N/A"
        record "flutter.doctor"       "FAIL" "N/A"
        record "flutter.dart"         "FAIL" "N/A"
        print_check "flutter.installed" "Flutter installed"
        print_check "flutter.version"   "Flutter >= $REQUIRED_FLUTTER_MAJOR.$REQUIRED_FLUTTER_MINOR"
        print_check "flutter.doctor"    "flutter doctor"
        print_check "flutter.dart"      "Dart SDK"
        return
    fi

    record "flutter.installed" "PASS" "$(which flutter)"
    print_check "flutter.installed" "Flutter installed"

    # Version
    local full_ver major minor
    full_ver=$(flutter --version 2>/dev/null | grep -oP 'Flutter \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
    major=$(echo "$full_ver" | cut -d. -f1)
    minor=$(echo "$full_ver" | cut -d. -f2)

    if [ "$major" -ge "$REQUIRED_FLUTTER_MAJOR" ] && [ "$minor" -ge "$REQUIRED_FLUTTER_MINOR" ]; then
        record "flutter.version" "PASS" "v$full_ver"
    else
        record "flutter.version" "FAIL" "v$full_ver — need >= $REQUIRED_FLUTTER_MAJOR.$REQUIRED_FLUTTER_MINOR"
    fi
    print_check "flutter.version" "Flutter >= $REQUIRED_FLUTTER_MAJOR.$REQUIRED_FLUTTER_MINOR"

    # flutter doctor
    local doctor_out
    echo "  Running flutter doctor (this may take a moment)..."
    doctor_out=$(flutter doctor 2>&1 || true)

    # Count [✗] markers in the output
    local error_count
    error_count=$(echo "$doctor_out" | grep -c '\[✗\]' || echo 0)

    if [ "$error_count" -gt 0 ]; then
        record "flutter.doctor" "WARN" "$error_count issue(s) — see environment_report.md" 0
    else
        record "flutter.doctor" "PASS" "no critical issues"
    fi
    print_check "flutter.doctor" "flutter doctor"
    # Store doctor output for the report
    FLUTTER_DOCTOR_OUTPUT="$doctor_out"

    # Dart
    local dart_ver
    dart_ver=$(dart --version 2>/dev/null | grep -oP 'Dart SDK version: \K[0-9.]+' || echo "bundled")
    record "flutter.dart" "PASS" "v$dart_ver"
    print_check "flutter.dart" "Dart SDK"
}

# =============================================================================
# NODE.JS VALIDATION
# =============================================================================

validate_node() {
    print_section "Node.js & npm"

    # Source nvm if available
    if [ -f "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
        # shellcheck disable=SC1091
        source "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
    fi

    # Installed?
    if ! command -v node &>/dev/null; then
        record "node.installed" "FAIL" "not in PATH — run: nvm install $REQUIRED_NODE_MAJOR"
        record "node.version"   "FAIL" "N/A"
        record "node.npm"       "FAIL" "N/A"
        record "node.nvm"       "WARN" "NVM not found — recommended" 0
        print_check "node.installed" "Node.js installed"
        print_check "node.version"   "Node.js = v$REQUIRED_NODE_MAJOR.x"
        print_check "node.npm"       "npm"
        print_check "node.nvm"       "NVM (version manager)"
        return
    fi

    record "node.installed" "PASS" "$(which node)"
    print_check "node.installed" "Node.js installed"

    # Version — must be EXACTLY v20.x
    local node_full node_major
    node_full=$(node --version 2>/dev/null)
    node_major=$(echo "$node_full" | grep -oP 'v\K[0-9]+')

    if [ "$node_major" = "$REQUIRED_NODE_MAJOR" ]; then
        record "node.version" "PASS" "$node_full"
    elif [ "$node_major" -lt "$REQUIRED_NODE_MAJOR" ]; then
        record "node.version" "FAIL" "$node_full is too old — need v$REQUIRED_NODE_MAJOR (run: nvm install $REQUIRED_NODE_MAJOR)"
    else
        record "node.version" "FAIL" "$node_full is too new — need exactly v$REQUIRED_NODE_MAJOR (run: nvm use $REQUIRED_NODE_MAJOR)"
    fi
    print_check "node.version" "Node.js = v$REQUIRED_NODE_MAJOR.x LTS"

    # npm
    if command -v npm &>/dev/null; then
        local npm_ver
        npm_ver=$(npm --version 2>/dev/null)
        record "node.npm" "PASS" "v$npm_ver"
    else
        record "node.npm" "FAIL" "npm not found"
    fi
    print_check "node.npm" "npm"

    # NVM
    if command -v nvm &>/dev/null || [ -f "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
        record "node.nvm" "PASS" "installed" 0
    else
        record "node.nvm" "WARN" "not found — run setup_environment.sh to install" 0
    fi
    print_check "node.nvm" "NVM (version manager)"
}

# =============================================================================
# ANDROID SDK VALIDATION
# =============================================================================

validate_android() {
    print_section "Android SDK"

    # Locate SDK root
    local sdk_root=""
    local candidates=(
        "${ANDROID_HOME:-}"
        "${ANDROID_SDK_ROOT:-}"
        "$HOME/Android/Sdk"
        "$HOME/Library/Android/sdk"
        "/opt/android-sdk"
    )
    for p in "${candidates[@]}"; do
        if [ -n "$p" ] && [ -d "$p" ]; then
            sdk_root="$p"
            break
        fi
    done

    if [ -z "$sdk_root" ]; then
        record "android.root"          "FAIL" "ANDROID_HOME not set — install Android Studio"
        record "android.api"           "FAIL" "SDK root unknown"
        record "android.build_tools"   "FAIL" "SDK root unknown"
        record "android.platform_tools" "FAIL" "SDK root unknown"
        record "android.env"           "FAIL" "ANDROID_HOME not exported"
        print_check "android.root"           "Android SDK root"
        print_check "android.api"            "Android API $REQUIRED_ANDROID_API"
        print_check "android.build_tools"    "Build-tools 34.x"
        print_check "android.platform_tools" "Platform-tools (adb)"
        print_check "android.env"            "ANDROID_HOME set"
        return
    fi

    record "android.root" "PASS" "$sdk_root"
    print_check "android.root" "Android SDK root"

    # API level
    if [ -d "$sdk_root/platforms/android-$REQUIRED_ANDROID_API" ]; then
        record "android.api" "PASS" "android-$REQUIRED_ANDROID_API"
    else
        record "android.api" "FAIL" "not found — run: sdkmanager 'platforms;android-$REQUIRED_ANDROID_API'"
    fi
    print_check "android.api" "Android API $REQUIRED_ANDROID_API"

    # Build-tools 34.x
    local bt_ver
    bt_ver=$(ls "$sdk_root/build-tools/" 2>/dev/null | grep "^34" | sort -V | tail -1)
    if [ -n "$bt_ver" ]; then
        record "android.build_tools" "PASS" "v$bt_ver"
    else
        record "android.build_tools" "FAIL" "not found — run: sdkmanager 'build-tools;34.0.0'"
    fi
    print_check "android.build_tools" "Build-tools 34.x"

    # ADB / platform-tools
    if command -v adb &>/dev/null || [ -f "$sdk_root/platform-tools/adb" ]; then
        local adb_ver
        adb_ver=$(adb version 2>/dev/null | grep -oP 'Android Debug Bridge version \K.+' || echo "present")
        record "android.platform_tools" "PASS" "$adb_ver"
    else
        record "android.platform_tools" "FAIL" "adb not found — run: sdkmanager 'platform-tools'"
    fi
    print_check "android.platform_tools" "Platform-tools (adb)"

    # ANDROID_HOME env var
    if [ -n "${ANDROID_HOME:-}" ]; then
        record "android.env" "PASS" "$ANDROID_HOME"
    else
        record "android.env" "WARN" "ANDROID_HOME not exported — add to shell profile" 0
    fi
    print_check "android.env" "ANDROID_HOME set"
}

# =============================================================================
# GIT & SSH VALIDATION
# =============================================================================

validate_git_ssh() {
    print_section "Git & SSH"

    # Git installed?
    if ! command -v git &>/dev/null; then
        record "git.installed"   "FAIL" "install from https://git-scm.com"
        record "git.user"        "FAIL" "N/A"
        record "git.ssh_key"     "FAIL" "N/A"
        record "git.ssh_perms"   "FAIL" "N/A"
        record "git.github_auth" "FAIL" "N/A"
        print_check "git.installed"   "Git installed"
        print_check "git.user"        "Git user configured"
        print_check "git.ssh_key"     "SSH key exists"
        print_check "git.ssh_perms"   "SSH key permissions (600)"
        print_check "git.github_auth" "GitHub SSH auth"
        return
    fi

    local git_ver
    git_ver=$(git --version | grep -oP 'git version \K.+')
    record "git.installed" "PASS" "v$git_ver"
    print_check "git.installed" "Git installed"

    # User identity
    local git_user git_email
    git_user=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    if [ -n "$git_user" ] && [ -n "$git_email" ]; then
        record "git.user" "PASS" "$git_user <$git_email>" 0
    else
        record "git.user" "WARN" "user.name or user.email not set (run: git config --global user.name/email)" 0
    fi
    print_check "git.user" "Git user configured"

    # SSH key
    local key_file=""
    for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
        [ -f "$k" ] && { key_file="$k"; break; }
    done

    if [ -n "$key_file" ]; then
        record "git.ssh_key" "PASS" "$key_file"
        print_check "git.ssh_key" "SSH key exists"

        # Permissions
        local perms
        perms=$(stat -c "%a" "$key_file" 2>/dev/null || stat -f "%OLp" "$key_file" 2>/dev/null || echo "???")
        if [ "$perms" = "600" ]; then
            record "git.ssh_perms" "PASS" "600" 0
        else
            record "git.ssh_perms" "WARN" "$perms (should be 600 — run: chmod 600 $key_file)" 0
        fi
        print_check "git.ssh_perms" "SSH key permissions (600)"

        # GitHub auth test
        echo "  Testing GitHub SSH (timeout 10s)..."
        local ssh_out
        ssh_out=$(ssh -T git@github.com \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            -o BatchMode=yes \
            2>&1) || true

        if echo "$ssh_out" | grep -q "successfully authenticated"; then
            record "git.github_auth" "PASS" "authenticated"
        elif echo "$ssh_out" | grep -qE "Connection refused|Network is unreachable|Could not resolve"; then
            record "git.github_auth" "WARN" "network error — check connectivity" 0
        else
            record "git.github_auth" "FAIL" "not authenticated — add public key to https://github.com/settings/keys"
        fi
        print_check "git.github_auth" "GitHub SSH auth"
    else
        record "git.ssh_key"     "FAIL" "no key in ~/.ssh — run: ssh-keygen -t ed25519"
        record "git.ssh_perms"   "SKIP" "N/A"
        record "git.github_auth" "FAIL" "no SSH key"
        print_check "git.ssh_key"     "SSH key exists"
        print_check "git.ssh_perms"   "SSH key permissions (600)"
        print_check "git.github_auth" "GitHub SSH auth"
    fi
}

# =============================================================================
# UNITY VALIDATION  (optional)
# =============================================================================

validate_unity() {
    print_section "Unity 2022.3 LTS  (optional)"

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
        record "unity.version" "PASS" "$unity_ver" 0
    else
        record "unity.version" "SKIP" "optional — required for Phase 3 avatar rendering" 0
    fi
    print_check "unity.version" "Unity 2022.3 LTS"

    # Unity Hub
    if [ -f "/Applications/Unity Hub.app/Contents/MacOS/Unity Hub" ] || \
       [ -f "$HOME/.local/share/applications/unity-hub.desktop" ]; then
        record "unity.hub" "PASS" "installed" 0
    else
        record "unity.hub" "SKIP" "optional — install from unityhub.com" 0
    fi
    print_check "unity.hub" "Unity Hub"
}

# =============================================================================
# VS CODE VALIDATION
# =============================================================================

validate_vscode() {
    print_section "VS Code & Extensions"

    if ! command -v code &>/dev/null; then
        record "vscode.cli" "WARN" "CLI not in PATH — install extensions manually" 0
        print_check "vscode.cli" "VS Code CLI"
        return
    fi

    local code_ver
    code_ver=$(code.cmd --version 2>/dev/null | head -1)
    record "vscode.cli" "PASS" "v$code_ver" 0
    print_check "vscode.cli" "VS Code CLI"

    local installed_exts
    installed_exts=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')

    local ext_list=(
        "dart-code.dart-code:Dart"
        "dart-code.flutter:Flutter"
        "dbaeumer.vscode-eslint:ESLint"
        "esbenp.prettier-vscode:Prettier"
        "eamodio.gitlens:GitLens"
        "GoogleCloudTools.firebase-dataconnect-vscode:Firebase Explorer"
    )

    for entry in "${ext_list[@]}"; do
        local ext_id="${entry%%:*}"
        local ext_name="${entry##*:}"
        local key="vscode.ext.${ext_id//./_}"

        if echo "$installed_exts" | grep -q "^${ext_id}$"; then
            record "$key" "PASS" "$ext_id" 0
        else
            record "$key" "FAIL" "missing — run: code --install-extension $ext_id" 0
        fi
        print_check "$key" "$ext_name"
    done
}

# =============================================================================
# MARKDOWN REPORT GENERATION
# =============================================================================

generate_report() {
    local timestamp os_info
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    os_info="$(uname -s) $(uname -r)"

    local flutter_ver node_ver git_ver android_root
    flutter_ver=$(flutter --version 2>/dev/null | grep -oP 'Flutter \K[0-9.]+' | head -1 || echo "N/A")
    node_ver=$(node --version 2>/dev/null || echo "N/A")
    git_ver=$(git --version 2>/dev/null | grep -oP 'git version \K.+' || echo "N/A")

    local sdk_root=""
    for p in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
        [ -n "$p" ] && [ -d "$p" ] && { sdk_root="$p"; break; }
    done
    android_root="${sdk_root:-Not configured}"

    # Status symbols
    _sym() {
        case "${CHECK_STATUS[$1]:-FAIL}" in
            PASS) echo "✓" ;; FAIL) echo "✗" ;;
            WARN) echo "⚠" ;; SKIP) echo "○" ;;
        esac
    }

    cat > "$REPORT_FILE" << REPORT
# KOI Development Environment Report

**Generated:** $timestamp
**OS:** $os_info
**Hostname:** $(hostname)

## Summary

| | Count |
|---|---|
| Total checks | $TOTAL |
| ✓ Passed | $PASSED |
| ✗ Failed | $FAILED |
| ⚠ Warnings | $WARNED |

## Component Versions

| Component | Required | Installed | Status |
|-----------|----------|-----------|--------|
| Flutter | >= $REQUIRED_FLUTTER_MAJOR.$REQUIRED_FLUTTER_MINOR | $flutter_ver | $(_sym flutter.version) |
| Node.js | = $REQUIRED_NODE_MAJOR.x LTS | $node_ver | $(_sym node.version) |
| Git | Latest | $git_ver | $(_sym git.installed) |
| Android SDK | API $REQUIRED_ANDROID_API | $android_root | $(_sym android.api) |
| Unity | 2022.3 LTS (opt.) | ${CHECK_DETAIL[unity.version]:-N/A} | $(_sym unity.version) |

## Detailed Check Results

| Check | Status | Detail |
|-------|--------|--------|
| Flutter installed | $(_sym flutter.installed) | ${CHECK_DETAIL[flutter.installed]:-} |
| Flutter version | $(_sym flutter.version) | ${CHECK_DETAIL[flutter.version]:-} |
| flutter doctor | $(_sym flutter.doctor) | ${CHECK_DETAIL[flutter.doctor]:-} |
| Dart SDK | $(_sym flutter.dart) | ${CHECK_DETAIL[flutter.dart]:-} |
| Node.js installed | $(_sym node.installed) | ${CHECK_DETAIL[node.installed]:-} |
| Node.js version | $(_sym node.version) | ${CHECK_DETAIL[node.version]:-} |
| npm | $(_sym node.npm) | ${CHECK_DETAIL[node.npm]:-} |
| NVM | $(_sym node.nvm) | ${CHECK_DETAIL[node.nvm]:-} |
| Android SDK root | $(_sym android.root) | ${CHECK_DETAIL[android.root]:-} |
| Android API $REQUIRED_ANDROID_API | $(_sym android.api) | ${CHECK_DETAIL[android.api]:-} |
| Build-tools 34 | $(_sym android.build_tools) | ${CHECK_DETAIL[android.build_tools]:-} |
| ADB / platform-tools | $(_sym android.platform_tools) | ${CHECK_DETAIL[android.platform_tools]:-} |
| ANDROID_HOME set | $(_sym android.env) | ${CHECK_DETAIL[android.env]:-} |
| Git installed | $(_sym git.installed) | ${CHECK_DETAIL[git.installed]:-} |
| Git user config | $(_sym git.user) | ${CHECK_DETAIL[git.user]:-} |
| SSH key | $(_sym git.ssh_key) | ${CHECK_DETAIL[git.ssh_key]:-} |
| SSH key permissions | $(_sym git.ssh_perms) | ${CHECK_DETAIL[git.ssh_perms]:-} |
| GitHub SSH auth | $(_sym git.github_auth) | ${CHECK_DETAIL[git.github_auth]:-} |
| Unity 2022.3 LTS | $(_sym unity.version) | ${CHECK_DETAIL[unity.version]:-} |
| VS Code CLI | $(_sym vscode.cli) | ${CHECK_DETAIL[vscode.cli]:-} |

## Flutter Doctor Output

\`\`\`
${FLUTTER_DOCTOR_OUTPUT:-Flutter not available}
\`\`\`

## Environment Variables

\`\`\`
ANDROID_HOME=${ANDROID_HOME:-Not set}
ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-Not set}
NVM_DIR=${NVM_DIR:-Not set}
FLUTTER_ROOT=${FLUTTER_ROOT:-Not set}
\`\`\`

## Recommendations

$(
    recs=""
    [ "${CHECK_STATUS[flutter.installed]:-FAIL}" = "FAIL" ] && \
        recs+="- **Flutter**: Install from https://docs.flutter.dev/get-started/install\n"
    [ "${CHECK_STATUS[node.version]:-FAIL}" = "FAIL" ] && \
        recs+="- **Node.js**: Run \`nvm install $REQUIRED_NODE_MAJOR && nvm use $REQUIRED_NODE_MAJOR\`\n"
    [ "${CHECK_STATUS[android.api]:-FAIL}" = "FAIL" ] && \
        recs+="- **Android SDK**: Install Android Studio (https://developer.android.com/studio) or run \`bash setup_environment.sh --install-android\`\n"
    [ "${CHECK_STATUS[git.github_auth]:-FAIL}" = "FAIL" ] && \
        recs+="- **SSH**: Run \`ssh-keygen -t ed25519\` then add public key to https://github.com/settings/keys\n"
    if [ -z "$recs" ]; then
        echo "All critical components are correctly configured — ready to develop!"
    else
        echo -e "$recs"
    fi
)

---
*Generated by KOI validate_environment.sh*
REPORT

    echo ""
    echo -e "${GREEN}Report written to: $REPORT_FILE${NC}"
}

# =============================================================================
# MAIN
# =============================================================================

FLUTTER_DOCTOR_OUTPUT=""

main() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║   KOI Environment Validation                 ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${NC}"

    validate_flutter
    validate_node
    validate_android
    validate_git_ssh
    validate_unity
    validate_vscode

    # Summary
    echo ""
    echo -e "${BOLD}${BLUE}── Summary $( printf '─%.0s' {1..40} )${NC}"
    echo ""
    printf "  %-20s %s\n" "Total checks:"   "$TOTAL"
    echo -e "  $(printf '%-20s' 'Passed:')  ${GREEN}$PASSED${NC}"
    echo -e "  $(printf '%-20s' 'Failed:')  ${RED}$FAILED${NC}"
    echo -e "  $(printf '%-20s' 'Warnings:') ${YELLOW}$WARNED${NC}"

    generate_report

    echo ""
    if [ "$FAILED" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ Environment fully validated — ready to develop!${NC}"
        exit 0
    elif [ "$FAILED" -le 2 ]; then
        echo -e "${YELLOW}${BOLD}⚠ Partially configured — some features may be unavailable.${NC}"
        echo    "  Check $REPORT_FILE for details."
        exit 0
    else
        echo -e "${RED}${BOLD}✗ Significant issues found — run ./setup_environment.sh to fix.${NC}"
        exit 1
    fi
}

main "$@"

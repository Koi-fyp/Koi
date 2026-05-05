#!/bin/bash

# KOI Project - Master Setup Script
# This script automates the complete GitHub organization setup process

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ORG_NAME="koi-fyp"
REPOS=(
    "koi-mobile:Flutter mobile application:mobile"
    "koi-web:Next.js web application:web"
    "koi-backend:Firebase Cloud Functions backend:backend"
    "koi-docs:Project documentation:docs"
)

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if GitHub CLI is installed
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI is not installed"
        echo "Install from: https://cli.github.com"
        exit 1
    fi
    print_success "GitHub CLI installed"

    # Check if Git is installed
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed"
        exit 1
    fi
    print_success "Git installed"

    # Check GitHub authentication
    if ! gh auth status > /dev/null 2>&1; then
        print_error "Not authenticated with GitHub"
        print_info "Running: gh auth login"
        gh auth login
    fi
    print_success "GitHub authenticated"
}

create_repositories() {
    print_header "Creating Repositories"

    for repo_info in "${REPOS[@]}"; do
        IFS=':' read -r repo_name repo_description repo_type <<< "$repo_info"

        print_info "Creating repository: $repo_name"

        if gh repo create "${ORG_NAME}/${repo_name}" \
            --public \
            --description "${repo_description}" \
            2>/dev/null; then
            print_success "Repository created: $repo_name"
        elif gh repo view "${ORG_NAME}/${repo_name}" &>/dev/null; then
            print_success "Repository already exists: $repo_name"
        else
            print_error "Failed to create repository: $repo_name"
            return 1
        fi
    done
}

clone_repositories() {
    print_header "Cloning Repositories"

    for repo_info in "${REPOS[@]}"; do
        IFS=':' read -r repo_name _ _ <<< "$repo_info"

        if [ -d "$repo_name" ]; then
            print_info "Repository directory already exists: $repo_name"
        else
            print_info "Cloning: $repo_name"
            gh repo clone "${ORG_NAME}/${repo_name}"
            print_success "Cloned: $repo_name"
        fi
    done
}

setup_repositories() {
    print_header "Setting Up Repository Configuration"

    for repo_info in "${REPOS[@]}"; do
        IFS=':' read -r repo_name _ repo_type <<< "$repo_info"

        if [ ! -d "$repo_name" ]; then
            print_error "Repository not found: $repo_name"
            continue
        fi

        print_info "Setting up: $repo_name"
        cd "$repo_name"

        # Create necessary directories
        mkdir -p .github/workflows
        mkdir -p .github/ISSUE_TEMPLATE
        mkdir -p .git/hooks

        # Copy shared configuration files
        if [ ! -f ".github/pull_request_template.md" ]; then
            cp ../shared/pull_request_template.md .github/
        fi

        if [ ! -f ".github/ISSUE_TEMPLATE/bug_report.yml" ]; then
            cp ../shared/.github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/
            cp ../shared/.github/ISSUE_TEMPLATE/feature_request.yml .github/ISSUE_TEMPLATE/
        fi

        if [ ! -f "CONTRIBUTING.md" ]; then
            cp ../shared/CONTRIBUTING.md .
        fi

        # Copy repository-specific files
        case $repo_type in
            mobile)
                [ ! -f ".gitignore" ] && cp ../koi-mobile/.gitignore .
                [ ! -f ".github/workflows/flutter-ci.yml" ] && cp ../koi-mobile/.github/workflows/flutter-ci.yml .github/workflows/
                ;;
            web)
                [ ! -f ".gitignore" ] && cp ../koi-web/.gitignore .
                [ ! -f ".github/workflows/nextjs-ci.yml" ] && cp ../koi-web/.github/workflows/nextjs-ci.yml .github/workflows/
                ;;
            backend)
                [ ! -f ".gitignore" ] && cp ../koi-backend/.gitignore .
                [ ! -f ".github/workflows/firebase-ci.yml" ] && cp ../koi-backend/.github/workflows/firebase-ci.yml .github/workflows/
                ;;
        esac

        # Install commit hook
        if [ ! -f ".git/hooks/commit-msg" ]; then
            cp ../shared/commit-msg-hook .git/hooks/commit-msg
            chmod +x .git/hooks/commit-msg
        fi

        # Configure git
        git config core.hooksPath .git/hooks

        # Commit initial setup
        if [ -n "$(git status -s)" ]; then
            print_info "Committing setup files to $repo_name"
            git add .
            git commit -m "chore: initialize project configuration" || true
            git push origin main || git push origin master || true
        fi

        cd ..
        print_success "Configured: $repo_name"
    done
}

print_next_steps() {
    print_header "Setup Complete! Next Steps"

    echo "1. Configure Branch Protection Rules"
    echo "   For each repository:"
    echo "   - Go to Settings → Branches"
    echo "   - Add rule for 'main' branch"
    echo "   - See BRANCH_PROTECTION_RULES.md for details"
    echo ""

    echo "2. Invite Team Members"
    echo "   - Go to: https://github.com/organizations/${ORG_NAME}/members"
    echo "   - Click 'Invite member'"
    echo "   - Set appropriate roles"
    echo ""

    echo "3. Configure GitHub Secrets"
    echo "   - Go to: https://github.com/organizations/${ORG_NAME}/settings/secrets"
    echo "   - Add: FIREBASE_TOKEN, API_KEY, etc."
    echo ""

    echo "4. Set Up Project Boards"
    echo "   - Create project board per repository"
    echo "   - Configure automation"
    echo ""

    echo "5. Review Documentation"
    echo "   - Read: SETUP_GUIDE.md"
    echo "   - Read: CONTRIBUTING.md (in each repo)"
    echo "   - Share with team"
    echo ""

    echo "Repositories Created:"
    for repo_info in "${REPOS[@]}"; do
        IFS=':' read -r repo_name _ _ <<< "$repo_info"
        echo "  - https://github.com/${ORG_NAME}/${repo_name}"
    done
    echo ""
}

# Main execution
print_header "KOI Project - GitHub Organization Setup"

print_info "Organization: $ORG_NAME"
print_info "Repositories: ${#REPOS[@]}"

# Run setup steps
check_prerequisites
create_repositories
clone_repositories
setup_repositories
print_next_steps

print_header "🎉 Setup Complete!"
echo "Start development with the GitFlow workflow described in SETUP_GUIDE.md"
echo ""

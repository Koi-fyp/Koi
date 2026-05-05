#!/bin/bash

# Repository-specific setup script
# This script initializes a repository with all necessary configuration files

set -e

REPO_NAME=$1
REPO_TYPE=$2  # mobile, web, backend, docs

if [ -z "$REPO_NAME" ] || [ -z "$REPO_TYPE" ]; then
    echo "Usage: ./setup_repo.sh <repo_name> <repo_type>"
    echo "Supported types: mobile, web, backend, docs"
    exit 1
fi

echo "Setting up repository: $REPO_NAME ($REPO_TYPE)"

# Create necessary directories
mkdir -p .github/workflows
mkdir -p .github/ISSUE_TEMPLATE
mkdir -p hooks

# Copy shared configuration files
echo "Copying configuration files..."

# Copy pull request template
if [ ! -f ".github/pull_request_template.md" ]; then
    cp ../shared/pull_request_template.md .github/
fi

# Copy commit message hook
if [ ! -f ".git/hooks/commit-msg" ]; then
    cp ../shared/commit-msg-hook .git/hooks/commit-msg
    chmod +x .git/hooks/commit-msg
    echo "✓ Commit message hook installed"
fi

# Copy issue templates
if [ ! -f ".github/ISSUE_TEMPLATE/bug_report.yml" ]; then
    mkdir -p .github/ISSUE_TEMPLATE
    cp ../shared/.github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/
    cp ../shared/.github/ISSUE_TEMPLATE/feature_request.yml .github/ISSUE_TEMPLATE/
    echo "✓ Issue templates copied"
fi

# Copy type-specific files
case $REPO_TYPE in
    mobile)
        echo "Configuring Flutter mobile project..."
        [ ! -f ".gitignore" ] && cp ../repos/koi-mobile/.gitignore .
        [ ! -f ".github/workflows/flutter-ci.yml" ] && cp ../repos/koi-mobile/.github/workflows/flutter-ci.yml .github/workflows/
        echo "✓ Flutter configuration complete"
        ;;
    web)
        echo "Configuring Next.js web project..."
        [ ! -f ".gitignore" ] && cp ../repos/koi-web/.gitignore .
        [ ! -f ".github/workflows/nextjs-ci.yml" ] && cp ../repos/koi-web/.github/workflows/nextjs-ci.yml .github/workflows/
        echo "✓ Next.js configuration complete"
        ;;
    backend)
        echo "Configuring Firebase backend..."
        [ ! -f ".gitignore" ] && cp ../repos/koi-backend/.gitignore .
        [ ! -f ".github/workflows/firebase-ci.yml" ] && cp ../repos/koi-backend/.github/workflows/firebase-ci.yml .github/workflows/
        echo "✓ Firebase configuration complete"
        ;;
    docs)
        echo "Configuring documentation site..."
        echo "✓ Documentation configuration complete"
        ;;
    *)
        echo "Unknown repository type: $REPO_TYPE"
        exit 1
        ;;
esac

# Copy CONTRIBUTING guide
if [ ! -f "CONTRIBUTING.md" ]; then
    cp ../shared/CONTRIBUTING.md .
    echo "✓ Contributing guide copied"
fi

# Initialize git if not already initialized
if [ ! -d ".git" ]; then
    git init
    echo "✓ Git repository initialized"
fi

# Configure git hooks path
git config core.hooksPath .git/hooks
echo "✓ Git hooks path configured"

echo ""
echo "========================================="
echo "✅ Repository setup complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Review and customize configuration files"
echo "2. Add .env.example file"
echo "3. Create initial documentation (README.md)"
echo "4. Commit initial files"
echo ""
echo "To commit initial setup:"
echo "  git add ."
echo "  git commit -m 'chore: initial project setup'"
echo "  git push -u origin main"

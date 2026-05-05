#!/bin/bash

# KOI Project - GitHub Organization Repository Setup
# This script creates all repositories and initializes them with proper structure

set -e

# Configuration
ORG_NAME="koi-fyp"
REPOS=(
  "koi-mobile:Flutter mobile application"
  "koi-web:Next.js web application"
  "koi-backend:Firebase Cloud Functions backend"
  "koi-docs:Project documentation"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}KOI Project - GitHub Repo Setup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo "Install it from: https://cli.github.com"
    exit 1
fi

# Check if user is authenticated
echo "Checking GitHub authentication..."
if ! gh auth status > /dev/null 2>&1; then
    echo -e "${YELLOW}Not authenticated. Please log in to GitHub${NC}"
    gh auth login
fi

echo ""
echo -e "${YELLOW}Creating repositories for organization: ${ORG_NAME}${NC}"
echo ""

# Create each repository
for repo_info in "${REPOS[@]}"; do
    IFS=':' read -r repo_name repo_description <<< "$repo_info"

    echo -e "${YELLOW}Creating repository: ${repo_name}${NC}"

    if gh repo create "${ORG_NAME}/${repo_name}" \
        --public \
        --description "${repo_description}" \
        --remote=origin \
        --source=. \
        --remote-name=origin \
        2>/dev/null || gh repo view "${ORG_NAME}/${repo_name}" &>/dev/null; then
        echo -e "${GREEN}✓ Repository created/verified: ${repo_name}${NC}"
    else
        echo -e "${RED}✗ Failed to create repository: ${repo_name}${NC}"
        continue
    fi

    echo ""
done

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${GREEN}Repository setup complete!${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Clone each repository locally"
echo "2. Copy configuration files (.gitignore, .github/, etc.)"
echo "3. Set up branch protection rules for main and develop"
echo "4. Configure repository settings"
echo ""
echo "GitHub Org: https://github.com/${ORG_NAME}"

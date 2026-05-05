#!/bin/bash
# Test Suite for Git Repository Configuration

set -e

echo "Testing Git Repository Configuration..."
echo ""

REPOS=("koi-mobile" "koi-web" "koi-backend" "koi-docs")
ORG="koi-fyp"

# Test 1: Repository Existence
test_repo_exists() {
    local repo=$1
    echo -n "Test: Repository $repo exists... "

    if gh repo view "$ORG/$repo" &> /dev/null; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL"
        return 1
    fi
}

# Test 2: Default Branch
test_default_branch() {
    local repo=$1
    echo -n "Test: Default branch is 'main'... "

    default_branch=$(gh repo view "$ORG/$repo" --json defaultBranchRef --jq '.defaultBranchRef.name')

    if [ "$default_branch" = "main" ]; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL (found: $default_branch)"
        return 1
    fi
}

# Test 3: Develop Branch Exists
test_develop_branch() {
    local repo=$1
    echo -n "Test: Develop branch exists... "

    if gh api "repos/$ORG/$repo/branches/develop" &> /dev/null; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL"
        return 1
    fi
}

# Test 4: Branch Protection on Main
test_branch_protection() {
    local repo=$1
    echo -n "Test: Branch protection on main... "

    protection=$(gh api "repos/$ORG/$repo/branches/main/protection" 2>/dev/null)

    if [ -n "$protection" ]; then
        # Check if PR reviews are required
        if echo "$protection" | jq -e '.required_pull_request_reviews' > /dev/null; then
            echo "✓ PASS"
            return 0
        fi
    fi

    echo "✗ FAIL"
    return 1
}

# Test 5: .gitignore Exists
test_gitignore_exists() {
    local repo=$1
    echo -n "Test: .gitignore exists... "

    if gh api "repos/$ORG/$repo/contents/.gitignore" &> /dev/null; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL"
        return 1
    fi
}

# Test 6: GitHub Actions Workflow
test_github_actions() {
    local repo=$1
    echo -n "Test: GitHub Actions configured... "

    workflows=$(gh api "repos/$ORG/$repo/contents/.github/workflows" 2>/dev/null)

    if [ -n "$workflows" ]; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL"
        return 1
    fi
}

# Test 7: Commit Message Validation
test_commit_message_validation() {
    echo -n "Test: Commit message hook... "

    if [ -f ".git/hooks/commit-msg" ] && [ -x ".git/hooks/commit-msg" ]; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL (hook not found or not executable)"
        return 1
    fi
}

# Test 8: Valid Commit Message Format
test_commit_format() {
    echo "Test: Commit message validation..."

    valid_messages=(
        "feat(auth): add OAuth support"
        "fix(api): resolve timeout issue"
        "docs: update README"
        "chore: update dependencies"
    )

    invalid_messages=(
        "added new feature"
        "Fixed bug"
        "Update docs"
        "WIP"
    )

    # Test valid messages
    for msg in "${valid_messages[@]}"; do
        if ./.git/hooks/commit-msg <(echo "$msg") 2>/dev/null; then
            echo "  ✓ Valid: $msg"
        else
            echo "  ✗ Should be valid: $msg"
            return 1
        fi
    done

    # Test invalid messages
    for msg in "${invalid_messages[@]}"; do
        if ! ./.git/hooks/commit-msg <(echo "$msg") 2>/dev/null; then
            echo "  ✓ Rejected: $msg"
        else
            echo "  ✗ Should be rejected: $msg"
            return 1
        fi
    done

    echo "  ✓ All commit format tests passed"
    return 0
}

# Run tests for each repository
echo "=========================================="
echo "Testing Repository Configuration"
echo "=========================================="
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0

for repo in "${REPOS[@]}"; do
    echo "Repository: $repo"
    echo "----------"

    test_repo_exists "$repo" && ((PASSED_TESTS++))
    ((TOTAL_TESTS++))

    test_default_branch "$repo" && ((PASSED_TESTS++))
    ((TOTAL_TESTS++))

    test_develop_branch "$repo" && ((PASSED_TESTS++))
    ((TOTAL_TESTS++))

    test_branch_protection "$repo" && ((PASSED_TESTS++))
    ((TOTAL_TESTS++))

    test_gitignore_exists "$repo" && ((PASSED_TESTS++))
    ((TOTAL_TESTS++))

    test_github_actions "$repo" && ((PASSED_TESTS++))
    ((TOTAL_TESTS++))

    echo ""
done

# Test commit hooks (only once, not per repo)
test_commit_message_validation && ((PASSED_TESTS++))
((TOTAL_TESTS++))

test_commit_format && ((PASSED_TESTS++))
((TOTAL_TESTS++))

echo "=========================================="
echo "Results: $PASSED_TESTS/$TOTAL_TESTS tests passed"
echo "=========================================="

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo "✓ All Git workflow tests passed!"
    exit 0
else
    echo "✗ Some tests failed. Review configuration."
    exit 1
fi

# GitHub Branch Protection Rules Configuration Guide

## Overview
This guide outlines the branch protection rules for the KOI project repositories. These rules are applied to the `main` and `develop` branches to ensure code quality and security.

## Protected Branches

### main (Production)
**Purpose**: Production-ready code only

**Protection Rules**:
1. ✅ Require pull request reviews (minimum 1 approval)
2. ✅ Require status checks to pass
   - CI/CD tests must pass
   - Linting must pass
   - Build must succeed
3. ✅ Require branches to be up to date before merging
4. ✅ Require signed commits
5. ✅ Include administrators in restrictions
6. ❌ Do not allow force pushes
7. ❌ Do not allow deletions
8. ✅ Dismiss stale pull request approvals on new commits
9. ✅ Require conversation resolution before merging

### develop (Integration)
**Purpose**: Integration branch for features

**Protection Rules**:
1. ✅ Require pull request reviews (minimum 1 approval)
2. ✅ Require status checks to pass
   - CI/CD tests must pass
   - Linting must pass
   - Build must succeed
3. ✅ Require branches to be up to date before merging
4. ✅ Dismiss stale pull request approvals on new commits
5. ❌ Do not allow force pushes
6. ❌ Do not allow deletions
7. ✅ Require conversation resolution before merging

## How to Configure (Manual Steps)

### Via GitHub Web Interface

1. Go to repository → Settings → Branches
2. Click "Add rule"
3. Fill in branch name pattern (e.g., `main`)
4. Configure options:

```
Branch name pattern: main

Protection rules:
☑ Require a pull request before merging
  ☑ Require approvals: 1
  ☑ Dismiss stale pull request approvals when new commits are pushed
  ☑ Require review from Code Owners

☑ Require status checks to pass before merging
  ☑ Require branches to be up to date before merging
  ✓ Select status checks:
    - Linting
    - Tests
    - Build

☑ Require signed commits

☑ Include administrators

☑ Restrict who can push to matching branches
  - Allow: Only administrators

☑ Require resolution of conversations before merging

☐ Allow force pushes
☐ Allow deletions
```

### Via GitHub CLI

```bash
# This example uses the GitHub CLI to protect branches
# Note: The CLI has limited support for branch protection rules
# Most features need to be configured via web interface

gh api repos/koi-fyp/{repo}/branches/{branch}/protection \
  -X PUT \
  -f required_pull_request_reviews='{"required_approving_review_count":1}' \
  -f enforce_admins=true \
  -f require_code_owner_reviews=false \
  -f dismiss_stale_reviews=true
```

## Bypass Rules

### When Can Rules Be Bypassed?
- Emergency hotfixes to production (with team lead approval)
- Security patches (with security team approval)

### Bypass Process
1. Contact repository administrators
2. Provide justification
3. Get at least one additional approval
4. Document the bypass reason

## Workflow Examples

### Feature Development
```
1. Create branch: feature/new-feature
2. Make commits: feat(scope): description
3. Push branch
4. Create PR to develop
5. Request review (1+ approval required)
6. All CI checks must pass
7. Merge to develop
```

### Hotfix to Production
```
1. Create branch from main: hotfix/bug-name
2. Make commits: fix(scope): description
3. Push branch
4. Create PR to main
5. Request urgent review (1+ approval required)
6. All CI checks must pass
7. Merge to main
8. Create PR from main to develop
9. Merge to develop
```

## Status Checks

Required status checks that must pass:

### koi-mobile
- Flutter analyze
- Flutter test
- Build APK (release)
- Build iOS

### koi-web
- Node.js lint
- Jest tests
- Build verification
- Snyk security scan

### koi-backend
- Node.js lint
- Jest tests
- Firebase validation
- Snyk security scan

### koi-docs
- Build documentation
- Link validation (if applicable)

## Review Requirements

### Code Owners
Each repository should have a `.github/CODEOWNERS` file:

```
# Frontend components
/src/components/ @frontend-team

# API routes
/functions/src/routes/ @backend-team

# Documentation
/docs/ @tech-writers

# CI/CD
/.github/workflows/ @devops-team
```

## Monitoring and Maintenance

### Check Rule Status
- GitHub automatically shows rule violations in PRs
- Red status checks prevent merging
- Administrators are notified of bypass requests

### Update Rules
- Review rules quarterly
- Update based on team feedback
- Document any changes to this guide

## Troubleshooting

### "Branch out of date" Error
```bash
git fetch origin
git rebase origin/develop
git push -f origin feature/branch
```

### "Signed commits required" Error
- Configure GPG signing: https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key
- Sign commits: `git commit -S -m "message"`

### Tests Not Passing
- Review CI/CD logs
- Fix code locally
- Commit and push
- Tests will re-run automatically

## Additional Resources

- [GitHub Branch Protection Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [Conventional Commits Guide](https://www.conventionalcommits.org/)
- [GitHub CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)

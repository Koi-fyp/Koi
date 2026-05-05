# KOI Project - GitHub Organization Setup Guide

## 📋 Overview

This guide covers the complete setup of the KOI Project GitHub organization with GitFlow workflow, branch protection, CI/CD automation, and developer guidelines.

**Organization**: `koi-fyp`

**Repositories**:
1. `koi-mobile` - Flutter mobile application
2. `koi-web` - Next.js web application
3. `koi-backend` - Firebase Cloud Functions
4. `koi-docs` - Project documentation

---

## 🚀 Quick Start

### Prerequisites
- GitHub CLI installed: `brew install gh` (macOS) or download from https://cli.github.com
- Git configured with your GitHub account

### Step 1: Create the Organization

```bash
# This must be done manually via GitHub web interface
# Visit: https://github.com/organizations/new
# Select: koi-fyp as organization name
```

### Step 2: Create Repositories

```bash
# Make the script executable
chmod +x create_repos.sh

# Run the script to create all repositories
./create_repos.sh
```

The script will create:
- koi-mobile
- koi-web
- koi-backend
- koi-docs

### Step 3: Clone Repositories

```bash
for repo in koi-mobile koi-web koi-backend koi-docs; do
    git clone https://github.com/koi-fyp/$repo.git
    cd $repo
    # Continue with Step 4 below
done
```

### Step 4: Initialize Each Repository

```bash
# For each cloned repository:
../setup_repo.sh koi-mobile mobile     # or web, backend, docs
```

### Step 5: Configure Branch Protection

For each repository:
1. Go to Settings → Branches
2. Click "Add rule"
3. Follow instructions in `BRANCH_PROTECTION_RULES.md`

---

## 📁 Repository Structure

```
koi-fyp/
├── koi-mobile/
│   ├── .github/
│   │   ├── workflows/
│   │   │   └── flutter-ci.yml
│   │   ├── ISSUE_TEMPLATE/
│   │   │   ├── bug_report.yml
│   │   │   └── feature_request.yml
│   │   └── pull_request_template.md
│   ├── .git/
│   │   └── hooks/
│   │       └── commit-msg
│   ├── .gitignore
│   └── CONTRIBUTING.md
│
├── koi-web/
│   ├── .github/
│   │   ├── workflows/
│   │   │   └── nextjs-ci.yml
│   │   ├── ISSUE_TEMPLATE/
│   │   │   ├── bug_report.yml
│   │   │   └── feature_request.yml
│   │   └── pull_request_template.md
│   ├── .git/
│   │   └── hooks/
│   │       └── commit-msg
│   ├── .gitignore
│   └── CONTRIBUTING.md
│
├── koi-backend/
│   ├── .github/
│   │   ├── workflows/
│   │   │   └── firebase-ci.yml
│   │   ├── ISSUE_TEMPLATE/
│   │   │   ├── bug_report.yml
│   │   │   └── feature_request.yml
│   │   └── pull_request_template.md
│   ├── .git/
│   │   └── hooks/
│   │       └── commit-msg
│   ├── .gitignore
│   └── CONTRIBUTING.md
│
└── koi-docs/
    ├── .github/
    │   ├── ISSUE_TEMPLATE/
    │   │   ├── bug_report.yml
    │   │   └── feature_request.yml
    │   └── pull_request_template.md
    ├── .git/
    │   └── hooks/
    │       └── commit-msg
    └── CONTRIBUTING.md
```

---

## 🌳 GitFlow Workflow

### Branch Structure

```
main ────────────────────────────────────
  ↑ (PR, merge after release)           │
  └──────────────────────────┐           │
                            │           │
develop ──────────────────────────────────
  ↑ (PR from features)       │
  ├─ feature/auth-system     │
  ├─ feature/payment         │
  ├─ bugfix/ui-issue         │
  └─ hotfix/critical-bug ────┘ (urgent)
```

### Branches

| Branch | Purpose | Created From | Merges To |
|--------|---------|--------------|-----------|
| `main` | Production release | N/A | N/A |
| `develop` | Integration | main | main |
| `feature/*` | New features | develop | develop |
| `bugfix/*` | Bug fixes | develop | develop |
| `hotfix/*` | Critical fixes | main | main + develop |
| `release/*` | Release prep | develop | main + develop |

### Daily Workflow

#### Creating a Feature

```bash
# Update develop
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feature/auth-system

# Make changes and commit
git add .
git commit -m "feat(auth): add OAuth login support"

# Push and create PR
git push -u origin feature/auth-system
```

#### Merging to Develop

1. Create PR from `feature/*` → `develop`
2. Request review (minimum 1 approval)
3. Wait for CI/CD checks to pass
4. Merge via "Create a merge commit"

#### Release to Production

```bash
# Create release branch
git checkout -b release/1.0.0 develop

# Update version numbers
# Make release-specific changes
git add .
git commit -m "chore(release): prepare v1.0.0"

# Create PR to main
git push origin release/1.0.0
# Create PR on GitHub

# After merging to main:
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# Also merge back to develop
git checkout develop
git pull origin develop
git merge main
git push origin develop
```

---

## 📝 Commit Message Standards

Follow Conventional Commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `style` - Code style
- `refactor` - Refactoring
- `test` - Tests
- `chore` - Build/deps
- `ci` - CI/CD
- `perf` - Performance
- `build` - Build system
- `revert` - Revert commit

### Examples

✅ Good:
```
feat(auth): add OAuth login

Implement OAuth 2.0 authentication using Google and GitHub providers.
This allows users to sign in without creating a new account.

Closes #123
```

✅ Good:
```
fix(ui): resolve button alignment on mobile

The login button was misaligned on screens < 600px.
Updated flex layout to center button properly.
```

❌ Bad:
```
added feature
Fixed bug
Update
```

---

## 🔒 Branch Protection Rules

### main Branch
- ✅ Require PR review (1+ approval)
- ✅ Require status checks pass
- ✅ Require branches up to date
- ✅ Require signed commits
- ✅ Dismiss stale reviews
- ❌ No force push
- ❌ No deletion

### develop Branch
- ✅ Require PR review (1+ approval)
- ✅ Require status checks pass
- ✅ Require branches up to date
- ✅ Dismiss stale reviews
- ❌ No force push
- ❌ No deletion

See `BRANCH_PROTECTION_RULES.md` for detailed setup.

---

## 🤖 CI/CD Workflows

### koi-mobile (Flutter)
- **Triggers**: Push to main/develop, PRs
- **Jobs**:
  - Flutter analyze
  - Flutter test
  - Build APK (release)
  - Build iOS

### koi-web (Next.js)
- **Triggers**: Push to main/develop, PRs
- **Jobs**:
  - Node.js lint
  - Jest tests
  - Build verification
  - Snyk security scan
  - Vercel preview deployment

### koi-backend (Firebase)
- **Triggers**: Push to main/develop, PRs
- **Jobs**:
  - Node.js lint
  - Jest tests
  - Firebase validation
  - Snyk security scan
  - Deploy to Firebase (main/develop)

---

## 👥 Team Roles

### Repository Permissions

| Role | Permissions |
|------|-----------|
| Owner | Full admin access |
| Maintainer | Review PRs, merge, manage issues |
| Developer | Create branches, push, open PRs |
| Contributor | Fork, create issues, comment |

### Code Owners

Create `.github/CODEOWNERS` in each repository:

```
# Frontend components
/src/components/ @frontend-team

# API routes
/functions/src/ @backend-team

# Workflows
/.github/workflows/ @devops-team
```

---

## 📚 Documentation

### For Each Repository:
- `README.md` - Project overview, setup, usage
- `CONTRIBUTING.md` - How to contribute
- `BRANCH_PROTECTION_RULES.md` - Branch rules
- `.env.example` - Environment variables template

### API Documentation:
- Include in `koi-backend/README.md` or separate `koi-docs`
- Use OpenAPI/Swagger if applicable
- Document endpoints, authentication, errors

### Release Notes:
- Maintain `CHANGELOG.md`
- Document breaking changes
- Link to related issues/PRs

---

## 🔐 Security Considerations

### Secrets Management
- Store secrets in GitHub Organization Secrets
- Never commit `.env` or configuration files
- Use `.env.example` for templates

### Code Scanning
- Enable Snyk security scanning
- Review security alerts regularly
- Fix vulnerabilities promptly

### Signed Commits
- Configure GPG signing (see `CONTRIBUTING.md`)
- Enforce for main branch
- Maintain audit trail

---

## 🚨 Troubleshooting

### Commit Hook Not Running
```bash
# Ensure hook is executable
chmod +x .git/hooks/commit-msg

# Verify hooks path is set
git config core.hooksPath
```

### "Branch out of date" Error
```bash
git fetch origin
git rebase origin/develop
git push -f origin feature/your-branch
```

### PR Status Checks Failing
1. Review CI/CD logs in GitHub
2. Fix issues locally
3. Commit and push
4. Checks will re-run automatically

### Can't Push to main/develop
- Branch protection is active
- Must create PR and get approval
- All status checks must pass

---

## 📋 Setup Checklist

- [ ] Organization created: `koi-fyp`
- [ ] Repositories created (koi-mobile, koi-web, koi-backend, koi-docs)
- [ ] Each repository cloned locally
- [ ] Configuration files copied to each repo
- [ ] Git hooks installed and executable
- [ ] Branch protection rules configured
- [ ] Team members added to organization
- [ ] GitHub Secrets configured (API keys, tokens)
- [ ] CI/CD workflows tested
- [ ] CONTRIBUTING.md guidelines communicated
- [ ] First development sprint planned

---

## 📞 Support & Resources

- **GitHub Docs**: https://docs.github.com
- **Conventional Commits**: https://www.conventionalcommits.org/
- **GitFlow**: https://git-flow.readthedocs.io/
- **GitHub Actions**: https://github.com/features/actions

---

## 🎉 Next Steps

1. ✅ Review this guide with the team
2. ✅ Complete the setup checklist
3. ✅ Invite team members
4. ✅ Create initial issues and projects
5. ✅ Start development on `develop` branch
6. ✅ Begin first sprint

**Happy coding! 🚀**

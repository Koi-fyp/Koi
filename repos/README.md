# KOI Project - GitHub Organization Infrastructure

Complete automation and configuration for the `koi-fyp` GitHub organization with GitFlow workflow, branch protection, CI/CD pipelines, and developer guidelines.

## 📂 Contents

```
repos/
├── create_repos.sh                          # Create all repositories via GitHub CLI
├── master_setup.sh                          # Master automation script
├── setup_repo.sh                            # Individual repository setup
│
├── SETUP_GUIDE.md                           # Comprehensive setup guide
├── BRANCH_PROTECTION_RULES.md               # Branch protection configuration
│
├── shared/                                  # Shared across all repos
│   ├── CONTRIBUTING.md                      # Contribution guidelines
│   ├── pull_request_template.md             # PR template
│   ├── commit-msg-hook                      # Commit message validator
│   └── .github/
│       └── ISSUE_TEMPLATE/
│           ├── bug_report.yml               # Bug report template
│           └── feature_request.yml          # Feature request template
│
├── koi-mobile/                              # Flutter mobile app
│   ├── .gitignore
│   └── .github/workflows/
│       └── flutter-ci.yml                   # Flutter CI/CD pipeline
│
├── koi-web/                                 # Next.js web app
│   ├── .gitignore
│   └── .github/workflows/
│       └── nextjs-ci.yml                    # Next.js CI/CD pipeline
│
└── koi-backend/                             # Firebase backend
    ├── .gitignore
    └── .github/workflows/
        └── firebase-ci.yml                  # Firebase CI/CD pipeline
```

## 🚀 Quick Start

### Option 1: Automated Setup (Recommended)

```bash
# Make the master setup script executable
chmod +x master_setup.sh

# Run the complete setup
./master_setup.sh
```

This will:
1. Check prerequisites (GitHub CLI, Git)
2. Authenticate with GitHub
3. Create all 4 repositories
4. Clone them locally
5. Configure all files
6. Commit initial setup

### Option 2: Manual Setup

```bash
# Step 1: Create repositories
chmod +x create_repos.sh
./create_repos.sh

# Step 2: Clone each repository
gh repo clone koi-fyp/koi-mobile
gh repo clone koi-fyp/koi-web
gh repo clone koi-fyp/koi-backend
gh repo clone koi-fyp/koi-docs

# Step 3: Initialize each repository
cd koi-mobile && ../setup_repo.sh koi-mobile mobile
cd ../koi-web && ../setup_repo.sh koi-web web
cd ../koi-backend && ../setup_repo.sh koi-backend backend
cd ../koi-docs && ../setup_repo.sh koi-docs docs
```

## 📋 Files Overview

### Scripts

#### `create_repos.sh`
- Creates all 4 repositories in the GitHub organization
- Requires GitHub CLI authentication
- Verifies each repository is created

**Usage**:
```bash
./create_repos.sh
```

#### `master_setup.sh`
- Complete end-to-end setup automation
- Creates repos, clones, and configures
- Recommended for first-time setup

**Usage**:
```bash
chmod +x master_setup.sh
./master_setup.sh
```

#### `setup_repo.sh`
- Sets up individual repository configuration
- Copies shared files and repo-specific files
- Installs Git hooks

**Usage**:
```bash
./setup_repo.sh <repo_name> <repo_type>
# Example:
./setup_repo.sh koi-mobile mobile
```

### Configuration Files

#### `.gitignore` (Repository-specific)
- **koi-mobile**: Flutter build outputs, IDE files, environment variables
- **koi-web**: Node.js packages, Next.js build, IDE files
- **koi-backend**: Node.js packages, Firebase config, build files

#### `.github/workflows/`
- **flutter-ci.yml**: Analyze, test, build APK/iOS
- **nextjs-ci.yml**: Lint, test, build, security scan, preview deploy
- **firebase-ci.yml**: Lint, test, security scan, deploy to Firebase

#### `.github/ISSUE_TEMPLATE/`
- **bug_report.yml**: Structured bug report form
- **feature_request.yml**: Feature request form with acceptance criteria

#### Shared Configuration
- **CONTRIBUTING.md**: Developer guidelines, workflow, commit standards
- **pull_request_template.md**: PR checklist and requirements
- **commit-msg-hook**: Validates Conventional Commits format

### Guides

#### `SETUP_GUIDE.md`
Complete setup documentation including:
- Prerequisites and installation
- Repository structure
- GitFlow workflow overview
- Commit message standards
- Branch protection rules
- CI/CD workflows for each repo
- Team roles and permissions

#### `BRANCH_PROTECTION_RULES.md`
Detailed configuration for branch protection:
- main branch rules
- develop branch rules
- Manual and CLI setup instructions
- Bypass procedures
- Troubleshooting

#### `CONTRIBUTING.md`
Developer guidelines covering:
- Code of conduct
- Initial setup
- GitFlow branching strategy
- Commit guidelines
- Pull request process
- Coding standards
- Testing requirements
- Documentation standards

## 🌳 GitFlow Architecture

```
main (production)
  ↓
develop (integration)
  ├─ feature/auth-system
  ├─ feature/payments
  ├─ bugfix/ui-glitch
  └─ hotfix/critical-bug (from main)
```

### Branch Types
- **main**: Production-ready code, tagged releases
- **develop**: Integration branch, acceptance testing
- **feature/**: New features (from develop)
- **bugfix/**: Non-critical fixes (from develop)
- **hotfix/**: Critical production fixes (from main)
- **release/**: Release preparation (from develop)

## 📝 Workflow Examples

### Creating a Feature
```bash
git checkout develop && git pull
git checkout -b feature/auth-system
# Make changes
git commit -m "feat(auth): add OAuth login"
git push -u origin feature/auth-system
# Create PR on GitHub
```

### Hotfix from Production
```bash
git checkout main && git pull
git checkout -b hotfix/payment-crash
# Fix issue
git commit -m "fix(payment): resolve crash on checkout"
git push -u origin hotfix/payment-crash
# Create PR to main
# Also merge to develop
```

### Release to Production
```bash
git checkout -b release/1.0.0 develop
# Update version, changelog
git commit -m "chore(release): prepare v1.0.0"
git push origin release/1.0.0
# Create PR to main
# After merge: tag and merge back to develop
```

## 🔐 Security Features

- **Signed Commits**: Required for main branch
- **Code Owners**: Review permissions per directory
- **Status Checks**: Lint, test, build must pass
- **Branch Protection**: Force push disabled, require reviews
- **Secrets Management**: GitHub org secrets for sensitive data
- **Security Scanning**: Snyk integration for vulnerabilities

## 🚀 CI/CD Pipelines

Each repository has automated workflows that:
- Run tests on every push to main/develop
- Lint code for style issues
- Build and verify functionality
- Generate security reports
- Deploy to preview/staging/production

### Workflow Triggers
- **Push**: Any push to main or develop
- **Pull Request**: All PRs to main or develop
- **Schedule**: Optional nightly runs

## 📚 Repository-Specific Information

### koi-mobile (Flutter)
- **Language**: Dart
- **Framework**: Flutter 3.19.0
- **Build**: APK (Android), IPA (iOS)
- **Workflow**: `flutter-ci.yml`

### koi-web (Next.js)
- **Language**: JavaScript/TypeScript
- **Framework**: Next.js 14+
- **Node Version**: 20.x
- **Deployment**: Vercel preview
- **Workflow**: `nextjs-ci.yml`

### koi-backend (Firebase)
- **Language**: JavaScript/TypeScript
- **Runtime**: Node.js 20+
- **Platform**: Firebase Cloud Functions
- **Database**: Firestore
- **Workflow**: `firebase-ci.yml`

### koi-docs
- **Purpose**: Project documentation
- **Format**: Markdown
- **Hosting**: GitHub Pages (optional)

## ✅ Pre-Launch Checklist

- [ ] Organization created: koi-fyp
- [ ] All 4 repositories created
- [ ] Branch protection configured for main and develop
- [ ] Team members invited with appropriate roles
- [ ] GitHub organization secrets configured
- [ ] CI/CD workflows tested
- [ ] Commit hooks installed in all repos
- [ ] README.md created in each repo
- [ ] .env.example files created
- [ ] First sprint issues created
- [ ] Team trained on GitFlow workflow

## 🎓 Learning Resources

- **GitFlow**: https://git-flow.readthedocs.io/
- **Conventional Commits**: https://www.conventionalcommits.org/
- **GitHub Flow**: https://guides.github.com/introduction/flow/
- **GitHub Actions**: https://github.com/features/actions
- **GitHub Docs**: https://docs.github.com

## 🔧 Troubleshooting

### Commit Hook Not Triggering
```bash
chmod +x .git/hooks/commit-msg
git config core.hooksPath .git/hooks
```

### Can't Merge to main/develop
- Branch protection requires PR review
- All status checks must pass
- Branch must be up to date

### Tests Failing in CI
- Check GitHub Actions logs
- Verify `.github/workflows/` files
- Test locally before pushing

### Repository Not Appearing
- Verify GitHub CLI is authenticated: `gh auth status`
- Check organization name: `koi-fyp`
- Verify permissions in organization settings

## 📞 Support

- Check `SETUP_GUIDE.md` for detailed documentation
- Review `BRANCH_PROTECTION_RULES.md` for branch configuration
- See `CONTRIBUTING.md` in each repository for developer guidelines
- Open issues in appropriate repository

## 📄 License

All configuration files and scripts are provided as-is for the KOI project.

---

**Last Updated**: May 5, 2026
**Organization**: koi-fyp
**Repositories**: 4 (mobile, web, backend, docs)
**Workflow**: GitFlow with GitHub Actions CI/CD

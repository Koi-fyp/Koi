# KOI Project Infrastructure - Complete File Index

## 📂 Repository Structure Overview

```
Koi-App/repos/
│
├── 📄 README.md                             # This directory overview
├── 📄 SETUP_GUIDE.md                        # Complete setup documentation
├── 📄 QUICK_REFERENCE.md                    # Developer quick reference
├── 📄 BRANCH_PROTECTION_RULES.md            # Branch protection configuration
│
├── 🔧 create_repos.sh                       # GitHub CLI repository creator
├── 🔧 master_setup.sh                       # Automated complete setup
├── 🔧 setup_repo.sh                         # Individual repo initializer
│
├── 📁 shared/                               # Shared across all repositories
│   ├── 📄 CONTRIBUTING.md                   # Developer guidelines
│   ├── 📄 pull_request_template.md          # GitHub PR template
│   ├── 🔧 commit-msg-hook                   # Git commit validator
│   └── 📁 .github/
│       ├── 📄 CODEOWNERS                    # Code ownership rules
│       └── 📁 ISSUE_TEMPLATE/
│           ├── 📄 bug_report.yml            # Bug report form
│           └── 📄 feature_request.yml       # Feature request form
│
├── 📁 koi-mobile/                           # Flutter mobile app config
│   ├── 📄 .gitignore                        # Git ignore rules
│   └── 📁 .github/workflows/
│       └── 📄 flutter-ci.yml                # Flutter CI/CD pipeline
│
├── 📁 koi-web/                              # Next.js web app config
│   ├── 📄 .gitignore                        # Git ignore rules
│   └── 📁 .github/workflows/
│       └── 📄 nextjs-ci.yml                 # Next.js CI/CD pipeline
│
└── 📁 koi-backend/                          # Firebase backend config
    ├── 📄 .gitignore                        # Git ignore rules
    └── 📁 .github/workflows/
        └── 📄 firebase-ci.yml               # Firebase CI/CD pipeline
```

---

## 📋 File Descriptions

### Root-Level Guides

#### `README.md` (This File)
- Overview of the infrastructure directory
- Quick start options
- File descriptions
- Troubleshooting guide

#### `SETUP_GUIDE.md` (Main Documentation)
- **Purpose**: Complete setup documentation
- **Audience**: DevOps engineers, team leads
- **Contents**:
  - Prerequisites and quick start
  - Repository structure
  - GitFlow workflow explanation
  - Commit message standards
  - Branch protection rules
  - CI/CD workflow details
  - Team roles and permissions
  - Security considerations
  - Troubleshooting guide

#### `BRANCH_PROTECTION_RULES.md`
- **Purpose**: Detailed branch protection configuration
- **Contents**:
  - Rule specifications for main and develop
  - Manual web interface steps
  - GitHub CLI examples
  - Bypass procedures
  - Workflow examples
  - Troubleshooting

#### `QUICK_REFERENCE.md`
- **Purpose**: Quick lookup for developers
- **Contents**:
  - Essential Git commands
  - Commit message examples
  - Branch naming patterns
  - Common workflows
  - Issue solutions
  - Security tips
  - PR checklist

---

### Automation Scripts

#### `create_repos.sh`
- **Purpose**: Create repositories in GitHub organization
- **Language**: Bash
- **Requirements**: GitHub CLI, authentication
- **What it does**:
  - Checks for GitHub CLI
  - Verifies authentication
  - Creates 4 repositories
  - Displays creation status

**Usage**:
```bash
chmod +x create_repos.sh
./create_repos.sh
```

#### `master_setup.sh`
- **Purpose**: Complete end-to-end setup automation
- **Language**: Bash
- **Requirements**: GitHub CLI, Git, curl
- **What it does**:
  1. Checks prerequisites
  2. Creates repositories
  3. Clones locally
  4. Copies configuration files
  5. Sets up Git hooks
  6. Commits initial setup

**Usage**:
```bash
chmod +x master_setup.sh
./master_setup.sh
```

#### `setup_repo.sh`
- **Purpose**: Initialize individual repository
- **Language**: Bash
- **What it does**:
  - Creates `.github/` directories
  - Copies shared files
  - Copies repo-specific files
  - Installs commit hook
  - Commits setup files

**Usage**:
```bash
cd koi-mobile
../setup_repo.sh koi-mobile mobile
```

---

### Shared Configuration Files

#### `shared/CONTRIBUTING.md`
- **Purpose**: Developer contribution guidelines
- **Applies to**: All repositories
- **Contents**:
  - Code of conduct
  - Development setup
  - GitFlow workflow
  - Commit guidelines
  - Pull request process
  - Coding standards
  - Testing requirements
  - Documentation standards

**Copy to**: Each repository root

#### `shared/pull_request_template.md`
- **Purpose**: GitHub PR template
- **Location**: `.github/pull_request_template.md`
- **Contents**:
  - Description section
  - Type of change checkboxes
  - Testing verification
  - Review checklist
  - Pre-merge verification

**Shows up**: Automatically when creating new PR

#### `shared/commit-msg-hook`
- **Purpose**: Git hook to validate commit messages
- **Format**: Conventional Commits validation
- **Location**: `.git/hooks/commit-msg`
- **Validates**:
  - Message format: `<type>(<scope>): <subject>`
  - Allowed types: feat, fix, docs, style, refactor, test, chore, ci, perf
  - Subject length: 1-100 characters

**Installation**:
```bash
cp shared/commit-msg-hook .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
git config core.hooksPath .git/hooks
```

#### `shared/.github/CODEOWNERS`
- **Purpose**: Define code ownership for reviews
- **Location**: `.github/CODEOWNERS`
- **Contents**:
  - Default owners
  - Directory-specific owners
  - File-type owners
  - Team assignments

**Customize for**: Each repository

#### `shared/.github/ISSUE_TEMPLATE/bug_report.yml`
- **Purpose**: Structured bug report form
- **Fields**:
  - Summary
  - Description
  - Steps to reproduce
  - Expected vs actual behavior
  - Severity level
  - Environment info
  - Error logs
  - Screenshots

**Shows up**: Automatically when creating bug issue

#### `shared/.github/ISSUE_TEMPLATE/feature_request.yml`
- **Purpose**: Structured feature request form
- **Fields**:
  - Feature title
  - Description
  - Problem it solves
  - Proposed solution
  - Alternatives considered
  - Priority
  - Affected areas
  - Acceptance criteria

**Shows up**: Automatically when creating feature issue

---

### Repository-Specific Files

#### `koi-mobile/.gitignore`
- **Purpose**: Ignore Flutter build outputs
- **Ignores**:
  - Flutter: `build/`, `.dart_tool/`, `.packages`, `pubspec.lock`
  - IDE: `.idea/`, `.vscode/`, `*.iml`
  - Environment: `.env`, `.env.local`
  - Build outputs: `*.apk`, `*.ipa`

#### `koi-mobile/.github/workflows/flutter-ci.yml`
- **Purpose**: Flutter CI/CD pipeline
- **Triggers**: Push to main/develop, PR
- **Jobs**:
  - Test (analyze, unit tests, coverage)
  - Build APK (Android release)
  - Build iOS (iOS release)

#### `koi-web/.gitignore`
- **Purpose**: Ignore Next.js build outputs
- **Ignores**:
  - Dependencies: `node_modules/`, `.pnp`
  - Build: `.next/`, `out/`, `dist/`
  - Environment: `.env`, `.env.local`
  - IDE: `.vscode/`, `.idea/`

#### `koi-web/.github/workflows/nextjs-ci.yml`
- **Purpose**: Next.js CI/CD pipeline
- **Triggers**: Push to main/develop, PR
- **Jobs**:
  - Lint and test (eslint, jest, build)
  - Security scan (Snyk)
  - Deploy preview (Vercel)

#### `koi-backend/.gitignore`
- **Purpose**: Ignore Firebase build outputs
- **Ignores**:
  - Dependencies: `node_modules/`, `.pnp`
  - Build: `lib/`, `dist/`
  - Firebase: `.firebase/`, `firebase-debug.log`
  - Environment: `.env`, `.runtimeconfig.json`

#### `koi-backend/.github/workflows/firebase-ci.yml`
- **Purpose**: Firebase CI/CD pipeline
- **Triggers**: Push to main/develop, PR
- **Jobs**:
  - Test and lint (eslint, jest, coverage)
  - Security scan (Snyk)
  - Deploy (to Firebase only from main/develop)

---

## 🚀 Implementation Order

### Phase 1: Preparation
1. [ ] Read `SETUP_GUIDE.md`
2. [ ] Create GitHub organization: `koi-fyp`
3. [ ] Ensure GitHub CLI is installed

### Phase 2: Repository Creation
4. [ ] Run `./master_setup.sh` OR
   - Run `./create_repos.sh`
   - Clone each repository
   - Run `setup_repo.sh` for each

### Phase 3: Configuration
5. [ ] Configure branch protection rules (see `BRANCH_PROTECTION_RULES.md`)
6. [ ] Invite team members to organization
7. [ ] Set up GitHub organization secrets

### Phase 4: Communication
8. [ ] Share `QUICK_REFERENCE.md` with developers
9. [ ] Share `CONTRIBUTING.md` with developers
10. [ ] Conduct team training on GitFlow

### Phase 5: Launch
11. [ ] Create first sprint issues
12. [ ] Begin development
13. [ ] Monitor CI/CD pipelines

---

## ✅ Verification Checklist

After setup, verify:

- [ ] All 4 repositories created in `koi-fyp` organization
- [ ] Each repository has:
  - [ ] `.gitignore` file
  - [ ] `.github/workflows/` CI/CD pipeline
  - [ ] `.github/pull_request_template.md`
  - [ ] `.github/ISSUE_TEMPLATE/` (bug & feature)
  - [ ] `.github/CODEOWNERS`
  - [ ] `CONTRIBUTING.md`
  - [ ] `.git/hooks/commit-msg` installed
- [ ] Branch protection rules configured for main and develop
- [ ] GitHub organization secrets configured
- [ ] Team members invited with appropriate roles
- [ ] CI/CD workflows passing test runs

---

## 🔧 Common Maintenance Tasks

### Update Commit Hook
```bash
cp shared/commit-msg-hook .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

### Update PR Template
```bash
cp shared/pull_request_template.md .github/
```

### Update CI/CD Pipeline
```bash
# For Flutter
cp shared/../koi-mobile/.github/workflows/flutter-ci.yml .github/workflows/

# For Next.js
cp shared/../koi-web/.github/workflows/nextjs-ci.yml .github/workflows/

# For Firebase
cp shared/../koi-backend/.github/workflows/firebase-ci.yml .github/workflows/
```

---

## 📞 Support & Resources

- **GitHub Documentation**: https://docs.github.com
- **GitFlow Guide**: https://git-flow.readthedocs.io/
- **Conventional Commits**: https://www.conventionalcommits.org/
- **GitHub Actions**: https://github.com/features/actions
- **Organization Docs**: See `SETUP_GUIDE.md` in this directory

---

## 📊 Statistics

**Files Created**: 20+
- Scripts: 3
- Configuration: 8
- Documentation: 9+
- Workflows: 3
- Templates: 2+

**Repositories**: 4
- koi-mobile (Flutter)
- koi-web (Next.js)
- koi-backend (Firebase)
- koi-docs (Documentation)

**Coverage**:
- ✅ Git workflow automation
- ✅ CI/CD pipelines
- ✅ Code quality standards
- ✅ Developer guidelines
- ✅ Issue templates
- ✅ Branch protection
- ✅ Commit validation
- ✅ Code ownership

---

**Last Updated**: May 5, 2026
**Status**: ✅ Complete
**Ready for**: Deployment to koi-fyp organization

# KOI Project - Developer Quick Reference

## 🚀 Essential Commands

### Initial Setup
```bash
# Clone repository
git clone https://github.com/koi-fyp/<repo-name>.git
cd <repo-name>

# Install commit hook
chmod +x .git/hooks/commit-msg

# Configure git
git config core.hooksPath .git/hooks
```

### Creating a Feature
```bash
# Update develop
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feature/feature-name

# Make changes and commit
git add .
git commit -m "feat(scope): description"

# Push and create PR
git push -u origin feature/feature-name
```

### Committing Work
```bash
# Stage changes
git add src/

# Commit with Conventional Commits format
git commit -m "feat(auth): add OAuth login"

# Push to remote
git push origin feature/feature-name
```

### Pulling Latest Changes
```bash
# Fetch latest from remote
git fetch origin

# Update current branch
git pull origin feature/feature-name

# Or rebase (keeps history linear)
git rebase origin/develop
git push -f origin feature/feature-name  # Only if force push allowed
```

---

## 📝 Commit Message Format

### Rules
1. Use **imperative mood**: "add" not "added"
2. Don't capitalize first letter
3. No period at the end
4. Keep subject under 50 characters

### Template
```
<type>(<scope>): <subject>

<optional body>

<optional footer>
```

### Examples

**Feature**:
```
feat(auth): add OAuth login support
```

**Bug Fix**:
```
fix(ui): resolve button alignment on mobile
```

**Documentation**:
```
docs: update API endpoint examples
```

**Refactoring**:
```
refactor(database): simplify query logic
```

**Tests**:
```
test(payment): add credit card validation
```

**Chore**:
```
chore(deps): upgrade React to 18.2.0
```

---

## 🌳 Branch Naming

| Branch | Pattern | Example |
|--------|---------|---------|
| Feature | `feature/*` | `feature/user-auth` |
| Bug Fix | `bugfix/*` | `bugfix/login-issue` |
| Hotfix | `hotfix/*` | `hotfix/payment-crash` |
| Release | `release/*` | `release/1.2.0` |

---

## 🔄 Common Workflows

### Feature Development Flow
```
1. Create branch: git checkout -b feature/my-feature
2. Make changes and commit: git commit -m "feat(scope): ..."
3. Push: git push -u origin feature/my-feature
4. Create PR on GitHub
5. Request review
6. Make requested changes (if any)
7. Merge to develop
```

### Bug Fix Flow
```
1. Create branch: git checkout -b bugfix/bug-name
2. Fix issue: git commit -m "fix(scope): ..."
3. Push: git push -u origin bugfix/bug-name
4. Create PR to develop
5. Get approval and merge
```

### Production Hotfix Flow
```
1. Create from main: git checkout -b hotfix/issue-name main
2. Fix critical issue: git commit -m "fix(scope): ..."
3. Push: git push -u origin hotfix/issue-name
4. Create PR to main (urgent)
5. After merge to main:
   - Tag: git tag -a v1.0.1 -m "Release v1.0.1"
   - Push tag: git push origin v1.0.1
   - Also merge back to develop
```

---

## ⚠️ Common Issues & Solutions

### "Commit message rejected"
**Problem**: Commit message doesn't follow format
**Solution**:
```bash
git commit --amend -m "feat(scope): proper message"
```

### "Branch out of date"
**Problem**: Can't merge PR because branch is behind
**Solution**:
```bash
git fetch origin
git rebase origin/develop
git push -f origin feature/my-feature
```

### "Can't push to main/develop"
**Problem**: Branch protection prevents direct push
**Solution**: Create PR instead
```bash
git push -u origin feature/my-feature
# Create PR on GitHub
```

### "Merge conflict"
**Problem**: Changes conflict with another branch
**Solution**:
```bash
git fetch origin
git rebase origin/develop
# Resolve conflicts in your editor
git add .
git rebase --continue
git push -f origin feature/my-feature
```

### "Accidentally committed to main"
**Problem**: Made commit to main instead of feature branch
**Solution**:
```bash
git log --oneline  # Find the commit hash
git reset --soft HEAD~1  # Undo commit, keep changes
git checkout -b feature/new-branch
git commit -m "feat(scope): ..."
git push -u origin feature/new-branch
```

---

## 🧪 Pre-Commit Testing

### JavaScript/TypeScript
```bash
npm run lint    # Check code style
npm run test    # Run unit tests
npm run build   # Verify build works
```

### Flutter
```bash
flutter analyze      # Check code style
flutter test         # Run unit tests
flutter build apk    # Verify build
```

### Before Pushing
```bash
# Always test locally before pushing
npm run test
git push origin feature/my-feature
```

---

## 📋 Pull Request Checklist

Before submitting a PR, ensure:
- ✅ Code follows style guidelines
- ✅ Tests pass locally (`npm run test` or `flutter test`)
- ✅ No console warnings or errors
- ✅ Commit messages follow Conventional Commits
- ✅ Branch is up to date with target branch
- ✅ PR description is complete
- ✅ No unrelated changes included

---

## 🔐 Security Tips

### Never Commit
- 🚫 `.env` files with secrets
- 🚫 API keys or tokens
- 🚫 Private credentials
- 🚫 Database passwords

### Always Use
- ✅ `.env.example` template
- ✅ GitHub organization secrets for CI/CD
- ✅ Signed commits (GPG)

### If You Accidentally Commit Secrets
```bash
# Remove file from git history
git rm --cached .env
git commit --amend -m "chore: remove .env"

# Or use BFG Repo-Cleaner
bfg --delete-files .env
```

---

## 🎯 Review Process

### Requesting Review
1. Create PR with complete description
2. Click "Reviewers" and select team members
3. Add labels (bug, feature, enhancement, etc.)
4. Link related issues

### Being a Reviewer
1. Read PR description and linked issues
2. Review code for:
   - Correctness
   - Style consistency
   - Test coverage
   - Performance
   - Security
3. Leave constructive comments
4. Approve or request changes

### Addressing Feedback
1. Don't force-push; add new commits
2. Each commit should be a logical change
3. After changes, push and request re-review
4. Thank reviewer for feedback

---

## 📚 Documentation

### Update README When
- Adding new features
- Changing setup process
- Updating dependencies
- Adding environment variables

### Commit Message for Docs
```bash
git commit -m "docs: update README with deployment steps"
```

### Keep Updated
- API documentation
- Setup instructions
- Architecture diagrams
- Deployment procedures

---

## 🤔 When to Create New Branch Types

| Situation | Branch Type | From | To |
|-----------|-------------|------|-----|
| New feature | feature/* | develop | develop |
| Non-critical bug | bugfix/* | develop | develop |
| Critical production bug | hotfix/* | main | main + develop |
| Preparing release | release/* | develop | main |

---

## 📞 Need Help?

- **Branch help**: `git branch --help`
- **Commit help**: `git commit --help`
- **Full guides**: See `CONTRIBUTING.md` in repo
- **Organization docs**: See `repos/SETUP_GUIDE.md`

---

**Branch**: Use `develop` as your main integration branch
**Commit**: Format: `<type>(<scope>): <subject>`
**Review**: Minimum 1 approval before merge
**Test**: Always test locally before pushing

🚀 **Happy coding!**

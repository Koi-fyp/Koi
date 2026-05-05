# Contributing to KOI Project

Thank you for your interest in contributing to the KOI Project! This document provides guidelines and instructions for contributing.

## Table of Contents
- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Documentation](#documentation)

---

## Code of Conduct

We are committed to providing a welcoming and inclusive environment for all contributors. Please:
- Be respectful and constructive in all interactions
- Welcome feedback and ideas from all contributors
- Report any unacceptable behavior to the maintainers

---

## Getting Started

### Prerequisites
- Git installed and configured
- Repository cloned locally
- Appropriate development tools for your repository:
  - **koi-mobile**: Flutter SDK 3.19.0+
  - **koi-web**: Node.js 20+, npm/yarn
  - **koi-backend**: Node.js 20+, Firebase CLI
  - **koi-docs**: Node.js or static site generator tools

### Initial Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/koi-fyp/[repository-name].git
   cd [repository-name]
   ```

2. Create a `.env` file from `.env.example`:
   ```bash
   cp .env.example .env
   ```

3. Install dependencies:
   ```bash
   # For Node.js projects
   npm install

   # For Flutter projects
   flutter pub get
   ```

4. Set up Git hooks:
   ```bash
   # Copy the commit-msg hook
   cp hooks/commit-msg .git/hooks/
   chmod +x .git/hooks/commit-msg
   ```

---

## Development Workflow

### GitFlow Strategy

We follow the GitFlow branching model:

```
main (production)
  ↑
develop (integration)
  ↑
feature/*, hotfix/*, release/*
```

### Branch Naming Conventions

- **Feature branches**: `feature/descriptive-name`
  - Example: `feature/user-authentication`
  - Use for new features and enhancements

- **Bugfix branches**: `bugfix/descriptive-name`
  - Example: `bugfix/login-validation`
  - Use for non-critical bug fixes

- **Hotfix branches**: `hotfix/descriptive-name`
  - Example: `hotfix/payment-processing-crash`
  - Use for critical production fixes (branch from `main`)

- **Release branches**: `release/version-number`
  - Example: `release/1.2.0`
  - Used for release preparation

### Creating a Feature Branch

1. Ensure you're on the `develop` branch:
   ```bash
   git checkout develop
   git pull origin develop
   ```

2. Create and checkout a new feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. Make your changes and commit regularly (see [Commit Guidelines](#commit-guidelines))

4. Push to remote:
   ```bash
   git push -u origin feature/your-feature-name
   ```

---

## Commit Guidelines

### Conventional Commits Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type
- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation only changes
- **style**: Code style changes (formatting, semicolons, etc.) - no logic change
- **refactor**: Code refactoring - no logic change
- **test**: Adding or updating tests
- **chore**: Build process, dependencies, tooling changes
- **ci**: CI/CD configuration changes
- **perf**: Performance improvements
- **build**: Build system changes
- **revert**: Reverts a previous commit

### Scope
The scope specifies what part of the codebase is affected (optional but recommended):
- Examples: `auth`, `api`, `ui`, `database`, `payments`

### Subject
- Use imperative, present tense: "add feature" not "added feature"
- Don't capitalize the first letter
- No period (.) at the end
- Maximum 50 characters

### Examples

✅ Good commits:
```
feat(auth): add OAuth login support
fix(ui): resolve button alignment issue
docs: update API documentation
refactor(database): simplify query logic
test(payment): add credit card validation tests
chore(deps): upgrade React to 18.2.0
ci: add workflow for automated testing
```

❌ Bad commits:
```
added new feature
Fixed bug
UPDATE DOCS
random changes
WIP
```

### Body (Optional)
Explain *what* and *why*, not *how*:
```
feat(payment): implement Stripe integration

Add support for credit card payments through Stripe API.
This enables users to make secure transactions directly
on the platform instead of using external payment links.

Fixes #123
```

### Footer (Optional)
Reference issues and breaking changes:
```
BREAKING CHANGE: changed API response format
Fixes #456
Related to #789
```

---

## Pull Request Process

### Before Creating a PR
1. Ensure your branch is up to date with the target branch:
   ```bash
   git fetch origin
   git rebase origin/develop
   ```

2. Run all checks locally:
   ```bash
   npm run lint      # Linting
   npm run test      # Unit tests
   npm run build     # Build
   ```

3. Push your branch:
   ```bash
   git push origin feature/your-feature-name
   ```

### Creating a PR
1. Go to the repository on GitHub
2. Click "New Pull Request"
3. Select your feature branch to merge into `develop` (or `main` for hotfixes)
4. Fill out the PR template completely
5. Add labels (bug, feature, documentation, etc.)
6. Request reviewers (at least 1)

### PR Requirements
- ✅ All CI/CD checks must pass
- ✅ Minimum 1 approval required
- ✅ Commits follow Conventional Commits format
- ✅ Code follows style guidelines
- ✅ Tests included for new functionality
- ✅ No merge conflicts
- ✅ Documentation updated

### PR Review Process
- Reviewers will check for:
  - Code quality and correctness
  - Test coverage
  - Documentation completeness
  - Security concerns
  - Performance implications
- Address feedback by making additional commits
- Do not force-push; add new commits instead
- Once approved, merge via "Squash and merge" or "Create a merge commit"

---

## Coding Standards

### General Guidelines
- Keep functions small and focused (single responsibility)
- Use meaningful variable and function names
- Add comments for complex logic
- Don't repeat code (DRY principle)
- Write defensive code (validate inputs)

### Language-Specific Standards

#### Dart (Flutter)
- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- Use `const` where applicable
- Format with `dart format`
- Analyze with `flutter analyze`

#### JavaScript/TypeScript (Web & Backend)
- Use ESLint and Prettier for consistency
- Use `const` and `let`, avoid `var`
- Add type annotations (TypeScript)
- Use async/await instead of callbacks

#### Git Commit History
- Keep history clean and meaningful
- Rebase before merging
- Use conventional commits

---

## Testing Requirements

### Unit Tests
- Minimum 80% code coverage for new features
- Run locally before pushing:
  ```bash
  npm run test          # JavaScript/TypeScript
  flutter test          # Flutter
  ```

### Integration Tests
- Test feature interactions
- Mock external dependencies
- Run before PR submission

### Manual Testing
- Test in a real environment
- Include screenshots/videos in PR if applicable
- Document steps to reproduce

### Run All Tests Locally
```bash
# JavaScript/TypeScript
npm run test -- --coverage

# Flutter
flutter test --coverage
```

---

## Documentation

### Code Documentation
- Add JSDoc comments for functions:
  ```javascript
  /**
   * Validates user email format
   * @param {string} email - The email to validate
   * @returns {boolean} True if valid, false otherwise
   */
  function validateEmail(email) { ... }
  ```

- Add inline comments for complex logic:
  ```javascript
  // Retry up to 3 times with exponential backoff
  for (let i = 0; i < 3; i++) { ... }
  ```

### README Updates
- Update README.md for significant features
- Include setup instructions
- Document new environment variables
- Add examples when applicable

### API Documentation
- Document endpoints with request/response examples
- Include error codes and messages
- Update OpenAPI/Swagger specs if applicable

---

## Getting Help

- **Questions?** Open a Discussion on GitHub
- **Found a bug?** Open an Issue with reproduction steps
- **Security concern?** Email maintainers directly (don't open public issue)

---

## License

By contributing, you agree that your contributions will be licensed under the project's license.

---

**Happy contributing! 🚀**

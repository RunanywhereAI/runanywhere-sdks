# Setting Up Pre-commit Hooks

This guide explains how to install and configure pre-commit hooks for the RunAnywhere SDKs project.

## Overview

Pre-commit hooks automatically check your code before each commit to ensure:
- Code quality standards are met
- TODO comments have GitHub issue references
- No large files are accidentally committed
- Files have proper formatting

## Installation

### 1. Install pre-commit

#### macOS (using Homebrew)
```bash
brew install pre-commit
```

#### macOS/Linux (using pip)
```bash
pip install pre-commit
# or
pip3 install pre-commit
```

#### Verify Installation
```bash
pre-commit --version
```

### 2. Install Git Hooks

Navigate to the project root and run:

```bash
# Install pre-commit hooks in your git repository
pre-commit install

# Verify hooks are installed
ls -la .git/hooks/pre-commit
```

For git worktrees, you might need to specify the git directory:
```bash
pre-commit install --git-dir $(git rev-parse --git-dir)
```

### 3. Run Hooks Manually (Optional)

To run all hooks on all files without committing:

```bash
# Run on all files
pre-commit run --all-files

# Run on specific files
pre-commit run --files path/to/file.swift

# Run specific hook
pre-commit run todo-issue-check --all-files
```

## Configured Hooks

Our project uses the following pre-commit hooks:

### 1. General Hooks
- **trailing-whitespace**: Removes trailing whitespace
- **end-of-file-fixer**: Ensures files end with a newline
- **check-yaml**: Validates YAML syntax
- **check-added-large-files**: Prevents large files (>1MB)
- **check-merge-conflict**: Checks for merge conflict markers

### 2. TODO Issue Check
- **todo-issue-check**: Ensures all TODO comments reference a GitHub issue
  - Pattern: `// TODO: #123 - Description`
  - Checks multiple languages: Swift, Kotlin, Java, etc.

### 3. Platform-Specific Linters
- **android-sdk-lint**: Runs Android lint on SDK files
- **android-app-lint**: Runs Android lint on app files
- **ios-sdk-swiftlint**: Runs SwiftLint on SDK files
- **ios-app-swiftlint**: Runs SwiftLint on app files

## Troubleshooting

### Pre-commit not found
If you get "command not found: pre-commit", ensure:
1. pre-commit is installed: `pip3 install pre-commit`
2. Your PATH includes pip's bin directory: `export PATH="$HOME/.local/bin:$PATH"`

### Hooks not running
If hooks don't run on commit:
1. Check if hooks are installed: `ls -la .git/hooks/pre-commit`
2. Reinstall: `pre-commit install --force`
3. Check git config: `git config core.hooksPath`

### Git worktree issues
For git worktrees:
```bash
# Find your git directory
git rev-parse --git-dir

# Install hooks with explicit git-dir
pre-commit install --git-dir $(git rev-parse --git-dir)
```

### SwiftLint not found
If SwiftLint checks fail:
```bash
# Install SwiftLint on macOS
brew install swiftlint
```

### Android lint failures
For Android lint issues:
1. Ensure you have Android SDK installed
2. Run `./gradlew lint` in the Android project directory

## Bypassing Hooks (Emergency Only)

If you absolutely need to commit without running hooks:
```bash
git commit -m "message" --no-verify
```

**⚠️ Warning**: Only use this in emergencies. It's better to fix the issues.

## Updating Hooks

When `.pre-commit-config.yaml` is updated:
```bash
# Update hooks to latest versions
pre-commit autoupdate

# Reinstall hooks
pre-commit install --force
```

## CI Integration

Pre-commit hooks also run in CI/CD pipelines. The configuration skips platform-specific linters in CI as they're handled by dedicated workflows.

## Additional Resources

- [Pre-commit documentation](https://pre-commit.com/)
- [Project TODO Policy](TODO_POLICY.md)
- [Main README](../README.md#code-quality--linting)

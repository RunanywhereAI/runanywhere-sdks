# Swift SDK Scripts

This directory contains utility scripts for the RunAnywhere Swift SDK.

## setup-hooks.sh

Installs and configures pre-commit hooks for code quality enforcement.

### Prerequisites

1. **pre-commit** (required)
   ```bash
   # Using Homebrew
   brew install pre-commit

   # Using pip
   pip install pre-commit

   # Using pipx (recommended)
   pipx install pre-commit
   ```

2. **SwiftLint** (required)
   ```bash
   # Using Homebrew (recommended)
   brew install swiftlint

   # Using Mint
   mint install realm/SwiftLint
   ```

### Usage

Run the setup script from the SDK root directory:

```bash
cd /Users/sanchitmonga/development/ODLM/runanywhere-all/sdks/sdk/runanywhere-swift
./scripts/setup-hooks.sh
```

The script will:
1. Check if pre-commit and SwiftLint are installed
2. Install pre-commit hooks into your Git repository
3. Optionally run pre-commit on all existing files
4. Display usage instructions

### Manual Setup

If you prefer to set up manually:

```bash
# Make the script executable
chmod +x scripts/setup-hooks.sh

# Install hooks
pre-commit install

# Run on all files (optional)
pre-commit run --all-files
```

## Pre-commit Hooks

The following hooks are configured:

### Swift-specific
- **SwiftLint**: Lints Swift code according to `.swiftlint.yml` (runs on commit)
- **SwiftLint AutoFix**: Auto-fixes SwiftLint issues (manual stage only)

### General File Hygiene
- **Trailing Whitespace**: Removes trailing whitespace from all files
- **End of File Fixer**: Ensures files end with a newline
- **Merge Conflict Checker**: Detects merge conflict markers
- **YAML Checker**: Validates YAML file syntax
- **Large File Checker**: Prevents files >1MB from being committed
- **Private Key Detector**: Prevents committing private keys
- **Case Conflict Checker**: Detects case-insensitive filename conflicts
- **Mixed Line Ending Fixer**: Normalizes line endings to LF

## Common Commands

```bash
# Run all hooks manually
pre-commit run --all-files

# Run specific hook
pre-commit run swiftlint --all-files

# Run SwiftLint auto-fix
pre-commit run swiftlint-fix --all-files

# Skip hooks for one commit (use sparingly)
git commit --no-verify -m "Your message"

# Update hooks to latest versions
pre-commit autoupdate

# Uninstall hooks
pre-commit uninstall
```

## Performance Notes

- SwiftLint only checks **staged Swift files** for better performance
- Build artifacts (`.build`, `DerivedData`) are excluded from all checks
- `Package.swift` is excluded from SwiftLint checks (system-generated)

## Troubleshooting

### "swiftlint: command not found"

Install SwiftLint:
```bash
brew install swiftlint
```

### "pre-commit: command not found"

Install pre-commit:
```bash
brew install pre-commit
# or
pip install pre-commit
```

### Hooks not running

Reinstall hooks:
```bash
pre-commit install
```

### Too many SwiftLint errors

Run auto-fix first:
```bash
swiftlint --fix --config .swiftlint.yml
```

Then review and manually fix remaining issues.

## Additional Resources

- [pre-commit documentation](https://pre-commit.com/)
- [SwiftLint documentation](https://github.com/realm/SwiftLint)
- [RunAnywhere Swift SDK SwiftLint configuration](../.swiftlint.yml)

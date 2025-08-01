# Pre-commit Setup Guide

This guide explains how to set up and use pre-commit hooks for the ODLM SDKs project.

## Installation

1. Install pre-commit:
   ```bash
   # Using pip
   pip install pre-commit

   # Using Homebrew (macOS)
   brew install pre-commit
   ```

2. Install SwiftLint (for iOS linting):
   ```bash
   brew install swiftlint
   ```

3. Install the pre-commit hooks:
   ```bash
   pre-commit install
   ```

## What the hooks do

The pre-commit configuration includes:

### General checks:
- Remove trailing whitespace
- Fix end of file issues
- Validate YAML files
- Check for large files (>1MB)
- Check for merge conflicts

### Android linting:
- **SDK**: Runs `./gradlew lint` on the Android SDK module
- **App**: Runs `./gradlew :app:lint` on the Android example app

### iOS linting:
- **SDK**: Runs SwiftLint on the iOS SDK (Swift Package)
- **App**: Runs SwiftLint on the iOS example app

## Manual runs

To run all hooks manually:
```bash
pre-commit run --all-files
```

To run specific hooks:
```bash
# Android SDK lint only
pre-commit run android-sdk-lint --all-files

# iOS App SwiftLint only
pre-commit run ios-app-swiftlint --all-files
```

## Skipping hooks

If you need to commit without running hooks:
```bash
git commit --no-verify
```

## Troubleshooting

1. **SwiftLint not found**: Install SwiftLint using `brew install swiftlint`
2. **Gradle errors**: Ensure you have JDK installed and JAVA_HOME set
3. **Permission errors**: Make sure gradle wrapper is executable: `chmod +x gradlew`

## Note for Xcode users

For the iOS app, you should also add a build phase script to run SwiftLint:
1. Open `RunAnywhereAI.xcodeproj` in Xcode
2. Select the RunAnywhereAI target
3. Go to Build Phases
4. Add a new "Run Script Phase"
5. Add the script: `"${SRCROOT}/swiftlint.sh"`
6. Make sure it runs after "Compile Sources"

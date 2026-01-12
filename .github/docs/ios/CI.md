# iOS SDK CI Pipeline

## Pipeline Steps

| Step | Tool | Purpose | Fails on |
|------|------|---------|----------|
| 1 | SwiftLint --fix | Auto-fix lint issues | Never (best effort) |
| 2 | SwiftLint --strict | Enforce code style | Any violation |
| 3 | Periphery | Detect unused code | Unused code found |
| 4 | swift build | Compile package | Build errors |
| 5 | swift test | Run unit tests | Test failures |
| 6 | xcodebuild | Build for iOS Simulator | Build errors |

## Run Locally

```bash
cd sdk/runanywhere-swift

# Full pipeline
swiftlint --fix --quiet 2>/dev/null || true
swiftlint --strict
periphery scan --targets RunAnywhere --targets ONNXRuntime --targets LlamaCPPRuntime --targets FoundationModelsAdapter --targets FluidAudioDiarization
swift build
swift test
```

## Pre-commit Hooks

```bash
# Install (one time)
pre-commit install

# Run manually
pre-commit run --all-files
```

| Hook | What it does |
|------|--------------|
| `ios-sdk-swiftlint-fix` | Auto-fixes lint issues |
| `ios-sdk-swiftlint` | Fails on lint violations |
| `ios-sdk-periphery` | Fails on unused code |

## Config Files

| File | Purpose |
|------|---------|
| `.swiftlint.yml` | SwiftLint rules |
| `.periphery.yml` | Periphery targets |
| `Package.swift` | Swift package definition |

## Common Fixes

**SwiftLint violation:**
```bash
swiftlint --fix   # Auto-fix what's possible
swiftlint         # See remaining issues
```

**Unused code detected:**
```bash
periphery scan    # See what's unused, then delete it
```

**Build failure:**
```bash
swift build -v 2>&1 | grep error:
```

## Install Tools

```bash
brew install swiftlint
brew install peripheryapp/periphery/periphery
brew install pre-commit
```

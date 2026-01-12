# Swift SDK Scripts

## build-swift.sh

Single entry point for building the RunAnywhere Swift SDK.

### First Time Setup

```bash
cd sdk/runanywhere-swift
./scripts/build-swift.sh --setup
```

This will:
1. Download ONNX Runtime & Sherpa-ONNX
2. Build all XCFrameworks from runanywhere-commons
3. Copy to `Binaries/`
4. Set `testLocal = true` in Package.swift

Takes 5-15 minutes on first run.

### Commands

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup (downloads deps, builds everything) |
| `--local` | Use local frameworks from `Binaries/` |
| `--remote` | Use frameworks from GitHub releases |
| `--build-commons` | Rebuild runanywhere-commons |

### Options

| Option | Description |
|--------|-------------|
| `--clean` | Clean build artifacts |
| `--release` | Build in release mode |
| `--skip-build` | Skip swift build |
| `--set-local` | Set testLocal = true |
| `--set-remote` | Set testLocal = false |

### Examples

```bash
# First time setup
./scripts/build-swift.sh --setup

# After modifying runanywhere-commons
./scripts/build-swift.sh --local --build-commons

# Quick rebuild (frameworks already built)
./scripts/build-swift.sh --local

# Switch to remote mode
./scripts/build-swift.sh --remote
```

### Sample App Workflow

```bash
# 1. Setup Swift SDK first
cd sdk/runanywhere-swift
./scripts/build-swift.sh --setup

# 2. Open sample app
cd ../../examples/ios/RunAnywhereAI
open RunAnywhereAI.xcodeproj

# 3. Reset package cache in Xcode if needed
# 4. Build & Run
```

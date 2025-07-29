# RunAnywhereAI Scripts

This directory contains utility scripts for the RunAnywhereAI iOS application.

## Scripts

### update_model_sizes.sh

A generic script that automatically updates model sizes in `ModelURLRegistry.swift` by fetching actual file sizes from remote URLs.

**Features:**
- Dynamically extracts model IDs and URLs from the Swift file (no hardcoding)
- Fetches actual file sizes from remote servers
- Handles both regular files and HuggingFace directory-based models (.mlpackage)
- Formats sizes in human-readable format (KB, MB, GB)
- Creates automatic backups (configurable)
- Provides detailed progress and summary

**Usage:**
```bash
# Run with automatic backup
./update_model_sizes.sh

# Run without creating backup
./update_model_sizes.sh --no-backup
```

**Requirements:**
- Must be run from the `scripts/` directory
- Requires `curl` and `bc` commands
- Internet connection to fetch file sizes

**How it works:**
1. Parses `ModelURLRegistry.swift` to extract all model definitions
2. For each model with a download URL, fetches the file size via HTTP HEAD request
3. For HuggingFace .mlpackage directories, uses the HuggingFace API to sum all file sizes
4. Updates the size field in the Swift file while preserving all other content
5. Keeps up to 5 most recent backups for safety

### verify_urls.sh

Verifies that all model download URLs in `ModelURLRegistry.swift` are accessible.

**Usage:**
```bash
# Basic verification
./verify_urls.sh

# With HuggingFace authentication
./verify_urls.sh YOUR_HF_TOKEN
```

### build_and_run.sh

Builds and runs the iOS app on simulator or device.

**Usage:**
```bash
# Run on simulator
./build_and_run.sh simulator "iPhone 16 Pro"

# Run on connected device
./build_and_run.sh device
```

### fix_pods_sandbox.sh

Fixes Xcode 16 sandbox issues with CocoaPods. Run after `pod install`.

**Usage:**
```bash
./fix_pods_sandbox.sh
```

## Notes

- Always run scripts from the `scripts/` directory
- The `ModelURLRegistry.swift` file is the single source of truth for all model information
- Model sizes are updated to reflect actual file sizes from remote servers
- Backups are automatically created and managed (keep 5 most recent)
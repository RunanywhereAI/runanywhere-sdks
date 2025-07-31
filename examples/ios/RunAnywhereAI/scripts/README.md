# RunAnywhereAI Scripts

This directory contains utility scripts for the RunAnywhereAI iOS application.

## Scripts

### verify_urls.sh

Verifies that all model download URLs in `ModelURLRegistry.swift` are accessible and optionally updates their sizes.

**Features:**
- Verifies URL accessibility for all models
- Optionally updates model sizes with actual file sizes from remote servers
- Dynamically extracts model information from the Swift file (no hardcoding)
- Handles both regular files and HuggingFace directory-based models (.mlpackage)
- Formats sizes in human-readable format (KB, MB, GB)
- Creates automatic backups when updating sizes
- Supports HuggingFace authentication for private models
- Provides detailed progress and summary

**Usage:**
```bash
# Basic URL verification only
./verify_urls.sh

# Verify URLs and update sizes
./verify_urls.sh --update-sizes

# With HuggingFace authentication
./verify_urls.sh YOUR_HF_TOKEN

# Update sizes with HuggingFace authentication
./verify_urls.sh --update-sizes YOUR_HF_TOKEN
```

**Requirements:**
- Must be run from the `scripts/` directory
- Requires `curl` and `bc` commands
- Internet connection to verify URLs and fetch sizes

**How it works:**
1. Parses `ModelURLRegistry.swift` to extract all model definitions
2. For each model with a download URL, verifies accessibility via HTTP HEAD request
3. When `--update-sizes` is used:
   - Fetches actual file sizes from remote servers
   - For HuggingFace .mlpackage directories, uses the HuggingFace API to sum all file sizes
   - Updates the size field in the Swift file while preserving all other content
   - Creates a backup before making changes
4. Provides a summary of accessible/failed URLs and any size updates

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
#!/usr/bin/env bash
# =============================================================================
# RunAnywhere Swift SDK Release Script
# =============================================================================
#
# Creates a production release from an existing test release.
#
# WORKFLOW:
#   1. Download assets from source test release
#   2. Calculate SHA256 checksums
#   3. Update root Package.swift with version and checksums
#   4. Commit, tag, and push
#   5. Create GitHub release with assets
#
# USAGE:
#   ./scripts/release-swift-sdk.sh --version VERSION --source-release TAG [OPTIONS]
#
# OPTIONS:
#   --version VERSION       Version to release (e.g., 0.17.0)
#   --source-release TAG    Source release to copy assets from (e.g., v0.16.0-test.53)
#   --dry-run               Validate only, don't modify anything
#   --help                  Show this help
#
# EXAMPLES:
#   # Release v0.17.0 using assets from v0.16.0-test.53
#   ./scripts/release-swift-sdk.sh --version 0.17.0 --source-release v0.16.0-test.53
#
#   # Dry run
#   ./scripts/release-swift-sdk.sh --version 0.17.0 --source-release v0.16.0-test.53 --dry-run
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SDK_ROOT}/../.." && pwd)"

GITHUB_REPO="RunanywhereAI/runanywhere-sdks"

# Arguments
VERSION=""
SOURCE_RELEASE=""
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()  { echo -e "${RED}[X]${NC} $1"; }
log_step()   { echo -e "${BLUE}==>${NC} $1"; }
log_header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

show_help() {
    head -35 "$0" | tail -30
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --source-release)
            SOURCE_RELEASE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            ;;
    esac
done

# Validate arguments
if [[ -z "$VERSION" ]]; then
    log_error "Missing --version"
    show_help
fi

if [[ -z "$SOURCE_RELEASE" ]]; then
    log_error "Missing --source-release"
    show_help
fi

# Validate prerequisites
validate() {
    log_header "Validating"

    # Check tools
    for tool in gh git curl shasum; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "Missing tool: $tool"
            exit 1
        fi
    done
    log_info "Required tools available"

    # Check GitHub auth
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI not authenticated. Run: gh auth login"
        exit 1
    fi
    log_info "GitHub CLI authenticated"

    # Check source release exists
    if ! gh release view "$SOURCE_RELEASE" --repo "$GITHUB_REPO" &>/dev/null; then
        log_error "Source release not found: $SOURCE_RELEASE"
        exit 1
    fi
    log_info "Source release found: $SOURCE_RELEASE"

    # Check target release doesn't exist
    if gh release view "v$VERSION" --repo "$GITHUB_REPO" &>/dev/null; then
        log_error "Target release already exists: v$VERSION"
        exit 1
    fi
    log_info "Target release available: v$VERSION"
}

# Download and calculate checksums
calculate_checksums() {
    log_header "Calculating Checksums"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    cd "$tmp_dir"

    # Download iOS assets from source release
    local assets=("RACommons-ios" "RABackendLLAMACPP-ios" "RABackendONNX-ios")
    local source_version="${SOURCE_RELEASE#v}"

    for asset_prefix in "${assets[@]}"; do
        local asset_name="${asset_prefix}-v${source_version}.zip"
        local url="https://github.com/$GITHUB_REPO/releases/download/$SOURCE_RELEASE/$asset_name"

        log_step "Downloading: $asset_name"
        if ! curl -sL "$url" -o "$asset_name"; then
            log_error "Failed to download: $url"
            exit 1
        fi
    done

    # Calculate checksums
    log_step "Calculating SHA256 checksums..."

    CHECKSUM_RACOMMONS=$(shasum -a 256 "RACommons-ios-v${source_version}.zip" | awk '{print $1}')
    CHECKSUM_LLAMACPP=$(shasum -a 256 "RABackendLLAMACPP-ios-v${source_version}.zip" | awk '{print $1}')
    CHECKSUM_ONNX=$(shasum -a 256 "RABackendONNX-ios-v${source_version}.zip" | awk '{print $1}')

    log_info "RACommons:   $CHECKSUM_RACOMMONS"
    log_info "LlamaCPP:    $CHECKSUM_LLAMACPP"
    log_info "ONNX:        $CHECKSUM_ONNX"

    # Store asset paths for later upload
    ASSET_RACOMMONS="$tmp_dir/RACommons-ios-v${source_version}.zip"
    ASSET_LLAMACPP="$tmp_dir/RABackendLLAMACPP-ios-v${source_version}.zip"
    ASSET_ONNX="$tmp_dir/RABackendONNX-ios-v${source_version}.zip"

    # Rename assets for new version
    mv "RACommons-ios-v${source_version}.zip" "RACommons-ios-v${VERSION}.zip"
    mv "RABackendLLAMACPP-ios-v${source_version}.zip" "RABackendLLAMACPP-ios-v${VERSION}.zip"
    mv "RABackendONNX-ios-v${source_version}.zip" "RABackendONNX-ios-v${VERSION}.zip"

    ASSET_RACOMMONS="$tmp_dir/RACommons-ios-v${VERSION}.zip"
    ASSET_LLAMACPP="$tmp_dir/RABackendLLAMACPP-ios-v${VERSION}.zip"
    ASSET_ONNX="$tmp_dir/RABackendONNX-ios-v${VERSION}.zip"

    cd - >/dev/null
}

# Update Package.swift
update_package_swift() {
    log_header "Updating Package.swift"

    local package_file="$REPO_ROOT/Package.swift"

    if [[ ! -f "$package_file" ]]; then
        log_error "Package.swift not found at: $package_file"
        exit 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN - Would update Package.swift with:"
        echo "  sdkVersion = \"$VERSION\""
        echo "  RACommons checksum = $CHECKSUM_RACOMMONS"
        echo "  LlamaCPP checksum = $CHECKSUM_LLAMACPP"
        echo "  ONNX checksum = $CHECKSUM_ONNX"
        return
    fi

    # Update version
    sed -i '' "s/let sdkVersion = \"[^\"]*\"/let sdkVersion = \"$VERSION\"/" "$package_file"
    log_info "Updated sdkVersion to $VERSION"

    # Update checksums
    sed -i '' "s/checksum: \"CHECKSUM_RACOMMONS\"/checksum: \"$CHECKSUM_RACOMMONS\"/" "$package_file"
    sed -i '' "s/checksum: \"CHECKSUM_LLAMACPP\"/checksum: \"$CHECKSUM_LLAMACPP\"/" "$package_file"
    sed -i '' "s/checksum: \"CHECKSUM_ONNX\"/checksum: \"$CHECKSUM_ONNX\"/" "$package_file"

    # Also update if they have old checksums (not placeholders)
    # Match pattern: checksum: "64 hex characters"
    local old_racommons_line
    old_racommons_line=$(grep -n "RACommons-ios-v" "$package_file" | head -1 | cut -d: -f1)
    if [[ -n "$old_racommons_line" ]]; then
        local checksum_line=$((old_racommons_line + 1))
        sed -i '' "${checksum_line}s/checksum: \"[a-f0-9]\{64\}\"/checksum: \"$CHECKSUM_RACOMMONS\"/" "$package_file"
    fi

    log_info "Updated checksums in Package.swift"

    # Also update VERSION file
    echo "$VERSION" > "$SDK_ROOT/VERSION"
    log_info "Updated VERSION file"
}

# Commit and tag
commit_and_tag() {
    log_header "Creating Git Commit and Tag"

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN - Would create:"
        echo "  Commit: chore(swift): release v$VERSION"
        echo "  Tag: v$VERSION"
        return
    fi

    cd "$REPO_ROOT"

    # Stage changes
    git add Package.swift sdk/runanywhere-swift/VERSION 2>/dev/null || true

    # Commit if there are changes
    if ! git diff --staged --quiet; then
        git commit -m "chore(swift): release v$VERSION

- Updated sdkVersion to $VERSION
- Updated binary checksums from $SOURCE_RELEASE"
        log_info "Created commit"
    else
        log_info "No changes to commit"
    fi

    # Create tag
    git tag -a "v$VERSION" -m "RunAnywhere SDK v$VERSION"
    log_info "Created tag: v$VERSION"
}

# Push and create release
push_and_release() {
    log_header "Pushing and Creating Release"

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN - Would:"
        echo "  - Push to origin"
        echo "  - Create release v$VERSION with iOS assets"
        return
    fi

    cd "$REPO_ROOT"

    # Push
    log_step "Pushing commits and tag..."
    git push origin HEAD
    git push origin "v$VERSION"
    log_info "Pushed to GitHub"

    # Create release
    log_step "Creating GitHub release..."
    gh release create "v$VERSION" \
        --repo "$GITHUB_REPO" \
        --title "RunAnywhere SDK v$VERSION" \
        --notes "## RunAnywhere SDK v$VERSION

Privacy-first, on-device AI SDK for iOS, Android, Flutter, and React Native.

### Swift Installation (SPM)

\`\`\`swift
dependencies: [
    .package(url: \"https://github.com/$GITHUB_REPO\", from: \"$VERSION\")
]
\`\`\`

### Features
- LLM: On-device text generation via llama.cpp
- STT: Speech-to-text via Sherpa-ONNX Whisper
- TTS: Text-to-speech via Sherpa-ONNX Piper
- VAD: Voice activity detection
- Privacy: All processing happens on-device

### iOS Assets
- RACommons-ios-v$VERSION.zip
- RABackendLLAMACPP-ios-v$VERSION.zip
- RABackendONNX-ios-v$VERSION.zip

---
Based on: $SOURCE_RELEASE
" \
        "$ASSET_RACOMMONS" \
        "$ASSET_LLAMACPP" \
        "$ASSET_ONNX"

    log_info "Created release: v$VERSION"
    log_info "URL: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
}

# Summary
print_summary() {
    log_header "Summary"

    echo ""
    echo "Version:        $VERSION"
    echo "Source Release: $SOURCE_RELEASE"
    echo "Repository:     https://github.com/$GITHUB_REPO"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN - No changes made"
        echo ""
        echo "To execute for real, remove --dry-run flag"
    else
        log_info "Release complete!"
        echo ""
        echo "Users can now install with:"
        echo ""
        echo "  .package(url: \"https://github.com/$GITHUB_REPO\", from: \"$VERSION\")"
        echo ""
        echo "Or in Xcode:"
        echo "  File > Add Package Dependencies"
        echo "  URL: https://github.com/$GITHUB_REPO"
        echo "  Version: $VERSION"
    fi
}

# Main
main() {
    log_header "RunAnywhere Swift SDK Release"
    echo ""
    echo "Version:        $VERSION"
    echo "Source Release: $SOURCE_RELEASE"
    echo "Dry Run:        $DRY_RUN"

    validate
    calculate_checksums
    update_package_swift
    commit_and_tag
    push_and_release
    print_summary
}

main "$@"

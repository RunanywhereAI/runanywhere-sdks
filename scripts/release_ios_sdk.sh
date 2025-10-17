#!/bin/bash

# RunAnywhere iOS SDK Release Script
# This script automates the release process for the iOS SDK

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SDK_DIR="sdk/runanywhere-swift"
VERSION_FILE="$SDK_DIR/VERSION"
CHANGELOG_FILE="$SDK_DIR/CHANGELOG.md"
README_ROOT="README.md"
README_SDK="$SDK_DIR/README.md"

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Validate preconditions
validate_preconditions() {
    print_header "Validating Preconditions"

    # Check if we're in the right directory
    if [ ! -f "Package.swift" ] || [ ! -d "$SDK_DIR" ]; then
        print_error "Must be run from repository root"
        exit 1
    fi
    print_success "Running from repository root"

    # Check if git is clean
    if [ -n "$(git status --porcelain)" ]; then
        print_error "Git working directory is not clean"
        print_info "Commit or stash your changes first"
        git status --short
        exit 1
    fi
    print_success "Git working directory is clean"

    # Check if on main branch
    CURRENT_BRANCH=$(git branch --show-current)
    if [ "$CURRENT_BRANCH" != "main" ]; then
        print_warning "You are on branch '$CURRENT_BRANCH', not 'main'"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted by user"
            exit 1
        fi
    else
        print_success "On main branch"
    fi

    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        print_info "Install it with: brew install gh"
        exit 1
    fi
    print_success "GitHub CLI is installed"

    # Check if authenticated with gh
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub CLI"
        print_info "Run: gh auth login"
        exit 1
    fi
    print_success "Authenticated with GitHub CLI"
}

# Get current version
get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "0.14.0"  # Fallback to last known version
    fi
}

# Calculate new version
calculate_new_version() {
    local current_version=$1
    local bump_type=$2

    IFS='.' read -r -a version_parts <<< "$current_version"
    local major="${version_parts[0]}"
    local minor="${version_parts[1]}"
    local patch="${version_parts[2]}"

    case $bump_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            print_error "Invalid bump type: $bump_type"
            exit 1
            ;;
    esac

    echo "$major.$minor.$patch"
}

# Update version in files
update_version_references() {
    local new_version=$1

    print_header "Updating Version References"

    # Update VERSION file
    echo "$new_version" > "$VERSION_FILE"
    print_success "Updated $VERSION_FILE"

    # Update root README.md
    if [ -f "$README_ROOT" ]; then
        sed -i '' "s/from: \"[0-9]*\.[0-9]*\.[0-9]*\"/from: \"$new_version\"/g" "$README_ROOT"
        sed -i '' "s/exact: \"[0-9]*\.[0-9]*\.[0-9]*\"/exact: \"$new_version\"/g" "$README_ROOT"
        sed -i '' "s/'RunAnywhere', '~> [0-9]*\.[0-9]*'/'RunAnywhere', '~> ${new_version%.*}'/g" "$README_ROOT"
        sed -i '' "s/'RunAnywhere', '[0-9]*\.[0-9]*\.[0-9]*'/'RunAnywhere', '$new_version'/g" "$README_ROOT"
        print_success "Updated $README_ROOT"
    fi

    # Update SDK README.md
    if [ -f "$README_SDK" ]; then
        sed -i '' "s/from: \"[0-9]*\.[0-9]*\.[0-9]*\"/from: \"$new_version\"/g" "$README_SDK"
        sed -i '' "s/exact: \"[0-9]*\.[0-9]*\.[0-9]*\"/exact: \"$new_version\"/g" "$README_SDK"
        print_success "Updated $README_SDK"
    fi

    # Update CHANGELOG.md - move [Unreleased] to new version
    if [ -f "$CHANGELOG_FILE" ]; then
        local today=$(date +%Y-%m-%d)
        # Replace ## [Unreleased] with ## [version] - date, and add new [Unreleased] section
        sed -i '' "s/## \[Unreleased\]/## [Unreleased]\n\n## [$new_version] - $today/g" "$CHANGELOG_FILE"
        print_success "Updated $CHANGELOG_FILE"
    fi
}

# Run tests
run_tests() {
    print_header "Running Tests"

    print_info "Building package..."
    if swift build --target RunAnywhere; then
        print_success "Package builds successfully"
    else
        print_error "Package build failed"
        exit 1
    fi

    # Note: Add actual tests when they exist
    # if swift test; then
    #     print_success "All tests passed"
    # else
    #     print_error "Tests failed"
    #     exit 1
    # fi
}

# Create git tag and push
create_release() {
    local new_version=$1
    local tag_name="v$new_version"

    print_header "Creating Release"

    # Commit changes
    git add "$VERSION_FILE" "$CHANGELOG_FILE" "$README_ROOT" "$README_SDK"
    git commit -m "Release v$new_version

- Updated version to $new_version
- Updated documentation
- See CHANGELOG.md for details"
    print_success "Created release commit"

    # Create annotated tag
    git tag -a "$tag_name" -m "Release v$new_version"
    print_success "Created tag $tag_name"

    # Push commit and tag
    print_info "Pushing to GitHub..."
    git push origin HEAD
    git push origin "$tag_name"
    print_success "Pushed commit and tag to GitHub"
}

# Create GitHub release
create_github_release() {
    local new_version=$1
    local tag_name="v$new_version"

    print_header "Creating GitHub Release"

    # Extract release notes from CHANGELOG
    local release_notes=$(sed -n "/## \[$new_version\]/,/## \[/p" "$CHANGELOG_FILE" | sed '$d' | tail -n +2)

    # Create GitHub release
    print_info "Creating GitHub release..."
    gh release create "$tag_name" \
        --title "RunAnywhere iOS SDK v$new_version" \
        --notes "$release_notes" \
        --latest

    print_success "GitHub release created: https://github.com/RunanywhereAI/sdks/releases/tag/$tag_name"
}

# Main script
main() {
    print_header "RunAnywhere iOS SDK Release"

    # Validate preconditions
    validate_preconditions

    # Get current version
    CURRENT_VERSION=$(get_current_version)
    print_info "Current version: $CURRENT_VERSION"

    # Ask for bump type
    echo ""
    echo "Select version bump type:"
    echo "  1) patch (bug fixes)           - $CURRENT_VERSION -> $(calculate_new_version "$CURRENT_VERSION" "patch")"
    echo "  2) minor (new features)        - $CURRENT_VERSION -> $(calculate_new_version "$CURRENT_VERSION" "minor")"
    echo "  3) major (breaking changes)    - $CURRENT_VERSION -> $(calculate_new_version "$CURRENT_VERSION" "major")"
    echo ""
    read -p "Enter choice (1-3): " choice

    case $choice in
        1) BUMP_TYPE="patch" ;;
        2) BUMP_TYPE="minor" ;;
        3) BUMP_TYPE="major" ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac

    # Calculate new version
    NEW_VERSION=$(calculate_new_version "$CURRENT_VERSION" "$BUMP_TYPE")

    # Confirm release
    echo ""
    print_warning "About to release v$NEW_VERSION (was $CURRENT_VERSION)"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Release cancelled by user"
        exit 0
    fi

    # Update version references
    update_version_references "$NEW_VERSION"

    # Run tests
    run_tests

    # Create release
    create_release "$NEW_VERSION"

    # Create GitHub release
    create_github_release "$NEW_VERSION"

    # Success!
    print_header "Release Complete!"
    print_success "Released v$NEW_VERSION successfully"
    print_info "Users can now install with:"
    echo ""
    echo "  dependencies: ["
    echo "      .package(url: \"https://github.com/RunanywhereAI/sdks\", from: \"$NEW_VERSION\")"
    echo "  ]"
    echo ""
    print_info "View release: https://github.com/RunanywhereAI/sdks/releases/tag/v$NEW_VERSION"
}

# Run main function
main "$@"

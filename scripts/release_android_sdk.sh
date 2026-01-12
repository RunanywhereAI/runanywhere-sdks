#!/usr/bin/env bash
# RunAnywhere Android SDK Release Script
# Based on iOS SDK release script pattern
# Automates version bumping, CHANGELOG updates, git tagging, and GitHub releases

set -euo pipefail

### Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}=== $* ===${NC}\n"; }
print_success() { echo -e "${GREEN}✔ $*${NC}"; }
print_error() { echo -e "${RED}✗ $*${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $*${NC}"; }
print_info() { echo -e "${BLUE}ℹ $*${NC}"; }

### Configuration
SDK_DIR="sdk/runanywhere-kotlin"
BUILD_FILE="$SDK_DIR/build.gradle.kts"
CHANGELOG_FILE="$SDK_DIR/CHANGELOG.md"
README_ROOT="README.md"
README_SDK="$SDK_DIR/README.md"

### Portable sed (GNU vs BSD)
sedi() {
    if sed --version >/dev/null 2>&1; then
        # GNU sed
        sed -i "$@"
    else
        # BSD sed (macOS)
        sed -i '' "$@"
    fi
}

### CLI flags
AUTO_YES=0
BUMP_TYPE=""
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            AUTO_YES=1
            shift
            ;;
        --bump)
            BUMP_TYPE="${2:-}"
            if [[ -z "$BUMP_TYPE" ]]; then
                print_error "--bump requires a value (major, minor, or patch)"
                exit 1
            fi
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --yes, -y          Auto-confirm all prompts"
            echo "  --bump TYPE        Version bump type: major, minor, or patch"
            echo "  --skip-build       Skip build verification"
            echo "  --help, -h         Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

### Validate preconditions
validate_preconditions() {
    print_header "Validating Preconditions"

    # Must run at repo root
    if [[ ! -d "$SDK_DIR" ]]; then
        print_error "SDK directory not found: $SDK_DIR"
        print_info "Must run from repository root"
        exit 1
    fi
    print_success "Running from repository root"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "Not in a git repository"
        exit 1
    fi

    # Check if working directory is clean
    if [[ -n "$(git status --porcelain)" ]]; then
        print_error "Working directory is not clean"
        print_info "Please commit or stash your changes before releasing"
        exit 1
    fi

    # Check if we're on main branch
    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "$current_branch" != "main" ]]; then
        print_warning "Not on main branch (currently on: $current_branch)"
        if [[ $AUTO_YES -ne 1 ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Release cancelled"
                exit 0
            fi
        fi
    fi

    # Check if GitHub CLI is installed
    if ! command -v gh >/dev/null 2>&1; then
        print_error "GitHub CLI (gh) is not installed"
        print_info "Install it from: https://cli.github.com/"
        exit 1
    fi

    # Check if gh is authenticated
    if ! gh auth status >/dev/null 2>&1; then
        print_error "GitHub CLI is not authenticated"
        print_info "Run: gh auth login"
        exit 1
    fi

    # Check if build.gradle.kts exists
    if [[ ! -f "$BUILD_FILE" ]]; then
        print_error "Build file not found: $BUILD_FILE"
        exit 1
    fi

    print_success "All preconditions met"
}

### Get current version from build.gradle.kts
get_current_version() {
    if [[ ! -f "$BUILD_FILE" ]]; then
        echo "0.1.0"  # Fallback
        return
    fi

    # Try to extract version with double quotes first
    local version
    version=$(grep -E "^\s*version\s*=" "$BUILD_FILE" | sed -E 's/.*version\s*=\s*"([^"]+)".*/\1/' | head -1)

    # If not found, try single quotes
    if [[ -z "$version" ]] || [[ "$version" == *"version"* ]]; then
        version=$(grep -E "^\s*version\s*=" "$BUILD_FILE" | sed -E "s/.*version\s*=\s*'([^']+)'.*/\1/" | head -1)
    fi

    # Validate version format (semver: x.y.z)
    if [[ -z "$version" ]] || [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_error "Failed to extract version from $BUILD_FILE"
        print_error "Expected format: version = \"x.y.z\" or version = 'x.y.z'"
        exit 1
    fi

    echo "$version"
}

### Calculate new version based on bump type
calculate_new_version() {
    local current="$1"
    local bump="$2"

    IFS='.' read -r major minor patch <<<"$current"

    case "$bump" in
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
            print_error "Invalid bump type: $bump (expected: major, minor, or patch)"
            exit 1
            ;;
    esac

    echo "$major.$minor.$patch"
}

### Update version references in files
update_version_references() {
    local new_version="$1"

    print_header "Updating Version References"

    # Update build.gradle.kts
    if [[ -f "$BUILD_FILE" ]]; then
        sedi "s/version = \"[0-9]*\.[0-9]*\.[0-9]*\"/version = \"$new_version\"/g" "$BUILD_FILE"
        print_success "Updated $BUILD_FILE"
    fi

    # Update root README.md (if it has Android version references)
    if [[ -f "$README_ROOT" ]]; then
        sedi "s/com\.runanywhere\.sdk:runanywhere-kotlin:[0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}/com.runanywhere.sdk:runanywhere-kotlin:$new_version/g" "$README_ROOT" || true
        print_success "Updated $README_ROOT"
    fi

    # Update SDK README.md
    if [[ -f "$README_SDK" ]]; then
        sedi "s/com\.runanywhere\.sdk:runanywhere-kotlin:[0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}/com.runanywhere.sdk:runanywhere-kotlin:$new_version/g" "$README_SDK" || true
        print_success "Updated $README_SDK"
    fi

    # Update CHANGELOG.md
    if [[ -f "$CHANGELOG_FILE" ]]; then
        local today
        today="$(date +%Y-%m-%d)"
        sedi "s/## \[Unreleased\]/## [Unreleased]\n\n## [$new_version] - $today/g" "$CHANGELOG_FILE"
        print_success "Updated $CHANGELOG_FILE"
    fi
}

### Run tests and build
run_tests() {
    if [[ $SKIP_BUILD -eq 1 ]]; then
        print_warning "Skipping build check (--skip-build flag)"
        return
    fi

    print_header "Building and Testing"

    print_info "Running SDK build..."
    (
        cd "$SDK_DIR" || { print_error "Failed to change to $SDK_DIR"; exit 1; }
        # Use sdk.sh wrapper if available, otherwise fall back to direct gradlew
        if [[ -f "./scripts/sdk.sh" ]]; then
            if ! ./scripts/sdk.sh build-all; then
                print_error "Build failed"
                exit 1
            fi
            print_success "Build successful"

            print_info "Running tests..."
            if ! ./scripts/sdk.sh test; then
                print_error "Tests failed"
                exit 1
            fi
        else
            # Fallback to direct gradlew if sdk.sh not found
            print_warning "sdk.sh not found, using direct gradlew"
            if ! ./gradlew build --no-daemon; then
                print_error "Build failed"
                exit 1
            fi
            print_success "Build successful"

            print_info "Running tests..."
            if ! ./gradlew test --no-daemon; then
                print_error "Tests failed"
                exit 1
            fi
        fi
        print_success "All tests passed"
    )
}

### Create GitHub release
create_github_release() {
    local new_version="$1"
    local tag_name="android/v$new_version"

    print_header "Creating GitHub Release"

    # Extract release notes from CHANGELOG
    local release_notes=""
    if [[ -f "$CHANGELOG_FILE" ]]; then
        release_notes="$(sed -n "/## \[$new_version\]/,/^## \[/p" "$CHANGELOG_FILE" | sed '$d' | tail -n +2)"
    fi

    # Fallback if no notes found
    if [[ -z "$release_notes" ]]; then
        release_notes="Android SDK v$new_version"
    fi

    # Create GitHub release
    print_info "Creating GitHub release..."
    gh release create "$tag_name" \
        --title "RunAnywhere Android SDK v$new_version" \
        --notes "$release_notes" \
        --latest

    print_success "GitHub release created: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/$tag_name"
}

### Main release process
main() {
    print_header "RunAnywhere Android SDK Release"

    # Validate everything first
    validate_preconditions

    # Get current version
    local current_version
    current_version="$(get_current_version)"
    print_info "Current version: $current_version"

    # Determine bump type
    if [[ -z "$BUMP_TYPE" ]]; then
        echo ""
        echo "Select version bump type:"
        echo "  1) patch (bug fixes)           - $current_version -> $(calculate_new_version "$current_version" "patch")"
        echo "  2) minor (new features)        - $current_version -> $(calculate_new_version "$current_version" "minor")"
        echo "  3) major (breaking changes)    - $current_version -> $(calculate_new_version "$current_version" "major")"
        echo ""

        if [[ $AUTO_YES -ne 1 ]]; then
            read -p "Enter choice (1-3): " choice
        else
            choice=1  # Default to patch in auto mode
        fi

        case "${choice:-1}" in
            1) BUMP_TYPE="patch" ;;
            2) BUMP_TYPE="minor" ;;
            3) BUMP_TYPE="major" ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi

    # Calculate new version
    local new_version
    new_version="$(calculate_new_version "$current_version" "$BUMP_TYPE")"

    # Confirm release
    print_warning "About to release v$new_version (was $current_version)"
    if [[ $AUTO_YES -ne 1 ]]; then
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Release cancelled by user"
            exit 0
        fi
    fi

    # Run tests before making any changes
    run_tests

    # Step 1: Update version files and commit to main
    print_header "Step 1: Committing Version Updates to Main"
    update_version_references "$new_version"

    local paths_to_add=("$BUILD_FILE")
    [[ -f "$CHANGELOG_FILE" ]] && paths_to_add+=("$CHANGELOG_FILE")
    [[ -f "$README_ROOT" ]] && paths_to_add+=("$README_ROOT")
    [[ -f "$README_SDK" ]] && paths_to_add+=("$README_SDK")

    git add "${paths_to_add[@]}"
    git commit -m "chore: bump Android SDK version to $new_version"

    print_success "Version updates committed to main"

    # Step 2: Push to GitHub
    print_header "Step 2: Pushing to GitHub"
    git push origin main
    print_success "Pushed to GitHub"

    # Step 3: Create tag
    print_header "Step 3: Creating Git Tag"
    local tag_name="android/v$new_version"
    git tag -a "$tag_name" -m "Android SDK v$new_version"
    git push origin "$tag_name"
    print_success "Created and pushed tag: $tag_name"

    # Step 4: Create GitHub release
    create_github_release "$new_version"

    # Summary
    print_header "Release Complete!"
    print_success "Released Android SDK v$new_version successfully"
    echo ""
    print_info "Next steps:"
    echo "  1. Verify the GitHub release: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/$tag_name"
    echo "  2. Publish to Maven Central (if configured)"
    echo "  3. Update documentation if needed"
    echo ""
}

# Run main function
main

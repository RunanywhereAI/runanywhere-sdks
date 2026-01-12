#!/usr/bin/env bash
# RunAnywhere iOS SDK Release Script
# Combines best practices from both approaches:
# - Git worktree for clean tag commits (no spurious commits on main)
# - Portable sed for GNU/BSD compatibility
# - CLI flags for CI automation (--yes, --bump)
# - BuildToken.swift in tags only (via .gitignore)

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
SDK_DIR="sdk/runanywhere-swift"
VERSION_FILE="$SDK_DIR/VERSION"
CHANGELOG_FILE="$SDK_DIR/CHANGELOG.md"
README_ROOT="README.md"
README_SDK="$SDK_DIR/README.md"
DEV_CONFIG_REL_PATH="Sources/RunAnywhere/Foundation/Constants/DevelopmentConfig.swift"
DEV_CONFIG_ABS_PATH="$SDK_DIR/$DEV_CONFIG_REL_PATH"
SECRETS_FILE="scripts/.release-secrets"

# These will be loaded from secrets file or environment
SUPABASE_URL=""
SUPABASE_ANON_KEY=""

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

### Load secrets from file or environment
load_secrets() {
  print_header "Loading Release Secrets"

  # Try to load from secrets file first
  if [[ -f "$SECRETS_FILE" ]]; then
    print_info "Loading secrets from $SECRETS_FILE"
    # Source the file to get variables (only SUPABASE_URL and SUPABASE_ANON_KEY)
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
  fi

  # Environment variables override file values (useful for CI)
  SUPABASE_URL="${SUPABASE_URL:-}"
  SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

  # Validate required secrets
  local missing_secrets=0

  if [[ -z "$SUPABASE_URL" ]]; then
    print_error "Missing SUPABASE_URL"
    missing_secrets=1
  else
    print_success "SUPABASE_URL: ${SUPABASE_URL:0:40}..."
  fi

  if [[ -z "$SUPABASE_ANON_KEY" ]]; then
    print_error "Missing SUPABASE_ANON_KEY"
    missing_secrets=1
  else
    print_success "SUPABASE_ANON_KEY: ${SUPABASE_ANON_KEY:0:20}..."
  fi

  if [[ $missing_secrets -eq 1 ]]; then
    echo ""
    print_error "Missing required secrets!"
    print_info "Option 1: Ensure scripts/.release-secrets exists with:"
    echo "  SUPABASE_URL=\"https://your-project.supabase.co\""
    echo "  SUPABASE_ANON_KEY=\"your-anon-key\""
    echo ""
    print_info "Option 2: Set environment variables:"
    echo "  export SUPABASE_URL=\"https://your-project.supabase.co\""
    echo "  export SUPABASE_ANON_KEY=\"your-anon-key\""
    echo ""
    exit 1
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
      echo "  --yes, -y           Auto-confirm prompts (for CI)"
      echo "  --bump TYPE         Version bump type: major|minor|patch"
      echo "  --skip-build        Skip build check (for testing)"
      echo "  --help, -h          Show this help"
      echo ""
      echo "Secrets (required - use ONE of these methods):"
      echo ""
      echo "  Method 1: Secrets file (for local dev)"
      echo "    Ensure scripts/.release-secrets exists with SUPABASE_URL and SUPABASE_ANON_KEY"
      echo ""
      echo "  Method 2: Environment variables (for CI)"
      echo "    export SUPABASE_URL=\"https://your-project.supabase.co\""
      echo "    export SUPABASE_ANON_KEY=\"your-anon-key\""
      echo ""
      echo "Other Environment Variables:"
      echo "  DATABASE_URL        PostgreSQL URL for auto-inserting build token"
      echo ""
      exit 0
      ;;
    *)
      print_warning "Unknown argument: $1 (use --help for usage)"
      shift
      ;;
  esac
done

### Validate preconditions
validate_preconditions() {
    print_header "Validating Preconditions"

    # Must run at repo root
    if [[ ! -f "Package.swift" || ! -d "$SDK_DIR" ]]; then
        print_error "Must run from repository root (expected Package.swift and $SDK_DIR)"
        exit 1
    fi
    print_success "Running from repository root"

    # Git working directory must be clean
    if [[ -n "$(git status --porcelain)" ]]; then
        print_error "Git working directory is not clean"
        print_info "Commit or stash your changes first"
        git status --short
        exit 1
    fi
    print_success "Git working directory is clean"

    # Warn if not on main branch
    CURRENT_BRANCH="$(git branch --show-current)"
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        print_warning "You are on branch '$CURRENT_BRANCH', not 'main'"
        if [[ $AUTO_YES -ne 1 ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Aborted by user"
                exit 1
            fi
        fi
    else
        print_success "On main branch"
    fi

    # Check required tools
    local required_tools=("gh" "git" "swift" "uuidgen")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null; then
            print_error "Required tool not found: $tool"
            exit 1
        fi
    done
    print_success "All required tools available"

    # Check GitHub CLI authentication
    if ! gh auth status &>/dev/null; then
        print_error "Not authenticated with GitHub CLI"
        print_info "Run: gh auth login"
        exit 1
    fi
    print_success "Authenticated with GitHub CLI"

    # Check for psql if DATABASE_URL is set
    if [[ -n "${DATABASE_URL:-}" ]] && ! command -v psql >/dev/null; then
        print_warning "DATABASE_URL is set but psql not found (will print SQL for manual execution)"
    fi

    # Verify .gitignore contains BuildToken.swift
    if ! grep -qF "$TOKEN_ABS_PATH" .gitignore 2>/dev/null; then
        print_warning "BuildToken.swift not in .gitignore - add this line:"
        print_info "  $TOKEN_ABS_PATH"
    fi
}

### Get current version from VERSION file
get_current_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "0.14.0"  # Fallback
    fi
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

### Generate build token (format: bt_<uuid>_<timestamp>)
generate_build_token() {
    local uuid
    local timestamp

    uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    timestamp="$(date +%s)"

    echo "bt_${uuid}_${timestamp}"
}
### Generate BuildToken.swift file with real token
generate_build_token_file() {
    local build_token="$1"
    local output_file="$2"
### Generate DevelopmentConfig.swift file with all 3 values
generate_dev_config_file() {
  local build_token="$1"
  local output_file="$2"
    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
import Foundation

/// Development mode configuration for SDK
///
/// WARNING: THIS FILE IS AUTO-GENERATED DURING RELEASES
/// WARNING: DO NOT MANUALLY EDIT THIS FILE
///
/// Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
/// Release: Auto-generated by scripts/release_ios_sdk.sh
///
/// Security Model:
/// - This file is in .gitignore (not committed to main branch)
/// - Real values are ONLY in release tags (for SPM distribution)
/// - Used ONLY when SDK is in .development mode
/// - Backend validates build token via POST /api/v1/devices/register/dev
///
/// This file contains all 3 values needed for development mode:
/// 1. Supabase project URL
/// 2. Supabase anon key (safe to expose - RLS controls data access)
/// 3. Build token (validates SDK installation)
///
/// Build Token Properties:
/// - Format: bt_<uuid>_<timestamp>
/// - Rotatable: Each release gets a new token
/// - Revocable: Backend can mark token as inactive
/// - Rate-limited: Backend enforces 100 req/min per device
enum DevelopmentConfig {
    // MARK: - Supabase Configuration

    /// Supabase project URL for development device analytics
    static let supabaseURL = "$SUPABASE_URL"

    /// Supabase anon/public API key
    /// Note: Anon key is safe to include in client code - data access is controlled by RLS policies
    // swiftlint:disable:next line_length
    static let supabaseAnonKey = "$SUPABASE_ANON_KEY"

    // MARK: - Build Token

    /// Development mode build token
    /// Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
    static let buildToken = "$build_token"
}
EOF
}

### Update version references in files
update_version_references() {
    local new_version="$1"

    print_header "Updating Version References"

    # Update VERSION file
    echo "$new_version" > "$VERSION_FILE"
    print_success "Updated $VERSION_FILE"

    # Update root README.md
    if [[ -f "$README_ROOT" ]]; then
        sedi "s/from: \"[0-9]*\.[0-9]*\.[0-9]*\"/from: \"$new_version\"/g" "$README_ROOT"
        sedi "s/exact: \"[0-9]*\.[0-9]*\.[0-9]*\"/exact: \"$new_version\"/g" "$README_ROOT"
        sedi "s/'RunAnywhere', '~> [0-9]*\.[0-9]*'/'RunAnywhere', '~> ${new_version%.*}'/g" "$README_ROOT"
        sedi "s/'RunAnywhere', '[0-9]*\.[0-9]*\.[0-9]*'/'RunAnywhere', '$new_version'/g" "$README_ROOT"
        print_success "Updated $README_ROOT"
    fi

    # Update SDK README.md
    if [[ -f "$README_SDK" ]]; then
        sedi "s/from: \"[0-9]*\.[0-9]*\.[0-9]*\"/from: \"$new_version\"/g" "$README_SDK"
        sedi "s/exact: \"[0-9]*\.[0-9]*\.[0-9]*\"/exact: \"$new_version\"/g" "$README_SDK"
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

### Display SQL command for manual Supabase insertion
show_build_token_sql() {
    local version="$1"
    local build_token="$2"

    print_header "Manual Supabase Setup Required"

    echo ""
    print_warning "IMPORTANT: You must manually insert this build token into Supabase"
    echo ""
    print_info "Run this SQL command in your Supabase SQL Editor:"
    echo ""
    echo -e "${GREEN}-------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}INSERT INTO build_tokens (token, platform, label, is_active, notes)"
    echo -e "VALUES ("
    echo -e "  '$build_token',"
    echo -e "  'ios',"
    echo -e "  'v$version',"
    echo -e "  TRUE,"
    echo -e "  'iOS SDK v$version - Released $(date +%Y-%m-%d)'"
    echo -e ");${NC}"
    echo -e "${GREEN}-------------------------------------------------------------------${NC}"
    echo ""
    echo ""
    print_info "This ensures only valid SDKs can register devices to your database."
    echo ""
}

### Run tests
run_tests() {
    if [[ $SKIP_BUILD -eq 1 ]]; then
        print_warning "Skipping build check (--skip-build flag)"
        return
    fi

    print_header "Building Package"

    print_info "Running swift build..."
    if swift build --target RunAnywhere; then
        print_success "Package builds successfully"
    else
        print_error "Swift build failed"
        exit 1
    fi

    # TODO: Add swift test when tests exist
    # if swift test; then
    #   print_success "All tests passed"
    # else
    #   print_error "Tests failed"
    #   exit 1
    # fi
}

### Create GitHub release
create_github_release() {
    local new_version="$1"
    local tag_name="v$new_version"

    print_header "Creating GitHub Release"

    # Extract release notes from CHANGELOG
    local release_notes=""
    if [[ -f "$CHANGELOG_FILE" ]]; then
        release_notes="$(sed -n "/## \[$new_version\]/,/^## \[/p" "$CHANGELOG_FILE" | sed '$d' | tail -n +2)"
    fi
    # Create GitHub release
    # SECURITY NOTE: DO NOT include build token in release notes (it's public)
    print_info "Creating GitHub release..."
    gh release create "$tag_name" \
        --title "RunAnywhere iOS SDK v$new_version" \
        --notes "$release_notes" \
        --latest

    print_success "GitHub release created: https://github.com/RunanywhereAI/sdks/releases/tag/$tag_name"
}

### Main release process
main() {
    print_header "RunAnywhere iOS SDK Release"

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

    # Generate build token
    local build_token
    build_token="$(generate_build_token)"
    print_success "Generated build token: $build_token"

    # Show SQL command for manual Supabase insertion
    show_build_token_sql "$new_version" "$build_token"

    # Run tests before making any changes
    run_tests

    # Step 1: Update version files and commit to main
    print_header "Step 1: Committing Version Updates to Main"
    update_version_references "$new_version"

    local paths_to_add=("$VERSION_FILE")
    [[ -f "$CHANGELOG_FILE" ]] && paths_to_add+=("$CHANGELOG_FILE")
    [[ -f "$README_ROOT" ]] && paths_to_add+=("$README_ROOT")
    [[ -f "$README_SDK" ]] && paths_to_add+=("$README_SDK")

    git add "${paths_to_add[@]}"
    git commit -m "Release v$new_version

- Updated version to $new_version
- Updated documentation
- See CHANGELOG.md for details"

    print_success "Committed version updates to main"
}

# Run main function
main "$@"

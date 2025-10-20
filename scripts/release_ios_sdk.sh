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
print_success() { echo -e "${GREEN}✓ $*${NC}"; }
print_error() { echo -e "${RED}✗ $*${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $*${NC}"; }
print_info() { echo -e "${BLUE}ℹ $*${NC}"; }

### Configuration
SDK_DIR="sdk/runanywhere-swift"
VERSION_FILE="$SDK_DIR/VERSION"
CHANGELOG_FILE="$SDK_DIR/CHANGELOG.md"
README_ROOT="README.md"
README_SDK="$SDK_DIR/README.md"
TOKEN_REL_PATH="Sources/RunAnywhere/Foundation/Constants/BuildToken.swift"
TOKEN_ABS_PATH="$SDK_DIR/$TOKEN_REL_PATH"

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
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --yes, -y           Auto-confirm prompts (for CI)"
      echo "  --bump TYPE         Version bump type: major|minor|patch"
      echo "  --help, -h          Show this help"
      echo ""
      echo "Environment Variables:"
      echo "  DATABASE_URL        PostgreSQL URL for auto-inserting build token"
      echo "  SUPABASE_PROJECT_ID Project UUID for build_tokens table"
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
  if [[ -n "${DATABASE_URL:-}" && ! $(command -v psql) ]]; then
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

  mkdir -p "$(dirname "$output_file")"

  cat > "$output_file" <<EOF
import Foundation

/// Build token for development mode device registration
///
/// ⚠️ THIS FILE IS AUTO-GENERATED DURING RELEASES
/// ⚠️ DO NOT MANUALLY EDIT THIS FILE
///
/// Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
/// Release: Auto-generated by scripts/release_ios_sdk.sh
///
/// Security Model:
/// - This file is in .gitignore (not committed to main branch)
/// - Real tokens are ONLY in release tags (for SPM distribution)
/// - Token is used ONLY when SDK is in .development mode
/// - Backend validates token via POST /v1/sdk/init
///
/// Token Properties:
/// - Format: bt_<uuid>_<timestamp>
/// - Rotatable: Each release gets a new token
/// - Revocable: Backend can mark token as inactive
/// - Rate-limited: Backend enforces 100 req/min per device
enum BuildToken {
    /// Development mode build token
    /// Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
    static let token = "$build_token"
}
EOF

  print_success "Generated BuildToken.swift"
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

### Store build token in Supabase (optional)
store_build_token_in_backend() {
  local version="$1"
  local build_token="$2"

  print_header "Storing Build Token in Backend"

  # Check if DATABASE_URL and project ID are set
  if [[ -z "${DATABASE_URL:-}" ]]; then
    print_warning "DATABASE_URL not set, skipping backend storage"
    print_info "Manually insert into Supabase build_tokens table:"
    echo ""
    echo "  INSERT INTO build_tokens (token, project_id, platform, label, is_active)"
    echo "  VALUES ('$build_token', '<your-project-id>', 'ios', 'v$version', TRUE);"
    echo ""
    return
  fi

  if [[ -z "${SUPABASE_PROJECT_ID:-}" ]]; then
    print_warning "SUPABASE_PROJECT_ID not set, cannot auto-insert"
    print_info "Set SUPABASE_PROJECT_ID environment variable or manually insert:"
    echo ""
    echo "  INSERT INTO build_tokens (token, project_id, platform, label, is_active)"
    echo "  VALUES ('$build_token', '<your-project-id>', 'ios', 'v$version', TRUE);"
    echo ""
    return
  fi

  # Check for psql
  if ! command -v psql >/dev/null; then
    print_warning "psql not found, cannot auto-insert"
    print_info "Install PostgreSQL client or manually insert:"
    echo ""
    echo "  INSERT INTO build_tokens (token, project_id, platform, label, is_active)"
    echo "  VALUES ('$build_token', '$SUPABASE_PROJECT_ID', 'ios', 'v$version', TRUE);"
    echo ""
    return
  fi

  # Insert into database
  if psql "$DATABASE_URL" -c "INSERT INTO build_tokens (token, project_id, platform, label, is_active) VALUES ('$build_token', '$SUPABASE_PROJECT_ID', 'ios', 'v$version', TRUE);"; then
    print_success "Build token stored in Supabase"
  else
    print_warning "Failed to store in backend (non-critical)"
    print_info "Manually insert:"
    echo ""
    echo "  INSERT INTO build_tokens (token, project_id, platform, label, is_active)"
    echo "  VALUES ('$build_token', '$SUPABASE_PROJECT_ID', 'ios', 'v$version', TRUE);"
    echo ""
  fi
}

### Run tests
run_tests() {
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

  # Fallback if no notes found
  if [[ -z "$release_notes" ]]; then
    release_notes="Release v$new_version"
  fi

  # Create GitHub release
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

  # Store in backend (optional)
  store_build_token_in_backend "$new_version" "$build_token"

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
- See CHANGELOG.md for details

  print_success "Committed version updates to main"

  # Step 2: Create worktree for tag commit (includes BuildToken.swift)
  print_header "Step 2: Creating Release Tag with BuildToken.swift"

  local worktree_dir
  worktree_dir="$(mktemp -d)/release-v$new_version"
  local release_branch="release/v$new_version"

  # Create worktree
  git worktree add -b "$release_branch" "$worktree_dir"
  print_info "Created worktree at $worktree_dir"

  # Generate BuildToken.swift in worktree
  local worktree_token_path="$worktree_dir/$TOKEN_ABS_PATH"
  generate_build_token_file "$build_token" "$worktree_token_path"

  # Commit BuildToken.swift in worktree
  pushd "$worktree_dir" >/dev/null
  git add -f "$TOKEN_ABS_PATH"
  git commit -m "Add BuildToken.swift for release v$new_version

SECURITY: BuildToken.swift is in .gitignore and NOT in main branch.
This file is ONLY included in release tags for SPM distribution.

Token: $build_token
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

  print_success "Committed BuildToken.swift in worktree"

  # Create annotated tag
  local tag_name="v$new_version"
  git tag -a "$tag_name" -m "Release v$new_version"
  print_success "Created tag $tag_name"

  # Push tag to GitHub
  git push origin "$tag_name"
  print_success "Pushed tag to GitHub"

  popd >/dev/null

  # Clean up worktree
  git worktree remove "$worktree_dir" --force
  git branch -D "$release_branch"
  print_success "Cleaned up worktree"

  # Step 3: Push main branch
  print_header "Step 3: Pushing Main Branch"
  git push origin HEAD
  print_success "Pushed main branch"

  # Step 4: Create GitHub release
  create_github_release "$new_version"

  # Success summary
  print_header "Release Complete!"
  print_success "Released v$new_version successfully"
  print_success "Build token: $build_token"
  echo ""
  print_info "Main branch: Contains version updates (NO BuildToken.swift)"
  print_info "Tag $tag_name: Contains BuildToken.swift with real token"
  print_info "SPM users downloading v$new_version will get the real token"
  echo ""
  print_info "Users can now install with:"
  echo ""
  echo "  dependencies: ["
  echo "      .package(url: \"https://github.com/RunanywhereAI/sdks\", from: \"$new_version\")"
  echo "  ]"
  echo ""

  # Reminder if DATABASE_URL not set
  if [[ -z "${DATABASE_URL:-}" || -z "${SUPABASE_PROJECT_ID:-}" ]]; then
    print_warning "IMPORTANT: Ensure build token is stored in Supabase!"
    echo ""
    print_info "Run this SQL command on your Supabase database:"
    echo ""
    echo "  INSERT INTO build_tokens (token, project_id, platform, label, is_active)"
    echo "  VALUES ('$build_token', '<your-project-id>', 'ios', 'v$new_version', TRUE);"
    echo ""
  fi

  print_info "View release: https://github.com/RunanywhereAI/sdks/releases/tag/v$new_version"
}

# Run main function
main "$@"

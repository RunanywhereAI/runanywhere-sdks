#!/bin/bash
# Flutter SDK Quality Check Script
# Run from sdk/runanywhere-flutter directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SDK_ROOT"

echo "=========================================="
echo "Flutter SDK Quality Check"
echo "SDK Root: $SDK_ROOT"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

# Find Flutter's embedded Dart SDK (uses Dart 3.x with full language support)
# Handle macOS (no readlink -f) and Linux
find_flutter_dart() {
    # Method 1: Use flutter pub deps to extract Dart SDK version path
    # This is the most reliable method as it uses Flutter's internal resolution
    local flutter_sdk_info
    flutter_sdk_info=$(cd "$SDK_ROOT" && flutter pub deps --style=compact 2>/dev/null | head -1)
    if [[ "$flutter_sdk_info" =~ "Dart SDK" ]]; then
        # Flutter pub deps worked, so Flutter knows the dart SDK location
        # Try to find it via common paths
        :
    fi

    # Method 2: Try Homebrew cask path (macOS) - most common
    for version in /opt/homebrew/Caskroom/flutter/*/flutter/bin/cache/dart-sdk/bin/dart; do
        if [ -x "$version" ]; then
            echo "$version"
            return
        fi
    done

    # Method 3: Check Linux/standard install path
    local flutter_path=$(which flutter 2>/dev/null)
    if [ -n "$flutter_path" ]; then
        # Get the real path (handles symlinks)
        local real_flutter
        if command -v realpath &>/dev/null; then
            real_flutter=$(realpath "$flutter_path" 2>/dev/null)
        elif command -v greadlink &>/dev/null; then
            real_flutter=$(greadlink -f "$flutter_path" 2>/dev/null)
        else
            real_flutter="$flutter_path"
        fi

        local flutter_root=$(dirname "$(dirname "$real_flutter")")
        local dart_path="${flutter_root}/bin/cache/dart-sdk/bin/dart"
        if [ -x "$dart_path" ]; then
            echo "$dart_path"
            return
        fi
    fi

    # Method 4: Check ~/.flutter path
    if [ -x "$HOME/.flutter/bin/cache/dart-sdk/bin/dart" ]; then
        echo "$HOME/.flutter/bin/cache/dart-sdk/bin/dart"
        return
    fi

    # Fallback to system dart (may not support Dart 3 features)
    echo "dart"
}

FLUTTER_DART=$(find_flutter_dart)
DART_VERSION=$("$FLUTTER_DART" --version 2>&1 | head -1)
echo "Using Dart: $FLUTTER_DART"
echo "  Version: $DART_VERSION"

# Verify Dart 3+ for records and sealed classes support
if [[ ! "$DART_VERSION" =~ "Dart SDK version: 3." ]]; then
    echo -e "${YELLOW}Warning: Dart SDK appears to be older than 3.0. Some features may not work.${NC}"
    echo "Consider using Flutter's bundled Dart or updating your Dart SDK."
fi

# Step 1: Format check
echo ""
echo "Step 1: Checking code formatting..."
if "$FLUTTER_DART" format --output=none --set-exit-if-changed lib/; then
    echo -e "${GREEN}✓ Code formatting OK${NC}"
else
    echo -e "${YELLOW}⚠ Code formatting issues found. Run '$FLUTTER_DART format lib/' to fix.${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Step 2: Static analysis
echo ""
echo "Step 2: Running flutter analyze..."
if flutter analyze lib/; then
    echo -e "${GREEN}✓ Static analysis passed${NC}"
else
    echo -e "${RED}✗ Static analysis found issues${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Step 3: Safe auto-fixes (dry run)
echo ""
echo "Step 3: Checking for available dart fixes..."
"$FLUTTER_DART" fix --dry-run lib/ 2>/dev/null || true

# Step 4: TODO checker
echo ""
echo "Step 4: Checking TODO/FIXME comments for issue references..."
if "$SCRIPT_DIR/todo_check.sh"; then
    echo -e "${GREEN}✓ All TODOs have issue references${NC}"
else
    echo -e "${YELLOW}⚠ Some TODOs missing issue references${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Step 5: Run tests (if they exist)
echo ""
echo "Step 5: Running tests..."
if [ -d "test" ] && [ "$(ls -A test 2>/dev/null)" ]; then
    if flutter test; then
        echo -e "${GREEN}✓ Tests passed${NC}"
    else
        echo -e "${RED}✗ Tests failed${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ No tests found${NC}"
fi

echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Quality check completed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Quality check completed with $ERRORS issue(s)${NC}"
    exit 1
fi

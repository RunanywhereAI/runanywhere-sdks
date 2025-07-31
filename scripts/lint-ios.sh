#!/bin/bash

# iOS-specific linting script

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🍎 Running iOS lint checks..."
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

# Check if SwiftLint is installed
if ! which swiftlint >/dev/null; then
    echo -e "${RED}ERROR: SwiftLint is not installed${NC}"
    echo "Install using: brew install swiftlint"
    exit 1
fi

OVERALL_STATUS=0

# Check iOS SDK
echo "📦 Linting iOS SDK..."
cd "$PROJECT_ROOT/sdk/runanywhere-swift"

# Run SwiftLint
if swiftlint --strict; then
    print_status 0 "iOS SDK passed all checks"
else
    print_status 1 "iOS SDK has lint issues"
    OVERALL_STATUS=1
fi

echo
echo "Detailed report:"
swiftlint --reporter json | jq -r '.[] | select(.severity == "error") | "  ❌ \(.file):\(.line):\(.character) - \(.reason)"' 2>/dev/null || true
swiftlint --reporter json | jq -r '.[] | select(.severity == "warning") | "  ⚠️  \(.file):\(.line):\(.character) - \(.reason)"' 2>/dev/null || true

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check iOS Example App
echo "📱 Linting iOS Example App..."
cd "$PROJECT_ROOT/examples/ios/RunAnywhereAI"

# Run SwiftLint
if swiftlint --strict; then
    print_status 0 "iOS App passed all checks"
else
    print_status 1 "iOS App has lint issues"
    OVERALL_STATUS=1
fi

echo
echo "Detailed report:"
swiftlint --reporter json | jq -r '.[] | select(.severity == "error") | "  ❌ \(.file):\(.line):\(.character) - \(.reason)"' 2>/dev/null || true
swiftlint --reporter json | jq -r '.[] | select(.severity == "warning") | "  ⚠️  \(.file):\(.line):\(.character) - \(.reason)"' 2>/dev/null || true

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Summary
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}✅ All iOS lint checks passed!${NC}"
else
    echo -e "${RED}❌ iOS lint checks failed${NC}"
    echo
    echo "Fix suggestions:"
    echo "1. For TODO issues: Add GitHub issue reference (e.g., // TODO: #123 - Description)"
    echo "2. For code style: Run 'swiftlint autocorrect' to fix some issues automatically"
    echo "3. For complex issues: Check the detailed report above"
fi

exit $OVERALL_STATUS
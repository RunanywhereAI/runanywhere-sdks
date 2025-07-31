#!/bin/bash

# Comprehensive linting script for all components
# This script runs all lint checks including TODO validation

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🔍 Running comprehensive lint checks..."
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

# Track overall status
OVERALL_STATUS=0

# Check for TODOs without issue references
echo "📝 Checking TODO comments..."
if grep -rEn "(//|/\*|#)\s*(TODO|FIXME|HACK|XXX|BUG|REFACTOR|OPTIMIZE)(?!.*#[0-9]+)" \
    --include="*.swift" \
    --include="*.kt" \
    --include="*.java" \
    --include="*.ts" \
    --include="*.tsx" \
    --include="*.js" \
    --include="*.jsx" \
    --include="*.py" \
    --include="*.rb" \
    --include="*.go" \
    --include="*.rs" \
    --include="*.cpp" \
    --include="*.c" \
    --include="*.h" \
    --include="*.hpp" \
    --include="*.cs" \
    --include="*.m" \
    --include="*.mm" \
    "$PROJECT_ROOT" 2>/dev/null | \
    grep -v ".git/" | \
    grep -v "node_modules/" | \
    grep -v ".build/" | \
    grep -v "build/" | \
    grep -v "DerivedData/" | \
    grep -v "scripts/lint-all.sh"; then
    echo -e "${RED}ERROR: Found TODOs without GitHub issue references${NC}"
    echo "All TODOs must reference an issue (e.g., // TODO: #123 - Description)"
    OVERALL_STATUS=1
else
    print_status 0 "All TODOs have issue references"
fi
echo

# iOS SDK Linting
echo "📱 iOS SDK Linting..."
if which swiftlint >/dev/null; then
    cd "$PROJECT_ROOT/sdk/runanywhere-swift"
    if swiftlint --strict --quiet; then
        print_status 0 "iOS SDK SwiftLint passed"
    else
        print_status 1 "iOS SDK SwiftLint failed"
        OVERALL_STATUS=1
    fi
else
    echo -e "${YELLOW}⚠️  SwiftLint not installed, skipping iOS SDK lint${NC}"
fi
echo

# iOS App Linting
echo "📱 iOS App Linting..."
if which swiftlint >/dev/null; then
    cd "$PROJECT_ROOT/examples/ios/RunAnywhereAI"
    if swiftlint --strict --quiet; then
        print_status 0 "iOS App SwiftLint passed"
    else
        print_status 1 "iOS App SwiftLint failed"
        OVERALL_STATUS=1
    fi
else
    echo -e "${YELLOW}⚠️  SwiftLint not installed, skipping iOS App lint${NC}"
fi
echo

# Android SDK Linting
echo "🤖 Android SDK Linting..."
cd "$PROJECT_ROOT/sdk/runanywhere-android"
if ./gradlew lint --quiet; then
    print_status 0 "Android SDK lint passed"
else
    print_status 1 "Android SDK lint failed"
    OVERALL_STATUS=1
fi

# Android SDK Detekt
if ./gradlew detekt --quiet; then
    print_status 0 "Android SDK Detekt passed"
else
    print_status 1 "Android SDK Detekt failed"
    OVERALL_STATUS=1
fi
echo

# Android App Linting
echo "🤖 Android App Linting..."
cd "$PROJECT_ROOT/examples/android/RunAnywhereAI"
if ./gradlew :app:lint --quiet; then
    print_status 0 "Android App lint passed"
else
    print_status 1 "Android App lint failed"
    OVERALL_STATUS=1
fi

# Android App Detekt
if ./gradlew :app:detekt --quiet; then
    print_status 0 "Android App Detekt passed"
else
    print_status 1 "Android App Detekt failed"
    OVERALL_STATUS=1
fi
echo

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}✅ All lint checks passed!${NC}"
else
    echo -e "${RED}❌ Some lint checks failed${NC}"
    echo "Please fix the issues above before committing."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $OVERALL_STATUS
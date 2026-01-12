#!/bin/bash

# Android-specific linting script

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🤖 Running Android lint checks..."
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

OVERALL_STATUS=0

# Check Android SDK
echo "📦 Linting Android SDK..."
cd "$PROJECT_ROOT/sdk/runanywhere-android"

# Run Android Lint
echo "Running Android Lint..."
if ./gradlew lint; then
    print_status 0 "Android SDK lint passed"
else
    print_status 1 "Android SDK lint failed"
    OVERALL_STATUS=1
    echo "Check the lint report at: sdk/runanywhere-android/build/reports/lint-results.html"
fi

# Run Detekt
echo
echo "Running Detekt..."
if ./gradlew detekt; then
    print_status 0 "Android SDK Detekt passed"
else
    print_status 1 "Android SDK Detekt failed"
    OVERALL_STATUS=1
    echo "Check the Detekt report at: sdk/runanywhere-android/build/reports/detekt/detekt.html"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Android Example App
echo "📱 Linting Android Example App..."
cd "$PROJECT_ROOT/examples/android/RunAnywhereAI"

# Run Android Lint
echo "Running Android Lint..."
if ./gradlew :app:lint; then
    print_status 0 "Android App lint passed"
else
    print_status 1 "Android App lint failed"
    OVERALL_STATUS=1
    echo "Check the lint report at: examples/android/RunAnywhereAI/app/build/reports/lint-results.html"
fi

# Run Detekt
echo
echo "Running Detekt..."
if ./gradlew :app:detekt; then
    print_status 0 "Android App Detekt passed"
else
    print_status 1 "Android App Detekt failed"
    OVERALL_STATUS=1
    echo "Check the Detekt report at: examples/android/RunAnywhereAI/app/build/reports/detekt/detekt.html"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Summary
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}✅ All Android lint checks passed!${NC}"
else
    echo -e "${RED}❌ Android lint checks failed${NC}"
    echo
    echo "Fix suggestions:"
    echo "1. For TODO issues: Add GitHub issue reference (e.g., // TODO: #123 - Description)"
    echo "2. For lint issues: Check the HTML reports mentioned above"
    echo "3. For Detekt issues: Some can be fixed with './gradlew detektBaseline'"
    echo "4. Run './gradlew lint --fix' to auto-fix some issues"
fi

exit $OVERALL_STATUS

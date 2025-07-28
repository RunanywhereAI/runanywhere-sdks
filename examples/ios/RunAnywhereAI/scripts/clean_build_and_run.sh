#!/bin/bash
# clean_build_and_run.sh - Clean, build, install, and run the RunAnywhereAI app
# Usage: ./clean_build_and_run.sh [simulator|device] [device-name-or-id]
# Examples:
#   ./clean_build_and_run.sh simulator "iPhone 16"
#   ./clean_build_and_run.sh device "00008140-000C6D860A3B001C"
#   ./clean_build_and_run.sh device "Monga's iphone"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Clean everything first
print_status "Cleaning build artifacts..."

# Clean DerivedData
print_status "Removing DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*

# Clean local build directory
if [ -d "build" ]; then
    print_status "Removing local build directory..."
    rm -rf build/
fi

# Clean using xcodebuild
print_status "Running xcodebuild clean..."
xcodebuild clean -workspace RunAnywhereAI.xcworkspace -scheme RunAnywhereAI -configuration Debug >/dev/null 2>&1 || true

# Clean Pods and reinstall
print_status "Cleaning and reinstalling CocoaPods..."
if [ -d "Pods" ]; then
    rm -rf Pods/
fi
if [ -f "Podfile.lock" ]; then
    rm -f Podfile.lock
fi

print_status "Running pod install..."
pod install

print_status "Clean complete! Now building..."

# Call the regular build script
./build_and_run.sh "$@"
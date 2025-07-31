#!/bin/bash
# ensure_models_in_project.sh - Ensure all model files are added to Xcode project

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

# Check if we're in the right directory
if [ ! -f "RunAnywhereAI.xcodeproj/project.pbxproj" ]; then
    print_error "This script must be run from the iOS example app directory"
    exit 1
fi

# Check if xcodeproj gem is installed
if ! gem list xcodeproj -i > /dev/null 2>&1; then
    print_warning "xcodeproj gem not found. Installing..."
    sudo gem install xcodeproj
fi

# Run the Ruby script to add models
print_status "Checking for model files to add to project..."
ruby scripts/add_models_to_project.rb RunAnywhereAI.xcodeproj RunAnywhereAI/Models

print_status "Model files have been added to the Xcode project"

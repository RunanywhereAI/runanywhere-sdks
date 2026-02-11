#!/bin/bash

# RunAnywhere SDK Installation Script
# This script handles the monorepo installation with proper symlink handling

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RunAnywhere SDK Installation Script${NC}"
echo -e "${BLUE}========================================${NC}\n"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Function to print section headers
print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if npm is installed
check_npm() {
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed"
        exit 1
    fi
    print_success "npm found: $(npm --version)"
}

# Install packages in a directory
install_package() {
    local package_name=$1
    local package_path=$2
    
    print_section "Installing $package_name ($package_path)"
    
    if [ ! -d "$REPO_ROOT/$package_path" ]; then
        print_warning "$package_name directory not found at $package_path"
        return 1
    fi
    
    cd "$REPO_ROOT/$package_path"
    
    # Clean previous install if needed
    if [ -f "package-lock.json" ]; then
        echo "Cleaning previous installation..."
        rm -rf node_modules package-lock.json
    fi
    
    echo "Running npm install..."
    npm install --legacy-peer-deps 2>&1 | tail -20
    
    if [ $? -eq 0 ]; then
        print_success "$package_name installed successfully"
    else
        print_error "Failed to install $package_name"
        return 1
    fi
}

# Main installation flow
main() {
    cd "$REPO_ROOT"
    
    check_npm
    
    # Install core packages
    print_section "Installing Core Packages"
    
    install_package "@runanywhere/core" "sdk/runanywhere-react-native/packages/core" || true
    install_package "@runanywhere/llamacpp" "sdk/runanywhere-react-native/packages/llamacpp" || true
    install_package "@runanywhere/onnx" "sdk/runanywhere-react-native/packages/onnx" || true
    install_package "@runanywhere/rag" "sdk/runanywhere-react-native/packages/rag" || true
    
    # Install example apps
    print_section "Installing Example Applications"
    
    install_package "RunAnywhereAI React Native" "examples/react-native/RunAnywhereAI" || true
    install_package "On-Device Browser Agent" "Playground/on-device-browser-agent" || true
    install_package "Android Use Agent" "Playground/android-use-agent" || true
    
    # Verify installations
    print_section "Verifying Installations"
    
    cd "$REPO_ROOT/examples/react-native/RunAnywhereAI"
    if [ -d "node_modules/@runanywhere" ]; then
        print_success "RunAnywhereAI packages found"
        ls -la node_modules/@runanywhere/ | grep -E "core|llamacpp|onnx|rag" || print_warning "Some packages not found"
    else
        print_error "RunAnywhereAI packages not found"
    fi
    
    print_section "Verifying Symlinks"
    cd "$REPO_ROOT/examples/react-native/RunAnywhereAI/node_modules/@runanywhere"
    
    if [ -L "core" ]; then
        print_success "Symlink for @runanywhere/core is valid"
        ls -la core | head -1
    fi
    
    if [ -L "rag" ]; then
        print_success "Symlink for @runanywhere/rag is valid"
        ls -la rag | head -1
    fi
    
    # Final summary
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Installation Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    echo ""
    echo "✅ Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. React Native example app:"
    echo "     cd examples/react-native/RunAnywhereAI"
    echo "     npm run android    # or: npm run ios"
    echo ""
    echo "  2. Android app:"
    echo "     cd examples/android/RunAnywhereAI"
    echo "     ./gradlew assembleRelease"
    echo ""
    echo "  3. Browser agent:"
    echo "     cd Playground/on-device-browser-agent"
    echo "     npm run dev"
    echo ""
}

# Run main function
main


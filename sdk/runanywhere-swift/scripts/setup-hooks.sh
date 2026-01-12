#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RunAnywhere Swift SDK - Pre-commit Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print success message
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print error message
print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to print warning message
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to print info message
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if we're in the correct directory
if [ ! -f "$PROJECT_ROOT/.pre-commit-config.yaml" ]; then
    print_error ".pre-commit-config.yaml not found in $PROJECT_ROOT"
    exit 1
fi

# Check if pre-commit is installed
echo -e "${BLUE}Checking dependencies...${NC}"
if ! command -v pre-commit &> /dev/null; then
    print_error "pre-commit is not installed"
    echo ""
    print_info "pre-commit is required to set up Git hooks for code quality."
    echo ""
    echo "Please install pre-commit using one of the following methods:"
    echo ""
    echo "  Using pip:"
    echo -e "    ${GREEN}pip install pre-commit${NC}"
    echo ""
    echo "  Using Homebrew (macOS):"
    echo -e "    ${GREEN}brew install pre-commit${NC}"
    echo ""
    echo "  Using pipx (recommended):"
    echo -e "    ${GREEN}pipx install pre-commit${NC}"
    echo ""
    echo "For more information, visit: https://pre-commit.com/#installation"
    exit 1
else
    print_success "pre-commit is installed ($(pre-commit --version))"
fi

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
    print_warning "SwiftLint is not installed"
    echo ""
    print_info "SwiftLint is required for Swift code linting."
    echo ""
    echo "Please install SwiftLint using one of the following methods:"
    echo ""
    echo "  Using Homebrew (recommended):"
    echo -e "    ${GREEN}brew install swiftlint${NC}"
    echo ""
    echo "  Using Mint:"
    echo -e "    ${GREEN}mint install realm/SwiftLint${NC}"
    echo ""
    echo "  Using CocoaPods (add to Podfile):"
    echo -e "    ${GREEN}pod 'SwiftLint'${NC}"
    echo ""
    echo "For more information, visit: https://github.com/realm/SwiftLint"
    echo ""
    read -p "Do you want to continue without SwiftLint? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "SwiftLint is installed ($(swiftlint version))"
fi

# Navigate to project root
cd "$PROJECT_ROOT"

# Install pre-commit hooks
echo ""
echo -e "${BLUE}Installing pre-commit hooks...${NC}"
if pre-commit install; then
    print_success "Pre-commit hooks installed successfully"
else
    print_error "Failed to install pre-commit hooks"
    exit 1
fi

# Install pre-commit hooks for commit-msg (optional)
if pre-commit install --hook-type commit-msg 2>/dev/null; then
    print_success "Commit message hooks installed"
fi

# Run pre-commit on all files to verify setup
echo ""
read -p "Do you want to run pre-commit on all files now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Running pre-commit on all files...${NC}"
    if pre-commit run --all-files; then
        print_success "All checks passed!"
    else
        print_warning "Some checks failed. Please review the output above."
        echo ""
        print_info "You can fix auto-fixable issues by running:"
        echo -e "  ${GREEN}pre-commit run --all-files${NC}"
        echo ""
        print_info "Or manually fix SwiftLint issues with:"
        echo -e "  ${GREEN}swiftlint --fix --config .swiftlint.yml${NC}"
    fi
fi

# Print usage instructions
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Pre-commit hooks are now installed and will run automatically on 'git commit'."
echo ""
echo -e "${BLUE}Usage:${NC}"
echo ""
echo "  Commit normally:"
echo -e "    ${GREEN}git commit -m \"Your commit message\"${NC}"
echo ""
echo "  Run all hooks manually:"
echo -e "    ${GREEN}pre-commit run --all-files${NC}"
echo ""
echo "  Run specific hook:"
echo -e "    ${GREEN}pre-commit run swiftlint --all-files${NC}"
echo ""
echo "  Run SwiftLint auto-fix manually:"
echo -e "    ${GREEN}pre-commit run swiftlint-fix --all-files${NC}"
echo "  or:"
echo -e "    ${GREEN}swiftlint --fix --config .swiftlint.yml${NC}"
echo ""
echo "  Skip hooks for a single commit (use sparingly):"
echo -e "    ${GREEN}git commit --no-verify -m \"Your message\"${NC}"
echo ""
echo "  Update hooks to latest versions:"
echo -e "    ${GREEN}pre-commit autoupdate${NC}"
echo ""
echo "  Uninstall hooks:"
echo -e "    ${GREEN}pre-commit uninstall${NC}"
echo ""
echo -e "${BLUE}Hooks Configuration:${NC}"
echo "  - SwiftLint: Lints Swift code according to .swiftlint.yml"
echo "  - SwiftLint AutoFix: Auto-fixes SwiftLint issues (manual stage)"
echo "  - Trailing Whitespace: Removes trailing whitespace"
echo "  - End of File Fixer: Ensures files end with newline"
echo "  - Merge Conflict Checker: Detects merge conflict markers"
echo "  - YAML Checker: Validates YAML syntax"
echo "  - Large File Checker: Prevents files >1MB from being committed"
echo "  - Private Key Detector: Prevents committing private keys"
echo ""
echo -e "${YELLOW}Note:${NC} SwiftLint will only check staged Swift files for better performance."
echo ""
print_success "You're all set! Happy coding!"

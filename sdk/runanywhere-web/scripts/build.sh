#!/bin/bash

# =============================================================================
# RunAnywhere Web SDK Build Script
# =============================================================================
#
# Unified build script with multiple options for building the entire SDK
# and optionally running demo applications.
#
# USAGE:
#   ./scripts/build.sh [OPTIONS]
#
# EXAMPLES:
#   ./scripts/build.sh                    # Fast build only (default)
#   ./scripts/build.sh --run              # Fast build + run React demo
#   ./scripts/build.sh --clean --run      # Clean build + run demo
#   ./scripts/build.sh -d -v              # Detailed build with verbose output
#   ./scripts/build.sh -r -t vue          # Build + run Vue demo
#   ./scripts/build.sh --help             # Show help
#
# OPTIONS:
#   -f, --fast              Fast build using pnpm workspace (default)
#   -d, --detailed          Detailed build with per-package progress
#   -c, --clean             Clean all build artifacts before building
#   -r, --run               Run demo app after successful build
#   -t, --demo-type TYPE    Demo to run: react (default), runanywhere, vue, or angular
#   -v, --verbose           Show detailed build output
#   -h, --help              Display help message
#
# WHAT GETS BUILT:
#   - Core packages (@runanywhere/core, @runanywhere/cache, etc.)
#   - Modular adapter packages (@runanywhere/vad-silero, @runanywhere/stt-whisper, etc.)
#   - Framework packages (@runanywhere/react, @runanywhere/vue, @runanywhere/angular)
#
# NOTES:
#   - Run from SDK root directory: /path/to/sdk/runanywhere-web/
#   - Automatically installs dependencies if needed
#   - Use --clean for fresh builds when having issues
#   - Demo runs at http://localhost:5173 (or next available port)
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
BUILD_MODE="fast"
RUN_DEMO=false
DEMO_TYPE="react"
VERBOSE=false
CLEAN=false
HELP=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}🚀 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Function to show help
show_help() {
    echo -e "${CYAN}RunAnywhere Web SDK Build Script${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --fast              Fast build using pnpm (default)"
    echo "  -d, --detailed          Detailed build with per-package output"
    echo "  -c, --clean             Clean build (remove dist folders first)"
    echo "  -r, --run               Run demo after building"
    echo "  -t, --demo-type TYPE    Demo type to run (react|runanywhere|vue|angular) [default: react]"
    echo "  -v, --verbose           Verbose output"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Fast build only"
    echo "  $0 --fast --run         # Fast build and run React demo"
    echo "  $0 --detailed --clean   # Clean detailed build"
    echo "  $0 -r -t vue           # Fast build and run Vue demo"
    echo "  $0 --clean --run        # Clean build and run demo"
    echo ""
}

# Function to clean build artifacts
clean_build() {
    print_status "Cleaning build artifacts..."

    find packages -name "dist" -type d -exec rm -rf {} + 2>/dev/null || true
    find packages -name "*.tsbuildinfo" -exec rm -f {} + 2>/dev/null || true

    # Clean demo build artifacts too
    if [ -d "../../examples/web/react-demo/dist" ]; then
        rm -rf "../../examples/web/react-demo/dist"
    fi
    if [ -d "../../examples/web/vue-demo/dist" ]; then
        rm -rf "../../examples/web/vue-demo/dist"
    fi

    print_success "Build artifacts cleaned"
}

# Function to build a package (for detailed mode)
build_package() {
    local package_name=$1
    local package_dir=$2

    if [ "$VERBOSE" = true ]; then
        print_status "Building $package_name..."
    fi

    if [ ! -d "$package_dir" ]; then
        print_warning "Package directory $package_dir not found, skipping..."
        return 0
    fi

    cd "$package_dir"

    # Check if it's a TypeScript package
    if [ -f "tsconfig.json" ]; then
        if [ "$VERBOSE" = true ]; then
            npx tsc --emitDeclarationOnly
        else
            npx tsc --emitDeclarationOnly > /dev/null 2>&1
        fi
    fi

    # Build with appropriate method
    if [ -f "package.json" ]; then
        if grep -q '"build".*vite build' package.json || [ -f "vite.config.ts" ] || [ -f "vite.config.js" ]; then
            if [ "$VERBOSE" = true ]; then
                npx vite build
            else
                npx vite build > /dev/null 2>&1
            fi
        elif grep -q '"build"' package.json; then
            if [ "$VERBOSE" = true ]; then
                pnpm build
            else
                pnpm build > /dev/null 2>&1
            fi
        fi
    fi

    cd - > /dev/null

    if [ "$VERBOSE" = true ]; then
        print_success "$package_name built successfully"
    fi
}

# Function for fast build
fast_build() {
    print_status "Fast building all packages..."

    if [ "$VERBOSE" = true ]; then
        pnpm build
    else
        pnpm build > /dev/null 2>&1
    fi

    print_success "Fast build completed"
}

# Function for detailed build
detailed_build() {
    print_status "Detailed build of all packages..."
    echo ""

    # Build packages in dependency order
    build_package "@runanywhere/core" "packages/core"
    build_package "@runanywhere/cache" "packages/cache"
    build_package "@runanywhere/monitoring" "packages/monitoring"
    build_package "@runanywhere/optimization" "packages/optimization"
    build_package "@runanywhere/workers" "packages/workers"

    # Build service packages
    build_package "@runanywhere/transcription" "packages/transcription"
    build_package "@runanywhere/llm" "packages/llm"
    build_package "@runanywhere/tts" "packages/tts"
    build_package "@runanywhere/voice" "packages/voice"

    # Build modular adapter packages
    print_info "Building modular adapter packages..."
    build_package "@runanywhere/vad-silero" "packages/vad-silero"
    build_package "@runanywhere/stt-whisper" "packages/stt-whisper"
    build_package "@runanywhere/llm-openai" "packages/llm-openai"
    build_package "@runanywhere/tts-webspeech" "packages/tts-webspeech"

    # Build framework packages
    print_info "Building framework packages..."
    build_package "@runanywhere/react" "packages/react"
    build_package "@runanywhere/vue" "packages/vue"
    build_package "@runanywhere/angular" "packages/angular"

    print_success "Detailed build completed"
}

# Function to run demo
run_demo() {
    local demo_path=""
    local dev_command=""
    local port=""

    case $DEMO_TYPE in
        "react")
            demo_path="../../examples/web/react-demo"
            dev_command="pnpm dev"
            port="5173"
            ;;
        "runanywhere")
            demo_path="../../examples/web/runanywhere-web"
            dev_command="npm run dev"
            port="3000"
            ;;
        "vue")
            demo_path="../../examples/web/vue-demo"
            dev_command="pnpm dev"
            port="5173"
            ;;
        "angular")
            demo_path="../../examples/web/angular-demo"
            dev_command="pnpm dev"
            port="5173"
            ;;
        *)
            print_error "Unknown demo type: $DEMO_TYPE"
            exit 1
            ;;
    esac

    if [ ! -d "$demo_path" ]; then
        print_error "$DEMO_TYPE demo not found at $demo_path"
        exit 1
    fi

    print_status "Starting $DEMO_TYPE demo..."
    cd "$demo_path"

    # Install demo dependencies if needed
    if [ ! -d "node_modules" ]; then
        print_status "Installing demo dependencies..."
        if [ "$DEMO_TYPE" = "runanywhere" ]; then
            npm install
        else
            pnpm install
        fi
    fi

    # Kill any existing processes
    pkill -f "vite" 2>/dev/null || true
    pkill -f "next" 2>/dev/null || true

    print_success "🎉 SDK built successfully!"
    echo ""
    print_status "Starting $DEMO_TYPE demo at http://localhost:$port"
    print_warning "Press Ctrl+C to stop the demo"
    echo ""

    # Start the demo
    $dev_command
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--fast)
            BUILD_MODE="fast"
            shift
            ;;
        -d|--detailed)
            BUILD_MODE="detailed"
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -r|--run)
            RUN_DEMO=true
            shift
            ;;
        -t|--demo-type)
            DEMO_TYPE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Show help if requested
if [ "$HELP" = true ]; then
    show_help
    exit 0
fi

# Main execution
echo -e "${CYAN}🚀 RunAnywhere Web SDK Build Script${NC}"
echo ""

# Ensure we're in the correct directory
if [ ! -f "package.json" ] || ! grep -q "@runanywhere/web-voice-sdk" package.json; then
    print_error "Please run this script from the SDK root directory (sdk/runanywhere-web/)"
    exit 1
fi

# Clean if requested
if [ "$CLEAN" = true ]; then
    clean_build
    echo ""
fi

# Install dependencies
print_status "Installing dependencies..."
if [ "$VERBOSE" = true ]; then
    pnpm install
else
    pnpm install > /dev/null 2>&1
fi
print_success "Dependencies installed"
echo ""

# Build based on mode
case $BUILD_MODE in
    "fast")
        fast_build
        ;;
    "detailed")
        detailed_build
        ;;
    *)
        print_error "Unknown build mode: $BUILD_MODE"
        exit 1
        ;;
esac

# Display build summary
echo ""
print_success "🎉 Build Summary:"
echo "  - Core packages: ✅"
echo "  - Performance packages: ✅"
echo "  - Service packages: ✅"
echo "  - Modular adapter packages: ✅"
echo "  - Framework adapters: ✅"
echo ""

# Run demo if requested
if [ "$RUN_DEMO" = true ]; then
    run_demo
else
    print_success "SDK built successfully!"
    echo ""
    print_info "To run a demo:"
    echo "  $0 --run                          # Run React demo"
    echo "  $0 --run --demo-type runanywhere  # Run RunAnywhere Next.js app"
    echo "  $0 --run --demo-type vue          # Run Vue demo"
    echo "  $0 --run --demo-type angular      # Run Angular demo"
fi

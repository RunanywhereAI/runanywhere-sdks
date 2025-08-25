#!/bin/bash

# =============================================================================
# RunAnywhere Web - Complete Build and Run Script
# =============================================================================
#
# This unified script handles everything: SDK building, web app building, and running.
# It combines functionality from the SDK build script and web app management.
#
# USAGE:
#   ./build-and-run.sh [COMMAND] [OPTIONS]
#
# COMMANDS:
#   build-sdk         Build only the SDK packages
#   build-app         Build only the web application
#   run               Build SDK + app and run (default)
#   dev               Start development server without building
#   clean             Clean all build artifacts
#
# OPTIONS:
#   --fast            Fast build using pnpm workspace (default)
#   --detailed        Detailed build with per-package progress
#   --clean           Clean all build artifacts before building
#   --test-stt        Open STT test page after launch
#   --test-vad        Open VAD test page after launch
#   --verbose         Show detailed build output
#   --install-deps    Install missing web app dependencies
#
# EXAMPLES:
#   ./build-and-run.sh                    # Full fast build and run (default)
#   ./build-and-run.sh build-sdk          # Build only SDK
#   ./build-and-run.sh run --test-stt     # Build and run with STT test page
#   ./build-and-run.sh dev --test-vad     # Just start dev server with VAD test
#   ./build-and-run.sh clean              # Clean everything
#   ./build-and-run.sh --detailed --clean # Detailed clean build
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
COMMAND="run"
BUILD_MODE="fast"
CLEAN=false
VERBOSE=false
TEST_PAGE=""
INSTALL_DEPS=false

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
    echo -e "${CYAN}RunAnywhere Web - Complete Build and Run Script${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  build-sdk           Build only the SDK packages (includes workers)"
    echo "  build-app           Build only the web application"
    echo "  run                 Build SDK + app and run (default)"
    echo "  dev                 Start development server without building"
    echo "  clean               Clean all build artifacts"
    echo ""
    echo "Options:"
    echo "  --fast              Fast build using pnpm workspace (default)"
    echo "  --detailed          Detailed build with per-package progress"
    echo "  --clean             Clean all build artifacts before building"
    echo "  --test-stt          Open STT test page after launch"
    echo "  --test-vad          Open VAD test page after launch"
    echo "  --verbose           Show detailed build output"
    echo "  --install-deps      Install missing web app dependencies"
    echo "  --help              Show this help message"
    echo ""
    echo "Build Process:"
    echo "  1. Cleans dist directories when --clean is used"
    echo "  2. Builds all SDK packages with TypeScript declarations"
    echo "  3. Special handling for stt-whisper:"
    echo "     - Builds main package with TypeScript"
    echo "     - Builds stt.worker.ts separately with Vite"
    echo "     - Bundles transformers.js (~57MB) into worker"
    echo "     - Copies worker to public/stt-worker.js"
    echo "  4. Verifies critical files are created"
    echo ""
    echo "Examples:"
    echo "  $0                      # Full fast build and run"
    echo "  $0 build-sdk --clean    # Clean and rebuild SDK only"
    echo "  $0 run --test-stt       # Build and run with STT test"
    echo "  $0 dev --test-vad       # Just start dev server with VAD test"
    echo "  $0 --detailed --clean   # Clean build with detailed output"
    echo ""
}

# Parse command line arguments
# First argument might be a command
if [[ $# -gt 0 ]] && [[ $1 != --* ]]; then
    COMMAND="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --fast)
            BUILD_MODE="fast"
            shift
            ;;
        --detailed)
            BUILD_MODE="detailed"
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --test-stt)
            TEST_PAGE="test-stt"
            shift
            ;;
        --test-vad)
            TEST_PAGE="test-vad"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --install-deps)
            INSTALL_DEPS=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Get the script directory and SDK root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "$SCRIPT_DIR/../../../sdk/runanywhere-web" && pwd)"
APP_ROOT="$SCRIPT_DIR"

# Function to run command with output control
run_command() {
    local cmd="$1"
    local desc="$2"

    if [ "$VERBOSE" = true ]; then
        print_status "$desc"
        eval "$cmd"
    else
        print_status "$desc"
        if ! eval "$cmd" > /dev/null 2>&1; then
            print_error "Failed: $desc"
            print_warning "Run with --verbose to see detailed errors"
            exit 1
        fi
    fi
}

# Function to kill existing processes
cleanup_processes() {
    print_status "Cleaning up existing processes..."
    pkill -f "next dev" 2>/dev/null || true
    pkill -f "vite" 2>/dev/null || true
    pkill -f "node.*next" 2>/dev/null || true
    lsof -ti:3000 2>/dev/null | xargs kill -9 2>/dev/null || true
    lsof -ti:3001 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 2
    print_success "Processes cleaned up"
}

# Function to clean build artifacts
clean_build() {
    if [ "$CLEAN" = true ]; then
        print_status "Cleaning build artifacts..."

        # Clean SDK packages
        cd "$SDK_ROOT"
        find packages -name "dist" -type d -exec rm -rf {} + 2>/dev/null || true
        find packages -name "*.tsbuildinfo" -exec rm -f {} + 2>/dev/null || true

        # Clean web app
        cd "$SCRIPT_DIR"
        rm -rf .next 2>/dev/null || true
        rm -rf node_modules/.cache 2>/dev/null || true

        print_success "Build artifacts cleaned"
    fi
}

# Function to clean all build artifacts
clean_all() {
    print_status "Cleaning all build artifacts..."

    # Clean SDK packages
    cd "$SDK_ROOT"
    find packages -name "dist" -type d -exec rm -rf {} + 2>/dev/null || true
    find packages -name "*.tsbuildinfo" -exec rm -f {} + 2>/dev/null || true
    rm -rf node_modules 2>/dev/null || true

    # Clean web app
    cd "$SCRIPT_DIR"
    rm -rf .next 2>/dev/null || true
    rm -rf node_modules/.cache 2>/dev/null || true
    rm -rf node_modules 2>/dev/null || true

    print_success "All build artifacts cleaned"
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

    # Check if it's a TypeScript package and build declarations first
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

    cd "$SDK_ROOT"

    if [ "$VERBOSE" = true ]; then
        print_success "$package_name built successfully"
    fi
}

# Function for fast build
fast_build_sdk() {
    print_status "Fast building all SDK packages..."
    cd "$SDK_ROOT"

    if [ "$VERBOSE" = true ]; then
        # Build core packages first
        pnpm build:core

        # Build adapter packages with proper TypeScript declarations
        for pkg in vad-silero stt-whisper llm-openai tts-webspeech; do
            if [ -d "packages/$pkg" ]; then
                echo "Building declarations and bundle for $pkg..."

                # Special handling for stt-whisper - clean and build with worker
                if [ "$pkg" = "stt-whisper" ]; then
                    cd "packages/$pkg"
                    echo "Cleaning STT build directory..."
                    rm -rf dist

                    # Build the main package
                    pnpm build

                    # Build the worker separately using Vite
                    echo "Building STT worker with Vite..."
                    npx vite build --config vite.config.worker.ts

                    # Find and copy the built worker
                    WORKER_FILE="dist/stt.worker.js"
                    if [ -f "$WORKER_FILE" ]; then
                        cp "$WORKER_FILE" "${APP_ROOT}/public/stt-worker.js"
                        echo "STT worker copied to public directory"
                    else
                        echo "Warning: STT worker build failed"
                    fi
                    cd "$SDK_ROOT"
                else
                    pnpm --filter "@runanywhere/$pkg" build
                fi
            fi
        done

        # Build remaining packages (excluding adapter packages and react which comes last)
        pnpm --filter '@runanywhere/cache' build
        pnpm --filter '@runanywhere/workers' build
        pnpm --filter '@runanywhere/monitoring' build
        pnpm --filter '@runanywhere/llm' build
        pnpm --filter '@runanywhere/transcription' build
        pnpm --filter '@runanywhere/tts' build
        pnpm --filter '@runanywhere/voice' build

        # Build react package last after adapter packages have declarations
        pnpm --filter '@runanywhere/react' build
    else
        # Build core packages first
        pnpm build:core > /dev/null 2>&1

        # Build adapter packages with proper TypeScript declarations
        for pkg in vad-silero stt-whisper llm-openai tts-webspeech; do
            if [ -d "packages/$pkg" ]; then
                echo "Building $pkg..." >&2

                # Special handling for stt-whisper - clean and build with worker
                if [ "$pkg" = "stt-whisper" ]; then
                    cd "packages/$pkg"
                    rm -rf dist > /dev/null 2>&1
                    pnpm build > /dev/null 2>&1

                    # Build the worker
                    npx vite build --config vite.config.worker.ts > /dev/null 2>&1

                    # Copy the built worker
                    WORKER_FILE="dist/stt.worker.js"
                    if [ -f "$WORKER_FILE" ]; then
                        cp "$WORKER_FILE" "$APP_ROOT/public/stt-worker.js" > /dev/null 2>&1
                        echo "STT worker built and deployed" >&2
                    fi
                    cd "$SDK_ROOT"
                else
                    pnpm --filter "@runanywhere/$pkg" build > /dev/null 2>&1
                fi
            fi
        done

        # Build remaining packages (excluding adapter packages and react which comes last)
        pnpm --filter '@runanywhere/cache' build > /dev/null 2>&1
        pnpm --filter '@runanywhere/workers' build > /dev/null 2>&1
        pnpm --filter '@runanywhere/monitoring' build > /dev/null 2>&1
        pnpm --filter '@runanywhere/llm' build > /dev/null 2>&1
        pnpm --filter '@runanywhere/transcription' build > /dev/null 2>&1
        pnpm --filter '@runanywhere/tts' build > /dev/null 2>&1
        pnpm --filter '@runanywhere/voice' build > /dev/null 2>&1

        # Build react package last after adapter packages have declarations
        pnpm --filter '@runanywhere/react' build > /dev/null 2>&1
    fi

    print_success "Fast build completed"
}

# Function for detailed build
detailed_build_sdk() {
    print_status "Detailed build of all SDK packages..."
    echo ""
    cd "$SDK_ROOT"

    # Build packages in dependency order
    print_info "Building core packages..."
    build_package "@runanywhere/core" "packages/core"
    build_package "@runanywhere/cache" "packages/cache"
    build_package "@runanywhere/monitoring" "packages/monitoring"
    build_package "@runanywhere/workers" "packages/workers"

    # Build service packages
    print_info "Building service packages..."
    build_package "@runanywhere/transcription" "packages/transcription"
    build_package "@runanywhere/llm" "packages/llm"
    build_package "@runanywhere/tts" "packages/tts"
    build_package "@runanywhere/voice" "packages/voice"

    # Build modular adapter packages (these need special handling for TypeScript declarations)
    print_info "Building adapter packages with TypeScript declarations..."

    for pkg in vad-silero stt-whisper llm-openai tts-webspeech; do
        if [ -d "packages/$pkg" ]; then
            cd "packages/$pkg"
            print_status "Building TypeScript declarations for @runanywhere/$pkg"
            if [ "$VERBOSE" = true ]; then
                # Always generate TypeScript declarations first
                npx tsc --emitDeclarationOnly
                npm run build:bundle
            else
                # Always generate TypeScript declarations first
                npx tsc --emitDeclarationOnly > /dev/null 2>&1
                npm run build:bundle > /dev/null 2>&1
            fi
            cd "$SDK_ROOT"
            print_success "@runanywhere/$pkg built successfully"
        else
            print_warning "Package @runanywhere/$pkg not found, skipping"
        fi
    done

    # Build framework packages
    print_info "Building framework packages..."
    build_package "@runanywhere/react" "packages/react"
    build_package "@runanywhere/vue" "packages/vue"
    build_package "@runanywhere/angular" "packages/angular"

    print_success "Detailed build completed"
}

# Function to build SDK packages
build_sdk_packages() {
    print_status "Building RunAnywhere Web SDK..."
    cd "$SDK_ROOT"

    # Clean build directories if requested
    if [ "$CLEAN" = true ]; then
        print_status "Cleaning build directories..."
        # Clean all dist directories in SDK packages
        find packages -type d -name "dist" -exec rm -rf {} + 2>/dev/null || true
        # Clean worker files from public directory
        rm -f "$APP_ROOT/public/stt-worker.js" 2>/dev/null || true
        rm -f "$APP_ROOT/public/vad-worker.js" 2>/dev/null || true
        print_success "Build directories cleaned"
    fi

    # Install dependencies first
    run_command "pnpm install" "Installing SDK dependencies"

    # Build based on mode
    case $BUILD_MODE in
        "fast")
            fast_build_sdk
            ;;
        "detailed")
            detailed_build_sdk
            ;;
        *)
            print_error "Unknown build mode: $BUILD_MODE"
            exit 1
            ;;
    esac

    # Verify critical files were built
    if [ ! -f "$APP_ROOT/public/stt-worker.js" ]; then
        print_warning "STT worker not found. Speech-to-text may not work."
    else
        print_success "STT worker built and deployed successfully"
    fi

    print_success "SDK packages built successfully!"
}

# Function to install web app dependencies
install_webapp_deps() {
    cd "$SCRIPT_DIR"

    # Install missing dependencies that are used by shadcn/ui components
    print_status "Installing missing web app dependencies..."

    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        print_error "package.json not found in web app directory"
        exit 1
    fi

    # Install the missing dependencies
    local deps_to_install=""

    # Check if @radix-ui/react-icons is missing (needed by select component)
    if ! grep -q "@radix-ui/react-icons" package.json; then
        deps_to_install="$deps_to_install @radix-ui/react-icons"
    fi

    # Check if @radix-ui/react-select is missing (needed by select component)
    if ! grep -q "@radix-ui/react-select" package.json; then
        deps_to_install="$deps_to_install @radix-ui/react-select"
    fi

    # Check if @radix-ui/react-progress is missing (needed by progress component)
    if ! grep -q "@radix-ui/react-progress" package.json; then
        deps_to_install="$deps_to_install @radix-ui/react-progress"
    fi

    if [ -n "$deps_to_install" ]; then
        print_status "Installing missing dependencies:$deps_to_install"
        if [ "$VERBOSE" = true ]; then
            npm install $deps_to_install
        else
            npm install $deps_to_install > /dev/null 2>&1
        fi
        print_success "Missing dependencies installed"
    else
        print_success "All dependencies are already installed"
    fi
}

# Function to build only web app
build_webapp_only() {
    print_status "Building web application..."
    cd "$SCRIPT_DIR"

    if [ "$INSTALL_DEPS" = true ]; then
        install_webapp_deps
    fi

    run_command "npm install" "Installing web app dependencies"
    run_command "npm run build" "Building web application"

    print_success "Web application built successfully!"
}

# Function to run web app (dev server)
run_webapp() {
    print_status "Starting Next.js development server..."
    cd "$SCRIPT_DIR"

    # Install web app dependencies if needed
    if [ ! -d "node_modules" ] || [ "$INSTALL_DEPS" = true ]; then
        install_webapp_deps
        run_command "npm install" "Installing web app dependencies"
    fi

    print_warning "Press Ctrl+C to stop the server"
    echo ""

    if [ -n "$TEST_PAGE" ]; then
        print_info "Will open /$TEST_PAGE after server starts"
        echo ""
    fi

    # Start the server and optionally open test page
    if [ -n "$TEST_PAGE" ]; then
        # Start server in background and wait for it to be ready
        npm run dev &
        SERVER_PID=$!

        # Wait for server to be ready
        echo "Waiting for server to start..."
        sleep 8

        # Try to open the test page
        if command -v open >/dev/null; then
            # macOS
            open "http://localhost:3000/$TEST_PAGE" || open "http://localhost:3001/$TEST_PAGE" || true
        elif command -v xdg-open >/dev/null; then
            # Linux
            xdg-open "http://localhost:3000/$TEST_PAGE" || xdg-open "http://localhost:3001/$TEST_PAGE" || true
        fi

        # Wait for server process
        wait $SERVER_PID
    else
        # Just run the server normally
        npm run dev
    fi
}

# Main execution
echo -e "${CYAN}🚀 RunAnywhere Web - Complete Build and Run Script${NC}"
echo -e "${YELLOW}Command: $COMMAND | Build Mode: $BUILD_MODE${NC}"
echo ""

# Execute the requested command
case $COMMAND in
    "clean")
        clean_all
        ;;
    "build-sdk")
        cleanup_processes
        if [ "$CLEAN" = true ]; then
            clean_build
        fi
        build_sdk_packages
        echo ""
        print_success "🎊 SDK Build Complete!"
        echo "  - Core packages: ✅"
        echo "  - Service packages: ✅"
        echo "  - Adapter packages: ✅ (VAD, STT, LLM, TTS with TypeScript declarations)"
        echo "  - Framework packages: ✅"
        ;;
    "build-app")
        cleanup_processes
        build_webapp_only
        ;;
    "dev")
        cleanup_processes
        run_webapp
        ;;
    "run")
        cleanup_processes
        if [ "$CLEAN" = true ]; then
            clean_build
        fi
        build_sdk_packages
        echo ""
        print_success "🎊 SDK Build Complete!"
        echo "  - Core packages: ✅"
        echo "  - Service packages: ✅"
        echo "  - Adapter packages: ✅ (VAD, STT, LLM, TTS with TypeScript declarations)"
        echo "  - Framework packages: ✅"
        echo ""
        run_webapp
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac

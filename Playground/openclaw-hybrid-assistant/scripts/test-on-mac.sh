#!/bin/bash

# =============================================================================
# test-on-mac.sh - Test OpenClaw Hybrid Assistant on Mac using Docker/Lima
# =============================================================================
# This script sets up a Linux environment on Mac and runs the tests.
#
# Usage:
#   ./scripts/test-on-mac.sh              # Auto-detect (Docker or Lima)
#   ./scripts/test-on-mac.sh --docker     # Use Docker
#   ./scripts/test-on-mac.sh --lima       # Use Lima VM
#   ./scripts/test-on-mac.sh --orbstack   # Use OrbStack
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${PROJECT_DIR}/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# =============================================================================
# Detect available virtualization
# =============================================================================

detect_runtime() {
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        echo "docker"
    elif command -v limactl &> /dev/null; then
        echo "lima"
    elif command -v orb &> /dev/null; then
        echo "orbstack"
    else
        echo "none"
    fi
}

# =============================================================================
# Docker testing
# =============================================================================

test_with_docker() {
    print_header "Testing with Docker"

    cd "${ROOT_DIR}"

    print_step "Building Docker image..."
    docker build -t openclaw-assistant -f "${PROJECT_DIR}/Dockerfile" .

    print_step "Running tests..."
    docker run --rm \
        -v "${PROJECT_DIR}/test-audio:/workspace/Playground/openclaw-hybrid-assistant/test-audio" \
        openclaw-assistant \
        ./build/test-components --run-all

    print_success "Docker tests completed"
}

# =============================================================================
# Lima testing
# =============================================================================

test_with_lima() {
    print_header "Testing with Lima VM"

    VM_NAME="openclaw-test"

    # Check if VM exists
    if ! limactl list | grep -q "${VM_NAME}"; then
        print_step "Creating Lima VM (this may take a few minutes)..."

        # Create a minimal Ubuntu VM
        cat > /tmp/lima-openclaw.yaml << 'EOF'
# Lima configuration for OpenClaw testing
images:
  - location: "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
    arch: "x86_64"
  - location: "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-arm64.img"
    arch: "aarch64"

cpus: 4
memory: "8GiB"
disk: "50GiB"

mounts:
  - location: "~"
    writable: true
  - location: "/tmp/lima"
    writable: true

provision:
  - mode: system
    script: |
      #!/bin/bash
      apt-get update
      apt-get install -y build-essential cmake git curl libasound2-dev sox espeak

containerd:
  system: false
  user: false
EOF

        limactl create --name="${VM_NAME}" /tmp/lima-openclaw.yaml
        limactl start "${VM_NAME}"
    else
        # Start VM if not running
        if ! limactl list | grep "${VM_NAME}" | grep -q "Running"; then
            print_step "Starting Lima VM..."
            limactl start "${VM_NAME}"
        fi
    fi

    print_step "Running build and tests in Lima VM..."

    # Run commands in VM
    limactl shell "${VM_NAME}" << EOF
set -e
cd "${ROOT_DIR}"

echo "=== Downloading Sherpa-ONNX ==="
./sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh

echo "=== Building runanywhere-commons ==="
./sdk/runanywhere-commons/scripts/build-linux.sh --shared

echo "=== Downloading models ==="
cd Playground/openclaw-hybrid-assistant
./scripts/download-models.sh
./scripts/download-models.sh --wakeword

echo "=== Generating test audio ==="
chmod +x ./scripts/generate-test-audio.sh
./scripts/generate-test-audio.sh

echo "=== Building ==="
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . -j\$(nproc)
cd ..

echo "=== Running tests ==="
export LD_LIBRARY_PATH="${ROOT_DIR}/sdk/runanywhere-commons/dist/linux/\$(uname -m):${ROOT_DIR}/sdk/runanywhere-commons/third_party/sherpa-onnx-linux/lib:\$LD_LIBRARY_PATH"
./build/test-components --run-all
EOF

    print_success "Lima tests completed"
}

# =============================================================================
# OrbStack testing
# =============================================================================

test_with_orbstack() {
    print_header "Testing with OrbStack"

    MACHINE_NAME="openclaw-test"

    # Check if machine exists
    if ! orb list | grep -q "${MACHINE_NAME}"; then
        print_step "Creating OrbStack machine..."
        orb create ubuntu:22.04 "${MACHINE_NAME}"
    fi

    print_step "Running build and tests in OrbStack..."

    # Install dependencies
    orb run -m "${MACHINE_NAME}" -- sudo apt-get update
    orb run -m "${MACHINE_NAME}" -- sudo apt-get install -y build-essential cmake git curl libasound2-dev sox espeak

    # Mount and run
    orb run -m "${MACHINE_NAME}" -- bash -c "
        cd ${ROOT_DIR}

        echo '=== Building ==='
        ./sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh
        ./sdk/runanywhere-commons/scripts/build-linux.sh --shared

        cd Playground/openclaw-hybrid-assistant
        ./scripts/download-models.sh
        ./scripts/download-models.sh --wakeword
        ./scripts/generate-test-audio.sh

        mkdir -p build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release
        cmake --build . -j\$(nproc)
        cd ..

        echo '=== Running tests ==='
        export LD_LIBRARY_PATH='${ROOT_DIR}/sdk/runanywhere-commons/dist/linux/\$(uname -m):${ROOT_DIR}/sdk/runanywhere-commons/third_party/sherpa-onnx-linux/lib:\$LD_LIBRARY_PATH'
        ./build/test-components --run-all
    "

    print_success "OrbStack tests completed"
}

# =============================================================================
# Main
# =============================================================================

print_header "OpenClaw Hybrid Assistant - Mac Testing"

# Parse arguments
RUNTIME=""
while [[ "$1" == --* ]]; do
    case "$1" in
        --docker)
            RUNTIME="docker"
            shift
            ;;
        --lima)
            RUNTIME="lima"
            shift
            ;;
        --orbstack)
            RUNTIME="orbstack"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--docker|--lima|--orbstack]"
            echo ""
            echo "Options:"
            echo "  --docker     Use Docker (recommended)"
            echo "  --lima       Use Lima VM"
            echo "  --orbstack   Use OrbStack"
            echo ""
            echo "If no option specified, auto-detects available runtime."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Auto-detect if not specified
if [ -z "$RUNTIME" ]; then
    RUNTIME=$(detect_runtime)
fi

case "$RUNTIME" in
    docker)
        test_with_docker
        ;;
    lima)
        test_with_lima
        ;;
    orbstack)
        test_with_orbstack
        ;;
    none)
        print_error "No virtualization runtime found!"
        echo ""
        echo "Please install one of:"
        echo "  - Docker Desktop: https://www.docker.com/products/docker-desktop"
        echo "  - Lima: brew install lima"
        echo "  - OrbStack: brew install --cask orbstack"
        exit 1
        ;;
    *)
        print_error "Unknown runtime: $RUNTIME"
        exit 1
        ;;
esac

echo ""
print_success "All tests completed!"

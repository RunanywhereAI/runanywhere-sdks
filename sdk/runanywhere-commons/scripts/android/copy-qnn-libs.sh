#!/bin/bash
# =============================================================================
# copy-qnn-libs.sh
# Copy QNN libraries for Android AAR bundling
# =============================================================================
#
# Copies the required QNN libraries from the QAIRT SDK to the specified
# output directory for bundling with the Android AAR.
#
# Usage:
#   ./copy-qnn-libs.sh <output_dir> [--include-prepare]
#
# Options:
#   --include-prepare   Include libQnnHtpPrepare.so (adds ~74MB, optional)
#
# Environment Variables:
#   QNN_SDK_ROOT or QAIRT_SDK_ROOT - Path to QAIRT/QNN SDK
#
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Parse Arguments
# =============================================================================

OUTPUT_DIR=""
INCLUDE_PREPARE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --include-prepare)
            INCLUDE_PREPARE=true
            shift
            ;;
        --help|-h)
            head -30 "$0" | grep -E "^#" | sed 's/^# *//' | tail -n +3
            exit 0
            ;;
        *)
            if [[ -z "$OUTPUT_DIR" ]]; then
                OUTPUT_DIR="$1"
            else
                log_error "Unknown option: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
    log_error "Usage: $0 <output_dir> [--include-prepare]"
    exit 1
fi

# =============================================================================
# Find QNN SDK
# =============================================================================

QNN_SDK_ROOT="${QNN_SDK_ROOT:-$QAIRT_SDK_ROOT}"
if [[ -z "$QNN_SDK_ROOT" ]]; then
    log_error "QNN SDK not found!"
    log_error "Set QNN_SDK_ROOT or QAIRT_SDK_ROOT environment variable"
    exit 1
fi

QNN_LIB_DIR="$QNN_SDK_ROOT/lib/aarch64-android"
if [[ ! -d "$QNN_LIB_DIR" ]]; then
    log_error "QNN Android libraries not found at: $QNN_LIB_DIR"
    exit 1
fi

log_info "QNN SDK: $QNN_SDK_ROOT"
log_info "Output: $OUTPUT_DIR"

# =============================================================================
# Required Libraries
# =============================================================================

# Core QNN libraries (always required)
CORE_LIBS=(
    "libQnnHtp.so"              # HTP backend (~2.5MB)
    "libQnnSystem.so"           # QNN system library
)

# HTP skeleton stubs (required for different Hexagon architectures)
HTP_STUBS=(
    "libQnnHtpV68Stub.so"       # Hexagon V68 (8 Gen 1)
    "libQnnHtpV69Stub.so"       # Hexagon V69 (8+ Gen 1)
    "libQnnHtpV73Stub.so"       # Hexagon V73 (8 Gen 2)
    "libQnnHtpV75Stub.so"       # Hexagon V75 (8 Gen 3)
)

# Optional prepare library (large, only needed for runtime compilation)
PREPARE_LIB="libQnnHtpPrepare.so"  # ~74MB

# =============================================================================
# Copy Libraries
# =============================================================================

mkdir -p "$OUTPUT_DIR/arm64-v8a"

TOTAL_SIZE=0

# Copy core libraries
log_info "Copying core QNN libraries..."
for lib in "${CORE_LIBS[@]}"; do
    src="$QNN_LIB_DIR/$lib"
    if [[ -f "$src" ]]; then
        cp "$src" "$OUTPUT_DIR/arm64-v8a/"
        size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null || echo 0)
        TOTAL_SIZE=$((TOTAL_SIZE + size))
        log_success "  $lib ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "$((size/1024))KB"))"
    else
        log_error "  Required library not found: $lib"
        exit 1
    fi
done

# Copy HTP stubs (best effort - not all may be present)
log_info "Copying HTP skeleton stubs..."
for lib in "${HTP_STUBS[@]}"; do
    src="$QNN_LIB_DIR/$lib"
    if [[ -f "$src" ]]; then
        cp "$src" "$OUTPUT_DIR/arm64-v8a/"
        size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null || echo 0)
        TOTAL_SIZE=$((TOTAL_SIZE + size))
        log_success "  $lib ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "$((size/1024))KB"))"
    else
        log_warning "  Not found (optional): $lib"
    fi
done

# Optionally copy prepare library
if [[ "$INCLUDE_PREPARE" == true ]]; then
    log_info "Copying HTP prepare library (large)..."
    src="$QNN_LIB_DIR/$PREPARE_LIB"
    if [[ -f "$src" ]]; then
        cp "$src" "$OUTPUT_DIR/arm64-v8a/"
        size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null || echo 0)
        TOTAL_SIZE=$((TOTAL_SIZE + size))
        log_success "  $PREPARE_LIB ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "$((size/1024/1024))MB"))"
    else
        log_warning "  Not found: $PREPARE_LIB"
    fi
else
    log_info "Skipping $PREPARE_LIB (use --include-prepare to include)"
    log_info "  Note: Only needed for runtime graph compilation"
    log_info "  Using pre-compiled context binaries avoids this 74MB library"
fi

# =============================================================================
# Create Manifest
# =============================================================================

cat > "$OUTPUT_DIR/QNN_LIBRARIES.md" << EOF
# QNN Libraries for RunAnywhere SDK

## Included Libraries

$(ls -la "$OUTPUT_DIR/arm64-v8a/"*.so 2>/dev/null | awk '{print "- " $NF " (" $5 " bytes)"}')

## Purpose

- **libQnnHtp.so**: QNN HTP (Hexagon Tensor Processor) backend
- **libQnnSystem.so**: QNN system utilities
- **libQnnHtpV*.Stub.so**: Hexagon architecture-specific skeletons

## Supported SoCs

- SM8650 (Snapdragon 8 Gen 3) - V75
- SM8550 (Snapdragon 8 Gen 2) - V73
- SM8450 (Snapdragon 8 Gen 1) - V69
- SM8350 (Snapdragon 888) - V68

## Notes

$(if [[ "$INCLUDE_PREPARE" == true ]]; then
    echo "- libQnnHtpPrepare.so included for runtime compilation"
else
    echo "- libQnnHtpPrepare.so NOT included (use pre-compiled context binaries)"
fi)

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
QNN SDK: $QNN_SDK_ROOT
EOF

log_success "Created QNN_LIBRARIES.md"

# =============================================================================
# Summary
# =============================================================================

log_info ""
log_info "=============================================="
log_success "QNN Libraries Copied"
log_info "=============================================="
log_info "Output: $OUTPUT_DIR/arm64-v8a/"
log_info ""
log_info "Libraries:"
ls -la "$OUTPUT_DIR/arm64-v8a/"
log_info ""
log_info "Total size: $(du -sh "$OUTPUT_DIR/arm64-v8a/" | cut -f1)"
log_info ""
log_info "To bundle with AAR:"
log_info "  Copy $OUTPUT_DIR/arm64-v8a/ to src/main/jniLibs/"
log_info "=============================================="

#!/bin/bash
#
# analyze-binary-size.sh - Analyze XCFramework binary sizes
#
# Usage: ./scripts/analyze-binary-size.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="${ROOT_DIR}/dist"

echo "=== RunAnywhere Commons Binary Size Analysis ==="
echo ""

# Function to format size
format_size() {
    local size=$1
    if [ "$size" -gt 1073741824 ]; then
        echo "$(echo "scale=2; $size/1073741824" | bc) GB"
    elif [ "$size" -gt 1048576 ]; then
        echo "$(echo "scale=2; $size/1048576" | bc) MB"
    elif [ "$size" -gt 1024 ]; then
        echo "$(echo "scale=2; $size/1024" | bc) KB"
    else
        echo "$size B"
    fi
}

# Expected limits
declare -A LIMITS
LIMITS["RACommons"]=2097152           # 2 MB
LIMITS["RABackendLlamaCPP"]=26214400  # 25 MB
LIMITS["RABackendONNX"]=73400320      # 70 MB
LIMITS["RABackendWhisperCPP"]=15728640 # 15 MB

TOTAL_SIZE=0
PASS=true

for FRAMEWORK in RACommons RABackendLlamaCPP RABackendONNX RABackendWhisperCPP; do
    XCFRAMEWORK="${DIST_DIR}/${FRAMEWORK}.xcframework"

    if [ -d "$XCFRAMEWORK" ]; then
        SIZE=$(du -sb "$XCFRAMEWORK" | cut -f1)
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
        LIMIT=${LIMITS[$FRAMEWORK]}

        if [ "$SIZE" -gt "$LIMIT" ]; then
            STATUS="❌ OVER"
            PASS=false
        else
            PERCENT=$((SIZE * 100 / LIMIT))
            STATUS="✅ ${PERCENT}%"
        fi

        echo "${FRAMEWORK}:"
        echo "  Size:  $(format_size $SIZE)"
        echo "  Limit: $(format_size $LIMIT)"
        echo "  Status: $STATUS"
        echo ""

        # Analyze internal structure
        echo "  Architectures:"
        for SLICE in "$XCFRAMEWORK"/*; do
            if [ -d "$SLICE" ]; then
                SLICE_NAME=$(basename "$SLICE")
                SLICE_SIZE=$(du -sb "$SLICE" | cut -f1)
                echo "    ${SLICE_NAME}: $(format_size $SLICE_SIZE)"
            fi
        done
        echo ""
    else
        echo "${FRAMEWORK}: NOT FOUND"
        echo ""
    fi
done

echo "=== Summary ==="
echo "Total size: $(format_size $TOTAL_SIZE)"
echo ""

if [ "$PASS" = true ]; then
    echo "✅ All frameworks within size limits"
    exit 0
else
    echo "❌ Some frameworks exceed size limits"
    exit 1
fi

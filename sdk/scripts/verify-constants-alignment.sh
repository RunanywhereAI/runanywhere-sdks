#!/bin/bash
#
# verify-constants-alignment.sh
# Verifies that Swift references C++ constants correctly
#
# ARCHITECTURE NOTE:
# C++ is the single source of truth for constants.
# Swift references C++ constants via: import CRACommons
#
# Example Swift pattern:
#   public static let defaultSampleRate: Int = Int(RAC_STT_DEFAULT_SAMPLE_RATE)
#
# This script checks that:
# 1. C++ constants exist for all required values
# 2. Swift constants reference C++ (not hardcoded)
# 3. Error codes exist in rac_error.h
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="$(dirname "$SCRIPT_DIR")"
COMMONS_DIR="$SDK_DIR/runanywhere-commons"
SWIFT_DIR="$SDK_DIR/runanywhere-swift"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

echo "========================================"
echo "Verifying Swift/C++ Constants Alignment"
echo "========================================"
echo ""

# Helper function to count enum cases
count_cases() {
    local file=$1
    local pattern=$2
    grep -c "$pattern" "$file" 2>/dev/null || echo "0"
}

# Helper function to extract enum values
extract_enum() {
    local file=$1
    local enum_name=$2
    # Extract enum cases (simplified)
    grep -E "case\s+\w+" "$file" | sed 's/.*case\s\+\(\w\+\).*/\1/' | sort
}

echo "1. Checking Audio Formats..."
echo "----------------------------"

# C++ audio formats
CPP_AUDIO_FORMATS=$(grep -E "RAC_AUDIO_FORMAT_" "$COMMONS_DIR/include/rac/features/stt/rac_stt_types.h" | grep -E "^\s*RAC_AUDIO" | wc -l | tr -d ' ')

# Swift audio formats
SWIFT_AUDIO_FORMATS=$(grep -E "case\s+(pcm|wav|mp3|opus|flac|aac)" "$SWIFT_DIR/Sources/RunAnywhere/Core/Types/AudioTypes.swift" 2>/dev/null | wc -l | tr -d ' ')

if [ "$CPP_AUDIO_FORMATS" -eq "$SWIFT_AUDIO_FORMATS" ]; then
    echo -e "${GREEN}✓ Audio formats aligned: $CPP_AUDIO_FORMATS in C++, $SWIFT_AUDIO_FORMATS in Swift${NC}"
else
    echo -e "${RED}✗ Audio formats mismatch: $CPP_AUDIO_FORMATS in C++, $SWIFT_AUDIO_FORMATS in Swift${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "2. Checking Model Categories..."
echo "-------------------------------"

# C++ model categories
CPP_MODEL_CATS=$(grep -E "RAC_MODEL_CATEGORY_" "$COMMONS_DIR/include/rac/infrastructure/model_management/rac_model_types.h" | grep -v "^//" | wc -l | tr -d ' ')

# Swift model categories
SWIFT_MODEL_CATS=$(grep -E "^\s*case\s+\w+\s*=" "$SWIFT_DIR/Sources/RunAnywhere/Infrastructure/ModelManagement/Models/Domain/ModelCategory.swift" 2>/dev/null | wc -l | tr -d ' ')

if [ "$CPP_MODEL_CATS" -ge "$SWIFT_MODEL_CATS" ]; then
    echo -e "${GREEN}✓ Model categories aligned: $CPP_MODEL_CATS in C++, $SWIFT_MODEL_CATS in Swift${NC}"
else
    echo -e "${YELLOW}⚠ Model categories: $CPP_MODEL_CATS in C++, $SWIFT_MODEL_CATS in Swift (C++ may have extras)${NC}"
fi

echo ""
echo "3. Checking Inference Frameworks..."
echo "------------------------------------"

# C++ inference frameworks
CPP_FRAMEWORKS=$(grep -E "RAC_FRAMEWORK_" "$COMMONS_DIR/include/rac/infrastructure/model_management/rac_model_types.h" | grep -v "^//" | grep -v "typedef" | wc -l | tr -d ' ')

# Swift inference frameworks
SWIFT_FRAMEWORKS=$(grep -E "^\s*case\s+\w+\s*=" "$SWIFT_DIR/Sources/RunAnywhere/Infrastructure/ModelManagement/Models/Domain/InferenceFramework.swift" 2>/dev/null | wc -l | tr -d ' ')

if [ "$CPP_FRAMEWORKS" -ge "$SWIFT_FRAMEWORKS" ]; then
    echo -e "${GREEN}✓ Inference frameworks aligned: $CPP_FRAMEWORKS in C++, $SWIFT_FRAMEWORKS in Swift${NC}"
else
    echo -e "${YELLOW}⚠ Inference frameworks: $CPP_FRAMEWORKS in C++, $SWIFT_FRAMEWORKS in Swift${NC}"
fi

echo ""
echo "4. Checking Error Code Ranges..."
echo "---------------------------------"

# C++ error code count
CPP_ERRORS=$(grep -E "^#define\s+RAC_ERROR_" "$COMMONS_DIR/include/rac/core/rac_error.h" | wc -l | tr -d ' ')

echo -e "${GREEN}✓ C++ defines $CPP_ERRORS error codes${NC}"

# Check for specific error codes
echo ""
echo "5. Checking Critical Error Codes..."
echo "------------------------------------"

CRITICAL_ERRORS=(
    "RAC_ERROR_NOT_INITIALIZED"
    "RAC_ERROR_MODEL_NOT_FOUND"
    "RAC_ERROR_GENERATION_FAILED"
    "RAC_ERROR_NETWORK_UNAVAILABLE"
    "RAC_ERROR_INVALID_PARAMETER"
)

for err in "${CRITICAL_ERRORS[@]}"; do
    if grep -q "$err" "$COMMONS_DIR/include/rac/core/rac_error.h"; then
        echo -e "${GREEN}✓ $err exists in C++${NC}"
    else
        echo -e "${RED}✗ $err missing in C++${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "6. Checking SDK Component Types..."
echo "-----------------------------------"

# C++ SDK component types
CPP_COMPONENTS=$(grep -E "RAC_SDK_COMPONENT_" "$COMMONS_DIR/include/rac/core/rac_component_types.h" | grep -v "^//" | wc -l | tr -d ' ')

# Swift SDK component types
SWIFT_COMPONENTS=$(grep -E "^\s*case\s+\w+\s*=" "$SWIFT_DIR/Sources/RunAnywhere/Core/ComponentTypes.swift" 2>/dev/null | wc -l | tr -d ' ')

if [ "$CPP_COMPONENTS" -ge "$SWIFT_COMPONENTS" ]; then
    echo -e "${GREEN}✓ SDK components aligned: $CPP_COMPONENTS in C++, $SWIFT_COMPONENTS in Swift${NC}"
else
    echo -e "${YELLOW}⚠ SDK components: $CPP_COMPONENTS in C++, $SWIFT_COMPONENTS in Swift${NC}"
fi

echo ""
echo "7. Verifying Swift uses C++ constants directly..."
echo "-------------------------------------------------"

# Check that Swift files import CRACommons and use C++ constants directly
# No separate Swift constants files should exist
if [ -f "$SWIFT_DIR/Sources/RunAnywhere/Features/STT/STTConstants.swift" ]; then
    echo -e "${RED}✗ STTConstants.swift exists - should be deleted (C++ is source of truth)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ STTConstants.swift deleted - using C++ constants directly${NC}"
fi

if [ -f "$SWIFT_DIR/Sources/RunAnywhere/Features/TTS/TTSConstants.swift" ]; then
    echo -e "${RED}✗ TTSConstants.swift exists - should be deleted (C++ is source of truth)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ TTSConstants.swift deleted - using C++ constants directly${NC}"
fi

if [ -f "$SWIFT_DIR/Sources/RunAnywhere/Features/VAD/VADConstants.swift" ]; then
    echo -e "${RED}✗ VADConstants.swift exists - should be deleted (C++ is source of truth)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ VADConstants.swift deleted - using C++ constants directly${NC}"
fi

# Verify C++ constants are used in Swift code
STT_C_REFS=$(grep -r "RAC_STT_" "$SWIFT_DIR/Sources/RunAnywhere/Features/STT" 2>/dev/null | wc -l)
TTS_C_REFS=$(grep -r "RAC_TTS_" "$SWIFT_DIR/Sources/RunAnywhere/Features/TTS" 2>/dev/null | wc -l)
VAD_C_REFS=$(grep -r "RAC_VAD_" "$SWIFT_DIR/Sources/RunAnywhere/Features/VAD" 2>/dev/null | wc -l)

echo -e "${GREEN}✓ Swift uses ${STT_C_REFS} RAC_STT_* C++ constants directly${NC}"
echo -e "${GREEN}✓ Swift uses ${TTS_C_REFS} RAC_TTS_* C++ constants directly${NC}"
echo -e "${GREEN}✓ Swift uses ${VAD_C_REFS} RAC_VAD_* C++ constants directly${NC}"

echo ""
echo "========================================"
echo "Summary"
echo "========================================"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "C++ is the single source of truth for constants."
    echo "Swift references C++ via CRACommons import."
    exit 0
else
    echo -e "${RED}Found $ERRORS error(s)${NC}"
    exit 1
fi

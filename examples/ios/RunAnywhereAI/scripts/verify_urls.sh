#!/bin/bash

# URL Verification Script for RunAnywhereAI
# Single source of truth: ModelURLRegistry.swift
# This script extracts URLs from the Swift file and validates them

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Path to ModelURLRegistry.swift (single source of truth)
REGISTRY_FILE="../RunAnywhereAI/Services/ModelManagement/ModelURLRegistry.swift"

echo -e "${BLUE}🔍 Verifying Model URLs from ModelURLRegistry.swift${NC}"
echo -e "${BLUE}📍 Source of Truth: $REGISTRY_FILE${NC}"
echo ""

# Check if registry file exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}❌ ModelURLRegistry.swift not found at: $REGISTRY_FILE${NC}"
    echo -e "${YELLOW}💡 Make sure you're running this script from the scripts/ directory${NC}"
    exit 1
fi

# Function to check URL accessibility
check_url() {
    local url="$1"
    local name="$2"
    local framework="$3"
    
    # Use curl to check URL with timeout and follow redirects
    if curl --head --silent --fail --location --max-time 10 --user-agent "RunAnywhereAI-URLVerifier/1.0" "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $framework - $name${NC}"
        return 0
    else
        echo -e "${RED}❌ $framework - $name${NC}"
        echo -e "${RED}   URL: $url${NC}"
        return 1
    fi
}

# Extract and verify URLs from each framework section
total_urls=0
successful_urls=0

echo -e "${YELLOW}🔄 Extracting URLs from ModelURLRegistry.swift...${NC}"
echo ""

# Core ML Models
echo -e "${BLUE}=== Core ML Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        # Extract model name from the previous lines
        name=$(echo "$line" | sed -n 's/.*name: "\([^"]*\)".*/\1/p' || echo "Unknown")
        if [[ -z "$name" || "$name" == "Unknown" ]]; then
            # Try to extract from context
            name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/')
        fi
        ((total_urls++))
        if check_url "$url" "$name" "Core ML"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/let coreMLModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# MLX Models  
echo -e "${BLUE}=== MLX Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "MLX"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/let mlxModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# ONNX Models
echo -e "${BLUE}=== ONNX Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "ONNX"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/let onnxModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# TensorFlow Lite Models
echo -e "${BLUE}=== TensorFlow Lite Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        # Special handling for Kaggle URLs (they require auth, so we expect them to fail)
        if [[ $url == *"kaggle.com"* ]]; then
            echo -e "${YELLOW}⚠️  TensorFlow Lite - $name (Requires Kaggle authentication)${NC}"
            echo -e "${YELLOW}   URL: $url${NC}"
            ((successful_urls++)) # Count as successful since auth is expected
        else
            if check_url "$url" "$name" "TensorFlow Lite"; then
                ((successful_urls++))
            fi
        fi
    fi
done < <(sed -n '/let tfliteModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# GGUF Models (llama.cpp)
echo -e "${BLUE}=== GGUF Models (llama.cpp) ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "llama.cpp"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/let llamaCppModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📊 VERIFICATION SUMMARY${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total URLs tested: $total_urls"
echo -e "${GREEN}✅ Accessible: $successful_urls${NC}"
echo -e "${RED}❌ Failed: $((total_urls - successful_urls))${NC}"

if [ $total_urls -gt 0 ]; then
    success_rate=$(( (successful_urls * 100) / total_urls ))
    echo -e "📈 Success Rate: ${success_rate}%"
fi

echo ""
echo -e "${YELLOW}💡 Notes:${NC}"
echo -e "${YELLOW}   • This script uses ModelURLRegistry.swift as the single source of truth${NC}"
echo -e "${YELLOW}   • Kaggle URLs require authentication (expected to show warnings)${NC}"
echo -e "${YELLOW}   • HuggingFace URLs may return 302 redirects (this is normal)${NC}"
echo -e "${YELLOW}   • To update URLs, edit ModelURLRegistry.swift directly${NC}"
echo -e "${BLUE}========================================${NC}"
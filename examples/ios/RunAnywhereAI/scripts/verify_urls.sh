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

# Function to format bytes to human readable format
format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes} bytes"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(( bytes / 1024 )) KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(( bytes / 1048576 )) MB"
    else
        echo "$(( bytes / 1073741824 )) GB"
    fi
}

# Function to check URL accessibility and file size
check_url() {
    local url="$1"
    local name="$2"
    local framework="$3"
    local expected_size="$4"
    
    # Skip built-in URLs
    if [[ $url == "builtin://"* ]]; then
        echo -e "${BLUE}🏗️  $framework - $name (Built-in model)${NC}"
        return 0
    fi
    
    # Get headers including content-length
    local headers=$(curl --head --silent --location --max-time 20 --retry 2 --user-agent "RunAnywhereAI-URLVerifier/1.0" "$url" 2>&1)
    local curl_exit_code=$?
    
    if [ $curl_exit_code -eq 0 ]; then
        # Extract content-length
        local content_length=$(echo "$headers" | grep -i "content-length" | tail -1 | awk '{print $2}' | tr -d '\r')
        local http_status=$(echo "$headers" | head -n 1 | awk '{print $2}')
        
        # If no content-length in headers, try a range request
        if [ -z "$content_length" ] || [ "$content_length" -eq 0 ]; then
            # Try to get file size with a partial content request
            local partial_headers=$(curl --head --silent --location --max-time 20 --retry 2 --user-agent "RunAnywhereAI-URLVerifier/1.0" --header "Range: bytes=0-0" "$url" 2>&1)
            if echo "$partial_headers" | grep -q "Content-Range"; then
                content_length=$(echo "$partial_headers" | grep -i "content-range" | sed 's/.*\///' | tr -d '\r')
            fi
        fi
        
        # Format size for display
        local size_display="Unknown"
        if [ -n "$content_length" ] && [ "$content_length" -gt 0 ]; then
            size_display=$(format_bytes $content_length)
        fi
        
        # Check if size is suspiciously small (less than 1KB)
        if [ -n "$content_length" ] && [ "$content_length" -lt 1024 ] && [ "$content_length" -gt 0 ]; then
            echo -e "${RED}⚠️  $framework - $name (WARNING: Suspiciously small - $size_display)${NC}"
            echo -e "${RED}   URL: $url${NC}"
            echo -e "${RED}   Expected: ~$expected_size, Actual: $size_display${NC}"
            return 1
        elif [ "$http_status" == "200" ] || [ "$http_status" == "302" ] || [ "$http_status" == "301" ]; then
            echo -e "${GREEN}✅ $framework - $name ($size_display)${NC}"
            if [ "$expected_size" != "Unknown" ] && [ "$size_display" != "Unknown" ]; then
                echo -e "${GREEN}   Expected: ~$expected_size, Actual: $size_display${NC}"
            fi
            return 0
        else
            echo -e "${RED}❌ $framework - $name (HTTP $http_status)${NC}"
            echo -e "${RED}   URL: $url${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ $framework - $name (Connection failed)${NC}"
        echo -e "${RED}   URL: $url${NC}"
        return 1
    fi
}

# Extract and verify URLs from each framework section
total_urls=0
successful_urls=0

echo -e "${YELLOW}🔄 Extracting URLs from ModelURLRegistry.swift...${NC}"
echo ""

# Foundation Models (Built-in)
echo -e "${BLUE}=== Foundation Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ downloadURL:\ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        size=$(grep -B15 "$line" "$REGISTRY_FILE" | grep 'size:' | tail -1 | sed 's/.*size: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "Foundation Models" "$size"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/private var _foundationModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# Core ML Models
echo -e "${BLUE}=== Core ML Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ downloadURL:\ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        size=$(grep -B15 "$line" "$REGISTRY_FILE" | grep 'size:' | tail -1 | sed 's/.*size: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "Core ML" "$size"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/private var _coreMLModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# MLX Models  
echo -e "${BLUE}=== MLX Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ downloadURL:\ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "MLX"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/private var _mlxModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# ONNX Models
echo -e "${BLUE}=== ONNX Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ downloadURL:\ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "ONNX"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/private var _onnxModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# TensorFlow Lite Models
echo -e "${BLUE}=== TensorFlow Lite Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ downloadURL:\ URL\(string:\ \"([^\"]+)\" ]]; then
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
done < <(sed -n '/private var _tfliteModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# Swift Transformers Models
echo -e "${BLUE}=== Swift Transformers Models ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ downloadURL:\ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        size=$(grep -B15 "$line" "$REGISTRY_FILE" | grep 'size:' | tail -1 | sed 's/.*size: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "Swift Transformers" "$size"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/private var _swiftTransformersModels.*=/,/^    ]/p' "$REGISTRY_FILE")

echo ""

# GGUF Models (llama.cpp)
echo -e "${BLUE}=== GGUF Models (llama.cpp) ===${NC}"
while IFS= read -r line; do
    if [[ $line =~ downloadURL:\ URL\(string:\ \"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
        name=$(grep -B5 "$line" "$REGISTRY_FILE" | grep 'name:' | tail -1 | sed 's/.*name: "\([^"]*\)".*/\1/' || echo "Unknown")
        ((total_urls++))
        if check_url "$url" "$name" "llama.cpp"; then
            ((successful_urls++))
        fi
    fi
done < <(sed -n '/private var _llamaCppModels.*=/,/^    ]/p' "$REGISTRY_FILE")

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
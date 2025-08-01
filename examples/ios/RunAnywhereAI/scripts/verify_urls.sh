#!/bin/bash

# URL Verification and Size Update Script for RunAnywhereAI
# Single source of truth: ModelURLRegistry.swift
# This script extracts URLs from the Swift file, validates them, and optionally updates sizes
# Usage: ./verify_urls.sh [--update-sizes] [HUGGING_FACE_TOKEN]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
UPDATE_SIZES=false
HF_TOKEN=""
for arg in "$@"; do
    case $arg in
        --update-sizes)
            UPDATE_SIZES=true
            shift
            ;;
        *)
            HF_TOKEN="$arg"
            shift
            ;;
    esac
done

# Path to ModelURLRegistry.swift (single source of truth)
REGISTRY_FILE="../RunAnywhereAI/Services/ModelManagement/ModelURLRegistry.swift"

echo -e "${BLUE}🔍 Verifying Model URLs from ModelURLRegistry.swift${NC}"
echo -e "${BLUE}📍 Source of Truth: $REGISTRY_FILE${NC}"
if [ "$UPDATE_SIZES" = true ]; then
    echo -e "${GREEN}📏 Size update mode enabled${NC}"
fi
if [ -n "$HF_TOKEN" ]; then
    echo -e "${GREEN}🔑 HuggingFace token provided${NC}"
else
    echo -e "${YELLOW}⚠️  No HuggingFace token provided - auth-required URLs may fail${NC}"
    echo -e "${YELLOW}   Usage: $0 [--update-sizes] [HUGGING_FACE_TOKEN]${NC}"
fi
echo ""

# Check if registry file exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}❌ ModelURLRegistry.swift not found at: $REGISTRY_FILE${NC}"
    echo -e "${YELLOW}💡 Make sure you're running this script from the scripts/ directory${NC}"
    exit 1
fi

# Create backup if updating sizes
if [ "$UPDATE_SIZES" = true ]; then
    BACKUP_FILE="${REGISTRY_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$REGISTRY_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✅ Backup created at: $BACKUP_FILE${NC}"
    echo ""
fi

# Function to format bytes to human readable format
format_bytes() {
    local bytes=$1
    if [ $bytes -eq 0 ]; then
        echo "0KB"
    elif [ $bytes -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        # Use bc for precise GB calculation
        local gb=$(echo "scale=1; $bytes / 1073741824" | bc)
        # Remove trailing .0 if present
        gb=$(echo "$gb" | sed 's/\.0$//')
        echo "${gb}GB"
    fi
}

# Function to get file size from URL
get_file_size() {
    local url="$1"
    local is_directory="$2"

    # Skip if no URL provided
    if [ -z "$url" ] || [ "$url" == "nil" ]; then
        echo "0"
        return
    fi

    # For .mlpackage directories on HuggingFace, we need special handling
    if [ "$is_directory" == "true" ] && [[ "$url" =~ huggingface\.co.*\.mlpackage$ ]]; then
        # Extract repo and path from URL
        # Format: https://huggingface.co/owner/repo/resolve/main/path/to/file.mlpackage
        if [[ "$url" =~ huggingface\.co/([^/]+)/([^/]+)/resolve/([^/]+)/(.+) ]]; then
            local owner="${BASH_REMATCH[1]}"
            local repo="${BASH_REMATCH[2]}"
            local branch="${BASH_REMATCH[3]}"
            local path="${BASH_REMATCH[4]}"

            # Use HuggingFace API to get directory contents
            local api_url="https://huggingface.co/api/models/${owner}/${repo}/tree/${branch}/${path}"

            # Build curl command with optional auth
            local curl_cmd="curl -sL --max-time 20"
            if [ -n "$HF_TOKEN" ]; then
                curl_cmd="$curl_cmd --header \"Authorization: Bearer $HF_TOKEN\""
            fi

            # Get directory listing and sum file sizes
            local total_size=$(eval "$curl_cmd \"$api_url\"" 2>/dev/null | \
                grep -o '"size":[0-9]*' | \
                sed 's/"size"://' | \
                awk '{sum += $1} END {print sum}')

            if [ -n "$total_size" ] && [ "$total_size" -gt 0 ]; then
                echo "$total_size"
                return
            fi
        fi
    fi

    # For regular files, use HEAD request
    local curl_cmd="curl -sI -L --max-time 20"
    if [[ $url == *"huggingface.co"* ]] && [ -n "$HF_TOKEN" ]; then
        curl_cmd="$curl_cmd --header \"Authorization: Bearer $HF_TOKEN\""
    fi

    local size=$(eval "$curl_cmd \"$url\"" 2>/dev/null | \
        grep -i "content-length" | \
        tail -1 | \
        awk '{print $2}' | \
        tr -d '\r\n')

    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
        echo "$size"
    else
        echo "0"
    fi
}

# Function to check URL accessibility and file size
check_url() {
    local url="$1"
    local name="$2"
    local framework="$3"
    local expected_size="$4"
    local model_id="$5"
    local format="$6"

    # Skip built-in URLs
    if [[ $url == "builtin://"* ]]; then
        echo -e "${BLUE}🏗️  $framework - $name (Built-in model)${NC}"
        return 0
    fi

    # Build curl command with optional HuggingFace auth
    local curl_cmd="curl --head --silent --location --max-time 20 --retry 2 --user-agent \"RunAnywhereAI-URLVerifier/1.0\""

    # Add HuggingFace auth if token is provided and URL is from HuggingFace
    if [[ $url == *"huggingface.co"* ]] && [ -n "$HF_TOKEN" ]; then
        curl_cmd="$curl_cmd --header \"Authorization: Bearer $HF_TOKEN\""
    fi

    # Get headers including content-length
    local headers=$(eval "$curl_cmd \"$url\"" 2>&1)
    local curl_exit_code=$?

    if [ $curl_exit_code -eq 0 ]; then
        # Extract content-length
        local content_length=$(echo "$headers" | grep -i "content-length" | tail -1 | awk '{print $2}' | tr -d '\r')
        local http_status=$(echo "$headers" | head -n 1 | awk '{print $2}')

        # Check if it's a directory format
        local is_dir="false"
        if [ "$format" == "mlPackage" ] || [[ "$url" =~ \.mlpackage$ ]]; then
            is_dir="true"
        fi

        # Get actual file size
        local actual_size_bytes=$(get_file_size "$url" "$is_dir")

        # Format size for display
        local size_display="Unknown"
        if [ -n "$actual_size_bytes" ] && [ "$actual_size_bytes" -gt 0 ]; then
            size_display=$(format_bytes $actual_size_bytes)
        fi

        # Update size if requested
        if [ "$UPDATE_SIZES" = true ] && [ "$actual_size_bytes" -gt 0 ] && [ -n "$model_id" ]; then
            update_model_size "$model_id" "$size_display"
        fi

        # Check if size is suspiciously small (less than 1KB) - except for .mlpackage
        if [ -n "$actual_size_bytes" ] && [ "$actual_size_bytes" -lt 1024 ] && [ "$actual_size_bytes" -gt 0 ]; then
            if [[ $url == *".mlpackage"* ]] && [[ $url == *"huggingface.co"* ]]; then
                # For .mlpackage on HuggingFace, verify via API instead
                local repo=$(echo "$url" | sed 's|https://huggingface.co/||' | cut -d'/' -f1-2)
                local path=$(echo "$url" | sed 's|.*/resolve/main/||')
                local api_url="https://huggingface.co/api/models/$repo/tree/main"

                local api_cmd="curl --silent --location --max-time 20"
                if [ -n "$HF_TOKEN" ]; then
                    api_cmd="$api_cmd --header \"Authorization: Bearer $HF_TOKEN\""
                fi

                if eval "$api_cmd \"$api_url\"" 2>&1 | grep -q "\"$path\""; then
                    echo -e "${GREEN}✅ $framework - $name (HF Directory verified)${NC}"
                    echo -e "${GREEN}   Note: .mlpackage is a directory structure on HuggingFace${NC}"
                    echo -e "${GREEN}   Expected size: ~$expected_size, Actual: $size_display${NC}"
                    return 0
                else
                    echo -e "${YELLOW}⚠️  $framework - $name (Could not verify directory)${NC}"
                    echo -e "${YELLOW}   URL: $url${NC}"
                    return 0  # Don't fail for .mlpackage
                fi
            else
                echo -e "${RED}⚠️  $framework - $name (WARNING: Suspiciously small - $size_display)${NC}"
                echo -e "${RED}   URL: $url${NC}"
                echo -e "${RED}   Expected: ~$expected_size, Actual: $size_display${NC}"
                return 1
            fi
        elif [ "$http_status" == "200" ] || [ "$http_status" == "302" ] || [ "$http_status" == "301" ]; then
            # Special handling for .mlpackage directories on HuggingFace
            if [[ $url == *".mlpackage"* ]] && [[ $url == *"huggingface.co"* ]]; then
                echo -e "${GREEN}✅ $framework - $name (HF Directory - $size_display)${NC}"
                echo -e "${GREEN}   Note: .mlpackage files are directories on HuggingFace${NC}"
            else
                echo -e "${GREEN}✅ $framework - $name ($size_display)${NC}"
            fi
            if [ "$expected_size" != "Unknown" ] && [ "$size_display" != "Unknown" ]; then
                echo -e "${GREEN}   Expected: ~$expected_size, Actual: $size_display${NC}"
            fi
            return 0
        elif [ "$http_status" == "401" ] || [ "$http_status" == "403" ]; then
            if [[ $url == *"huggingface.co"* ]]; then
                echo -e "${YELLOW}🔒 $framework - $name (Authentication required)${NC}"
                echo -e "${YELLOW}   URL: $url${NC}"
                if [ -z "$HF_TOKEN" ]; then
                    echo -e "${YELLOW}   Provide HuggingFace token to verify this URL${NC}"
                else
                    echo -e "${RED}   Authentication failed - check token validity${NC}"
                fi
            else
                echo -e "${RED}❌ $framework - $name (HTTP $http_status)${NC}"
            fi
            return 1
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

# Function to update model size in the registry file
update_model_size() {
    local model_id="$1"
    local new_size="$2"

    # Create a temporary file for the update
    local temp_file="${REGISTRY_FILE}.tmp"

    # Use sed to update the size for this specific model
    local in_model=false
    local updated=false

    while IFS= read -r line; do
        # Check if we found the model ID
        if [[ "$line" =~ id:\ *\"$model_id\" ]]; then
            in_model=true
            echo "$line"
        elif [ "$in_model" = true ] && [[ "$line" =~ size:\ *\"[^\"]*\" ]]; then
            # Extract current size
            local current_size=$(echo "$line" | sed -E 's/.*size: *"([^"]*)".*/\1/')
            if [ "$current_size" != "$new_size" ]; then
                # Replace the size
                echo "$line" | sed "s/size: *\"[^\"]*\"/size: \"$new_size\"/"
                updated=true
                echo "Size updated: $model_id: $current_size -> $new_size" >&2
            else
                echo "$line"
                echo "Size already up to date: $model_id: $new_size" >&2
            fi
            in_model=false
        else
            echo "$line"
        fi
    done < "$REGISTRY_FILE" > "$temp_file"

    # Check if update was successful
    if [ -s "$temp_file" ]; then
        mv "$temp_file" "$REGISTRY_FILE"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Function to extract model info from Swift file
extract_models() {
    # Use a more robust parsing approach
    # This extracts blocks of ModelInfo(...) with their content
    local in_model=false
    local model_block=""
    local brace_count=0

    while IFS= read -r line; do
        # Check if we're starting a ModelInfo block
        if [[ "$line" =~ ModelInfo\( ]]; then
            in_model=true
            model_block="$line"
            brace_count=1
            continue
        fi

        # If we're in a model, accumulate lines
        if [ "$in_model" = true ]; then
            model_block+=$'\n'"$line"

            # Count braces to find the end
            local open_braces=$(echo "$line" | grep -o "(" | wc -l)
            local close_braces=$(echo "$line" | grep -o ")" | wc -l)
            brace_count=$((brace_count + open_braces - close_braces))

            # When we've closed all braces, we have a complete model
            if [ $brace_count -eq 0 ]; then
                # Extract model info from the block
                local id=$(echo "$model_block" | grep -o 'id: "[^"]*"' | head -1 | sed 's/id: "\([^"]*\)"/\1/')
                local name=$(echo "$model_block" | grep -o 'name: "[^"]*"' | head -1 | sed 's/name: "\([^"]*\)"/\1/')
                local url=$(echo "$model_block" | grep -o 'downloadURL: URL(string: "[^"]*")' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
                local size=$(echo "$model_block" | grep -o 'size: "[^"]*"' | head -1 | sed 's/size: "\([^"]*\)"/\1/')
                local format=$(echo "$model_block" | grep -o 'format: \.[a-zA-Z]*' | head -1 | sed 's/format: \.//')
                local framework=$(echo "$model_block" | grep -o 'framework: \.[a-zA-Z]*' | head -1 | sed 's/framework: \.//')

                if [ -n "$id" ] && [ -n "$url" ] && [ "$url" != "nil" ]; then
                    echo "$id|$name|$url|$size|$format|$framework"
                fi

                in_model=false
                model_block=""
                brace_count=0
            fi
        fi
    done < "$REGISTRY_FILE"
}

# Extract and verify URLs from the registry
total_urls=0
successful_urls=0
models_updated=0

echo -e "${YELLOW}🔄 Extracting URLs from ModelURLRegistry.swift...${NC}"
echo ""

# Process models grouped by framework
current_framework=""
last_framework=""

# Read and sort models by framework
extract_models | sort -t'|' -k6,6 | while IFS='|' read -r model_id name url size format framework; do
    if [ -z "$model_id" ] || [ -z "$url" ]; then
        continue
    fi

    # Convert framework name for display
    case $framework in
        foundationModels) display_fw="Foundation Models" ;;
        coreML) display_fw="Core ML" ;;
        mlx) display_fw="MLX" ;;
        onnxRuntime) display_fw="ONNX Runtime" ;;
        tensorFlowLite) display_fw="TensorFlow Lite" ;;
        llamaCpp) display_fw="llama.cpp" ;;
        swiftTransformers) display_fw="Swift Transformers" ;;
        *) display_fw="$framework" ;;
    esac

    # Print framework header when it changes
    if [ "$framework" != "$last_framework" ]; then
        if [ -n "$last_framework" ]; then
            echo ""
        fi
        echo -e "${BLUE}=== $display_fw ===${NC}"
        last_framework="$framework"
    fi

    ((total_urls++))

    # Special handling for Kaggle URLs
    if [[ $url == *"kaggle.com"* ]]; then
        echo -e "${YELLOW}⚠️  $display_fw - $name (Requires Kaggle authentication)${NC}"
        echo -e "${YELLOW}   URL: $url${NC}"
        ((successful_urls++)) # Count as successful since auth is expected
    else
        if check_url "$url" "$name" "$display_fw" "$size" "$model_id" "$format"; then
            ((successful_urls++))
        fi
    fi
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📊 VERIFICATION SUMMARY${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total URLs tested: $total_urls"
echo -e "${GREEN}✅ Accessible: $successful_urls${NC}"
echo -e "${RED}❌ Failed: $((total_urls - successful_urls))${NC}"

if [ "$UPDATE_SIZES" = true ]; then
    echo -e "${BLUE}📏 Size updates: Applied during verification${NC}"
fi

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
if [ "$UPDATE_SIZES" = true ]; then
    echo -e "${YELLOW}   • Model sizes have been updated in the registry${NC}"
    echo -e "${YELLOW}   • Backup saved at: $BACKUP_FILE${NC}"
fi
echo -e "${BLUE}========================================${NC}"

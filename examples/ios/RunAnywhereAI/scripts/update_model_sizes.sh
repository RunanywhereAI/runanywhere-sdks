#!/bin/bash

# Generic script to update model sizes in ModelURLRegistry.swift
# This script extracts model IDs and URLs from the Swift file itself
# and updates sizes dynamically without hardcoding
# Usage: ./update_model_sizes.sh [--no-backup]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for --no-backup flag
NO_BACKUP=false
if [ "$1" == "--no-backup" ]; then
    NO_BACKUP=true
fi

# Path to ModelURLRegistry.swift
REGISTRY_FILE="../RunAnywhereAI/Services/ModelManagement/ModelURLRegistry.swift"

echo -e "${BLUE}📏 Generic Model Size Updater for ModelURLRegistry.swift${NC}"
echo -e "${BLUE}📍 Target file: $REGISTRY_FILE${NC}"
echo ""

# Check if registry file exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}❌ ModelURLRegistry.swift not found at: $REGISTRY_FILE${NC}"
    echo -e "${YELLOW}💡 Make sure you're running this script from the scripts/ directory${NC}"
    exit 1
fi

# Create backup unless --no-backup flag is set
if [ "$NO_BACKUP" != true ]; then
    BACKUP_FILE="${REGISTRY_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$REGISTRY_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✅ Backup created at: $BACKUP_FILE${NC}"
else
    echo -e "${YELLOW}⚠️  Running without backup (--no-backup flag set)${NC}"
fi
echo ""

# Function to format bytes to human readable format
format_bytes() {
    local bytes=$1
    if [ $bytes -eq 0 ]; then
        echo "0B"
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
            
            # Get directory listing and sum file sizes
            local total_size=$(curl -sL --max-time 20 "$api_url" 2>/dev/null | \
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
    local size=$(curl -sI -L --max-time 20 "$url" 2>/dev/null | \
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
                local url=$(echo "$model_block" | grep -o 'downloadURL: URL(string: "[^"]*")' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
                local format=$(echo "$model_block" | grep -o 'format: \.[a-zA-Z]*' | head -1 | sed 's/format: \.//')
                
                if [ -n "$id" ] && [ -n "$url" ] && [ "$url" != "nil" ]; then
                    # Check if it's a directory format
                    local is_dir="false"
                    if [ "$format" == "mlPackage" ] || [[ "$url" =~ \.mlpackage$ ]]; then
                        is_dir="true"
                    fi
                    
                    echo "$id|$url|$is_dir"
                fi
                
                in_model=false
                model_block=""
                brace_count=0
            fi
        fi
    done < "$REGISTRY_FILE"
}

echo -e "${YELLOW}🔄 Extracting models from Swift file...${NC}"

# Extract all models with their URLs
models_updated=0
models_skipped=0
models_failed=0

# Process each model found in the file
while IFS='|' read -r model_id url is_directory; do
    if [ -z "$model_id" ] || [ -z "$url" ]; then
        continue
    fi
    
    echo -n "📊 Processing $model_id... "
    
    # Get the file size
    size_bytes=$(get_file_size "$url" "$is_directory")
    
    if [ "$size_bytes" -gt 0 ]; then
        # Format the size
        formatted_size=$(format_bytes "$size_bytes")
        
        # Create a temporary file for the update
        temp_file="${REGISTRY_FILE}.tmp"
        
        # Use awk to update the size for this specific model
        awk -v id="$model_id" -v new_size="$formatted_size" '
            BEGIN { found_id = 0; }
            /id: "/ && $0 ~ "\"" id "\"" { found_id = 1; }
            found_id && /size: "[^"]*"/ {
                # Extract current size for comparison
                match($0, /size: "([^"]*)"/, current);
                if (current[1] != new_size) {
                    sub(/size: "[^"]*"/, "size: \"" new_size "\"");
                    print "Updated: " current[1] " → " new_size > "/dev/stderr";
                } else {
                    print "Already up to date: " new_size > "/dev/stderr";
                }
                found_id = 0;
            }
            { print }
        ' "$REGISTRY_FILE" > "$temp_file" 2>&1
        
        # Check if update was successful
        if [ -s "$temp_file" ]; then
            mv "$temp_file" "$REGISTRY_FILE"
            ((models_updated++))
        else
            rm -f "$temp_file"
            echo -e "${RED}Failed${NC}"
            ((models_failed++))
        fi
    else
        echo -e "${YELLOW}Skipped (couldn't fetch size)${NC}"
        ((models_skipped++))
    fi
done < <(extract_models)

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📊 UPDATE SUMMARY${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Updated: $models_updated models${NC}"
echo -e "${YELLOW}⏭️  Skipped: $models_skipped models${NC}"
echo -e "${RED}❌ Failed: $models_failed models${NC}"

if [ "$NO_BACKUP" != true ] && [ -n "$BACKUP_FILE" ]; then
    echo -e "${BLUE}💾 Backup: $BACKUP_FILE${NC}"
fi

# Clean up old backups (keep only the 5 most recent)
if [ "$NO_BACKUP" != true ]; then
    echo ""
    echo -e "${YELLOW}🧹 Cleaning up old backups...${NC}"
    backup_count=$(ls "${REGISTRY_FILE}.backup_"* 2>/dev/null | wc -l)
    if [ $backup_count -gt 5 ]; then
        ls -t "${REGISTRY_FILE}.backup_"* 2>/dev/null | tail -n +6 | xargs -r rm -f
        echo -e "${GREEN}✅ Kept only the 5 most recent backups${NC}"
    else
        echo -e "${GREEN}✅ All $backup_count backups retained (under limit)${NC}"
    fi
fi

echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}✅ Model size update complete!${NC}"

# Exit with appropriate code
if [ $models_failed -gt 0 ]; then
    exit 1
else
    exit 0
fi
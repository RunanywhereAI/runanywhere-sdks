#!/bin/bash
# RunAnywhere Core - C++ Linting Script
# Can be used as a pre-commit hook or standalone

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default settings
CHECK_FORMAT=true
CHECK_TIDY=true
FIX_FORMAT=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --format-only)
            CHECK_TIDY=false
            shift
            ;;
        --tidy-only)
            CHECK_FORMAT=false
            shift
            ;;
        --fix)
            FIX_FORMAT=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --format-only    Only run clang-format checks"
            echo "  --tidy-only      Only run clang-tidy checks"
            echo "  --fix            Fix formatting issues (clang-format only)"
            echo "  -v, --verbose    Show verbose output"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

cd "${PROJECT_ROOT}"

# Find clang tools - check PATH, then homebrew, then Xcode
find_clang_format() {
    if command -v clang-format &> /dev/null; then
        echo "clang-format"
    elif [ -x "/opt/homebrew/opt/llvm/bin/clang-format" ]; then
        echo "/opt/homebrew/opt/llvm/bin/clang-format"
    elif [ -x "/usr/local/opt/llvm/bin/clang-format" ]; then
        echo "/usr/local/opt/llvm/bin/clang-format"
    elif xcrun -find clang-format &>/dev/null; then
        xcrun -find clang-format
    else
        echo ""
    fi
}

find_clang_tidy() {
    if command -v clang-tidy &> /dev/null; then
        echo "clang-tidy"
    elif [ -x "/opt/homebrew/opt/llvm/bin/clang-tidy" ]; then
        echo "/opt/homebrew/opt/llvm/bin/clang-tidy"
    elif [ -x "/usr/local/opt/llvm/bin/clang-tidy" ]; then
        echo "/usr/local/opt/llvm/bin/clang-tidy"
    elif xcrun -find clang-tidy &>/dev/null; then
        xcrun -find clang-tidy
    else
        echo ""
    fi
}

CLANG_FORMAT=$(find_clang_format)
CLANG_TIDY=$(find_clang_tidy)

# Find all C/C++ files (only in src directory, not build or third_party)
find_source_files() {
    find src -name "*.cpp" -o -name "*.h" -o -name "*.c" 2>/dev/null || true
}

# Check if clang-format is available
check_clang_format() {
    if [ -z "$CLANG_FORMAT" ]; then
        echo -e "${YELLOW}Warning: clang-format not found, skipping format checks${NC}"
        return 1
    fi
    return 0
}

# Check if clang-tidy is available
check_clang_tidy() {
    if [ -z "$CLANG_TIDY" ]; then
        echo -e "${YELLOW}Warning: clang-tidy not found, skipping static analysis${NC}"
        return 1
    fi
    return 0
}

# Run clang-format
run_format() {
    if ! check_clang_format; then
        return 0
    fi

    echo -e "${GREEN}Running clang-format...${NC}"

    local files
    files=$(find_source_files)

    if [ -z "$files" ]; then
        echo "No source files found"
        return 0
    fi

    local errors=0

    if [ "$FIX_FORMAT" = true ]; then
        echo "$files" | xargs "$CLANG_FORMAT" -i
        echo -e "${GREEN}Format fixes applied${NC}"
    else
        for file in $files; do
            if [ "$VERBOSE" = true ]; then
                echo "Checking: $file"
            fi

            if ! "$CLANG_FORMAT" --dry-run --Werror "$file" 2>/dev/null; then
                echo -e "${RED}Format error in: $file${NC}"
                ((errors++))
            fi
        done

        if [ $errors -gt 0 ]; then
            echo -e "${RED}Found $errors files with format errors${NC}"
            echo "Run '$0 --fix' to automatically fix formatting"
            return 1
        else
            echo -e "${GREEN}All files properly formatted${NC}"
        fi
    fi

    return 0
}

# Check if file is platform-specific and should be skipped
should_skip_file() {
    local file="$1"

    # Skip JNI files on non-Android platforms (they require Android NDK headers)
    if [[ "$file" == *"/jni/"* ]]; then
        if [[ "$(uname)" != "Linux" ]] || [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
            if [ "$VERBOSE" = true ]; then
                echo "Skipping Android-only file: $file"
            fi
            return 0  # true = should skip
        fi
    fi

    return 1  # false = should not skip
}

# Run clang-tidy
run_tidy() {
    if ! check_clang_tidy; then
        return 0
    fi

    # Check if compile_commands.json exists and contains project sources
    local compile_db=""
    local has_project_sources=false

    for db_path in "build/compile_commands.json" "build/macos/arm64/compile_commands.json" "cmake-build-debug/compile_commands.json"; do
        if [ -f "$db_path" ]; then
            # Check if the compile_commands.json contains project source files
            if grep -q "runanywhere_bridge\|onnx_backend\|llamacpp_backend\|whispercpp_backend" "$db_path" 2>/dev/null; then
                compile_db="-p $(dirname "$db_path")"
                has_project_sources=true
                break
            else
                # compile_commands.json exists but doesn't have project sources
                if [ "$VERBOSE" = true ]; then
                    echo "Found $db_path but it doesn't contain project source entries"
                fi
            fi
        fi
    done

    if [ "$has_project_sources" = false ]; then
        echo -e "${YELLOW}Warning: No compile_commands.json with project sources found${NC}"
        echo "Skipping clang-tidy checks (requires project build with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON)"
        echo "To generate: mkdir -p build && cd build && cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && make"
        return 0
    fi

    echo -e "${GREEN}Running clang-tidy...${NC}"

    # Only check .cpp files with clang-tidy
    local files
    files=$(find src -name "*.cpp" 2>/dev/null || true)

    if [ -z "$files" ]; then
        echo "No C++ source files found"
        return 0
    fi

    local errors=0
    local skipped=0

    for file in $files; do
        # Skip platform-specific files that can't be analyzed
        if should_skip_file "$file"; then
            ((skipped++))
            continue
        fi

        if [ "$VERBOSE" = true ]; then
            echo "Analyzing: $file"
        fi

        if ! "$CLANG_TIDY" $compile_db "$file" 2>/dev/null; then
            ((errors++))
        fi
    done

    if [ $skipped -gt 0 ]; then
        echo -e "${YELLOW}Skipped $skipped platform-specific files${NC}"
    fi

    if [ $errors -gt 0 ]; then
        echo -e "${RED}Found issues in $errors files${NC}"
        return 1
    else
        echo -e "${GREEN}No clang-tidy issues found${NC}"
    fi

    return 0
}

# Main execution
main() {
    local exit_code=0

    if [ "$CHECK_FORMAT" = true ]; then
        if ! run_format; then
            exit_code=1
        fi
    fi

    if [ "$CHECK_TIDY" = true ]; then
        if ! run_tidy; then
            exit_code=1
        fi
    fi

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}All checks passed!${NC}"
    else
        echo -e "${RED}Some checks failed${NC}"
    fi

    exit $exit_code
}

main

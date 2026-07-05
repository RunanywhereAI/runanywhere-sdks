#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/validation/lint-cpp.sh [--fix] [--tidy]

Runs clang-format (style enforcement) against all C++ sources under
sdk/runanywhere-commons/{src,include}. Honors .clang-format and .clang-tidy.

Options:
  --fix         Auto-apply clang-format fixes in place
  --tidy        Also run clang-tidy (slower, needs compile_commands.json)
  -h, --help    Show this help

Environment overrides:
  CLANG_FORMAT    Path to clang-format binary (auto-detected if unset)
  CLANG_TIDY      Path to clang-tidy binary  (auto-detected if unset)
EOF
}

PROJECT_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"
cd "$PROJECT_ROOT"

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

find_tool() {
    local name="$1"
    local env_var
    env_var="$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
    local override="${!env_var:-}"
    if [[ -n "$override" ]]; then
        echo "$override"
        return 0
    fi
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    # Homebrew LLVM on macOS
    for base in /opt/homebrew/opt/llvm /usr/local/opt/llvm /opt/homebrew/opt/llvm@21 /opt/homebrew/opt/llvm@20 /opt/homebrew/opt/llvm@19 /opt/homebrew/opt/llvm@18; do
        if [[ -x "$base/bin/$name" ]]; then
            echo "$base/bin/$name"
            return 0
        fi
    done
    # Xcode (clang-format only, no clang-tidy shipped)
    if xcode_path="$(xcrun --find "$name" 2>/dev/null)"; then
        echo "$xcode_path"
        return 0
    fi
    return 1
}

CLANG_FORMAT="${CLANG_FORMAT:-$(find_tool clang-format || true)}"
CLANG_TIDY="${CLANG_TIDY:-$(find_tool clang-tidy || true)}"

MODE="check"
RUN_TIDY=false

for arg in "$@"; do
    case "$arg" in
        --fix)       MODE="fix" ;;
        --tidy)      RUN_TIDY=true ;;
        -h|--help)   usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown argument: $arg${RESET}" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$CLANG_FORMAT" ]]; then
    echo -e "${RED}ERROR: clang-format not found.${RESET}" >&2
    echo "Install: brew install llvm  (macOS)  or  apt install clang-format  (Linux)" >&2
    exit 3
fi

if [[ ! -f ".clang-format" ]]; then
    echo -e "${RED}ERROR: .clang-format missing at $PROJECT_ROOT${RESET}" >&2
    exit 3
fi

echo -e "${BOLD}${BLUE}==>${RESET} ${BOLD}C++ Lint (runanywhere-commons)${RESET}"
echo "    Project:      $PROJECT_ROOT"
echo "    clang-format: $CLANG_FORMAT"
echo "    Version:      $("$CLANG_FORMAT" --version | head -1)"
echo "    Mode:         $MODE"

# Collect files (src/ + include/ only; skip third_party, build dirs, _deps).
# tmpfile + IFS read stays compatible with bash 3.2 (macOS default).
FILE_LIST="$(mktemp)"
trap 'rm -f "$FILE_LIST"' EXIT

find include src \
    -type f \
    \( -name "*.cpp" -o -name "*.cc" -o -name "*.cxx" \
    -o -name "*.h"   -o -name "*.hpp" \) \
    ! -path "*/_deps/*" \
    ! -path "*/third_party/*" \
    ! -path "*/build*/*" \
    ! -path "*/dist/*" \
    ! -path "*/.git/*" \
    ! -path "*src/generated/*" \
    | sort > "$FILE_LIST"

FILES=()
while IFS= read -r line; do
    FILES+=("$line")
done < "$FILE_LIST"

echo "    Files:        ${#FILES[@]}"
echo

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No files to check.${RESET}"
    exit 0
fi

echo -e "${BOLD}${BLUE}==>${RESET} Running clang-format ($MODE)..."

fmt_issues=0
fmt_issue_files=()

if [[ "$MODE" == "fix" ]]; then
    for f in "${FILES[@]}"; do
        if ! "$CLANG_FORMAT" -i "$f" 2>/dev/null; then
            echo -e "${RED}  failed: $f${RESET}"
            fmt_issues=$((fmt_issues + 1))
        fi
    done
    echo -e "${GREEN}  applied clang-format to ${#FILES[@]} files${RESET}"
else
    # Dry-run: any non-empty output == needs reformatting
    for f in "${FILES[@]}"; do
        if ! out="$("$CLANG_FORMAT" --dry-run --Werror "$f" 2>&1)"; then
            fmt_issues=$((fmt_issues + 1))
            fmt_issue_files+=("$f")
            # First issue per file only, indented. awk avoids SIGPIPE from head.
            printf '%s\n' "$out" | awk 'NR<=3 {print "    " $0}'
        fi
    done
    if [[ $fmt_issues -eq 0 ]]; then
        echo -e "${GREEN}  clang-format: no issues${RESET}"
    else
        echo -e "${RED}  clang-format: ${fmt_issues} file(s) need formatting${RESET}"
        echo -e "${YELLOW}  Run './scripts/validation/lint-cpp.sh --fix' to auto-apply${RESET}"
    fi
fi

tidy_issues=0

if [[ "$RUN_TIDY" == "true" ]]; then
    echo
    echo -e "${BOLD}${BLUE}==>${RESET} Running clang-tidy..."

    tidy_build_dir=""
    for candidate in build build-tidy build-verify; do
        if [[ -f "$candidate/compile_commands.json" ]]; then
            tidy_build_dir="$candidate"
            break
        fi
    done

    if [[ -z "$CLANG_TIDY" ]]; then
        echo -e "${YELLOW}  clang-tidy not found — skipping semantic checks${RESET}"
    elif [[ -z "$tidy_build_dir" ]]; then
        echo -e "${YELLOW}  compile_commands.json not found — skipping${RESET}"
        echo -e "${YELLOW}  Generate: cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON${RESET}"
    else
        echo "    compile_commands: $tidy_build_dir/compile_commands.json"
        # modernize-use-scoped-lock: known crash in LLVM 21.1.x
        tidy_disabled_checks='-modernize-use-scoped-lock'

        # On macOS, Homebrew clang-tidy doesn't pick up the Xcode SDK
        # automatically (compile_commands.json invokes /usr/bin/c++ which has
        # implicit SDK paths). Prepend -isysroot so system headers resolve.
        tidy_extra_args=()
        if [[ "$(uname -s)" == "Darwin" ]] && command -v xcrun >/dev/null 2>&1; then
            sdk_path="$(xcrun --show-sdk-path 2>/dev/null || true)"
            if [[ -n "$sdk_path" ]]; then
                tidy_extra_args+=(--extra-arg-before=-isysroot --extra-arg-before="$sdk_path")
            fi
        fi

        if [[ "$MODE" == "fix" ]]; then
            tidy_args=(-p="$tidy_build_dir" --fix --fix-errors --quiet
                       --checks="$tidy_disabled_checks"
                       --header-filter='.*rac_.*\.h$'
                       --exclude-header-filter='.*/src/generated/.*\.pb\.h$'
                       "${tidy_extra_args[@]}")
        else
            tidy_args=(-p="$tidy_build_dir" --quiet
                       --checks="$tidy_disabled_checks"
                       --header-filter='.*rac_.*\.h$'
                       --exclude-header-filter='.*/src/generated/.*\.pb\.h$'
                       "${tidy_extra_args[@]}")
        fi

        # Only run on .cpp files (headers covered via HeaderFilterRegex)
        CPP_FILES=()
        for f in "${FILES[@]}"; do
            case "$f" in
                *.cpp|*.cc|*.cxx) CPP_FILES+=("$f") ;;
            esac
        done
        tidy_log="$(mktemp)"
        for f in "${CPP_FILES[@]}"; do
            "$CLANG_TIDY" "${tidy_args[@]}" "$f" 2>/dev/null >>"$tidy_log" || true
        done
        # Count project warnings only (strip system/_deps/generated headers)
        tidy_issues="$(grep -E 'warning:|error:' "$tidy_log" \
            | grep -v '^/opt/' \
            | grep -v '^/Applications/' \
            | grep -v '/_deps/' \
            | grep -v '/third_party/' \
            | grep -v '/src/generated/' \
            | grep -c '' || true)"
        if [[ "$tidy_issues" -eq 0 ]]; then
            echo -e "${GREEN}  clang-tidy: no project issues${RESET}"
        else
            echo -e "${RED}  clang-tidy: $tidy_issues project warning(s)/error(s)${RESET}"
            grep -E 'warning:|error:' "$tidy_log" \
                | grep -v '^/opt/' \
                | grep -v '^/Applications/' \
                | grep -v '/_deps/' \
                | grep -v '/third_party/' \
                | grep -v '/src/generated/' \
                | awk 'NR<=30 {print "    " $0}'
        fi
        rm -f "$tidy_log"
    fi
fi

echo
echo -e "${BOLD}${BLUE}==>${RESET} Summary"
echo "    clang-format issues: $fmt_issues"
if [[ "$RUN_TIDY" == "true" ]]; then
    echo "    clang-tidy issues:   $tidy_issues"
fi

total=$((fmt_issues + tidy_issues))
if [[ $total -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All lint checks passed.${RESET}"
    exit 0
fi

if [[ "$MODE" == "fix" ]]; then
    # In fix mode, treat format success as pass-through (tidy-fix may remain)
    if [[ $fmt_issues -eq 0 ]]; then
        echo -e "${GREEN}Formatting auto-applied. Re-run without --fix to verify.${RESET}"
        exit 0
    fi
fi

exit 1

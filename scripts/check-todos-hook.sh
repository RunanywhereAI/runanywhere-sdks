#!/usr/bin/env bash

# Pre-commit hook script to check for TODOs without GitHub issue references

set -e

# Pattern to match TODO keywords
TODO_PATTERN="(//|/\*|#)\s*(TODO|FIXME|HACK|XXX|BUG|REFACTOR|OPTIMIZE)"
# Pattern to match TODO with issue reference
TODO_WITH_ISSUE_PATTERN="(//|/\*|#)\s*(TODO|FIXME|HACK|XXX|BUG|REFACTOR|OPTIMIZE)[^#]*#[0-9]+"

# Check if filenames were passed (from pre-commit with pass_filenames: true)
if [ $# -gt 0 ]; then
    # Process only the files passed as arguments (staged files)
    found_todos=false
    for file in "$@"; do
        # Skip deleted files
        if [ ! -f "$file" ]; then
            continue
        fi

        # Check if file matches supported extensions
        case "$file" in
            *.swift|*.kt|*.java|*.ts|*.tsx|*.js|*.jsx|*.py|*.rb|*.go|*.rs|*.cpp|*.c|*.h|*.hpp|*.cs|*.m|*.mm)
                # Find TODOs in this file
                if grep -nE "$TODO_PATTERN" "$file" 2>/dev/null | grep -vE "$TODO_WITH_ISSUE_PATTERN" >/dev/null 2>&1; then
                    if [ "$found_todos" = false ]; then
                        echo "ERROR: Found TODOs without GitHub issue references"
                        echo "All TODOs must reference an issue (e.g., // TODO: #123 - Description)"
                        echo ""
                        found_todos=true
                    fi
                    # Show the problematic lines
                    grep -nE "$TODO_PATTERN" "$file" 2>/dev/null | grep -vE "$TODO_WITH_ISSUE_PATTERN" | while IFS= read -r line; do
                        echo "$file:$line"
                    done
                fi
                ;;
        esac
    done

    if [ "$found_todos" = true ]; then
        echo ""
        echo "Run './scripts/fix-todos.sh' to see all TODOs that need fixing"
        exit 1
    fi
else
    # Fallback: check entire repository if no files passed (for manual runs)
    if grep -rEn "$TODO_PATTERN" \
        --include="*.swift" \
        --include="*.kt" \
        --include="*.java" \
        --include="*.ts" \
        --include="*.tsx" \
        --include="*.js" \
        --include="*.jsx" \
        --include="*.py" \
        --include="*.rb" \
        --include="*.go" \
        --include="*.rs" \
        --include="*.cpp" \
        --include="*.c" \
        --include="*.h" \
        --include="*.hpp" \
        --include="*.cs" \
        --include="*.m" \
        --include="*.mm" \
        . 2>/dev/null | \
        grep -v ".git/" | \
        grep -v "node_modules/" | \
        grep -v ".build/" | \
        grep -v "build/" | \
        grep -v "DerivedData/" | \
        grep -v "vendor/" | \
        grep -v "Pods/" | \
        grep -v ".dart_tool/" | \
        grep -v "scripts/check-todos-hook.sh" | \
        grep -vE "$TODO_WITH_ISSUE_PATTERN"; then

        echo "ERROR: Found TODOs without GitHub issue references"
        echo "All TODOs must reference an issue (e.g., // TODO: #123 - Description)"
        echo ""
        echo "Run './scripts/fix-todos.sh' to see all TODOs that need fixing"
        exit 1
    fi
fi

exit 0

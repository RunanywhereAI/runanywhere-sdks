#!/usr/bin/env bash

# Pre-commit hook script to check for TODOs without GitHub issue references

set -e

# Find TODOs without issue references
# First find all TODOs, then filter out those with issue references
if grep -rEn "(//|/\*|#)\s*(TODO|FIXME|HACK|XXX|BUG|REFACTOR|OPTIMIZE)" \
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
    grep -v "scripts/check-todos-hook.sh" | \
    grep -vE "#[0-9]+"; then

    echo "ERROR: Found TODOs without GitHub issue references"
    echo "All TODOs must reference an issue (e.g., // TODO: #123 - Description)"
    echo ""
    echo "Run './scripts/fix-todos.sh' to see all TODOs that need fixing"
    exit 1
fi

exit 0

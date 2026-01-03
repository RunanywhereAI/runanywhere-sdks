#!/bin/bash
# TODO/FIXME/HACK/XXX Checker
# Ensures all TODO comments reference an issue number (e.g., #123)
# Run from sdk/runanywhere-flutter directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SDK_ROOT"

# Find TODOs without issue references
# Pattern: TODO/FIXME/HACK/XXX not followed by #<number>
# This regex looks for TODO/FIXME/HACK/XXX that are NOT followed by #<digits>

VIOLATIONS=$(grep -rn --include="*.dart" -E "(TODO|FIXME|HACK|XXX)(:|\s)" lib/ 2>/dev/null | grep -v "#[0-9]" || true)

if [ -z "$VIOLATIONS" ]; then
    echo "All TODO/FIXME/HACK/XXX comments have issue references."
    exit 0
else
    echo "The following TODO/FIXME/HACK/XXX comments are missing issue references (e.g., #123):"
    echo ""
    echo "$VIOLATIONS"
    echo ""
    echo "Please update these comments to include an issue reference."
    exit 1
fi

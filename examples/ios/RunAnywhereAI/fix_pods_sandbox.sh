#!/bin/bash
# fix_pods_sandbox.sh
# 
# This script fixes the Xcode 16 sandbox issue with CocoaPods resource copying
# Run this after each 'pod install' to replace rsync with cp in the resources script

SCRIPT_PATH="Pods/Target Support Files/Pods-RunAnywhereAI/Pods-RunAnywhereAI-resources.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Pods resources script not found at $SCRIPT_PATH"
    echo "Make sure you run 'pod install' first"
    exit 1
fi

echo "Fixing Xcode 16 sandbox issue in CocoaPods resources script..."

# Create a temporary file
TEMP_FILE=$(mktemp)

# Read the script and replace rsync commands and fix realpath
awk '
/realpath -mq/ {
    gsub("realpath -mq", "cd \"$(dirname", $0)
    gsub("\"\\${0}\"", "\"${0}\")\" && pwd)/$(basename \"${0}\"", $0)
}
/^[[:space:]]*rsync -avr --copy-links/ {
    # Extract the destination path
    if (match($0, /\$\{[^}]+\}/)) {
        dest = substr($0, RSTART, RLENGTH)
        print "  # Use cp instead of rsync for sandbox compatibility"
        print "  if [[ -f \"$RESOURCES_TO_COPY\" ]]; then"
        print "    while IFS= read -r file; do"
        print "      if [[ -n \"$file\" ]] && [[ -e \"$file\" ]]; then"
        print "        cp -R \"$file\" \"" dest "/\" || true"
        print "      fi"
        print "    done < \"$RESOURCES_TO_COPY\""
        print "  fi"
    }
    next
}
{ print }
' "$SCRIPT_PATH" > "$TEMP_FILE"

# Replace the original file
mv "$TEMP_FILE" "$SCRIPT_PATH"

# Make the script executable
chmod +x "$SCRIPT_PATH"

echo "✅ Successfully fixed CocoaPods resources script for Xcode 16 compatibility"
echo ""
echo "Note: This fix needs to be applied after each 'pod install' as the script is auto-generated."
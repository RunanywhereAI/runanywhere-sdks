#!/bin/bash

# Detect installed IDEs and their versions

detect_android_studio_mac() {
    local as_path="/Applications/Android Studio.app"
    if [[ -d "$as_path" ]]; then
        # Try to get version from Info.plist
        local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$as_path/Contents/Info.plist" 2>/dev/null)
        # Also get build number
        local build_file="$as_path/Contents/Resources/build.txt"
        local build_info=""
        if [[ -f "$build_file" ]]; then
            build_info=$(cat "$build_file" | grep -oE 'AI-[0-9]+\.[0-9]+' | cut -d'-' -f2 | cut -d'.' -f1)
        fi
        if [[ -n "$version" ]]; then
            echo "AS:$version:$as_path:$build_info"
        fi
    fi
}

detect_intellij_mac() {
    # Check for IntelliJ IDEA Community
    local idea_ce="/Applications/IntelliJ IDEA CE.app"
    if [[ -d "$idea_ce" ]]; then
        local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$idea_ce/Contents/Info.plist" 2>/dev/null)
        if [[ -n "$version" ]]; then
            echo "IC:$version:$idea_ce"
        fi
    fi

    # Check for IntelliJ IDEA Ultimate
    local idea_ult="/Applications/IntelliJ IDEA.app"
    if [[ -d "$idea_ult" ]]; then
        local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$idea_ult/Contents/Info.plist" 2>/dev/null)
        if [[ -n "$version" ]]; then
            echo "IU:$version:$idea_ult"
        fi
    fi
}

# Main detection
case "$(uname -s)" in
    Darwin)
        detect_android_studio_mac
        detect_intellij_mac
        ;;
    Linux)
        # Add Linux detection if needed
        echo "Linux IDE detection not yet implemented"
        ;;
    *)
        echo "Unsupported OS"
        ;;
esac

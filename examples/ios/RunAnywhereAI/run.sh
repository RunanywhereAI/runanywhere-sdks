#!/bin/bash

# RunAnywhereAI - Run Script
# This script builds and runs the app in the iOS Simulator

echo "🚀 Building and running RunAnywhereAI..."

# Build the app
echo "📦 Building..."
xcodebuild -project RunAnywhereAI.xcodeproj \
    -scheme RunAnywhereAI \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -quiet \
    build

if [ $? -eq 0 ]; then
    echo "✅ Build succeeded!"
    
    # Get the app path
    APP_PATH=$(xcodebuild -project RunAnywhereAI.xcodeproj \
        -scheme RunAnywhereAI \
        -showBuildSettings \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        | grep -E '^\s*BUILT_PRODUCTS_DIR' \
        | awk '{print $3}')
    
    # Launch the simulator
    echo "📱 Launching simulator..."
    xcrun simctl boot "iPhone 16" 2>/dev/null || true
    open -a Simulator
    
    # Install and launch the app
    echo "🚀 Installing and launching app..."
    xcrun simctl install "iPhone 16" "$APP_PATH/RunAnywhereAI.app"
    xcrun simctl launch "iPhone 16" com.runanywhere.ai.RunAnywhereAI
    
    echo "✨ App is running!"
else
    echo "❌ Build failed!"
    exit 1
fi
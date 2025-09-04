#!/bin/bash
set -e

echo "Building RunAnywhereAI app..."

# Clean
./gradlew clean

# Build debug APK
./gradlew :app:assembleDebug

# Check if build was successful
if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
    echo "Build successful! Installing on device..."

    # Install on device
    adb install -r app/build/outputs/apk/debug/app-debug.apk

    # Launch the app
    echo "Launching app..."
    adb shell am start -n com.runanywhere.runanywhereai/.SimpleMainActivity

    echo "Done! App should be running on your Pixel 8 Pro."
else
    echo "Build failed! APK not found."
    exit 1
fi

#!/bin/bash

echo "Cleaning Kotlin caches..."
rm -rf ~/.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/
rm -rf .gradle
rm -rf app/build
rm -rf build

echo "Stopping Gradle daemons..."
./gradlew --stop

echo "Cleaning project..."
./gradlew clean

echo "Building app..."
./gradlew :app:assembleDebug

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Installing on device..."
    adb install -r app/build/outputs/apk/debug/app-debug.apk

    if [ $? -eq 0 ]; then
        echo "Launching app..."
        adb shell am start -n com.runanywhere.runanywhereai/.SimpleMainActivity
    else
        echo "Installation failed!"
    fi
else
    echo "Build failed!"
fi

# Android Development Setup Guide
**Date**: October 8, 2025  
**Purpose**: Complete setup guide for Android development and testing of RunAnywhere SDK  
**Target**: Developers working on Android/Kotlin implementation  

## Quick Start Summary

This guide will help you set up your Android development environment to work on the RunAnywhere Kotlin SDK and Android sample app. The setup includes emulator configuration, project build, and testing validation.

**Estimated Setup Time**: 30-45 minutes  
**Prerequisites**: Basic Android development experience  

---

## 1. Prerequisites & System Requirements

### Development Tools
- **Android Studio**: Hedgehog (2023.1.1) or newer
- **JDK**: Version 17 or higher (required for Kotlin 2.1.21)
- **Git**: Latest version for repository access
- **Minimum RAM**: 8GB (16GB recommended for emulator)
- **Disk Space**: 10GB free space minimum

### Operating System Support
- **macOS**: 10.15+ (Catalina or newer)
- **Windows**: Windows 10 64-bit or newer
- **Linux**: Ubuntu 18.04+ or equivalent

### Android SDK Requirements
- **API Level**: 24+ (Android 7.0) minimum
- **Target API**: 34 (Android 14) recommended
- **Build Tools**: 34.0.0 or newer
- **NDK**: 25.1.8937393 (for native components)

---

## 2. Environment Setup

### Step 1: Install Android Studio
1. Download from [developer.android.com](https://developer.android.com/studio)
2. Install with default settings
3. Launch and complete initial setup wizard
4. Install additional SDK components when prompted

### Step 2: Configure Android SDK
```bash
# Open Android Studio → Tools → SDK Manager
# Install these SDK packages:
Android SDK Platform 34
Android SDK Build-Tools 34.0.0
Android Emulator
Android SDK Platform-Tools
Android SDK Tools

# Install these NDK components:
NDK (Side by side) 25.1.8937393
CMake 3.22.1
```

### Step 3: Set Environment Variables
#### macOS/Linux:
```bash
# Add to ~/.zshrc or ~/.bashrc
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin

# Reload shell configuration
source ~/.zshrc  # or ~/.bashrc
```

#### Windows:
```powershell
# Add to system environment variables
ANDROID_HOME = C:\Users\%USERNAME%\AppData\Local\Android\Sdk
Path = %Path%;%ANDROID_HOME%\emulator;%ANDROID_HOME%\platform-tools
```

### Step 4: Verify Installation
```bash
# Check Android tools are accessible
adb --version
emulator -version
sdkmanager --version

# Should output version information for each tool
```

---

## 3. Repository Setup

### Step 1: Clone Repository
```bash
# Clone the repository
git clone <repository-url>
cd RunanywhereAI/sdks

# Verify repository structure
ls -la
# Should show: sdk/, examples/, .github/, README.md, etc.
```

### Step 2: Build Kotlin Multiplatform SDK
```bash
# Navigate to Kotlin SDK
cd sdk/runanywhere-kotlin

# Verify Gradle wrapper
ls -la
# Should show: gradlew, gradlew.bat, gradle/wrapper/

# Build the SDK (this may take 5-10 minutes on first run)
./gradlew build

# Expected output: BUILD SUCCESSFUL
# This builds both JVM and Android targets
```

### Step 3: Publish SDK to Local Maven
```bash
# Publish to local Maven repository (~/.m2/repository)
./gradlew publishToMavenLocal

# Verify publication
ls ~/.m2/repository/com/runanywhere/sdk/
# Should show: RunAnywhereKotlinSDK/, maven-metadata-local.xml
```

### Step 4: Validate Build Outputs
```bash
# Check build outputs
ls build/libs/
# Should show: RunAnywhereKotlinSDK-jvm-0.1.0.jar

ls build/outputs/aar/
# Should show: RunAnywhereKotlinSDK-debug.aar, RunAnywhereKotlinSDK-release.aar
```

---

## 4. Android Emulator Configuration

### Step 1: Create Optimal AVD
```bash
# List available system images
sdkmanager --list | grep "system-images"

# Download recommended system image
sdkmanager "system-images;android-34;google_apis;x86_64"

# Create AVD with optimal configuration
avdmanager create avd \
  --name "RunAnywhere_Test_Pixel7" \
  --package "system-images;android-34;google_apis;x86_64" \
  --device "pixel_7_pro" \
  --sdcard 2048M \
  --tag "google_apis"
```

### Step 2: Configure AVD Settings
```bash
# Edit AVD configuration (optional)
# Location: ~/.android/avd/RunAnywhere_Test_Pixel7.avd/config.ini

# Recommended settings for RunAnywhere testing:
# hw.ramSize = 4096 (4GB RAM)
# vm.heapSize = 512 (512MB heap)
# hw.audioInput = yes (required for voice features)
# hw.camera.back = emulated
# hw.camera.front = emulated
```

### Step 3: Launch Emulator
```bash
# Start emulator (takes 2-3 minutes first time)
emulator -avd RunAnywhere_Test_Pixel7 -no-snapshot-save

# Alternative: Launch from Android Studio
# Tools → AVD Manager → Click Play button
```

### Step 4: Verify Emulator
```bash
# Check emulator is running
adb devices
# Should show: emulator-5554    device

# Test audio capabilities (important for voice features)
adb shell getprop ro.config.vc_call_vol_steps
# Should return numeric value indicating audio support
```

---

## 5. Android Project Setup

### Step 1: Open Project in Android Studio
```bash
# Navigate to Android example app
cd examples/android/RunAnywhereAI

# Open in Android Studio
# File → Open → Select this directory
# OR from command line (if Android Studio is in PATH):
studio .
```

### Step 2: Project Configuration
1. **Gradle Sync**: Wait for initial Gradle sync to complete
2. **SDK Path**: Verify `local.properties` contains correct SDK path
3. **Build Variants**: Select `debug` build variant
4. **Dependencies**: Ensure all dependencies download successfully

### Step 3: Verify Dependencies
Check `app/build.gradle.kts` for proper SDK dependency:
```kotlin
dependencies {
    // RunAnywhere Kotlin SDK
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
    
    // Jetpack Compose
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    
    // Other dependencies...
}
```

### Step 4: Build Project
```bash
# From command line
./gradlew assembleDebug

# Expected output: BUILD SUCCESSFUL
# APK location: app/build/outputs/apk/debug/app-debug.apk
```

---

## 6. Testing & Validation

### Step 1: Install and Launch App
```bash
# Install on emulator
./gradlew installDebug

# Launch app
adb shell am start -n com.runanywhere.runanywhereai/.MainActivity

# Or use Android Studio: Run → Run 'app'
```

### Step 2: Basic Functionality Test

#### Test 1: App Launch ✅
- [ ] App launches without crashes
- [ ] Bottom navigation shows 5 tabs
- [ ] No immediate error dialogs

#### Test 2: Chat Feature ✅
- [ ] Navigate to Chat tab
- [ ] Type a message and send
- [ ] Receives response (may be mock initially)
- [ ] Streaming animation works

#### Test 3: Quiz Feature ✅
- [ ] Navigate to Quiz tab
- [ ] Enter a topic and generate quiz
- [ ] Swipe through questions
- [ ] View results at the end

#### Test 4: Models Tab ✅
- [ ] Navigate to Models tab
- [ ] See list of available models
- [ ] Model categories expand/collapse
- [ ] Device information displays

#### Test 5: Voice Feature (Partial) ⚠️
- [ ] Navigate to Voice tab
- [ ] Microphone permission requested
- [ ] Microphone button responds to taps
- [ ] Audio level visualization shows activity

#### Test 6: Settings Tab (Skeleton) ❌
- [ ] Navigate to Settings tab
- [ ] Basic UI structure visible
- [ ] Placeholder content shown

### Step 3: Emulator-Specific Testing

#### Audio Testing
```bash
# Test microphone input
adb shell "dumpsys media.audio_policy | grep -A5 -B5 'input devices'"

# Should show microphone device available
```

#### Storage Testing
```bash
# Check app data directory
adb shell "ls -la /data/data/com.runanywhere.runanywhereai/"

# Verify app can write files
adb shell "run-as com.runanywhere.runanywhereai ls -la files/"
```

#### Performance Testing
```bash
# Monitor memory usage
adb shell "dumpsys meminfo com.runanywhere.runanywhereai"

# Check CPU usage
adb shell "top -n 1 | grep runanywhereai"
```

---

## 7. Physical Device Testing

### Setup for Physical Device
1. **Enable Developer Options**: Settings → About → Tap Build Number 7 times
2. **Enable USB Debugging**: Developer Options → USB Debugging
3. **Connect Device**: Use USB cable
4. **Verify Connection**: `adb devices` should show device

### Physical Device Benefits
- **Better Audio Quality**: Real microphone for voice testing
- **Performance Testing**: Actual device performance
- **User Experience**: Real touch interactions
- **Camera Access**: If needed for future features

### Recommended Test Devices
- **Minimum**: Any Android 7.0+ device
- **Recommended**: Pixel, Samsung Galaxy, or OnePlus (recent models)
- **Avoid**: Very old or heavily customized devices

---

## 8. Development Workflow

### Daily Development Setup
```bash
# 1. Pull latest changes
git pull origin main

# 2. Rebuild Kotlin SDK if changed
cd sdk/runanywhere-kotlin
./gradlew publishToMavenLocal

# 3. Clean and rebuild Android app
cd ../../examples/android/RunAnywhereAI
./gradlew clean assembleDebug

# 4. Install and test
./gradlew installDebug
```

### Code Changes Workflow
1. **SDK Changes**: Rebuild and republish to local Maven
2. **App Changes**: Standard Android development workflow
3. **Testing**: Use emulator for quick testing, device for thorough testing
4. **Debugging**: Use Android Studio debugger and logs

### Common Issues & Solutions

#### Issue: Gradle Sync Fails
```bash
# Clear Gradle cache
./gradlew clean
rm -rf ~/.gradle/caches/

# Re-sync project
./gradlew build
```

#### Issue: App Crashes on Launch
```bash
# Check logcat for crash details
adb logcat | grep -i "runanywhere\|crash\|error"

# Common fixes:
# - Check minSdkVersion compatibility
# - Verify all dependencies are available
# - Clear app data: adb shell pm clear com.runanywhere.runanywhereai
```

#### Issue: Voice Features Don't Work
```bash
# Check microphone permissions
adb shell "dumpsys package com.runanywhere.runanywhereai | grep -A1 android.permission.RECORD_AUDIO"

# Grant permission manually
adb shell "pm grant com.runanywhere.runanywhereai android.permission.RECORD_AUDIO"
```

#### Issue: Models Don't Download
- Check internet connectivity on emulator
- Verify backend URLs in configuration
- Check storage permissions

---

## 9. Debugging & Logging

### Enable Debug Logging
Add to `app/src/main/res/values/bools.xml`:
```xml
<resources>
    <bool name="debug_logging_enabled">true</bool>
</resources>
```

### View Logs
```bash
# Filter RunAnywhere logs
adb logcat | grep "RunAnywhere"

# Filter by log level
adb logcat | grep -E "(E/|W/|I/)"

# Save logs to file
adb logcat > debug_logs.txt
```

### Performance Monitoring
```bash
# GPU rendering profile
adb shell setprop debug.hwui.profile visual_bars

# Memory monitoring
adb shell "while true; do dumpsys meminfo com.runanywhere.runanywhereai | grep 'TOTAL'; sleep 5; done"
```

---

## 10. Validation Checklist

### Initial Setup ✅
- [ ] Android Studio installed and configured
- [ ] SDK tools available in PATH
- [ ] Repository cloned successfully
- [ ] Kotlin SDK builds without errors
- [ ] SDK published to local Maven

### Emulator Configuration ✅
- [ ] AVD created with recommended specs
- [ ] Emulator launches successfully
- [ ] Audio input/output working
- [ ] Network connectivity available

### App Development ✅
- [ ] Android project opens in Android Studio
- [ ] Gradle sync completes successfully
- [ ] App builds without errors
- [ ] App installs on emulator/device
- [ ] App launches without immediate crashes

### Feature Testing ✅
- [ ] Chat feature works (even with mock responses)
- [ ] Quiz generation functions
- [ ] Voice UI responds to interactions
- [ ] Models tab displays information
- [ ] Navigation between tabs works smoothly

### Development Ready ✅
- [ ] Can make code changes and rebuild
- [ ] Debugging works in Android Studio
- [ ] Logs are accessible via logcat
- [ ] Physical device testing available (optional)

---

## 11. Next Steps

### For Development
1. **Start with Chat Feature**: Ensure real LLM integration
2. **Voice Pipeline**: Fix audio capture reliability
3. **Settings Implementation**: Complete missing functionality
4. **Storage Management**: Add real storage analysis

### For Testing
1. **Create Test Cases**: Based on iOS app functionality
2. **Performance Benchmarks**: Compare with iOS performance
3. **User Experience**: Ensure native Android feel

### For Deployment
1. **Release Build**: Configure signing and optimization
2. **Testing Matrix**: Multiple devices and Android versions
3. **CI/CD**: Automate build and testing process

This setup guide provides everything needed to start developing on the Android RunAnywhere implementation. The environment will be ready for implementing the features identified in the gap analysis and detailed implementation plan.
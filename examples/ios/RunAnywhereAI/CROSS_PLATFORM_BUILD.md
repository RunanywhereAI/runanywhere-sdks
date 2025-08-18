# Cross-Platform Build Guide

## Overview
RunAnywhereAI now supports both iOS and macOS platforms. The app uses Swift Package Manager for dependency management, ensuring consistent builds across platforms.

## Platform Requirements

### iOS
- iOS 16.0+
- Xcode 15.0+
- iPhone, iPad, or iOS Simulator

### macOS
- macOS 13.0+
- Xcode 15.0+
- Mac with Apple Silicon or Intel processor

## Building the App

### Option 1: Using Xcode
1. Open `RunAnywhereAI.xcodeproj` (NOT .xcworkspace)
2. Select your target device:
   - For iOS: Choose an iPhone/iPad simulator or connected device
   - For macOS: Choose "My Mac" as the destination
3. Build and run with Cmd+R

### Option 2: Using Command Line

#### iOS Build
```bash
xcodebuild -project RunAnywhereAI.xcodeproj \
           -scheme RunAnywhereAI \
           -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
           build
```

#### macOS Build
```bash
xcodebuild -project RunAnywhereAI.xcodeproj \
           -scheme RunAnywhereAI \
           -destination 'platform=macOS' \
           build
```

### Option 3: Using Build Scripts
```bash
# iOS Simulator
./scripts/build_and_run.sh simulator "iPhone 16 Pro"

# macOS
./scripts/build_and_run.sh mac

# Verify both platforms
./scripts/verify_macos_build.sh
```

## Swift Package Manager

The app uses Swift Package Manager for dependencies. The `Package.resolved` file will be automatically generated when you build the project and will work for both iOS and macOS platforms.

### Current Dependencies (via SPM)
- RunAnywhereSDK (local package)
- ZIPFoundation
- WhisperKit
- swift-transformers
- executorch (with various backends)
- LLM

All these packages support both iOS and macOS platforms.

## Platform-Specific Code

The codebase uses conditional compilation to handle platform differences:

```swift
#if os(iOS)
    // iOS-specific code
#elseif os(macOS)
    // macOS-specific code
#endif
```

### Common Platform Differences

1. **Audio Session**: iOS requires AVAudioSession setup, macOS doesn't
2. **Navigation**: Different toolbar placements between platforms
3. **Colors**: UIColor (iOS) vs NSColor (macOS)
4. **Text Fields**: Some modifiers like `.keyboardType` are iOS-only

## Troubleshooting

### CocoaPods Removal
This project previously used CocoaPods but has been migrated to Swift Package Manager only. If you see errors about missing Pods framework:

1. Run `pod deintegrate` if you have CocoaPods installed
2. Delete `Pods/`, `Podfile.lock`, and `*.xcworkspace`
3. Open the `.xcodeproj` file directly, not the workspace

### Build Errors
If you encounter build errors:

1. Clean build folder: Cmd+Shift+K
2. Reset package caches: File → Packages → Reset Package Caches
3. Ensure Xcode is properly selected: `sudo xcode-select -s /Applications/Xcode.app`

## Architecture Notes

The app is designed with cross-platform compatibility in mind:

- Shared business logic in RunAnywhereSDK
- Platform-agnostic SwiftUI views where possible
- Minimal platform-specific code, clearly marked with conditionals
- All dependencies support both iOS and macOS

## Testing

Run tests for both platforms:

```bash
# iOS tests
xcodebuild test -project RunAnywhereAI.xcodeproj \
                -scheme RunAnywhereAI \
                -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# macOS tests
xcodebuild test -project RunAnywhereAI.xcodeproj \
                -scheme RunAnywhereAI \
                -destination 'platform=macOS'
```
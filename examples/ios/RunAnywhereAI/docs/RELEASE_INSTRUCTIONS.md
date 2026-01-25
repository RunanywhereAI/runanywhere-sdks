# RunAnywhereAI iOS App - Release Instructions

This document outlines the steps required to release a new version of the RunAnywhereAI iOS app to the App Store.

## Pre-Release Checklist

### 1. Update Production Credentials

Before releasing, ensure the production API key and base URL are configured in the app:

**File:** `RunAnywhereAI/App/RunAnywhereAIApp.swift`

In the `#else` block (production mode), update:
```swift
let apiKey = "<PRODUCTION_API_KEY>"
let baseURL = "<PRODUCTION_BASE_URL>"
```

The app uses compile-time flags:
- `#if DEBUG` - Development mode (no API key needed, uses Supabase)
- `#else` - Production mode (requires API key and backend URL)

### 2. Verify iOS Deployment Target

**CRITICAL:** The app's deployment target MUST match the SDK requirements.

| Component | Required Value |
|-----------|----------------|
| App Deployment Target | **iOS 17.0** |
| SDK Requirement | iOS 17.0 (defined in `Package.swift`) |
| Framework MinimumOSVersion | 17.0 |

**File:** `RunAnywhereAI.xcodeproj/project.pbxproj`

Verify all `IPHONEOS_DEPLOYMENT_TARGET` entries are set to `17.0`:
```
IPHONEOS_DEPLOYMENT_TARGET = 17.0;
```

**Warning:** Do NOT set the deployment target higher than what the SDK supports. Setting it to iOS 18.x when frameworks were built for iOS 17 will cause validation errors.

### 3. Bump Version Number

Update the marketing version in Xcode project settings. The version must be higher than any previously submitted version.

**File:** `RunAnywhereAI.xcodeproj/project.pbxproj`

Search for `MARKETING_VERSION` and update all occurrences:
```
MARKETING_VERSION = X.Y.Z;
```

Alternatively, update via Xcode:
1. Select the project in Navigator
2. Select the RunAnywhereAI target
3. Go to "General" tab
4. Update "Version" field

### 4. Framework Info.plist Requirements

Apple requires all embedded frameworks to have specific keys in their Info.plist files with **matching values** to the app's deployment target.

#### Required Keys:
- `CFBundleVersion` - Build version string
- `MinimumOSVersion` - Must be set to **17.0** (matching SDK requirement)

#### Frameworks to Check:

**RunAnywhere SDK Frameworks** (in `sdks/sdk/runanywhere-swift/Binaries/`):
- `RACommons.xcframework/ios-arm64/RACommons.framework/Info.plist`
- `RACommons.xcframework/ios-arm64_x86_64-simulator/RACommons.framework/Info.plist`
- `RABackendLLAMACPP.xcframework/ios-arm64/RABackendLLAMACPP.framework/Info.plist`
- `RABackendLLAMACPP.xcframework/ios-arm64_x86_64-simulator/RABackendLLAMACPP.framework/Info.plist`
- `RABackendONNX.xcframework/ios-arm64/RABackendONNX.framework/Info.plist`
- `RABackendONNX.xcframework/ios-arm64_x86_64-simulator/RABackendONNX.framework/Info.plist`

**ONNX Runtime Framework** (third-party binary):
- `sdks/sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Info.plist`
- `sdks/sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework/ios-arm64_x86_64-simulator/onnxruntime.framework/Info.plist`

### 5. Automated Fix: patch-framework-plist.sh

We've created a script to automatically fix framework Info.plist files in DerivedData.

**Location:** `scripts/patch-framework-plist.sh`

**Usage:**
```bash
# Run from the RunAnywhereAI app directory
./scripts/patch-framework-plist.sh
```

**What it does:**
- Searches all DerivedData directories for framework Info.plist files
- Patches `onnxruntime.framework`, `RACommons.framework`, `RABackendLLAMACPP.framework`, `RABackendONNX.framework`
- Adds or updates `MinimumOSVersion=17.0`
- Reports which files were patched vs. already correct

**When to run:**
- After cleaning DerivedData (`rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*`)
- After resetting SPM packages (File > Packages > Reset Package Caches)
- Before archiving if you've done a clean build

### 6. Manual Fix (Alternative)

If you prefer to fix manually using PlistBuddy:

```bash
# Add or update MinimumOSVersion for all frameworks in DerivedData
for framework in onnxruntime RACommons RABackendLLAMACPP RABackendONNX; do
  for plist in $(find ~/Library/Developer/Xcode/DerivedData -path "*${framework}.framework/Info.plist" -type f 2>/dev/null); do
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion 17.0" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string 17.0" "$plist" 2>/dev/null
    echo "Patched: $plist"
  done
done
```

## Build & Archive

### 1. Build First (Required)

Build the project to populate DerivedData:
```
Cmd+B (or Product > Build)
```

### 2. Run Patch Script

```bash
cd sdks/examples/ios/RunAnywhereAI
./scripts/patch-framework-plist.sh
```

### 3. Archive (Without Cleaning!)

**Important:** Do NOT clean after running the patch script.

1. Select "RunAnywhereAI" scheme
2. Set destination to "Any iOS Device (arm64)"
3. Product > Archive
4. Wait for archive to complete
5. Organizer window will open automatically

## Upload to App Store Connect

### 1. Validate Archive

In Organizer:
1. Select the new archive
2. Click "Validate App"
3. Follow the prompts
4. Fix any validation errors before proceeding

### 2. Distribute App

1. Click "Distribute App"
2. Select "App Store Connect"
3. Select "Upload"
4. Follow the prompts
5. Wait for upload to complete

### 3. App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select "RunAnywhereAI" app
3. Create new version or select existing
4. Add the uploaded build
5. Fill in release notes
6. Submit for review

## Troubleshooting

### Error: "Invalid Bundle - does not support the minimum OS Version"

**Error Message:**
```
Invalid Bundle. The bundle RunAnywhereAI.app/Frameworks/onnxruntime.framework does not support the minimum OS Version specified in the Info.plist.
```

**Cause:** Mismatch between the app's deployment target and the framework's MinimumOSVersion. This happens when:
- App deployment target is set higher than what frameworks support (e.g., iOS 18.5 when frameworks were built for iOS 17)
- Framework MinimumOSVersion doesn't match the SDK requirements

**Solution:**
1. Verify app deployment target is `17.0` (not higher!)
2. Run the patch script: `./scripts/patch-framework-plist.sh`
3. Re-archive **without cleaning**

### Error: "Invalid MinimumOSVersion - is ''"

**Error Message:**
```
Invalid MinimumOSVersion. Apps that only support 64-bit devices must specify a deployment target of 8.0 or later. MinimumOSVersion in 'RunAnywhereAI.app/Frameworks/onnxruntime.framework' is ''
```

**Cause:** The ONNX Runtime binary downloaded via SPM from Microsoft's servers (`download.onnxruntime.ai`) doesn't include the `MinimumOSVersion` key in its Info.plist.

**Solution:**
1. Run the patch script: `./scripts/patch-framework-plist.sh`
2. Re-archive **without cleaning**

### dSYM Upload Warnings

**Warning:**
```
Upload Symbols Failed - The archive did not include a dSYM for the framework
```

**Cause:** Third-party frameworks (Sentry, onnxruntime) don't include dSYM files in their binary distributions.

**Solution:** These warnings can be safely ignored. The frameworks either:
- Have their own symbol upload mechanisms (Sentry)
- Don't provide dSYMs in their binary distributions (onnxruntime)

### Build Fails After SPM Clean

If build fails after cleaning SPM cache:

1. Resolve packages: File > Packages > Resolve Package Versions
2. Build the project once (Cmd+B)
3. Run the patch script: `./scripts/patch-framework-plist.sh`
4. Archive the app (Product > Archive)

### Code Signing Issues

Ensure your Apple Developer account has:

- Valid distribution certificate
- App Store provisioning profile for `com.runanywhere.RunAnywhere`

## Quick Release Checklist

```
[ ] 1. Update production API key and base URL
[ ] 2. Verify deployment target is iOS 17.0 (NOT higher!)
[ ] 3. Bump MARKETING_VERSION
[ ] 4. Build project (Cmd+B)
[ ] 5. Run patch script: ./scripts/patch-framework-plist.sh
[ ] 6. Archive (Product > Archive) - DO NOT CLEAN!
[ ] 7. Validate in Organizer
[ ] 8. Upload to App Store Connect
[ ] 9. Submit for review
```

## Environment Configuration

The app automatically selects the environment based on build configuration:

| Build | Environment | API Key Required |
|-------|-------------|------------------|
| Debug | Development | No |
| Release | Production | Yes |

### Verifying Production Mode

To verify the app is in production mode:
1. Archive the app (Release build)
2. Check logs for: `SDK initialized in PRODUCTION mode`

## Version History

| Version | Date       | Notes                                                    |
|---------|------------|----------------------------------------------------------|
| 0.17.2  | 2025-01-24 | Fixed deployment target to iOS 17.0, updated MinimumOSVersion to 17.0 for all frameworks |
| 0.17.1  | 2025-01-24 | Added patch script for ONNX Runtime MinimumOSVersion fix |
| 0.17.0  | 2025-01-24 | Production release with backend integration              |
| 0.16.0  | -          | Previous release                                         |

## Technical Details

### Why iOS 17.0?

The RunAnywhere SDK requires iOS 17.0 minimum (defined in `Package.swift`):
```swift
platforms: [
    .iOS(.v17),
    .macOS(.v14),
    ...
]
```

All framework `MinimumOSVersion` values and the app's `IPHONEOS_DEPLOYMENT_TARGET` must be consistent with this requirement.

### Framework Version Alignment

| Framework | MinimumOSVersion |
|-----------|------------------|
| App (RunAnywhereAI) | 17.0 |
| RACommons | 17.0 |
| RABackendLLAMACPP | 17.0 |
| RABackendONNX | 17.0 |
| onnxruntime | 17.0 |

## Contacts

- **App Store Connect Team ID:** L86FH3K93L
- **Bundle Identifier:** com.runanywhere.RunAnywhere

# TensorFlow Lite Import Fix Guide

If you're seeing "TensorFlow Lite not found" errors when running the app, here are several solutions:

## Solution 1: Update Import Statements (Already Applied)

The TFLiteService.swift has been updated to check for both possible module names:
```swift
#if canImport(TensorFlowLite)
import TensorFlowLite
#elseif canImport(TFLiteSwift_TensorFlowLite)
import TFLiteSwift_TensorFlowLite
#endif
```

## Solution 2: Clean and Rebuild

1. Clean build folder:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*
   ```

2. Clean CocoaPods:
   ```bash
   pod deintegrate
   pod install
   ```

3. Open workspace and build:
   ```bash
   open RunAnywhereAI.xcworkspace
   ```
   Then press Cmd+Shift+K (Clean) and Cmd+B (Build)

## Solution 3: Update Podfile

Update the Podfile to specify the exact version:
```ruby
platform :ios, '16.0'

target 'RunAnywhereAI' do
  use_frameworks!
  
  # Specify exact version
  pod 'TensorFlowLiteSwift', '~> 2.14.0'
  # Or try the C API version
  # pod 'TensorFlowLiteC', '~> 2.14.0'
end
```

Then run:
```bash
pod update
```

## Solution 4: Add to Build Settings

1. In Xcode, select the RunAnywhereAI target
2. Go to Build Settings
3. Search for "Import Paths"
4. Add to "Swift Compiler - Search Paths > Import Paths":
   ```
   $(SRCROOT)/Pods/TensorFlowLiteSwift
   ```

## Solution 5: Bridging Header (If nothing else works)

1. Create a bridging header file: `RunAnywhereAI-Bridging-Header.h`
2. Add:
   ```objc
   #import <TensorFlowLite/TensorFlowLite.h>
   ```
3. Set in Build Settings > "Objective-C Bridging Header":
   ```
   RunAnywhereAI/RunAnywhereAI-Bridging-Header.h
   ```

## Solution 6: Use Swift Package Manager Instead

Remove from Podfile and add via SPM:
1. File > Add Package Dependencies
2. Add: `https://github.com/tensorflow/tensorflow`
3. Select TensorFlowLiteSwift product

## Verification

After applying fixes, verify TensorFlow Lite is working:

1. Check if the framework is linked:
   - Select target > General > Frameworks, Libraries, and Embedded Content
   - Should see TensorFlowLite.framework

2. Run a test in the app:
   ```swift
   // In TFLiteService.swift, add to initialize():
   print("TensorFlow Lite Version: \(TensorFlowLite.version())")
   ```

## Common Issues

1. **Module compiled with Swift X.X cannot be imported**
   - Update to latest TensorFlowLiteSwift pod version
   - Ensure Xcode is up to date

2. **Framework not found TensorFlowLiteC**
   - Add to Podfile:
     ```ruby
     pod 'TensorFlowLiteC', '~> 2.14.0'
     ```

3. **Sandbox errors during build**
   - Disable "Copy Pods Resources" script temporarily
   - Or build from Xcode GUI instead of command line

## Testing

To test if TensorFlow Lite is working:
1. Download a test model:
   ```bash
   curl -o test_model.tflite https://storage.googleapis.com/download.tensorflow.org/models/mobilenet_v1_1.0_224_quant.tflite
   ```

2. Add to app bundle and test loading in TFLiteService

If you continue to have issues, please check:
- Xcode version (should be 15.0+)
- iOS deployment target (should be 16.0+)
- CocoaPods version: `pod --version` (should be 1.12+)
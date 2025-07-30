# Troubleshooting Guide

This guide covers common issues and solutions when setting up and using the RunAnywhereAI iOS app.

## Table of Contents
- [TensorFlow Lite Import Issues](#tensorflow-lite-import-issues)
- [Xcode 16 Sandbox Errors](#xcode-16-sandbox-errors)
- [Model Download Issues](#model-download-issues)
- [Framework-Specific Issues](#framework-specific-issues)
- [General Build Issues](#general-build-issues)

## TensorFlow Lite Import Issues

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

## Xcode 16 Sandbox Errors

### Error: "Sandbox: rsync deny(1) file-write-create"

This error occurs with Xcode 16 when building projects with CocoaPods.

**Solution**: Run the fix script after `pod install`:
```bash
./fix_pods_sandbox.sh
```

This script adds `ENABLE_USER_SCRIPT_SANDBOXING = NO` to all Pod xcconfig files.

## Model Download Issues

### "Authentication Required" for Public Models

**Issue**: Public models showing authentication required message.

**Solutions**:
1. Verify the model URL is correct
2. Check if the model is actually public on HuggingFace
3. Ensure `requiresAuth: false` in provider configuration

### "404 Not Found" for .mlpackage Downloads

**Issue**: Directory-based models failing to download.

**Solutions**:
1. Verify the model uses HuggingFaceDirectoryDownloader
2. Check if the path includes the .mlpackage extension
3. Ensure the repository exists on HuggingFace

### Slow Downloads

**Solutions**:
1. Add HuggingFace token for better rate limits (optional)
2. Check network conditions
3. Use background downloads for large models
4. Try alternative mirror URLs if available

## Framework-Specific Issues

### Foundation Models
- **"Not Available"**: Requires iOS 26+ and iPhone 15 Pro or later
- **"Framework Not Found"**: Need Xcode 26 beta

### Core ML
- **"Failed to Load Model"**: Check model format (.mlpackage vs .mlmodel)
- **"Unsupported Model"**: Verify model was converted for iOS deployment

### MLX
- **"Module Not Found"**: Ensure MLX Swift package is added correctly
- **"GPU Not Available"**: Requires A14 chip or later

### ONNX Runtime
- **"Provider Not Available"**: CoreML provider requires specific model format
- **"Session Creation Failed"**: Check model compatibility

### TensorFlow Lite
- **"Delegate Creation Failed"**: Metal delegate requires compatible device
- **"Model Not Valid"**: Ensure .tflite file is not corrupted

## General Build Issues

### Clean Build Solutions

1. **Clean Derived Data**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*
   ```

2. **Reset CocoaPods**:
   ```bash
   pod deintegrate
   pod cache clean --all
   pod install
   ./fix_pods_sandbox.sh
   ```

3. **Reset Package Dependencies**:
   - File → Packages → Reset Package Caches
   - File → Packages → Update to Latest Package Versions

### Memory Issues

**"App Terminated Due to Memory Pressure"**:
1. Use smaller models
2. Implement proper model cleanup
3. Enable memory monitoring in Settings
4. Test on devices with more RAM

### Performance Issues

**Slow Inference**:
1. Check if using appropriate hardware acceleration
2. Verify model quantization
3. Consider using smaller models
4. Profile with Instruments

## Getting Help

If you continue to experience issues:

1. Check the [GitHub Issues](https://github.com/anthropics/claude-code/issues)
2. Review framework-specific documentation in [frameworks/](../frameworks/)
3. Verify your setup matches the [implementation guide](../implementation/README.md)
4. Ensure you're using supported iOS versions and devices

---

*For framework-specific setup guides, see the [frameworks documentation](../frameworks/)*
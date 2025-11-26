# ONNX Runtime Integration Testing Guide

## Quick Start - Testing ONNX Integration

This guide will help you test the newly integrated ONNX Runtime module in the RunAnywhereAI example app.

## Step 1: Add ONNXRuntime Package to Xcode Project

1. **Open the project in Xcode**:
   ```bash
   open /Users/shubhammalhotra/Desktop/RunAnywhereAI/sdks/examples/ios/RunAnywhereAI/RunAnywhereAI.xcodeproj
   ```

2. **Add the ONNXRuntime local package**:
   - In Xcode, select the `RunAnywhereAI` project in the navigator
   - Select the `RunAnywhereAI` target
   - Go to the **"Frameworks, Libraries, and Embedded Content"** section
   - Click the **"+"** button
   - Click **"Add Package Dependency..."**
   - Click **"Add Local..."** at the bottom
   - Navigate to: `/Users/shubhammalhotra/Desktop/RunAnywhereAI/sdks/sdk/runanywhere-swift/Modules/ONNXRuntime`
   - Click **"Add Package"**
   - Select **"ONNXRuntime"** product
   - Click **"Add Package"**

## Step 2: Build and Run

The app initialization code has already been updated to:
- Import ONNXRuntime ✅
- Register ONNXServiceProvider ✅
- Register ONNXAdapter with **Wav2Vec2 Base ONNX** model ✅
  - **Note**: Using Wav2Vec2 (Facebook's model) instead of Whisper to test a different architecture!

Just build and run:

```bash
# From the project directory
xcodebuild -workspace RunAnywhereAI.xcodeproj/project.xcworkspace \
  -scheme RunAnywhereAI \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

Or simply press **⌘R** in Xcode.

## Step 3: What to Expect

### Successful Integration Signs

When the app launches, check the **Xcode Console** for these log messages:

```
🎯 Initializing SDK...
✅ LLMSwift registered with custom models (lazy loading)
✅ WhisperKit registered with custom models (lazy loading)
✅ ONNX Runtime registered with Wav2Vec2 model (lazy loading)  ← NEW!
✅ FluidAudioDiarization registered
🎉 All adapters registered with custom models for development
✅ SDK successfully initialized!
```

### Current Implementation Status

**What Works** ✅:
- ONNX module compiles and links
- Adapter registration succeeds
- Model appears in available models list
- C bridge API can be called from Swift

**What's Stubbed** ⚠️:
- Audio preprocessing (mel spectrogram generation)
- Actual ONNX model inference

**Expected Behavior**:
When you try to transcribe audio with the ONNX model, you'll get a stub response like:
```
"Audio transcription not yet implemented"
```

This is expected! It confirms the integration works, but shows the C++ backend needs implementation.

## Step 4: Test Transcription (Optional)

To test if the ONNX adapter is being called:

### Option A: Use Existing App UI

1. Launch the app
2. Navigate to the STT/transcription feature
3. Select "Wav2Vec2 Base (ONNX)" from the model dropdown
4. Try to transcribe some audio
5. You should see the stub message

### Option B: Quick Code Test

Add this to `ContentView.swift` for a quick test:

```swift
import ONNXRuntime

// Add a test button
Button("Test ONNX") {
    Task {
        do {
            let stt = try await RunAnywhere.stt()
            let options = STTOptions(
                language: "en",
                audioFormat: .pcm
            )

            // Create dummy audio data (1 second of silence)
            let dummyAudio = Data(count: 16000 * 2) // 16kHz, 16-bit

            let result = try await stt.transcribe(
                audioData: dummyAudio,
                options: options
            )

            print("ONNX Transcription Result: \(result.transcript)")
        } catch {
            print("ONNX Test Error: \(error)")
        }
    }
}
```

## Step 5: Verify Integration

Check these points:

- [ ] ✅ App builds without errors
- [ ] ✅ "ONNX Runtime registered with Wav2Vec2 model" appears in logs
- [ ] ✅ "Wav2Vec2 Base (ONNX)" appears in model list
- [ ] ✅ Can select ONNX model in UI
- [ ] ⚠️ Transcription returns stub message (expected for now)

## Troubleshooting

### Build Error: "No such module 'ONNXRuntime'"

**Solution**: Make sure you added the local package in Xcode (Step 1 above).

### Runtime Error: "Failed to create ONNX Runtime handle"

**Check**:
1. XCFramework is present: `ls /Users/shubhammalhotra/Desktop/RunAnywhereAI/sdks/sdk/runanywhere-swift/XCFrameworks/RunAnywhereONNX.xcframework`
2. XCFramework has correct structure with module.modulemap
3. App is linking against the XCFramework

### App Crashes on Launch

**Check Console Logs**:
- Look for "ONNX" related error messages
- Check if registration failed
- Verify all imports are correct

## Next Steps After Successful Integration

Once you confirm the integration works:

1. **Implement Audio Preprocessing**:
   - File: `/Users/shubhammalhotra/Desktop/RunanywhereAI/runanywhere-core/src/backends/onnx/bridge/ios/onnx_bridge.cpp`
   - Function: `ra_onnx_transcribe` (lines 298-302)
   - Add mel spectrogram feature extraction for Whisper

2. **Test with Real Model**:
   - Download actual Whisper Tiny ONNX model
   - Implement model loading
   - Run real transcription

3. **Performance Testing**:
   - Measure transcription speed
   - Check memory usage
   - Compare with WhisperKit performance

## Logs to Monitor

Key log categories to watch in Xcode Console:

- `com.runanywhere.RunAnywhereAI.RunAnywhereAIApp` - App initialization
- `com.runanywhere.onnx.ONNXServiceProvider` - Service provider
- `com.runanywhere.onnx.ONNXAdapter` - Adapter operations
- `com.runanywhere.onnx.ONNXSTTService` - Transcription calls

## Success Criteria

Integration is successful if:

✅ App builds and runs
✅ Console shows "ONNX Runtime registered"
✅ Model appears in UI
✅ Can initiate transcription (even if stubbed)
✅ No crashes or errors during registration

---

**Integration Status**: ✅ Swift layer complete, ⚠️ C++ backend stubbed

Ready to test? Open Xcode and follow Step 1!

# Full NPU Acceleration: End-to-End Implementation Guide

This guide explains how QNN NPU acceleration works and provides step-by-step instructions to complete the implementation and test it.

---

## Part 1: How NPU Acceleration Works

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ANDROID APPLICATION                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────────────────┐ │
│  │ Kotlin SDK  │───▶│  JNI Bridge  │───▶│       onnx_backend.cpp          │ │
│  └─────────────┘    └──────────────┘    │                                 │ │
│                                          │  ┌─────────────────────────┐   │ │
│                                          │  │ get_optimal_provider()  │   │ │
│                                          │  │                         │   │ │
│                                          │  │  1. is_qualcomm_device()│   │ │
│                                          │  │  2. is_qnn_available()  │   │ │
│                                          │  │  3. Return provider     │   │ │
│                                          │  └───────────┬─────────────┘   │ │
│                                          └──────────────┼─────────────────┘ │
│                                                         │                    │
│                                                         ▼                    │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     SHERPA-ONNX / ONNX RUNTIME                        │   │
│  │                                                                       │   │
│  │   provider="qnn"  ───▶  QNN Execution Provider  ───▶  libQnnHtp.so   │   │
│  │   provider="nnapi" ──▶  NNAPI Execution Provider ──▶  Android NNAPI  │   │
│  │   provider="cpu"  ───▶  CPU Execution Provider  ───▶  SIMD/NEON      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                         │                    │
└─────────────────────────────────────────────────────────┼────────────────────┘
                                                          │
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HARDWARE LAYER                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐          │
│   │   Hexagon NPU   │   │   Adreno GPU    │   │    Kryo CPU     │          │
│   │   (QNN HTP)     │   │   (QNN GPU)     │   │   (Fallback)    │          │
│   │                 │   │                 │   │                 │          │
│   │  ⚡ 10x faster  │   │  ⚡ 3x faster   │   │  ⚡ Baseline    │          │
│   │  🔋 Low power   │   │  🔋 Medium      │   │  🔋 High power  │          │
│   └─────────────────┘   └─────────────────┘   └─────────────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. App calls: RunAnywhere.speak("Hello world")
       │
       ▼
2. Kotlin SDK → JNI → rac_tts_synthesize()
       │
       ▼
3. onnx_backend.cpp::ONNXTTS::synthesize()
       │
       ├── Detects model type (Kokoro/VITS)
       ├── Calls get_optimal_provider()
       │       │
       │       ├── Check ro.soc.model → "SM8650" (Qualcomm)
       │       ├── Check dlopen("libQnnHtp.so") → Available
       │       └── Return "qnn"
       │
       ▼
4. Sherpa-ONNX creates session with provider="qnn"
       │
       ▼
5. ONNX Runtime loads model into QNN context
       │
       ▼
6. Inference runs on Hexagon NPU (HTP)
       │
       ▼
7. Audio samples returned → Played through speakers
```

### Provider Selection Logic (from onnx_backend.cpp)

```cpp
static const char* get_optimal_provider(bool prefer_npu = true) {
    #if defined(__APPLE__)
        return "coreml";           // → Apple Neural Engine
    
    #elif defined(__ANDROID__)
        if (is_qualcomm_device() && is_qnn_available()) {
            return "qnn";          // → Hexagon NPU (BEST)
        }
        return "nnapi";            // → Generic Android NPU
    
    #else
        return "cpu";              // → Desktop/Server
    #endif
}
```

---

## Part 2: Complete Implementation Steps

### Step 1: Build the C++ Backend

```bash
cd sdk/runanywhere-commons

# Build for Android arm64 (Qualcomm devices)
./scripts/build-android.sh all arm64-v8a
```

**What this produces:**
```
dist/android/
├── onnx/arm64-v8a/
│   ├── librac_backend_onnx.so      # Our backend with QNN support
│   ├── librac_backend_onnx_jni.so  # JNI bridge
│   ├── libonnxruntime.so           # ONNX Runtime
│   └── libsherpa-onnx-*.so         # Sherpa-ONNX libs
├── commons/arm64-v8a/
│   └── librac_commons.so           # Core library
└── packages/
    └── RunAnywhereUnified-android-X.X.X.zip
```

### Step 2: Download QNN Libraries

```bash
# Download and extract QNN libraries
./scripts/android/download-qnn-sdk.sh

# This creates:
# third_party/qnn-libs/arm64-v8a/
#   ├── libQnnHtp.so           # Hexagon NPU backend
#   ├── libQnnHtpPrepare.so    # Model preparation
#   ├── libQnnHtpV75Stub.so    # Snapdragon 8 Gen 3
#   ├── libQnnHtpV73Stub.so    # Snapdragon 8 Gen 2
#   ├── libQnnSystem.so        # System interface
#   └── libQnnCpu.so           # CPU fallback
```

### Step 3: Prepare FP16 Model

```bash
# Convert Kokoro model to FP16 for NPU optimization
cd tools/qnn

python compile_model_for_qnn.py \
    /path/to/kokoro-multi-lang-v1_0/model.onnx \
    --convert-fp16 \
    --output-dir ./output
```

**Why FP16?**
- NPUs are optimized for FP16 operations
- 50% smaller model size
- 2-3x faster inference
- Minimal quality loss for TTS

### Step 4: Integrate into Android App

**4a. Copy libraries to your app:**
```bash
# Native libraries
cp -r dist/android/onnx/arm64-v8a/* \
      app/src/main/jniLibs/arm64-v8a/

# QNN libraries
cp -r third_party/qnn-libs/arm64-v8a/* \
      app/src/main/jniLibs/arm64-v8a/
```

**4b. Update build.gradle:**
```groovy
android {
    defaultConfig {
        ndk {
            abiFilters 'arm64-v8a'  // QNN only supports ARM64
        }
    }
    
    packagingOptions {
        doNotStrip '*/arm64-v8a/libQnn*.so'
    }
}
```

**4c. Register model:**
```kotlin
// In your Application.onCreate()
ModelRegistry.registerModel(
    id = "kokoro-fp16-v1",
    name = "Kokoro TTS (NPU Optimized)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/kokoro-qnn-fp16-v1.0/kokoro-qnn-fp16-v1.0.tar.gz",
    framework = Framework.ONNX,
    modality = Modality.SPEECH_SYNTHESIS
)
```

### Step 5: Verify NPU Usage

```bash
# Monitor logs during TTS synthesis
adb logcat | grep -E "(ONNX|QNN|NPU|HTP)"
```

**Expected output on Qualcomm device:**
```
D/ONNX.NPU: Detected Qualcomm SoC: SM8650
D/ONNX.NPU: QNN HTP library available
I/ONNX.NPU: ============================================
I/ONNX.NPU:   USING QUALCOMM QNN (HTP/NPU)
I/ONNX.NPU:   Provider: QNN
I/ONNX.NPU:   Hardware: Hexagon Tensor Processor
I/ONNX.NPU: ============================================
I/ONNX.TTS: TTS MODEL LOADED WITH NPU ACCELERATION
I/ONNX.TTS: Model Type: Kokoro
I/ONNX.TTS: Sample Rate: 24000 Hz
```

---

## Part 3: Testing Options

### Option A: Physical Device (Recommended for NPU Testing)

**Best Devices:**
| Device | Price | Why |
|--------|-------|-----|
| OnePlus 11 | ~$500 | Best value, developer-friendly |
| Galaxy S24 | ~$800 | Latest Snapdragon 8 Gen 3 |
| Galaxy S22 (used) | ~$300 | Budget option |

**Setup:**
```bash
# Enable USB debugging
# Connect device via USB/WiFi

# Install and run
adb install -r app-debug.apk
adb logcat | grep -E "(ONNX|QNN|NPU)"
```

### Option B: Firebase Test Lab (Cloud Testing)

Firebase has Samsung Galaxy S23/S24 devices available.

**Setup:**
```bash
# Install gcloud CLI
brew install google-cloud-sdk

# Login
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# List available Samsung devices
gcloud firebase test android models list | grep -i samsung

# Run test on Galaxy S23
gcloud firebase test android run \
    --type instrumentation \
    --app app-debug.apk \
    --test app-debug-androidTest.apk \
    --device model=a]54,version=33 \
    --timeout 5m
```

**Limitations:**
- May not have QNN libraries pre-installed
- Limited NPU verification capability
- Good for functional testing, not NPU benchmarking

### Option C: AWS Device Farm

**Setup:**
```bash
# Install AWS CLI
brew install awscli

# Configure
aws configure

# Create device pool with Qualcomm devices
aws devicefarm create-device-pool \
    --project-arn arn:aws:devicefarm:us-west-2:... \
    --name "Qualcomm-NPU-Test" \
    --rules '[{"attribute":"MANUFACTURER","operator":"EQUALS","value":"Samsung"}]'

# Schedule test run
aws devicefarm schedule-run \
    --project-arn arn:aws:devicefarm:us-west-2:... \
    --app-arn arn:aws:devicefarm:us-west-2:...:upload:... \
    --device-pool-arn arn:aws:devicefarm:us-west-2:...:devicepool:...
```

### Option D: BrowserStack App Live

BrowserStack has newer devices including Galaxy S24.

```bash
# Upload APK
curl -u "USERNAME:ACCESS_KEY" \
    -X POST "https://api-cloud.browserstack.com/app-automate/upload" \
    -F "file=@app-debug.apk"

# Start session
# Use their web console to select Galaxy S24
# Run app and check logs
```

### Option E: Samsung Remote Test Lab (Free)

Samsung offers free access to their devices for testing.

1. Sign up at: https://developer.samsung.com/remote-test-lab
2. Select Galaxy S24/S23
3. Install APK and run tests
4. Check device logs for NPU messages

---

## Part 4: Automated Test Script

Create a test script to verify NPU acceleration:

```kotlin
// NPUAccelerationTest.kt
@RunWith(AndroidJUnit4::class)
class NPUAccelerationTest {
    
    @Test
    fun testQNNProviderDetection() {
        // Check if we're on a Qualcomm device
        val socModel = System.getProperty("ro.soc.model") ?: ""
        val isQualcomm = socModel.startsWith("SM8") || socModel.startsWith("SM7")
        
        if (isQualcomm) {
            // Verify QNN libraries are available
            val qnnAvailable = try {
                System.loadLibrary("QnnHtp")
                true
            } catch (e: UnsatisfiedLinkError) {
                false
            }
            
            assertTrue("QNN should be available on Qualcomm device", qnnAvailable)
        }
    }
    
    @Test
    fun testTTSWithNPUAcceleration() {
        val tts = RunAnywhere.tts()
        
        // Load model
        tts.loadModel("kokoro-fp16-v1")
        
        // Measure inference time
        val startTime = System.currentTimeMillis()
        val audio = tts.synthesize("Hello, this is a test of NPU acceleration.")
        val inferenceTime = System.currentTimeMillis() - startTime
        
        // On NPU: should be < 100ms
        // On CPU: typically 300-500ms
        Log.d("NPU_TEST", "Inference time: ${inferenceTime}ms")
        
        // Assert performance (adjust threshold based on device)
        assertTrue("Inference should be fast on NPU", inferenceTime < 200)
    }
}
```

---

## Part 5: Performance Verification

### Benchmark Script

```bash
#!/bin/bash
# benchmark_npu.sh

echo "=== NPU Acceleration Benchmark ==="
echo ""

# Check device info
echo "Device: $(adb shell getprop ro.product.model)"
echo "SoC: $(adb shell getprop ro.soc.model)"
echo "Android: $(adb shell getprop ro.build.version.release)"
echo ""

# Run TTS benchmark
echo "Running TTS benchmark..."
adb shell am start -n com.runanywhere.demo/.MainActivity \
    --es action "benchmark_tts" \
    --es text "The quick brown fox jumps over the lazy dog."

# Wait and collect results
sleep 10

# Get timing from logs
echo ""
echo "=== Results ==="
adb logcat -d | grep -E "(Inference time|USING.*NPU|Provider)" | tail -10
```

### Expected Performance

| Scenario | Latency | Provider |
|----------|---------|----------|
| Qualcomm + QNN | 40-60ms | qnn |
| Qualcomm + NNAPI | 150-200ms | nnapi |
| Qualcomm + CPU | 400-500ms | cpu |
| Non-Qualcomm + NNAPI | 180-250ms | nnapi |

---

## Summary Checklist

- [ ] Build C++ backend with `build-android.sh`
- [ ] Download QNN libraries with `download-qnn-sdk.sh`
- [ ] Convert model to FP16 with `compile_model_for_qnn.py`
- [ ] Copy all .so files to app/src/main/jniLibs/arm64-v8a/
- [ ] Update build.gradle for ARM64-only
- [ ] Register FP16 model in app
- [ ] Test on physical Qualcomm device OR device farm
- [ ] Verify logs show "USING QUALCOMM QNN (HTP/NPU)"
- [ ] Benchmark shows < 100ms for TTS

---

## Quick Start Commands

```bash
# 1. Build everything
cd sdk/runanywhere-commons
./scripts/build-android.sh all arm64-v8a

# 2. Get QNN libs
./scripts/android/download-qnn-sdk.sh

# 3. Convert model (optional - FP16 already available)
cd tools/qnn
python compile_model_for_qnn.py model.onnx --convert-fp16

# 4. Test on device
adb install -r app-debug.apk
adb logcat | grep -E "(ONNX|QNN|NPU)"
```

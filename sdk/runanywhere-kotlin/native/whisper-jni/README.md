# Whisper JNI Native Library

This directory contains the native library implementation for whisper.cpp JNI bindings used by the RunAnywhere KMP SDK.

## Structure

```
native/whisper-jni/
├── build-native.sh          # Build script
├── CMakeLists.txt           # CMake configuration
├── README.md               # This file
├── whisper.cpp/            # Whisper.cpp submodule (auto-downloaded)
├── jni/                    # JNI headers
├── src/                    # C++ implementation
│   └── whisper_jni.cpp     # Main JNI wrapper
└── build/                  # Build directory (generated)
```

## Building

### Prerequisites

- CMake 3.18+
- C++17 compiler (GCC, Clang, or MSVC)
- Android NDK (for Android builds)
- JDK with JNI headers

### Build Commands

```bash
# Build for current platform (JVM)
./build-native.sh jvm

# Build for Android (requires Android NDK)
./build-native.sh android

# Build all platforms
./build-native.sh all

# Clean build
./build-native.sh clean
```

### Environment Variables

- `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT`: Path to Android NDK
- `JAVA_HOME`: Path to JDK (for JNI headers)

## Output

Built libraries are placed in:
- `../src/jvmAndroidMain/resources/native/`
  - `android/arm64-v8a/libwhisper-jni.so`
  - `linux/libwhisper-jni.so`
  - `macos/libwhisper-jni.dylib`
  - `windows/whisper-jni.dll`

## Usage

The native library is automatically loaded by the `WhisperJNI` Kotlin object when the SDK is used.

## Performance Notes

- Optimized for speech recognition at 16kHz sample rate
- Uses CPU-based inference (GPU support planned)
- Memory usage scales with model size (base: ~140MB, small: ~244MB, etc.)
- Real-time factor typically 0.1-0.3x (faster than real-time)

## Troubleshooting

### Library Loading Issues

1. Check that the correct architecture library is built
2. Verify JNI method signatures match
3. Ensure native library is in the correct resource path

### Runtime Errors

1. Check whisper model file exists and is readable
2. Verify audio format (16kHz, mono, float32 or int16)
3. Check memory availability (models require significant RAM)

### Build Issues

1. Ensure CMake and compilers are up to date
2. For Android: verify NDK path and version (r21+ recommended)
3. For JVM: check JAVA_HOME points to JDK (not JRE)

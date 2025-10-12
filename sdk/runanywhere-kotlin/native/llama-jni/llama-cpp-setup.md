# llama.cpp Submodule Setup

## Overview

The Android SDK uses [llama.cpp](https://github.com/ggerganov/llama.cpp) as a git submodule for
on-device LLM inference.

## Required Version

- **Repository**: https://github.com/ggerganov/llama.cpp
- **Commit**: `1faa13a1`
- **Tag**: `b6725`
- **Date**: January 2025

This version includes both legacy and current API names, ensuring compatibility with our JNI
bindings.

## Initial Setup

### 1. Initialize the Submodule

```bash
# From the project root directory
git submodule update --init --recursive sdk/runanywhere-kotlin/native/llama-jni/llama.cpp
```

### 2. Verify Correct Version

```bash
cd sdk/runanywhere-kotlin/native/llama-jni/llama.cpp
git describe --tags
# Should output: b6725

git log --oneline -1
# Should output: 1faa13a1 webui: updated the chat service to only include max_tokens...
```

## Building

The native libraries are built automatically by Gradle during the Android build process:

```bash
# Build the module
./gradlew :RunAnywhereAI:sdk:runanywhere-kotlin:modules:runanywhere-llm-llamacpp:build

# Or build the entire app
./gradlew :RunAnywhereAI:app:assembleDebug
```

## Troubleshooting

### Submodule Not Initialized

**Error**: `llama.cpp not found at .../native/llama-jni/llama.cpp`

**Solution**:

```bash
git submodule update --init --recursive sdk/runanywhere-kotlin/native/llama-jni/llama.cpp
```

### Wrong Version

If you see API compilation errors (undefined functions like `llama_model_load_from_file`), you may
be on the wrong commit.

**Solution**:

```bash
cd sdk/runanywhere-kotlin/native/llama-jni/llama.cpp
git fetch origin
git checkout b6725
cd ../../../..
git add sdk/runanywhere-kotlin/native/llama-jni/llama.cpp
```

### Clean Build

If you encounter build issues, perform a clean build:

```bash
./gradlew :RunAnywhereAI:sdk:runanywhere-kotlin:modules:runanywhere-llm-llamacpp:clean
./gradlew :RunAnywhereAI:sdk:runanywhere-kotlin:modules:runanywhere-llm-llamacpp:build
```

## API Compatibility

The `b6725` version includes:

- **Current API** (used by our code):
    - `llama_model_load_from_file()`
    - `llama_model_free()`
    - `llama_init_from_model()`
    - `llama_vocab_is_eog()`
    - `llama_memory_clear()` + `llama_get_memory()`

- **Legacy API** (deprecated but still available):
    - `llama_load_model_from_file()` (deprecated)
    - `llama_free_model()` (deprecated)
    - `llama_new_context_with_model()` (deprecated)

## Build Outputs

Native libraries are generated for the following architectures:

- `arm64-v8a` (7 optimized variants: baseline, fp16, dotprod, v8_4, i8mm, sve, i8mm-sve)

Libraries are located at:

```
sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/build/intermediates/cxx/Release/
```

## Updating llama.cpp

⚠️ **Warning**: Updating to a newer version may require updating the JNI bindings in
`src/llama-android.cpp` if the API has changed.

To update:

1. Check the target version's API compatibility
2. Update the submodule:
   ```bash
   cd sdk/runanywhere-kotlin/native/llama-jni/llama.cpp
   git fetch origin
   git checkout <new-tag>
   cd ../../../..
   git add sdk/runanywhere-kotlin/native/llama-jni/llama.cpp
   git commit -m "Update llama.cpp to <new-tag>"
   ```
3. Test thoroughly

## Team Onboarding

For new team members:

```bash
# 1. Clone the repository
git clone <repository-url>
cd sdks

# 2. Initialize all submodules
git submodule update --init --recursive

# 3. Verify llama.cpp version
cd sdk/runanywhere-kotlin/native/llama-jni/llama.cpp && git describe --tags
# Expected: b6725

# 4. Build the project
cd ../../../..
./gradlew :RunAnywhereAI:app:assembleDebug
```

## Notes

- The submodule path changed from `EXTERNAL/llama.cpp` to
  `sdk/runanywhere-kotlin/native/llama-jni/llama.cpp` to keep dependencies colocated with the module
- CMake configuration is in `sdk/runanywhere-kotlin/native/llama-jni/CMakeLists.txt`
- Build variants and optimizations are configured to match performance requirements

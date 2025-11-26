# C Bridge Architecture

This document explains why we have C header files and a `dummy.c` file in the Swift SDK, and how they relate to the C++ implementation in the core repository.

## Overview

The ONNXRuntime module uses a **C bridge layer** to allow Swift code to call C++ functions. This is necessary because **Swift cannot directly import C++ code**.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Swift Code (ONNXSTTService.swift)                            │
│                                                                  │
│    import CRunAnywhereONNX  // ← Imports the C bridge module   │
│                                                                  │
│    let recognizer = ra_sherpa_create_recognizer(...)           │
│    ra_sherpa_accept_waveform(stream, samples, count)           │
│                                                                  │
└────────────────────────┬────────────────────────────────────────┘
                         │ Swift needs C headers to know
                         │ what functions are available
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. C Bridge Headers (CRunAnywhereONNX target)                  │
│                                                                  │
│    Sources/CRunAnywhereONNX/                                   │
│    ├── include/                                                 │
│    │   ├── onnx_bridge.h          // C function declarations   │
│    │   ├── onnx_bridge_wrapper.h  // Wrapper header            │
│    │   ├── modality_types.h       // Shared types              │
│    │   ├── types.h                 // Additional types         │
│    │   └── module.modulemap        // Swift import config      │
│    └── dummy.c                      // Empty (SPM requirement)  │
│                                                                  │
│    ⚠️  These contain DECLARATIONS ONLY (no implementation)      │
│                                                                  │
└────────────────────────┬────────────────────────────────────────┘
                         │ At link time, Swift finds the
                         │ implementations in the XCFramework
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. XCFramework Binary (RunAnywhereONNX.xcframework)           │
│                                                                  │
│    Built from runanywhere-core, contains:                      │
│    ├── librunanywhere_onnx_combined.a  // Compiled code        │
│    └── Headers/                         // For documentation    │
│                                                                  │
│    ✅ This is where the ACTUAL IMPLEMENTATION lives!            │
│                                                                  │
└────────────────────────┬────────────────────────────────────────┘
                         │ Built from C++ source code
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. C++ Implementation (runanywhere-core)                       │
│                                                                  │
│    src/backends/onnx/bridge/ios/                               │
│    ├── sherpa_bridge.cpp     // ✅ ACTUAL IMPLEMENTATION        │
│    │    extern "C" {                                            │
│    │      ra_sherpa_recognizer_handle                          │
│    │      ra_sherpa_create_recognizer(...) {                   │
│    │        // Real C++ code here                              │
│    │      }                                                     │
│    │    }                                                       │
│    ├── onnx_bridge.cpp        // ONNX Runtime implementation   │
│    ├── onnx_bridge.h          // Header definitions            │
│    └── modality_types.h       // Type definitions              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Why Can't Swift Import C++ Directly?

### Problem: Language Incompatibility

Swift and C++ are fundamentally incompatible:

```cpp
// ❌ Swift cannot understand C++ features:
class SherpaRecognizer {  // C++ classes
public:
    template<typename T>  // C++ templates
    void process(T data);

    std::vector<float> samples;  // C++ STL
};
```

```swift
// ❌ This doesn't work:
import sherpa_bridge  // Can't import C++ directly
let recognizer = SherpaRecognizer()  // Error: undefined type
```

### Solution: C Bridge Layer

C is a common language that both Swift and C++ can understand:

**Step 1: C++ code exposes C-compatible functions**
```cpp
// In sherpa_bridge.cpp
extern "C" {  // Use C naming, not C++ name mangling
    ra_sherpa_recognizer_handle ra_sherpa_create_recognizer(...) {
        // C++ implementation inside
        return handle;
    }
}
```

**Step 2: C header declares the function**
```c
// In onnx_bridge.h
#ifdef __cplusplus
extern "C" {
#endif

ra_sherpa_recognizer_handle ra_sherpa_create_recognizer(...);

#ifdef __cplusplus
}
#endif
```

**Step 3: Swift imports and calls it**
```swift
// In ONNXSTTService.swift
import CRunAnywhereONNX
let handle = ra_sherpa_create_recognizer(...)  // ✅ Works!
```

## File Responsibilities

### 1. CRunAnywhereONNX Target (Swift SDK)

**Location**: `Modules/ONNXRuntime/Sources/CRunAnywhereONNX/`

| File | Purpose | Contains Implementation? |
|------|---------|--------------------------|
| `onnx_bridge.h` | Declares C functions for ONNX Runtime | ❌ No |
| `onnx_bridge_wrapper.h` | Main wrapper that includes other headers | ❌ No |
| `modality_types.h` | Shared type definitions (enums, structs) | ❌ No |
| `types.h` | Additional type definitions | ❌ No |
| `module.modulemap` | Tells Swift how to import as a module | N/A |
| `dummy.c` | Empty file (SPM requirement) | ❌ No |

**Why these files are needed:**

1. **Swift Compilation**: Swift compiler needs to see function declarations
2. **Type Definitions**: Swift needs to know about C types (structs, enums, typedefs)
3. **Module System**: `module.modulemap` packages everything as importable module
4. **SPM Requirement**: Swift Package Manager requires at least one source file (`.c` or `.m`)

### 2. C++ Implementation (Core Repository)

**Location**: `runanywhere-core/src/backends/onnx/bridge/ios/`

| File | Purpose | Contains Implementation? |
|------|---------|--------------------------|
| `sherpa_bridge.cpp` | Sherpa-ONNX C++ implementation | ✅ Yes |
| `onnx_bridge.cpp` | ONNX Runtime C++ implementation | ✅ Yes |
| `onnx_bridge.h` | Header declarations (matches Swift SDK) | ❌ No |
| `modality_types.h` | Type definitions (matches Swift SDK) | ❌ No |

**Why these files are needed:**

1. **Implementation**: The actual working C++ code
2. **Compilation**: Compiled into the XCFramework binary
3. **Runtime**: This code actually executes when Swift calls the functions

### 3. XCFramework Binary

**Location**: `Modules/ONNXRuntime/Sources/RunAnywhereONNX.xcframework/`

Contains:
- `librunanywhere_onnx_combined.a` - Compiled machine code from C++ files
- `Headers/` - Copy of headers for documentation (not used by Swift)

**Why this is needed:**

1. **Linking**: Connects Swift function calls to C++ implementations
2. **Binary Distribution**: Pre-compiled code ready to use
3. **Platform Support**: Separate binaries for device (arm64) and simulator (x86_64, arm64)

## The Flow: From Swift to C++

### Example: Creating a Sherpa Recognizer

**1. Swift calls the function:**
```swift
// ONNXSTTService.swift
let handle = ra_sherpa_create_recognizer(
    modelPath,
    configJSON
)
```

**2. Swift imports from CRunAnywhereONNX:**
```swift
// At top of file
import CRunAnywhereONNX
```

**3. module.modulemap tells Swift what to import:**
```
module CRunAnywhereONNX {
    header "onnx_bridge_wrapper.h"
    export *
}
```

**4. onnx_bridge_wrapper.h includes the declarations:**
```c
#include "onnx_bridge.h"
#include "modality_types.h"
```

**5. onnx_bridge.h declares the function:**
```c
extern "C" {
    ra_sherpa_recognizer_handle ra_sherpa_create_recognizer(
        const char* model_dir,
        const char* config_json
    );
}
```

**6. At link time, XCFramework provides the implementation:**
```
Swift app links with RunAnywhereONNX.xcframework
└── librunanywhere_onnx_combined.a
    └── Contains compiled sherpa_bridge.cpp code
```

**7. sherpa_bridge.cpp executes:**
```cpp
extern "C" {
    ra_sherpa_recognizer_handle ra_sherpa_create_recognizer(
        const char* model_dir,
        const char* config_json
    ) {
        // C++ code that actually runs
        SherpaOnnxOnlineRecognizerConfig config;
        // ... setup code ...
        const SherpaOnnxOnlineRecognizer* recognizer =
            SherpaOnnxCreateOnlineRecognizer(&config);
        return (void*)recognizer;
    }
}
```

## Why dummy.c Exists

Swift Package Manager has a requirement that **every target must have at least one source file** (`.c`, `.cpp`, `.m`, or `.mm` file).

Our `CRunAnywhereONNX` target only has:
- Headers (`.h` files)
- Module map

So we need `dummy.c` to satisfy SPM:

```c
// dummy.c - INTENTIONALLY EMPTY
// This file exists only to satisfy Swift Package Manager's requirement
// that every target must have at least one source file.
// The actual implementations are in the XCFramework binary.
```

**Alternative approaches we could use:**
1. ❌ Remove CRunAnywhereONNX target → Swift can't import the C functions
2. ❌ Put implementation in dummy.c → Duplicates code, defeats purpose of XCFramework
3. ✅ Keep dummy.c as empty placeholder → Clean, standard approach

## Header File Duplication

You may notice that header files exist in **two locations**:

```
Swift SDK:  CRunAnywhereONNX/include/onnx_bridge.h
Core Repo:  src/backends/onnx/bridge/ios/onnx_bridge.h
```

**Why are they duplicated?**

1. **Swift SDK needs them**: For Swift compilation
2. **Core repo needs them**: For C++ compilation

**Important**: These files must be **kept in sync**!

If you change a function signature in the C++ implementation, you must update both copies:

```cpp
// 1. Update in core repo
// runanywhere-core/src/backends/onnx/bridge/ios/onnx_bridge.h
void ra_sherpa_new_function(int param);

// 2. Update in Swift SDK (copy the header)
// runanywhere-swift/Modules/ONNXRuntime/Sources/CRunAnywhereONNX/include/onnx_bridge.h
void ra_sherpa_new_function(int param);

// 3. Rebuild XCFramework
cd runanywhere-core
./scripts/build-ios-onnx.sh

// 4. Copy XCFramework to Swift SDK
cp -r dist/RunAnywhereONNX.xcframework ../sdks/sdk/runanywhere-swift/Modules/ONNXRuntime/Sources/
```

## Package.swift Configuration

Here's how the C bridge is configured in Package.swift:

```swift
.target(
    name: "CRunAnywhereONNX",
    dependencies: [],
    path: "Sources/CRunAnywhereONNX",
    sources: ["dummy.c"],  // Required by SPM
    publicHeadersPath: "include",
    cSettings: [
        .headerSearchPath("include")
    ]
),

.target(
    name: "ONNXRuntime",
    dependencies: [
        "CRunAnywhereONNX",  // Import the C bridge
        .target(name: "RunAnywhere")
    ],
    path: "Sources/ONNXRuntime",
    linkerSettings: [
        // Link the XCFramework binary
        .linkedFramework("Foundation"),
        .linkedFramework("CoreML"),
        .linkedFramework("Accelerate"),
        .linkedLibrary("archive"),
        .linkedLibrary("bz2")
    ]
)
```

## Common Questions

### Q: Can we remove the C bridge and use Swift/C++ interop?

**A**: Not yet. Swift 5.9+ has experimental C++ interop, but it's:
- ⚠️ Still experimental and unstable
- ⚠️ Doesn't support all C++ features (templates, exceptions, etc.)
- ⚠️ Not recommended for production use
- ⚠️ Requires specific compiler flags and setup

The C bridge is the **standard, stable approach** for Swift ↔ C++ interop.

### Q: Why not compile C++ directly in Swift package?

**A**: We could, but:
- ❌ Would require users to have full build toolchain
- ❌ Slow compilation times (C++ compiles slower than Swift)
- ❌ Complex build configuration (CMake, dependencies, etc.)
- ✅ XCFramework provides pre-compiled binary (fast, simple)

### Q: Could we use Swift's @_cdecl instead?

**A**: `@_cdecl` is for exporting Swift functions to C, not importing C++ to Swift. It works in the opposite direction.

### Q: Do we need dummy.c or can we use header-only module?

**A**: SPM requires source files. Header-only modules are not supported (unlike CocoaPods or Carthage).

### Q: Why not use Objective-C++ as a bridge?

**A**: We could, but:
- ⚠️ Adds another language to the stack
- ⚠️ More complex than pure C bridge
- ⚠️ Objective-C++ is iOS/macOS specific
- ✅ Pure C bridge is simpler and cross-platform

## Troubleshooting

### Error: "Use of undeclared identifier 'ra_sherpa_create_recognizer'"

**Cause**: Swift can't find the C function declaration

**Solution**:
1. Check that `import CRunAnywhereONNX` is at top of Swift file
2. Verify headers exist in `Sources/CRunAnywhereONNX/include/`
3. Check `module.modulemap` is correctly configured
4. Clean build: `rm -rf .build && swift build`

### Error: "Undefined symbol: _ra_sherpa_create_recognizer"

**Cause**: Function declared in header but not implemented in XCFramework

**Solution**:
1. Rebuild XCFramework: `cd runanywhere-core && ./scripts/build-ios-onnx.sh`
2. Copy to Swift SDK: `cp -r dist/RunAnywhereONNX.xcframework ../sdks/.../Sources/`
3. Verify function is implemented in `sherpa_bridge.cpp`
4. Check `extern "C"` wrapper exists around function

### Error: "Module 'CRunAnywhereONNX' not found"

**Cause**: Swift package not configured correctly

**Solution**:
1. Check `Package.swift` has `CRunAnywhereONNX` target defined
2. Verify target has `publicHeadersPath: "include"` set
3. Check `module.modulemap` exists in include directory
4. Run `swift package clean && swift package resolve`

### Error: "Target requires at least one source file"

**Cause**: Missing `dummy.c` in CRunAnywhereONNX target

**Solution**:
1. Create `Sources/CRunAnywhereONNX/dummy.c` (can be empty)
2. Add to Package.swift: `sources: ["dummy.c"]`

## Related Documentation

- [Building XCFramework](../../../runanywhere-core/docs/building-xcframework-ios.md)
- [XCFramework Deployment](DEPLOYMENT.md)
- [Sherpa-ONNX Integration](../../../runanywhere-core/docs/sherpa-onnx-integration.md)

## Summary

The C bridge architecture is necessary because:

1. ✅ **Swift cannot import C++** - Language incompatibility
2. ✅ **C is the common ground** - Both Swift and C++ understand C
3. ✅ **Headers provide declarations** - Tell Swift what functions exist
4. ✅ **XCFramework provides implementations** - Compiled C++ code
5. ✅ **dummy.c satisfies SPM** - Package manager requirement
6. ✅ **Standard approach** - Used by many Swift/C++ projects

This architecture is clean, maintainable, and follows industry best practices for Swift/C++ interoperability.

# RunAnywhere React Native SDK - Nitrogen Migration Plan

## Migration Progress

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Setup Nitrogen Infrastructure | ✅ Complete |
| Phase 2 | Define Nitrogen Specs (*.nitro.ts) | ✅ Complete |
| Phase 3 | C++ HybridRunAnywhere Implementation | ✅ Complete |
| Phase 4 | Platform Utilities (Swift/Kotlin) | ✅ Complete |
| Phase 5 | iOS Build Integration (podspec) | ✅ Complete |
| Phase 6 | Android Build Integration (gradle/cmake) | ✅ Complete |
| Phase 7 | TypeScript Native Layer | ✅ Complete |
| Phase 8 | Test on iOS device | ⏳ Pending |
| Phase 9 | Test on Android device | ⏳ Pending |

## Executive Summary

Migrate from Codegen TurboModules to **Nitrogen** for unified C++ implementation across iOS and Android, following the Nitrogen HybridObject pattern for cross-platform native modules.

## Current State

### Problems with Current Implementation
1. **Android not working** - Complex JNI bridge, library loading issues, ONNX binary compatibility
2. **Dual maintenance** - Different bridge code for iOS (Obj-C++) and Android (JNI/Kotlin)
3. **Complex setup** - Manual JSI installation, library load order dependencies
4. **Type mismatches** - Codegen types don't perfectly match C++ implementations

### Current Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│  TypeScript (src/Public/RunAnywhere.ts)                         │
├─────────────────────────────────────────────────────────────────┤
│  Codegen Interface (NativeRunAnywhere.ts)                       │
├───────────────────────────┬─────────────────────────────────────┤
│  iOS                      │  Android                            │
│  RunAnywhere.mm           │  RunAnywhereModule.kt               │
│  RunAnywhereModule.cpp    │  react-native-runanywhere.cpp (JNI) │
│                           │  RunAnywhereModule.cpp              │
├───────────────────────────┴─────────────────────────────────────┤
│  runanywhere-core (C API)                                       │
└─────────────────────────────────────────────────────────────────┘
```

## Target State (Nitrogen)

### Architecture After Migration
```
┌─────────────────────────────────────────────────────────────────┐
│  TypeScript (src/Public/RunAnywhere.ts)                         │
├─────────────────────────────────────────────────────────────────┤
│  Native Layer (src/native/)                                     │
│  - NitroModules.ts → getRunAnywhere()                           │
├─────────────────────────────────────────────────────────────────┤
│  Nitrogen Spec (src/specs/RunAnywhere.nitro.ts)                 │
├─────────────────────────────────────────────────────────────────┤
│  nitrogen/generated/ (AUTO-GENERATED - iOS + Android bridges)   │
├─────────────────────────────────────────────────────────────────┤
│  cpp/HybridRunAnywhere.cpp (SINGLE C++ IMPLEMENTATION)          │
├─────────────────────────────────────────────────────────────────┤
│  Platform Utils (when needed):                                  │
│  - HybridRunAnywhereFileSystem.kt / .swift                      │
│  - HybridRunAnywhereAudioDecoder.kt / .swift                    │
├─────────────────────────────────────────────────────────────────┤
│  runanywhere-core (C API via xcframework/jniLibs)               │
└─────────────────────────────────────────────────────────────────┘
```

## Migration Phases

### Phase 1: Setup Nitrogen Infrastructure (Day 1)

**Tasks:**
1. Add nitrogen dependencies to package.json
2. Create `nitro.json` configuration file
3. Create initial spec file structure

**Files to Create:**
```
nitro.json
src/specs/
  ├── RunAnywhere.nitro.ts      # Main interface
  ├── RunAnywhereFileSystem.nitro.ts
  ├── RunAnywhereDeviceInfo.nitro.ts
  └── RunAnywhereAudioDecoder.nitro.ts
```

**nitro.json:**
```json
{
  "cxxNamespace": ["runanywhere"],
  "ios": {
    "iosModuleName": "RunAnywhere"
  },
  "android": {
    "androidNamespace": ["runanywhere"],
    "androidCxxLibName": "runanywhere"
  },
  "autolinking": {
    "RunAnywhere": {
      "cpp": "HybridRunAnywhere"
    },
    "RunAnywhereFileSystem": {
      "kotlin": "HybridRunAnywhereFileSystem",
      "swift": "HybridRunAnywhereFileSystem"
    },
    "RunAnywhereDeviceInfo": {
      "kotlin": "HybridRunAnywhereDeviceInfo",
      "swift": "HybridRunAnywhereDeviceInfo"
    },
    "RunAnywhereAudioDecoder": {
      "kotlin": "HybridRunAnywhereAudioDecoder",
      "swift": "HybridRunAnywhereAudioDecoder"
    }
  },
  "ignorePaths": ["node_modules", "lib"]
}
```

### Phase 2: Define Nitrogen Specs (Day 1-2)

Create TypeScript interface definitions that Nitrogen will use to generate bridges.

**src/specs/RunAnywhere.nitro.ts:**
```typescript
import type { HybridObject } from 'react-native-nitro-modules';

export interface RunAnywhere extends HybridObject<{ ios: 'c++'; android: 'c++' }> {
  // Backend Lifecycle
  createBackend(name: string): Promise<boolean>;
  initialize(configJson: string): Promise<boolean>;
  destroy(): Promise<void>;
  isInitialized(): Promise<boolean>;
  getBackendInfo(): Promise<string>;
  
  // Text Generation (LLM)
  loadTextModel(path: string, configJson?: string): Promise<boolean>;
  isTextModelLoaded(): Promise<boolean>;
  unloadTextModel(): Promise<boolean>;
  generate(
    prompt: string,
    optionsJson?: string,
    callback?: (token: string, isComplete: boolean) => void
  ): Promise<string>;
  cancelGeneration(): Promise<boolean>;
  
  // Speech-to-Text (STT)
  loadSTTModel(path: string, modelType: string, configJson?: string): Promise<boolean>;
  isSTTModelLoaded(): Promise<boolean>;
  unloadSTTModel(): Promise<boolean>;
  transcribe(audioBase64: string, sampleRate: number, language?: string): Promise<string>;
  
  // Text-to-Speech (TTS)
  loadTTSModel(path: string, modelType: string, configJson?: string): Promise<boolean>;
  isTTSModelLoaded(): Promise<boolean>;
  unloadTTSModel(): Promise<boolean>;
  synthesize(text: string, voiceId?: string, speedRate: number, pitchShift: number): Promise<string>;
  
  // Utility
  getLastError(): Promise<string>;
  extractArchive(archivePath: string, destPath: string): Promise<boolean>;
}
```

### Phase 3: Create HybridRunAnywhere C++ Implementation (Day 2-3)

**Files to Create:**
```
cpp/
  ├── HybridRunAnywhere.hpp
  ├── HybridRunAnywhere.cpp
  └── runanywhere_ffi.h  (wrapper around ra_core.h)
```

**Key Implementation Pattern:**
```cpp
#pragma once
#include "HybridRunAnywhereSpec.hpp"
#include "RunAnywhereCore/ra_core.h"
#include <mutex>

namespace margelo::nitro::runanywhere {

class HybridRunAnywhere : public HybridRunAnywhereSpec {
public:
  HybridRunAnywhere();
  ~HybridRunAnywhere();

  std::shared_ptr<Promise<bool>> createBackend(const std::string& name) override;
  std::shared_ptr<Promise<bool>> initialize(const std::string& configJson) override;
  // ... other methods

private:
  ra_backend_handle backend_ = nullptr;
  ra_backend_handle onnxBackend_ = nullptr;
  std::mutex modelMutex_;
};

} // namespace
```

### Phase 4: Platform-Specific Utilities (Day 3-4)

**iOS Swift Files (ios/):**
- `HybridRunAnywhereFileSystem.swift` - File operations using FileManager
- `HybridRunAnywhereAudioDecoder.swift` - Audio decoding using AVFoundation

**Android Kotlin Files (android/src/main/java/com/runanywhere/):**
- `HybridRunAnywhereFileSystem.kt` - File operations using java.io
- `HybridRunAnywhereAudioDecoder.kt` - Audio decoding using Android MediaCodec

### Phase 5: Build System Updates (Day 4-5)

**Update package.json:**
```json
{
  "devDependencies": {
    "nitrogen": "^0.31.3",
    "react-native-nitro-modules": "^0.31.3"
  },
  "peerDependencies": {
    "react-native-nitro-modules": "^0.31.3"
  },
  "scripts": {
    "nitrogen": "nitrogen",
    "prepare": "nitrogen && bob build"
  }
}
```

**Update Podspec:**
```ruby
# Add to runanywhere-react-native.podspec
load 'nitrogen/generated/ios/RunAnywhere+autolinking.rb'
add_nitrogen_files(s)
```

**Update Android build.gradle:**
```gradle
// Add nitrogen autolinking
apply from: file("nitrogen/generated/android/runanywhere+autolinking.gradle")
```

**Update Android CMakeLists.txt:**
```cmake
# Include nitrogen-generated files
include(${CMAKE_SOURCE_DIR}/nitrogen/generated/android/runanywhere+autolinking.cmake)
```

### Phase 6: JNI Setup for Android (Day 5)

**android/src/main/cpp/cpp-adapter.cpp:**
```cpp
#include <jni.h>
#include "runanywhereOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return margelo::nitro::runanywhere::initialize(vm);
}
```

### Phase 7: Update TypeScript Native Layer (Day 5-6)

**src/native/RunAnywhere.ts:**
```typescript
import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhere } from '../specs/RunAnywhere.nitro';

export const RunAnywhereNative = NitroModules.createHybridObject<RunAnywhere>('RunAnywhere');
```

### Phase 8: Update Public API (Day 6)

Keep the existing public API (`src/Public/RunAnywhere.ts`) largely unchanged, just update internal calls to use the Nitrogen module.

### Phase 9: Sample App Updates (Day 6-7)

1. Update sample app's package.json to include `react-native-nitro-modules`
2. Test on iOS simulator/device
3. Test on Android emulator/device
4. Align features with Swift sample app

### Phase 10: Testing & Polish (Day 7+)

1. Test all features: LLM, STT, TTS on both platforms
2. Fix any edge cases
3. Update documentation
4. Remove old codegen-related files

## Files to Delete After Migration

```
# Old Codegen files (after verification)
ios/RunAnywhere.mm
ios/RunAnywhere.h
ios/RunAnywhereTurboModuleProvider.mm
android/src/main/cpp/react-native-runanywhere.cpp
android/src/main/cpp/android_bridge_stub.cpp
```

## Risk Mitigation

1. **Keep old implementation** in a branch until new one is verified
2. **Incremental migration** - start with basic methods, expand gradually
3. **Feature flags** - allow switching between old/new bridge if needed

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| nitrogen | ^0.31.3 | Code generation |
| react-native-nitro-modules | ^0.31.3 | Runtime support |

## Success Criteria

1. ✅ Same TypeScript API as before (no breaking changes)
2. ✅ iOS works with all features (LLM, STT, TTS)
3. ✅ Android works with all features (LLM, STT, TTS)
4. ✅ Single C++ implementation for core logic
5. ✅ Clean build without manual library loading
6. ✅ Sample app works on both platforms
7. ✅ Aligned with Swift SDK patterns

## Timeline Estimate

- **Phase 1-2**: 2 days (Setup + Specs)
- **Phase 3**: 2 days (C++ Implementation)
- **Phase 4**: 2 days (Platform Utils)
- **Phase 5-6**: 2 days (Build System)
- **Phase 7-8**: 2 days (TypeScript Updates)
- **Phase 9-10**: 2 days (Testing + Polish)

**Total: ~12 days** for complete migration


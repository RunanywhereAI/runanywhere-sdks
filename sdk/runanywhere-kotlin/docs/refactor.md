# RunAnywhere SDK - Complete Common Code Migration Plan

## Target Architecture

**Final Goal:**

- **Common:** 92-95% of all code
- **Platform:** 5-8% (ONLY platform API calls)
- **Zero duplication, zero backwards compatibility**

## Migration Progress Status

### COMPLETED Migrations

#### Files Successfully Deleted (16 files)
```
androidMain/data/models/TelemetryModels.kt
jvmMain/data/models/TelemetryModels.kt
androidMain/data/models/ModelInfoModels.kt
jvmMain/data/models/ModelInfoModels.kt
androidMain/utils/TimeUtils.kt
jvmMain/utils/TimeUtils.kt
androidMain/services/AndroidMD5.kt
jvmMain/services/JvmMD5.kt
androidMain/network/AndroidHttpClient.kt
jvmMain/network/JvmHttpClient.kt
androidMain/jni/NativeLoader.kt
androidMain/network/APIClient.kt
androidMain/foundation/ServiceContainer.kt
jvmMain/foundation/ServiceContainer.kt
androidMain/models/ModelStorage.kt
jvmMain/models/ModelStorage.kt
```

#### Files Moved to jvmAndroidMain (7 files)

```
jvmAndroidMain/data/models/TelemetryModels.kt (generateUUID)
jvmAndroidMain/data/models/ModelInfoModels.kt (fileExists)
jvmAndroidMain/utils/TimeUtils.kt (getCurrentTimeMillis)
jvmAndroidMain/services/MD5Service.kt (calculateMD5)
jvmAndroidMain/network/OkHttpEngine.kt (shared HTTP client - 160 lines)
jvmAndroidMain/jni/NativeLoader.kt (native library loader - 67 lines)
jvmAndroidMain/network/FileWriter.kt (writeFileBytes)
```

#### Files Moved to Common (3 major components)

```
commonMain/foundation/ServiceContainer.kt (119 lines)
commonMain/network/APIClient.kt (345 lines)
commonMain/foundation/PlatformContext.kt (expect class)
```

#### Platform-Specific Implementations Created

```
androidMain/foundation/PlatformContext.kt (Android context)
jvmMain/foundation/PlatformContext.kt (JVM working directory)
nativeMain/foundation/PlatformContext.kt (Native placeholder)
androidMain/network/AndroidNetworkChecker.kt (51 lines)
jvmMain/network/JvmNetworkChecker.kt (24 lines)
nativeMain/network/FileWriter.kt (Native placeholder)
```

### Files Still to Process (22 files remaining)

#### Android-Specific Files to Review

```
androidMain/
├── data/
│   ├── models/DeviceInfoModels.kt (Platform-specific, keep)
│   └── repositories/
│       ├── ConfigurationRepositoryImpl.kt
│       ├── DeviceInfoRepositoryImpl.kt
│       └── TelemetryRepositoryImpl.kt
├── public/
│   ├── RunAnywhere.kt
│   └── RunAnywhereAndroid.kt
├── utils/
│   └── BuildConfig.kt
├── models/
│   ├── PlatformModels.kt (Platform-specific, keep)
│   └── WhisperModel.kt
└── files/
    └── FileManager.kt (605 lines → move most to common)
```

#### JVM-Specific Files to Review

```
jvmMain/
├── data/
│   ├── models/DeviceInfoModels.kt (Platform-specific, keep)
│   └── repositories/ (empty?)
├── utils/
│   └── BuildConfig.kt
├── models/
│   └── PlatformModels.kt (Platform-specific, keep)
├── plugin/
├── files/
│   └── FileManager.kt (82 lines)
└── components/
    └── vad/JvmVADServiceProvider.kt
```

## Current Directory Structure

```
src/
├── commonMain/           # ~85% of code (increasing)
│   └── kotlin/com/runanywhere/sdk/
│       ├── core/
│       │   └── ServiceContainer.kt
│       ├── network/
│       │   ├── APIClient.kt
│       │   ├── NetworkService.kt (existing)
│       │   └── HttpClient.kt (existing)
│       ├── foundation/
│       │   ├── ServiceContainer.kt
│       │   └── PlatformContext.kt
│       └── models/
│           └── ModelStorage.kt (existing)
│
├── jvmAndroidMain/       # ~5% shared JVM/Android
│   └── kotlin/com/runanywhere/sdk/
│       ├── network/
│       │   ├── OkHttpEngine.kt (160 lines)
│       │   └── FileWriter.kt
│       ├── jni/
│       │   └── NativeLoader.kt (67 lines)
│       ├── services/
│       │   └── MD5Service.kt
│       ├── utils/
│       │   └── TimeUtils.kt
│       └── data/models/
│           ├── TelemetryModels.kt
│           └── ModelInfoModels.kt
│
├── androidMain/          # ~5% Android-specific
│   └── kotlin/com/runanywhere/sdk/
│       ├── foundation/
│       │   └── PlatformContext.kt
│       ├── network/
│       │   └── AndroidNetworkChecker.kt
│       └── (remaining platform-specific code)
│
└── jvmMain/             # ~5% JVM-specific
    └── kotlin/com/runanywhere/sdk/
        ├── foundation/
        │   └── PlatformContext.kt
        ├── network/
        │   └── JvmNetworkChecker.kt
        └── (remaining platform-specific code)
```

## Next Steps - Implementation Checklist

### Phase 1: FileManager Migration

- Move FileManager business logic to common (600+ lines)
- Keep only platform I/O operations in platform modules
- Create FileSystem abstraction in common

### Phase 2: Repository Cleanup

- Review and potentially delete empty repositories
- Move any actual implementations to common
- Create common repository interfaces

### Phase 3: BuildConfig Consolidation

- Move BuildConfig to jvmAndroidMain or common
- Delete duplicate BuildConfig files

### Phase 4: Public API Cleanup

- Review RunAnywhere.kt files
- Consolidate public API surface
- Create single entry point in common

### Phase 5: Component Migration

- Move VAD base logic to common
- Move STT base logic to common
- Keep only platform-specific implementations

## Success Metrics

### Code Distribution After Migration
```
Current Status:
Common:        ~85% (increasing)
JvmAndroid:    ~5% (stable)
Android:       ~5% (decreasing)
JVM:           ~5% (decreasing)

Target:
Common:        92-95%
JvmAndroid:    3-5%
Android:       1-2%
JVM:           1-2%
```

### File Count
```
Before: 200+ files
Current: ~180 files
Target: 65 files (67% reduction)

Files deleted so far: 16
Files to review: 22
```

### Duplication
```
Before: 2,100+ lines duplicated
Current: ~1,500 lines duplicated
Target: 0 lines duplicated

Lines eliminated: ~600
```

## Key Migration Rules

1. **If it's business logic → Common**
2. **If it's an algorithm → Common**
3. **If it's data manipulation → Common**
4. **If it's a platform API call → Platform**
5. **If JVM and Android share it → jvmAndroidMain**
6. **If it's configuration → Common with expect/actual**

## Build Configuration Updates

### Gradle Configuration

- Created jvmAndroidMain source set
- Configured shared dependencies
- Set up proper source set hierarchy

```kotlin
val jvmAndroidMain by creating {
    dependsOn(commonMain.get())
    dependencies {
        implementation(libs.okhttp)
        implementation(libs.okhttp.logging)
        implementation(libs.gson)
        implementation(libs.commons.io)
        implementation(libs.whisper.jni)
    }
}
```

## Validation Steps

### Completed

- jvmAndroidMain source set created and configured
- Shared implementations moved successfully
- 16 duplicate files deleted
- ServiceContainer unified in common
- APIClient unified with platform abstractions
- Network layer consolidated with OkHttpEngine

### In Progress

- Full compilation verification
- Test suite execution
- Documentation update

### TODO

- Complete FileManager migration
- Repository cleanup
- Final duplication elimination
- Performance benchmarking

## Timeline

**Completed:** Day 1-2 tasks
**In Progress:** Day 3 tasks
**Remaining:** 2-3 days of work

## Notes

- Migration is proceeding smoothly with minimal issues
- jvmAndroidMain source set is working as expected
- Compilation issues are being resolved incrementally
- Code quality improving with each refactor

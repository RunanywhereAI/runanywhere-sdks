# Kotlin/Android Architecture - RunAnywhere SDK

> **Document Purpose:** This document defines how the C++ `runanywhere-commons` layer integrates with the Android/Kotlin SDK, mirroring the Swift SDK architecture.

## Architecture Overview

The Kotlin SDK follows the same architectural principles as the Swift SDK:
- **C++ Commons Layer**: Contains all business logic, shared across platforms
- **Kotlin Thin Wrappers**: Minimal JNI bridges that call C++ functions
- **Platform Adapters**: Kotlin implementations of platform-specific functionality

```
┌────────────────────────────────────────────────────────────────────────┐
│                         Kotlin SDK Layer                               │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                 RunAnywhere (Core SDK - Kotlin)                  │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │ ServiceRegistry │  │ ManagedLifecycle│  │ EventPublisher  │  │  │
│  │  │ (Kotlin-only)   │  │ (Kotlin wrapper)│  │ (Kotlin event   │  │  │
│  │  │                 │  │                 │  │  routing)       │  │  │
│  │  └────┬────────────┘  └────┬────────────┘  └────┬────────────┘  │  │
│  │       │                     │                     │               │  │
│  │       ▼                     ▼                     ▼               │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  │                       JNI Bridge Layer                          │  │
│  │  └────┬────────────────────────────────────────────────────────────┘  │
│  └───────┼───────────────────────────────────────────────────────────────┘  │
│          │                                                                  │
│          ▼                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                         C++ Commons Layer                              │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │  │
│  │  │ Core Services   │  │ Capabilities    │  │ Infrastructure  │      │  │
│  │  │ (rac_log,       │  │ (LLM, STT, TTS, │  │ (Model Mgmt,    │      │  │
│  │  │  rac_error,     │  │  VAD, Lifecycle)│  │  Download Svc,  │      │  │
│  │  │  rac_types)     │  │                 │  │  Event Gen)     │      │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                       Platform Adapter (C Interface)            │  │  │
│  │  │  (File System, Logging, Secure Storage, Clock, HTTP, Archive)  │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

## JNI Bridge Pattern

### Library Structure

```
runanywhere-android/
├── src/main/
│   ├── kotlin/
│   │   └── com/runanywhere/sdk/
│   │       ├── core/
│   │       │   ├── ServiceRegistry.kt      # Kotlin-only service discovery
│   │       │   ├── ManagedLifecycle.kt     # Wrapper around C++ lifecycle
│   │       │   └── EventPublisher.kt       # Kotlin event routing
│   │       ├── features/
│   │       │   ├── llm/
│   │       │   │   ├── LLMCapability.kt    # Thin wrapper
│   │       │   │   └── LLMService.kt       # JNI interface
│   │       │   ├── stt/
│   │       │   │   ├── STTCapability.kt
│   │       │   │   └── STTService.kt
│   │       │   ├── tts/
│   │       │   │   ├── TTSCapability.kt
│   │       │   │   └── TTSService.kt
│   │       │   └── vad/
│   │       │       ├── VADCapability.kt
│   │       │       └── VADService.kt
│   │       └── platform/
│   │           ├── AndroidFileSystem.kt    # Platform adapter impl
│   │           ├── AndroidHttpClient.kt
│   │           └── AndroidSecureStorage.kt
│   └── cpp/
│       ├── jni_bridge.cpp                  # JNI function implementations
│       ├── jni_llm.cpp
│       ├── jni_stt.cpp
│       ├── jni_tts.cpp
│       ├── jni_vad.cpp
│       └── jni_platform.cpp                # Platform adapter JNI
└── libs/
    ├── arm64-v8a/
    │   └── librac_commons.so
    └── armeabi-v7a/
        └── librac_commons.so
```

### JNI Bridge Example

```cpp
// jni_llm.cpp
#include <jni.h>
#include "rac/features/llm/rac_llm_component.h"

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_features_llm_LLMService_nativeCreate(
    JNIEnv* env,
    jobject thiz
) {
    rac_handle_t handle = nullptr;
    rac_result_t result = rac_llm_component_create(&handle);
    if (result != RAC_SUCCESS) {
        // Throw Java exception
        jclass exClass = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exClass, rac_error_message(result));
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_features_llm_LLMService_nativeGenerate(
    JNIEnv* env,
    jobject thiz,
    jlong handle,
    jstring prompt,
    jobject options
) {
    const char* promptStr = env->GetStringUTFChars(prompt, nullptr);

    // Convert Java options to C struct
    rac_llm_options_t cOptions;
    // ... conversion code ...

    rac_llm_result_t result;
    rac_result_t status = rac_llm_component_generate(
        reinterpret_cast<rac_handle_t>(handle),
        promptStr,
        &cOptions,
        &result
    );

    env->ReleaseStringUTFChars(prompt, promptStr);

    if (status != RAC_SUCCESS) {
        jclass exClass = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exClass, rac_error_message(status));
        return nullptr;
    }

    jstring output = env->NewStringUTF(result.text);
    rac_free(result.text);
    return output;
}

} // extern "C"
```

### Kotlin Service Interface

```kotlin
// LLMService.kt
package com.runanywhere.sdk.features.llm

/**
 * LLM Service - Thin JNI wrapper around C++ rac_llm_component
 *
 * IMPORTANT: All business logic is in C++. This is just the JNI bridge.
 */
class LLMService internal constructor() {
    private var nativeHandle: Long = 0

    init {
        System.loadLibrary("rac_commons")
        nativeHandle = nativeCreate()
    }

    suspend fun generate(prompt: String, options: LLMOptions): String {
        return withContext(Dispatchers.IO) {
            nativeGenerate(nativeHandle, prompt, options)
        }
    }

    fun destroy() {
        if (nativeHandle != 0L) {
            nativeDestroy(nativeHandle)
            nativeHandle = 0
        }
    }

    // Native methods - implemented in C++ via JNI
    private external fun nativeCreate(): Long
    private external fun nativeDestroy(handle: Long)
    private external fun nativeGenerate(handle: Long, prompt: String, options: LLMOptions): String
    private external fun nativeGenerateStream(
        handle: Long,
        prompt: String,
        options: LLMOptions,
        callback: (String, Boolean) -> Unit
    )
}
```

## Platform Adapter Implementation

### Platform Adapter Interface (C)

The C++ layer defines a platform adapter interface that Kotlin implements via JNI:

```c
// rac_platform_adapter.h (already defined in commons)
typedef struct rac_platform_adapter {
    // File system
    int (*file_exists)(const char* path, void* user_data);
    int (*read_file)(const char* path, char** out_data, size_t* out_size, void* user_data);
    int (*write_file)(const char* path, const char* data, size_t size, void* user_data);

    // HTTP
    int (*http_download)(const char* url, const char* path, rac_download_callback callback, void* user_data);

    // Secure storage
    int (*secure_get)(const char* key, char** out_value, void* user_data);
    int (*secure_set)(const char* key, const char* value, void* user_data);

    // Logging
    void (*log)(int level, const char* category, const char* message, void* user_data);

    void* user_data;
} rac_platform_adapter_t;
```

### Kotlin Platform Adapter

```kotlin
// AndroidPlatformAdapter.kt
package com.runanywhere.sdk.platform

class AndroidPlatformAdapter(private val context: Context) {

    init {
        // Register the adapter with C++
        nativeRegisterAdapter(this)
    }

    // Called from C++ via JNI
    @JvmName("fileExists")
    fun fileExists(path: String): Boolean {
        return File(path).exists()
    }

    @JvmName("readFile")
    fun readFile(path: String): ByteArray? {
        return try {
            File(path).readBytes()
        } catch (e: Exception) {
            null
        }
    }

    @JvmName("writeFile")
    fun writeFile(path: String, data: ByteArray): Boolean {
        return try {
            File(path).writeBytes(data)
            true
        } catch (e: Exception) {
            false
        }
    }

    @JvmName("httpDownload")
    fun httpDownload(url: String, path: String, callback: Long): Boolean {
        // Use OkHttp or Ktor for HTTP downloads
        // Call native callback with progress updates
        return performDownload(url, path, callback)
    }

    @JvmName("secureGet")
    fun secureGet(key: String): String? {
        val sharedPrefs = EncryptedSharedPreferences.create(
            context,
            "runanywhere_secure",
            MasterKey.Builder(context).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
        return sharedPrefs.getString(key, null)
    }

    @JvmName("log")
    fun log(level: Int, category: String, message: String) {
        when (level) {
            0 -> Log.v(category, message)  // TRACE
            1 -> Log.d(category, message)  // DEBUG
            2 -> Log.i(category, message)  // INFO
            3 -> Log.w(category, message)  // WARNING
            4 -> Log.e(category, message)  // ERROR
        }
    }

    private external fun nativeRegisterAdapter(adapter: AndroidPlatformAdapter)
}
```

## Type Mappings

### C++ to Kotlin Type Conversions

| C++ Type | Kotlin Type | Notes |
|----------|-------------|-------|
| `rac_handle_t` | `Long` | Native pointer as Long |
| `rac_result_t` | Throws `Exception` | Errors become exceptions |
| `rac_bool_t` | `Boolean` | Direct mapping |
| `const char*` | `String` | UTF-8 encoding |
| `float` | `Float` | Direct mapping |
| `double` | `Double` | Direct mapping |
| `int32_t` | `Int` | Direct mapping |
| `int64_t` | `Long` | Direct mapping |
| `rac_llm_options_t` | `LLMOptions` | Data class |
| `rac_stt_options_t` | `STTOptions` | Data class |

### Data Class Mapping

```kotlin
// LLMOptions.kt - mirrors rac_llm_options_t
data class LLMOptions(
    val maxTokens: Int = 512,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,
    val stopSequences: List<String> = emptyList(),
    val systemPrompt: String? = null,
    val streamingEnabled: Boolean = true
)

// STTOptions.kt - mirrors rac_stt_options_t
data class STTOptions(
    val language: String? = null,
    val sampleRate: Int = 16000,
    val enablePunctuation: Boolean = true,
    val enableTimestamps: Boolean = false,
    val detectLanguage: Boolean = false
)
```

## Build Configuration

### CMakeLists.txt for Android

```cmake
cmake_minimum_required(VERSION 3.18)

project(rac_android)

# Find the pre-built runanywhere-commons
set(RAC_COMMONS_DIR ${CMAKE_SOURCE_DIR}/../runanywhere-commons)

# Add the JNI bridge sources
add_library(rac_android SHARED
    jni_bridge.cpp
    jni_llm.cpp
    jni_stt.cpp
    jni_tts.cpp
    jni_vad.cpp
    jni_platform.cpp
)

# Link with runanywhere-commons
target_include_directories(rac_android PRIVATE
    ${RAC_COMMONS_DIR}/include
)

target_link_libraries(rac_android
    ${RAC_COMMONS_DIR}/libs/${ANDROID_ABI}/librac_commons.a
    log
)
```

### Gradle Configuration

```kotlin
// build.gradle.kts
android {
    ndkVersion = "25.1.8937393"

    defaultConfig {
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

dependencies {
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.squareup.okhttp3:okhttp:4.11.0")
}
```

## Event System

### Event Publishing from C++ to Kotlin

```cpp
// jni_events.cpp
void publish_event_to_kotlin(JNIEnv* env, rac_event_t* event) {
    jclass eventClass = env->FindClass("com/runanywhere/sdk/events/SDKEvent");
    jmethodID constructor = env->GetMethodID(eventClass, "<init>",
        "(Ljava/lang/String;Ljava/lang/String;IJLjava/lang/String;)V");

    jstring id = env->NewStringUTF(event->id);
    jstring type = env->NewStringUTF(event->type);
    jstring props = env->NewStringUTF(event->properties_json);

    jobject javaEvent = env->NewObject(eventClass, constructor,
        id, type, event->category, event->timestamp_ms, props);

    // Call Kotlin EventPublisher.publish(event)
    jclass publisherClass = env->FindClass("com/runanywhere/sdk/core/EventPublisher");
    jmethodID publishMethod = env->GetStaticMethodID(publisherClass, "publish",
        "(Lcom/runanywhere/sdk/events/SDKEvent;)V");

    env->CallStaticVoidMethod(publisherClass, publishMethod, javaEvent);

    env->DeleteLocalRef(id);
    env->DeleteLocalRef(type);
    env->DeleteLocalRef(props);
    env->DeleteLocalRef(javaEvent);
}
```

```kotlin
// EventPublisher.kt
object EventPublisher {
    private val subscribers = mutableMapOf<EventCategory, MutableList<(SDKEvent) -> Unit>>()

    @JvmStatic
    fun publish(event: SDKEvent) {
        subscribers[event.category]?.forEach { callback ->
            callback(event)
        }
    }

    fun subscribe(category: EventCategory, callback: (SDKEvent) -> Unit) {
        subscribers.getOrPut(category) { mutableListOf() }.add(callback)
    }
}
```

## Summary: Kotlin vs Swift Patterns

| Aspect | Swift | Kotlin |
|--------|-------|--------|
| **FFI Mechanism** | C interop via `import CRACommons` | JNI via `external fun` |
| **Memory Management** | ARC + manual `rac_free()` | JVM GC + native pointers |
| **Async Pattern** | `async/await` actors | Coroutines + `Dispatchers.IO` |
| **Type Conversion** | Swift structs to C structs | Data classes to JNI objects |
| **Platform Adapter** | Swift implementations | Kotlin implementations via JNI callbacks |
| **Error Handling** | `throws SDKError` | `throws Exception` |
| **Service Discovery** | Swift protocols + generics | Kotlin interfaces + generics |

## Key Principles

1. **C++ is the Source of Truth**: All business logic resides in the C++ layer
2. **Thin Wrappers**: Kotlin code only handles JNI bridging and type conversion
3. **No Duplicated Logic**: Never implement business logic in Kotlin
4. **Consistent APIs**: Kotlin API mirrors Swift API for developer familiarity
5. **Platform Adapters**: Platform-specific code only in adapter implementations

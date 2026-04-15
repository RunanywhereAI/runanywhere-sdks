/**
 * @file src/jni/jni_shared.h
 * @brief Shared state for the runanywhere-commons JNI bridge.
 *
 * INTERNAL ONLY. Not installed, not visible to SDK consumers.
 *
 * The JNI bridge in `runanywhere_commons_jni.cpp` has grown to ~4,800
 * lines that mix five distinct concerns:
 *   - JVM / adapter / method-ID registration (Init)
 *   - Platform adapter callback implementations (PlatformAdapter)
 *   - Per-feature JNIEXPORT entry points (LLM, STT, TTS, VAD, VLM)
 *   - Model registry / download orchestration bridges
 *   - Telemetry and device callback bridges
 *
 * Phase 7 of the C++ cleanup is a per-feature file split. This header
 * is the scaffolding that all future .cpp shards will share: it
 * declares the global state (g_jvm, g_platform_adapter, method-ID
 * caches) as `extern`, and pulls in jni_scope.h + the RAC public
 * headers that every JNI TU needs. The plan is:
 *
 *   runanywhere_commons_jni.cpp    (entry point, JNI_OnLoad, rac_init wrapper)
 *   jni_shared.h / .cpp            (this file + the global-state definitions)
 *   jni_platform_adapter.cpp       (~250 LOC, 9 callbacks)
 *   jni_llm.cpp                    (LLM JNIEXPORTs)
 *   jni_stt.cpp                    (STT JNIEXPORTs)
 *   jni_tts.cpp                    (TTS JNIEXPORTs)
 *   jni_vad_wakeword.cpp           (VAD + wakeword JNIEXPORTs)
 *   jni_vlm.cpp                    (VLM JNIEXPORTs)
 *   jni_model_registry.cpp         (model assignment / LoRA / download)
 *   jni_device.cpp                 (device registration)
 *   jni_telemetry.cpp              (telemetry callbacks + HTTP)
 *   jni_benchmark.cpp              (benchmark JNIEXPORTs)
 *
 * This commit ships the shared header; the actual file split across
 * source files is incremental and can land in subsequent commits so
 * each review is manageable. Every shard will `#include "jni_shared.h"`
 * as its first internal include.
 */

#ifndef RAC_JNI_SHARED_H
#define RAC_JNI_SHARED_H

#include <jni.h>

#include <mutex>
#include <string>

#include "jni_scope.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"

// --- Logging shortcuts (already used throughout runanywhere_commons_jni.cpp) ---
#ifdef __ANDROID__
#include <android/log.h>
#define RAC_JNI_LOG_TAG "RACCommonsJNI"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO,  RAC_JNI_LOG_TAG, __VA_ARGS__)
#define LOGd(...) __android_log_print(ANDROID_LOG_DEBUG, RAC_JNI_LOG_TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN,  RAC_JNI_LOG_TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, RAC_JNI_LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGi(...) do { std::fprintf(stdout, "[INFO]  " __VA_ARGS__); std::fputc('\n', stdout); } while (0)
#define LOGd(...) do { std::fprintf(stdout, "[DEBUG] " __VA_ARGS__); std::fputc('\n', stdout); } while (0)
#define LOGw(...) do { std::fprintf(stderr, "[WARN]  " __VA_ARGS__); std::fputc('\n', stderr); } while (0)
#define LOGe(...) do { std::fprintf(stderr, "[ERROR] " __VA_ARGS__); std::fputc('\n', stderr); } while (0)
#endif

// --- Global state set by JNI_OnLoad + racSetPlatformAdapter ----------------
//
// These are DEFINED in runanywhere_commons_jni.cpp (file-scope statics
// today). Shards produced by the phase-7 split will redeclare them as
// `extern` via this header once the definitions move to jni_shared.cpp.
//
// Today this header serves purely as documentation and as a staging point
// for the split; runanywhere_commons_jni.cpp continues to own these as
// `static` until the split lands. We include the forward declarations
// below commented-out so reviewers can see what will become extern.

// extern JavaVM*    g_jvm;
// extern jobject    g_platform_adapter;   // global ref, DeleteGlobalRef in cleanup
// extern std::mutex g_adapter_mutex;
// extern jmethodID  g_method_log;
// extern jmethodID  g_method_file_exists;
// extern jmethodID  g_method_file_read;
// extern jmethodID  g_method_file_write;
// extern jmethodID  g_method_file_delete;
// extern jmethodID  g_method_secure_get;
// extern jmethodID  g_method_secure_set;
// extern jmethodID  g_method_secure_delete;
// extern jmethodID  g_method_now_ms;

// --- Helpers shared by every TU --------------------------------------------

/** Get a JNIEnv for the current thread, attaching if needed. Implementation
 *  stays in runanywhere_commons_jni.cpp for now. */
JNIEnv* getJNIEnv();

/** Copy a jstring to a std::string. Empty string on null input. */
std::string getCString(JNIEnv* env, jstring str);

#endif  // RAC_JNI_SHARED_H

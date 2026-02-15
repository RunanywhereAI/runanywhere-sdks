#include <jni.h>
#include <string>
#include <android/log.h>
#include "runanywherecoreOnLoad.hpp"
#include "PlatformDownloadBridge.h"

#define LOG_TAG "ArchiveJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Store JavaVM globally for JNI calls from background threads
// NOT static - needs to be accessible from InitBridge.cpp for secure storage
JavaVM* g_javaVM = nullptr;

// Cache class and method references at JNI_OnLoad time
// This is necessary because FindClass from native threads uses the system class loader
static jclass g_archiveUtilityClass = nullptr;
static jmethodID g_extractMethod = nullptr;

// PlatformAdapterBridge class and methods for secure storage (used by InitBridge.cpp)
// NOT static - needs to be accessible from InitBridge.cpp
jclass g_platformAdapterBridgeClass = nullptr;
jclass g_httpResponseClass = nullptr;  // Inner class for httpPostSync response
jmethodID g_secureSetMethod = nullptr;
jmethodID g_secureGetMethod = nullptr;
jmethodID g_secureDeleteMethod = nullptr;
jmethodID g_secureExistsMethod = nullptr;
jmethodID g_getPersistentDeviceUUIDMethod = nullptr;
jmethodID g_httpPostSyncMethod = nullptr;
jmethodID g_getDeviceModelMethod = nullptr;
jmethodID g_getOSVersionMethod = nullptr;
jmethodID g_getChipNameMethod = nullptr;
jmethodID g_getTotalMemoryMethod = nullptr;
jmethodID g_getAvailableMemoryMethod = nullptr;
jmethodID g_getCoreCountMethod = nullptr;
jmethodID g_getArchitectureMethod = nullptr;
jmethodID g_getGPUFamilyMethod = nullptr;
jmethodID g_isTabletMethod = nullptr;
jmethodID g_httpDownloadMethod = nullptr;
jmethodID g_httpDownloadCancelMethod = nullptr;
// HttpResponse field IDs
jfieldID g_httpResponse_successField = nullptr;
jfieldID g_httpResponse_statusCodeField = nullptr;
jfieldID g_httpResponse_responseBodyField = nullptr;
jfieldID g_httpResponse_errorMessageField = nullptr;

// Forward declaration
extern "C" bool ArchiveUtility_extractAndroid(const char* archivePath, const char* destinationPath);

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  g_javaVM = vm;

  // Get JNIEnv to cache class references
  JNIEnv* env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK && env != nullptr) {
    // Find and cache the ArchiveUtility class
    jclass localClass = env->FindClass("com/margelo/nitro/runanywhere/ArchiveUtility");
    if (localClass != nullptr) {
      // Create a global reference so it persists across JNI calls
      g_archiveUtilityClass = (jclass)env->NewGlobalRef(localClass);
      env->DeleteLocalRef(localClass);

      // Cache the extract method
      g_extractMethod = env->GetStaticMethodID(
        g_archiveUtilityClass,
        "extract",
        "(Ljava/lang/String;Ljava/lang/String;)Z"
      );

      if (g_extractMethod != nullptr) {
        LOGI("ArchiveUtility class and method cached successfully");
      } else {
        LOGE("Failed to find extract method in ArchiveUtility");
        if (env->ExceptionCheck()) {
          env->ExceptionClear();
        }
      }
    } else {
      LOGE("Failed to find ArchiveUtility class at JNI_OnLoad");
      if (env->ExceptionCheck()) {
        env->ExceptionClear();
      }
    }

    // Find and cache the PlatformAdapterBridge class (for secure storage)
    jclass platformClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
    if (platformClass != nullptr) {
      g_platformAdapterBridgeClass = (jclass)env->NewGlobalRef(platformClass);
      env->DeleteLocalRef(platformClass);

      // Cache all methods we need
      g_secureSetMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "secureSet", "(Ljava/lang/String;Ljava/lang/String;)Z");
      g_secureGetMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "secureGet", "(Ljava/lang/String;)Ljava/lang/String;");
      g_secureDeleteMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "secureDelete", "(Ljava/lang/String;)Z");
      g_secureExistsMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "secureExists", "(Ljava/lang/String;)Z");
      g_getPersistentDeviceUUIDMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getPersistentDeviceUUID", "()Ljava/lang/String;");
      g_httpPostSyncMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "httpPostSync", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Lcom/margelo/nitro/runanywhere/PlatformAdapterBridge$HttpResponse;");
      g_getDeviceModelMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getDeviceModel", "()Ljava/lang/String;");
      g_getOSVersionMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getOSVersion", "()Ljava/lang/String;");
      g_getChipNameMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getChipName", "()Ljava/lang/String;");
      g_getTotalMemoryMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getTotalMemory", "()J");
      g_getAvailableMemoryMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getAvailableMemory", "()J");
      g_getCoreCountMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getCoreCount", "()I");
      g_getArchitectureMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getArchitecture", "()Ljava/lang/String;");
      g_getGPUFamilyMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getGPUFamily", "()Ljava/lang/String;");
      g_isTabletMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "isTablet", "()Z");
      g_httpDownloadMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "httpDownload", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I");
      g_httpDownloadCancelMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "httpDownloadCancel", "(Ljava/lang/String;)Z");

      if (g_secureSetMethod && g_secureGetMethod && g_getPersistentDeviceUUIDMethod &&
          g_getDeviceModelMethod && g_getOSVersionMethod && g_getChipNameMethod &&
          g_getTotalMemoryMethod && g_getAvailableMemoryMethod && g_getCoreCountMethod &&
          g_getArchitectureMethod && g_getGPUFamilyMethod && g_isTabletMethod &&
          g_httpDownloadMethod && g_httpDownloadCancelMethod) {
        LOGI("PlatformAdapterBridge class and methods cached successfully");
      } else {
        LOGE("Failed to cache some PlatformAdapterBridge methods");
        if (env->ExceptionCheck()) {
          env->ExceptionClear();
        }
      }

      // Cache HttpResponse inner class and its fields
      jclass responseClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge$HttpResponse");
      if (responseClass != nullptr) {
        g_httpResponseClass = (jclass)env->NewGlobalRef(responseClass);
        env->DeleteLocalRef(responseClass);

        g_httpResponse_successField = env->GetFieldID(g_httpResponseClass, "success", "Z");
        g_httpResponse_statusCodeField = env->GetFieldID(g_httpResponseClass, "statusCode", "I");
        g_httpResponse_responseBodyField = env->GetFieldID(g_httpResponseClass, "responseBody", "Ljava/lang/String;");
        g_httpResponse_errorMessageField = env->GetFieldID(g_httpResponseClass, "errorMessage", "Ljava/lang/String;");

        if (g_httpResponse_successField && g_httpResponse_statusCodeField) {
          LOGI("HttpResponse class and fields cached successfully");
        } else {
          LOGE("Failed to cache HttpResponse fields");
        }
      } else {
        LOGE("Failed to find HttpResponse inner class at JNI_OnLoad");
        if (env->ExceptionCheck()) {
          env->ExceptionClear();
        }
      }
    } else {
      LOGE("Failed to find PlatformAdapterBridge class at JNI_OnLoad");
      if (env->ExceptionCheck()) {
        env->ExceptionClear();
      }
    }
  }

  return margelo::nitro::runanywhere::initialize(vm);
}

/**
 * Get JNIEnv for the current thread
 * Attaches thread if not already attached
 */
static JNIEnv* getJNIEnv() {
    JNIEnv* env = nullptr;
    if (g_javaVM == nullptr) {
        LOGE("JavaVM is null");
        return nullptr;
    }

    int status = g_javaVM->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (g_javaVM->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            LOGE("Failed to attach thread");
            return nullptr;
        }
        LOGI("Attached thread to JVM");
    } else if (status != JNI_OK) {
        LOGE("Failed to get JNIEnv, status=%d", status);
        return nullptr;
    }
    return env;
}

/**
 * Log Java exception details before clearing
 */
static void logAndClearException(JNIEnv* env, const char* context) {
    if (env->ExceptionCheck()) {
        jthrowable exception = env->ExceptionOccurred();
        env->ExceptionClear();

        // Get exception message
        jclass throwableClass = env->FindClass("java/lang/Throwable");
        if (throwableClass) {
            jmethodID getMessageMethod = env->GetMethodID(throwableClass, "getMessage", "()Ljava/lang/String;");
            if (getMessageMethod) {
                jstring messageStr = (jstring)env->CallObjectMethod(exception, getMessageMethod);
                if (messageStr) {
                    const char* message = env->GetStringUTFChars(messageStr, nullptr);
                    LOGE("[%s] Java exception: %s", context, message);
                    env->ReleaseStringUTFChars(messageStr, message);
                    env->DeleteLocalRef(messageStr);
                } else {
                    LOGE("[%s] Java exception (no message)", context);
                }
            }
            env->DeleteLocalRef(throwableClass);
        }

        // Also print stack trace to logcat
        jclass exceptionClass = env->GetObjectClass(exception);
        if (exceptionClass) {
            jmethodID printStackTraceMethod = env->GetMethodID(exceptionClass, "printStackTrace", "()V");
            if (printStackTraceMethod) {
                env->CallVoidMethod(exception, printStackTraceMethod);
                env->ExceptionClear(); // Clear any exception from printStackTrace
            }
            env->DeleteLocalRef(exceptionClass);
        }

        env->DeleteLocalRef(exception);
    }
}

/**
 * Call Kotlin ArchiveUtility.extract() via JNI
 * Uses cached class and method references from JNI_OnLoad
 */
extern "C" bool ArchiveUtility_extractAndroid(const char* archivePath, const char* destinationPath) {
    LOGI("Starting extraction: %s -> %s", archivePath, destinationPath);

    // Check if class and method were cached
    if (g_archiveUtilityClass == nullptr || g_extractMethod == nullptr) {
        LOGE("ArchiveUtility class or method not cached. JNI_OnLoad may have failed.");
        return false;
    }

    JNIEnv* env = getJNIEnv();
    if (env == nullptr) {
        LOGE("Failed to get JNIEnv");
        return false;
    }

    LOGI("Using cached ArchiveUtility class and method");

    // Create Java strings
    jstring jArchivePath = env->NewStringUTF(archivePath);
    jstring jDestinationPath = env->NewStringUTF(destinationPath);

    if (jArchivePath == nullptr || jDestinationPath == nullptr) {
        LOGE("Failed to create Java strings");
        if (jArchivePath) env->DeleteLocalRef(jArchivePath);
        if (jDestinationPath) env->DeleteLocalRef(jDestinationPath);
        return false;
    }

    // Call the method using cached references
    LOGI("Calling ArchiveUtility.extract()...");
    jboolean result = env->CallStaticBooleanMethod(
        g_archiveUtilityClass,
        g_extractMethod,
        jArchivePath,
        jDestinationPath
    );

    // Check for exceptions
    if (env->ExceptionCheck()) {
        LOGE("Exception during extraction");
        logAndClearException(env, "extract");
        result = JNI_FALSE;
    } else {
        LOGI("Extraction returned: %s", result ? "true" : "false");
    }

    // Cleanup local references
    env->DeleteLocalRef(jArchivePath);
    env->DeleteLocalRef(jDestinationPath);

    return result == JNI_TRUE;
}

// =============================================================================
// HTTP Download Callback Reporting (from Kotlin to C++)
// =============================================================================

static std::string jstringToStdString(JNIEnv* env, jstring value) {
    if (value == nullptr) {
        return "";
    }
    const char* chars = env->GetStringUTFChars(value, nullptr);
    std::string result = chars ? chars : "";
    if (chars) {
        env->ReleaseStringUTFChars(value, chars);
    }
    return result;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_margelo_nitro_runanywhere_PlatformAdapterBridge_nativeHttpDownloadReportProgress(
    JNIEnv* env, jclass clazz, jstring taskId, jlong downloadedBytes, jlong totalBytes) {
    (void)clazz;
    std::string task = jstringToStdString(env, taskId);
    return RunAnywhereHttpDownloadReportProgress(task.c_str(),
                                                 static_cast<int64_t>(downloadedBytes),
                                                 static_cast<int64_t>(totalBytes));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_margelo_nitro_runanywhere_PlatformAdapterBridge_nativeHttpDownloadReportComplete(
    JNIEnv* env, jclass clazz, jstring taskId, jint result, jstring downloadedPath) {
    (void)clazz;
    std::string task = jstringToStdString(env, taskId);
    if (downloadedPath == nullptr) {
        return RunAnywhereHttpDownloadReportComplete(task.c_str(),
                                                     static_cast<int>(result),
                                                     nullptr);
    }
    std::string path = jstringToStdString(env, downloadedPath);
    return RunAnywhereHttpDownloadReportComplete(task.c_str(),
                                                 static_cast<int>(result),
                                                 path.c_str());
}

#include <jni.h>
#include <string>
#include <android/log.h>
#include <fbjni/fbjni.h>
#include "runanywherecoreOnLoad.hpp"
#include "PlatformDownloadBridge.h"

#define LOG_TAG "RunAnywhereJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Store JavaVM globally for JNI calls from background threads
// NOT static - needs to be accessible from InitBridge.cpp for secure storage
JavaVM* g_javaVM = nullptr;

// PlatformAdapterBridge class and methods for secure storage (used by InitBridge.cpp)
// NOT static - needs to be accessible from InitBridge.cpp
jclass g_platformAdapterBridgeClass = nullptr;
jmethodID g_secureSetMethod = nullptr;
jmethodID g_secureGetMethod = nullptr;
jmethodID g_secureDeleteMethod = nullptr;
jmethodID g_getModelBaseDirectoryMethod = nullptr;
jmethodID g_getDeviceModelMethod = nullptr;
jmethodID g_getOSVersionMethod = nullptr;
jmethodID g_getChipNameMethod = nullptr;
jmethodID g_getTotalMemoryMethod = nullptr;
jmethodID g_getAvailableMemoryMethod = nullptr;
jmethodID g_getCoreCountMethod = nullptr;
jmethodID g_getArchitectureMethod = nullptr;
jmethodID g_getGPUFamilyMethod = nullptr;
jmethodID g_isTabletMethod = nullptr;
jmethodID g_getAppIdentifierMethod = nullptr;
jmethodID g_getAppNameMethod = nullptr;
jmethodID g_getAppVersionMethod = nullptr;
jmethodID g_getAppBuildMethod = nullptr;
jmethodID g_getLocaleIdentifierMethod = nullptr;
jmethodID g_getTimezoneIdentifierMethod = nullptr;
jmethodID g_httpDownloadMethod = nullptr;
jmethodID g_httpDownloadCancelMethod = nullptr;
// Directory enumeration slots: cached so InitBridge.cpp can populate
// rac_platform_adapter_t::file_list_directory
// and rac_platform_adapter_t::is_non_empty_directory.
jmethodID g_fileListDirectoryMethod = nullptr;
jmethodID g_isNonEmptyDirectoryMethod = nullptr;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  g_javaVM = vm;

  // Get JNIEnv to cache class references
  JNIEnv* env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK && env != nullptr) {
    // Find and cache the PlatformAdapterBridge class (for secure storage)
    jclass platformClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
    if (platformClass != nullptr) {
      g_platformAdapterBridgeClass = (jclass)env->NewGlobalRef(platformClass);
      env->DeleteLocalRef(platformClass);

      // Cache all methods we need
      g_secureSetMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "secureSet", "(Ljava/lang/String;Ljava/lang/String;)Z");
      g_secureGetMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "secureGet", "(Ljava/lang/String;)Ljava/lang/String;");
      g_secureDeleteMethod =
          env->GetStaticMethodID(g_platformAdapterBridgeClass, "secureDelete",
                                 "(Ljava/lang/String;)Z");
      g_getModelBaseDirectoryMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getModelBaseDirectory", "()Ljava/lang/String;");
      g_getDeviceModelMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getDeviceModel", "()Ljava/lang/String;");
      g_getOSVersionMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getOSVersion", "()Ljava/lang/String;");
      g_getChipNameMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getChipName", "()Ljava/lang/String;");
      g_getTotalMemoryMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getTotalMemory", "()J");
      g_getAvailableMemoryMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getAvailableMemory", "()J");
      g_getCoreCountMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getCoreCount", "()I");
      g_getArchitectureMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getArchitecture", "()Ljava/lang/String;");
      g_getGPUFamilyMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getGPUFamily", "()Ljava/lang/String;");
      g_isTabletMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "isTablet", "()Z");
      g_getAppIdentifierMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getAppIdentifier", "()Ljava/lang/String;");
      g_getAppNameMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getAppName", "()Ljava/lang/String;");
      g_getAppVersionMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getAppVersion", "()Ljava/lang/String;");
      g_getAppBuildMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getAppBuild", "()Ljava/lang/String;");
      g_getLocaleIdentifierMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getLocaleIdentifier", "()Ljava/lang/String;");
      g_getTimezoneIdentifierMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "getTimezoneIdentifier", "()Ljava/lang/String;");
      g_httpDownloadMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "httpDownload", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I");
      g_httpDownloadCancelMethod = env->GetStaticMethodID(g_platformAdapterBridgeClass, "httpDownloadCancel", "(Ljava/lang/String;)Z");
      g_fileListDirectoryMethod = env->GetStaticMethodID(
          g_platformAdapterBridgeClass,
          "fileListDirectory",
          "(Ljava/lang/String;)[Lcom/margelo/nitro/runanywhere/PlatformAdapterBridge$RacDirectoryEntry;");
      g_isNonEmptyDirectoryMethod = env->GetStaticMethodID(
          g_platformAdapterBridgeClass, "isNonEmptyDirectory", "(Ljava/lang/String;)Z");

      if (g_secureSetMethod && g_secureGetMethod && g_secureDeleteMethod &&
          g_getModelBaseDirectoryMethod && g_fileListDirectoryMethod &&
          g_isNonEmptyDirectoryMethod && g_getDeviceModelMethod &&
          g_getOSVersionMethod && g_getChipNameMethod &&
          g_getTotalMemoryMethod && g_getAvailableMemoryMethod &&
          g_getCoreCountMethod && g_getArchitectureMethod &&
          g_getGPUFamilyMethod && g_isTabletMethod &&
          g_getAppIdentifierMethod && g_getAppNameMethod &&
          g_getAppVersionMethod && g_getAppBuildMethod &&
          g_getLocaleIdentifierMethod && g_getTimezoneIdentifierMethod &&
          g_httpDownloadMethod && g_httpDownloadCancelMethod) {
        LOGI("PlatformAdapterBridge class and methods cached successfully");
      } else {
        LOGE("Failed to cache some PlatformAdapterBridge methods");
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

  return facebook::jni::initialize(vm, []() {
    margelo::nitro::runanywhere::registerAllNatives();
  });
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

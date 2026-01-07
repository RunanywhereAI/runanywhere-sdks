#include <jni.h>
#include <string>
#include <android/log.h>
#include "runanywherecoreOnLoad.hpp"

#define LOG_TAG "ArchiveJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Store JavaVM globally for JNI calls from background threads
static JavaVM* g_javaVM = nullptr;

// Cache class and method references at JNI_OnLoad time
// This is necessary because FindClass from native threads uses the system class loader
static jclass g_archiveUtilityClass = nullptr;
static jmethodID g_extractMethod = nullptr;

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

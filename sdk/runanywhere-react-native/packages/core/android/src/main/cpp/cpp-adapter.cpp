#include <jni.h>
#include <string>
#include "runanywherecoreOnLoad.hpp"

// Store JavaVM globally for JNI calls from background threads
static JavaVM* g_javaVM = nullptr;

// Forward declaration
extern "C" bool ArchiveUtility_extractAndroid(const char* archivePath, const char* destinationPath);

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  g_javaVM = vm;
  return margelo::nitro::runanywhere::initialize(vm);
}

/**
 * Get JNIEnv for the current thread
 * Attaches thread if not already attached
 */
static JNIEnv* getJNIEnv() {
    JNIEnv* env = nullptr;
    if (g_javaVM == nullptr) {
        return nullptr;
    }

    int status = g_javaVM->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (g_javaVM->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            return nullptr;
        }
    } else if (status != JNI_OK) {
        return nullptr;
    }
    return env;
}

/**
 * Call Kotlin ArchiveUtility.extract() via JNI
 */
extern "C" bool ArchiveUtility_extractAndroid(const char* archivePath, const char* destinationPath) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr) {
        return false;
    }

    // Find the ArchiveUtility class
    jclass archiveUtilityClass = env->FindClass("com/margelo/nitro/runanywhere/ArchiveUtility");
    if (archiveUtilityClass == nullptr) {
        env->ExceptionClear();
        return false;
    }

    // Get the static extract method
    jmethodID extractMethod = env->GetStaticMethodID(
        archiveUtilityClass,
        "extract",
        "(Ljava/lang/String;Ljava/lang/String;)Z"
    );
    if (extractMethod == nullptr) {
        env->ExceptionClear();
        env->DeleteLocalRef(archiveUtilityClass);
        return false;
    }

    // Create Java strings
    jstring jArchivePath = env->NewStringUTF(archivePath);
    jstring jDestinationPath = env->NewStringUTF(destinationPath);

    // Call the method
    jboolean result = env->CallStaticBooleanMethod(
        archiveUtilityClass,
        extractMethod,
        jArchivePath,
        jDestinationPath
    );

    // Check for exceptions
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        result = JNI_FALSE;
    }

    // Cleanup
    env->DeleteLocalRef(jArchivePath);
    env->DeleteLocalRef(jDestinationPath);
    env->DeleteLocalRef(archiveUtilityClass);

    return result == JNI_TRUE;
}

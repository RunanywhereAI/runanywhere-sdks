/**
 * react-native-runanywhere.cpp
 *
 * JNI entry point for Android - registers the C++ TurboModule with React Native.
 * This uses the modern approach where Java/Kotlin calls a native install method
 * with the JSI runtime pointer.
 */

#include <jni.h>
#include <jsi/jsi.h>
#include "RunAnywhereModule.h"

using namespace facebook::jsi;

// Global reference for callbacks
static JavaVM* g_jvm = nullptr;

/**
 * JNI_OnLoad - called when the native library is loaded.
 * Just stores the JavaVM reference for later use.
 */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

/**
 * Native install function - called from Kotlin/Java with the JSI runtime pointer.
 * This installs the RunAnywhere module as a global object in the JS runtime.
 */
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_reactnative_RunAnywhereModule_nativeInstall(
    JNIEnv *env,
    jobject thiz,
    jlong jsiPtr) {

    auto runtime = reinterpret_cast<Runtime*>(jsiPtr);
    if (!runtime) {
        return;
    }

    Runtime &rt = *runtime;

    // Create the RunAnywhere module as a HostObject
    auto runAnywhereModule = std::make_shared<facebook::react::RunAnywhereModule>(nullptr);
    auto moduleHostObject = Object::createFromHostObject(rt, runAnywhereModule);

    // Install it as a global property accessible from JavaScript
    rt.global().setProperty(
        rt,
        "RunAnywhereNative",
        std::move(moduleHostObject)
    );
}

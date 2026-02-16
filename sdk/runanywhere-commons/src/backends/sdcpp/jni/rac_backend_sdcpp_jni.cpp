/**
 * @file rac_backend_sdcpp_jni.cpp
 * @brief JNI bridge for the sd.cpp diffusion backend.
 *
 * Provides a single JNI entry point for registering the sd.cpp backend
 * with the RAC service registry from Kotlin/Android.
 *
 * Mirrors the pattern in rac_backend_llamacpp_jni.cpp.
 */

#include <jni.h>

#include "rac/backends/rac_diffusion_sdcpp.h"
#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "Backend.SDCPP.JNI";

extern "C" {

/**
 * Register the sd.cpp diffusion backend.
 * Called from Kotlin: SdcppBridge.nativeRegister()
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_diffusion_sdcpp_SdcppBridge_nativeRegister(JNIEnv* /*env*/,
                                                                     jclass /*clazz*/) {
    RAC_LOG_INFO(LOG_CAT, "JNI: Registering sd.cpp diffusion backend");
    return static_cast<jint>(rac_backend_sdcpp_register());
}

}  // extern "C"

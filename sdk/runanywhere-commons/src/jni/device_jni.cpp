/**
 * JNI Bridge for Device Capabilities (GPU Detection)
 * 
 * Exposes Vulkan GPU detection to Kotlin/Java layer
 */

#include <jni.h>
#include "rac/infrastructure/device/vulkan_detector.h"
#include "rac/core/rac_logger.h"

extern "C" {

/**
 * Detect Vulkan GPU and return GPUInfo object
 * 
 * Java signature:
 * com.runanywhere.sdk.platform.DeviceCapabilities.detectVulkanGPU() -> GPUInfo
 */
JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_platform_DeviceCapabilities_detectVulkanGPU(
    JNIEnv* env, jclass /* clazz */) {
    
    RAC_LOG_INFO("DeviceJNI", "Detecting Vulkan GPU from JNI...");
    
    // Detect GPU using C++ layer
    auto info = runanywhere::VulkanDetector::detect();
    
    // Find GPUInfo class
    jclass gpu_info_class = env->FindClass("com/runanywhere/sdk/platform/GPUInfo");
    if (gpu_info_class == nullptr) {
        RAC_LOG_ERROR("DeviceJNI", "Failed to find GPUInfo class");
        return nullptr;
    }
    
    // Find constructor: GPUInfo(boolean, String, String, String, long, boolean)
    jmethodID constructor = env->GetMethodID(
        gpu_info_class, 
        "<init>", 
        "(ZLjava/lang/String;Ljava/lang/String;Ljava/lang/String;JZ)V"
    );
    
    if (constructor == nullptr) {
        RAC_LOG_ERROR("DeviceJNI", "Failed to find GPUInfo constructor");
        return nullptr;
    }
    
    // Convert C++ strings to Java strings
    jstring device_name = env->NewStringUTF(info.device_name.c_str());
    jstring driver_version = env->NewStringUTF(info.driver_version.c_str());
    jstring api_version = env->NewStringUTF(
        runanywhere::VulkanDetector::get_version_string(info.api_version).c_str()
    );
    
    // Create GPUInfo object
    jobject gpu_info = env->NewObject(
        gpu_info_class,
        constructor,
        (jboolean)info.is_available,
        device_name,
        driver_version,
        api_version,
        (jlong)info.max_memory_mb,
        (jboolean)info.supports_compute
    );
    
    // Clean up local references
    env->DeleteLocalRef(device_name);
    env->DeleteLocalRef(driver_version);
    env->DeleteLocalRef(api_version);
    env->DeleteLocalRef(gpu_info_class);
    
    RAC_LOG_INFO("DeviceJNI", "GPU detection complete: available=%d, device=%s", 
                 info.is_available, info.device_name.c_str());
    
    return gpu_info;
}

/**
 * Quick check if Vulkan is supported
 * 
 * Java signature:
 * com.runanywhere.sdk.platform.DeviceCapabilities.isVulkanSupported() -> boolean
 */
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_platform_DeviceCapabilities_isVulkanSupported(
    JNIEnv* env, jclass /* clazz */) {
    
    bool supported = runanywhere::VulkanDetector::is_vulkan_supported();
    RAC_LOG_INFO("DeviceJNI", "Vulkan supported: %s", supported ? "YES" : "NO");
    return (jboolean)supported;
}

/**
 * List all available Vulkan devices
 * 
 * Java signature:
 * com.runanywhere.sdk.platform.DeviceCapabilities.listVulkanDevices() -> List<GPUInfo>
 */
JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_platform_DeviceCapabilities_listVulkanDevices(
    JNIEnv* env, jclass /* clazz */) {
    
    RAC_LOG_INFO("DeviceJNI", "Listing all Vulkan devices...");
    
    auto devices = runanywhere::VulkanDetector::list_devices();
    
    // Find ArrayList class
    jclass array_list_class = env->FindClass("java/util/ArrayList");
    if (array_list_class == nullptr) {
        RAC_LOG_ERROR("DeviceJNI", "Failed to find ArrayList class");
        return nullptr;
    }
    
    jmethodID array_list_constructor = env->GetMethodID(array_list_class, "<init>", "()V");
    jmethodID array_list_add = env->GetMethodID(array_list_class, "add", "(Ljava/lang/Object;)Z");
    
    // Create ArrayList
    jobject device_list = env->NewObject(array_list_class, array_list_constructor);
    
    // Find GPUInfo class
    jclass gpu_info_class = env->FindClass("com/runanywhere/sdk/platform/GPUInfo");
    jmethodID gpu_info_constructor = env->GetMethodID(
        gpu_info_class, 
        "<init>", 
        "(ZLjava/lang/String;Ljava/lang/String;Ljava/lang/String;JZ)V"
    );
    
    // Add each device to list
    for (const auto& info : devices) {
        jstring device_name = env->NewStringUTF(info.device_name.c_str());
        jstring driver_version = env->NewStringUTF(info.driver_version.c_str());
        jstring api_version = env->NewStringUTF(
            runanywhere::VulkanDetector::get_version_string(info.api_version).c_str()
        );
        
        jobject gpu_info = env->NewObject(
            gpu_info_class,
            gpu_info_constructor,
            (jboolean)info.is_available,
            device_name,
            driver_version,
            api_version,
            (jlong)info.max_memory_mb,
            (jboolean)info.supports_compute
        );
        
        env->CallBooleanMethod(device_list, array_list_add, gpu_info);
        
        env->DeleteLocalRef(device_name);
        env->DeleteLocalRef(driver_version);
        env->DeleteLocalRef(api_version);
        env->DeleteLocalRef(gpu_info);
    }
    
    env->DeleteLocalRef(array_list_class);
    env->DeleteLocalRef(gpu_info_class);
    
    RAC_LOG_INFO("DeviceJNI", "Found %zu Vulkan device(s)", devices.size());
    
    return device_list;
}

}  // extern "C"

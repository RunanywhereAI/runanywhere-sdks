#include "cpu_features.h"
#include <fstream>
#include <sstream>
#include <algorithm>
#include <android/log.h>

#define LOG_TAG "CPUFeatures"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace cpu_features {

static std::string read_cpuinfo() {
    std::ifstream file("/proc/cpuinfo");
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

static bool has_feature(const std::string& feature_name) {
    std::string cpuinfo = read_cpuinfo();
    return cpuinfo.find(feature_name) != std::string::npos;
}

bool has_fp16() {
    return has_feature("fphp") || has_feature("asimdhp");
}

bool has_dotprod() {
    return has_feature("asimddp");
}

bool has_i8mm() {
    return has_feature("i8mm");
}

bool has_sve() {
    return has_feature("sve");
}

std::string get_cpu_info() {
    std::string cpuinfo = read_cpuinfo();

    // Extract relevant lines
    std::stringstream ss(cpuinfo);
    std::string line;
    std::stringstream result;

    while (std::getline(ss, line)) {
        if (line.find("CPU implementer") != std::string::npos ||
            line.find("CPU architecture") != std::string::npos ||
            line.find("CPU variant") != std::string::npos ||
            line.find("CPU part") != std::string::npos ||
            line.find("Features") != std::string::npos) {
            result << line << "\n";
        }
    }

    return result.str();
}

std::string detect_best_variant() {
    bool fp16 = has_fp16();
    bool dotprod = has_dotprod();
    bool i8mm = has_i8mm();
    bool sve = has_sve();

    LOGI("CPU Features detected:");
    LOGI("  FP16: %s", fp16 ? "yes" : "no");
    LOGI("  DotProd: %s", dotprod ? "yes" : "no");
    LOGI("  I8MM: %s", i8mm ? "yes" : "no");
    LOGI("  SVE: %s", sve ? "yes" : "no");

    // Fallback chain: i8mm-sve > sve > i8mm > v8_4 > dotprod > fp16 > baseline
    std::string variant;

    if (i8mm && sve) {
        variant = "-i8mm-sve";
    } else if (sve) {
        variant = "-sve";
    } else if (i8mm) {
        variant = "-i8mm";
    } else if (dotprod) {
        // Check if we have armv8.4-a features (dotprod is present in 8.2+)
        // For simplicity, if i8mm is not present but dotprod is, use dotprod variant
        variant = "-dotprod";
    } else if (fp16) {
        variant = "-fp16";
    } else {
        variant = ""; // baseline
    }

    LOGI("Selected library variant: libllama-android%s.so", variant.c_str());

    return variant;
}

} // namespace cpu_features

// JNI entry point for CPU feature detection
extern "C" {

#include <jni.h>

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_00024Companion_detectCPUFeatures(
    JNIEnv* env, jobject /* this */) {

    std::string variant = cpu_features::detect_best_variant();
    return env->NewStringUTF(variant.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_00024Companion_getCPUInfo(
    JNIEnv* env, jobject /* this */) {

    std::string info = cpu_features::get_cpu_info();
    return env->NewStringUTF(info.c_str());
}

} // extern "C"

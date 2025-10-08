#include "llama_jni_utils.h"
#include <cstdarg>
#include <cstdio>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "LlamaJNIUtils"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#include <iostream>
#define LOGI(...) fprintf(stdout, __VA_ARGS__); fprintf(stdout, "\n")
#define LOGE(...) fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n")
#define LOGD(...) fprintf(stdout, __VA_ARGS__); fprintf(stdout, "\n")
#endif

std::string jstring_to_string(JNIEnv* env, jstring jstr) {
    if (!jstr) return "";
    
    const char* cstr = env->GetStringUTFChars(jstr, nullptr);
    std::string result(cstr);
    env->ReleaseStringUTFChars(jstr, cstr);
    return result;
}

jstring string_to_jstring(JNIEnv* env, const std::string& str) {
    return env->NewStringUTF(str.c_str());
}

std::vector<std::string> jstring_array_to_vector(JNIEnv* env, jobjectArray array) {
    std::vector<std::string> result;
    if (!array) return result;
    
    jsize length = env->GetArrayLength(array);
    result.reserve(length);
    
    for (jsize i = 0; i < length; ++i) {
        jstring jstr = static_cast<jstring>(env->GetObjectArrayElement(array, i));
        if (jstr) {
            result.push_back(jstring_to_string(env, jstr));
            env->DeleteLocalRef(jstr);
        }
    }
    
    return result;
}

jobjectArray vector_to_jstring_array(JNIEnv* env, const std::vector<std::string>& vec) {
    jclass string_class = env->FindClass("java/lang/String");
    jobjectArray result = env->NewObjectArray(vec.size(), string_class, nullptr);
    
    for (size_t i = 0; i < vec.size(); ++i) {
        jstring jstr = string_to_jstring(env, vec[i]);
        env->SetObjectArrayElement(result, i, jstr);
        env->DeleteLocalRef(jstr);
    }
    
    return result;
}

jobject create_model_info_object(JNIEnv* env, const std::string& name, 
                                 const std::string& type, long parameter_count,
                                 const std::string& quantization, long file_size,
                                 int context_length, int embedding_size,
                                 int layer_count, int head_count, int vocab_size,
                                 bool is_multilingual, bool is_finetuned) {
    
    jclass model_info_class = env->FindClass("com/runanywhere/sdk/llm/llamacpp/ModelInfo");
    if (!model_info_class) {
        LOGE("Failed to find ModelInfo class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(model_info_class, "<init>", 
        "(Ljava/lang/String;Ljava/lang/String;JLjava/lang/String;JIIIIZZ)V");
    if (!constructor) {
        LOGE("Failed to find ModelInfo constructor");
        return nullptr;
    }
    
    jstring j_name = string_to_jstring(env, name);
    jstring j_type = string_to_jstring(env, type);
    jstring j_quantization = string_to_jstring(env, quantization);
    
    jobject result = env->NewObject(model_info_class, constructor,
        j_name,
        j_type,
        (jlong)parameter_count,
        j_quantization,
        (jlong)file_size,
        (jint)context_length,
        (jint)embedding_size,
        (jint)layer_count,
        (jint)head_count,
        (jint)vocab_size,
        (jboolean)is_multilingual,
        (jboolean)is_finetuned
    );
    
    env->DeleteLocalRef(j_name);
    env->DeleteLocalRef(j_type);
    env->DeleteLocalRef(j_quantization);
    
    return result;
}

jobject create_gpu_info_object(JNIEnv* env, const std::string& device_name,
                               long total_memory, long available_memory,
                               const std::string& compute_capability,
                               bool supports_float16, bool supports_bfloat16) {
    
    jclass gpu_info_class = env->FindClass("com/runanywhere/sdk/llm/llamacpp/GpuInfo");
    if (!gpu_info_class) {
        LOGE("Failed to find GpuInfo class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(gpu_info_class, "<init>", 
        "(Ljava/lang/String;JJLjava/lang/String;ZZ)V");
    if (!constructor) {
        LOGE("Failed to find GpuInfo constructor");
        return nullptr;
    }
    
    jstring j_device_name = string_to_jstring(env, device_name);
    jstring j_compute_capability = string_to_jstring(env, compute_capability);
    
    jobject result = env->NewObject(gpu_info_class, constructor,
        j_device_name,
        (jlong)total_memory,
        (jlong)available_memory,
        j_compute_capability,
        (jboolean)supports_float16,
        (jboolean)supports_bfloat16
    );
    
    env->DeleteLocalRef(j_device_name);
    env->DeleteLocalRef(j_compute_capability);
    
    return result;
}

jobject create_memory_usage_object(JNIEnv* env, long model_memory,
                                  long context_memory, long scratch_memory,
                                  long total_memory, long peak_memory) {
    
    jclass memory_usage_class = env->FindClass("com/runanywhere/sdk/llm/llamacpp/MemoryUsage");
    if (!memory_usage_class) {
        LOGE("Failed to find MemoryUsage class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(memory_usage_class, "<init>", "(JJJJJ)V");
    if (!constructor) {
        LOGE("Failed to find MemoryUsage constructor");
        return nullptr;
    }
    
    return env->NewObject(memory_usage_class, constructor,
        (jlong)model_memory,
        (jlong)context_memory,
        (jlong)scratch_memory,
        (jlong)total_memory,
        (jlong)peak_memory
    );
}

void throw_runtime_exception(JNIEnv* env, const std::string& message) {
    jclass exception_class = env->FindClass("java/lang/RuntimeException");
    if (exception_class) {
        env->ThrowNew(exception_class, message.c_str());
    }
}

void throw_illegal_argument_exception(JNIEnv* env, const std::string& message) {
    jclass exception_class = env->FindClass("java/lang/IllegalArgumentException");
    if (exception_class) {
        env->ThrowNew(exception_class, message.c_str());
    }
}

void log_info(const char* format, ...) {
    va_list args;
    va_start(args, format);
    
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    LOGI("%s", buffer);
    
    va_end(args);
}

void log_error(const char* format, ...) {
    va_list args;
    va_start(args, format);
    
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    LOGE("%s", buffer);
    
    va_end(args);
}

void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    LOGD("%s", buffer);
    
    va_end(args);
}
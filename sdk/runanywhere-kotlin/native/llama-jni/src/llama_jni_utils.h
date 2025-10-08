#ifndef LLAMA_JNI_UTILS_H
#define LLAMA_JNI_UTILS_H

#include <jni.h>
#include <string>
#include <vector>

// Utility functions for JNI operations

/**
 * Convert Java string to C++ string
 */
std::string jstring_to_string(JNIEnv* env, jstring jstr);

/**
 * Convert C++ string to Java string
 */
jstring string_to_jstring(JNIEnv* env, const std::string& str);

/**
 * Convert Java string array to C++ vector
 */
std::vector<std::string> jstring_array_to_vector(JNIEnv* env, jobjectArray array);

/**
 * Convert C++ vector to Java string array
 */
jobjectArray vector_to_jstring_array(JNIEnv* env, const std::vector<std::string>& vec);

/**
 * Create Java object from model info
 */
jobject create_model_info_object(JNIEnv* env, const std::string& name,
                                 const std::string& type, long parameter_count,
                                 const std::string& quantization, long file_size,
                                 int context_length, int embedding_size,
                                 int layer_count, int head_count, int vocab_size,
                                 bool is_multilingual, bool is_finetuned);

/**
 * Create Java object from GPU info
 */
jobject create_gpu_info_object(JNIEnv* env, const std::string& device_name,
                               long total_memory, long available_memory,
                               const std::string& compute_capability,
                               bool supports_float16, bool supports_bfloat16);

/**
 * Create Java object from memory usage
 */
jobject create_memory_usage_object(JNIEnv* env, long model_memory,
                                  long context_memory, long scratch_memory,
                                  long total_memory, long peak_memory);

/**
 * Exception handling utilities
 */
void throw_runtime_exception(JNIEnv* env, const std::string& message);
void throw_illegal_argument_exception(JNIEnv* env, const std::string& message);

/**
 * Logging utilities
 */
void log_info(const char* format, ...);
void log_error(const char* format, ...);
void log_debug(const char* format, ...);

#endif // LLAMA_JNI_UTILS_H

#include <jni.h>
#include <string>
#include <vector>
#include <memory>
#include <android/log.h>
#include "../jni/com_runanywhere_sdk_components_stt_WhisperJNI.h"
#include "../whisper.cpp/whisper.h"

#define LOG_TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

// Helper functions
std::string jstring_to_string(JNIEnv* env, jstring jstr) {
    if (jstr == nullptr) return "";
    const char* chars = env->GetStringUTFChars(jstr, nullptr);
    std::string result(chars);
    env->ReleaseStringUTFChars(jstr, chars);
    return result;
}

jstring string_to_jstring(JNIEnv* env, const std::string& str) {
    return env->NewStringUTF(str.c_str());
}

// JNI implementations
JNIEXPORT jlong JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperInit
  (JNIEnv* env, jclass clazz, jstring model_path) {

    std::string path = jstring_to_string(env, model_path);
    LOGI("Initializing whisper with model: %s", path.c_str());

    struct whisper_context* ctx = whisper_init_from_file(path.c_str());
    if (ctx == nullptr) {
        LOGE("Failed to initialize whisper context from file: %s", path.c_str());
        return 0;
    }

    LOGI("Whisper context initialized successfully");
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT jlong JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperInitFromBuffer
  (JNIEnv* env, jclass clazz, jbyteArray model_data) {

    jsize data_len = env->GetArrayLength(model_data);
    jbyte* data_ptr = env->GetByteArrayElements(model_data, nullptr);

    LOGI("Initializing whisper from buffer (%d bytes)", data_len);

    struct whisper_context* ctx = whisper_init_from_buffer(data_ptr, data_len);

    env->ReleaseByteArrayElements(model_data, data_ptr, JNI_ABORT);

    if (ctx == nullptr) {
        LOGE("Failed to initialize whisper context from buffer");
        return 0;
    }

    LOGI("Whisper context initialized from buffer successfully");
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperFree
  (JNIEnv* env, jclass clazz, jlong context_handle) {

    if (context_handle == 0) return;

    struct whisper_context* ctx = reinterpret_cast<struct whisper_context*>(context_handle);
    whisper_free(ctx);

    LOGI("Whisper context freed");
}

JNIEXPORT jobject JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperGetModelInfo
  (JNIEnv* env, jclass clazz, jlong context_handle) {

    if (context_handle == 0) return nullptr;

    struct whisper_context* ctx = reinterpret_cast<struct whisper_context*>(context_handle);

    // Get model information
    int n_vocab = whisper_n_vocab(ctx);
    int n_audio_ctx = whisper_n_audio_ctx(ctx);
    int n_audio_state = whisper_n_audio_state(ctx);
    int n_audio_head = whisper_n_audio_head(ctx);
    int n_audio_layer = whisper_n_audio_layer(ctx);
    int n_text_ctx = whisper_n_text_ctx(ctx);
    int n_text_state = whisper_n_text_state(ctx);
    int n_text_head = whisper_n_text_head(ctx);
    int n_text_layer = whisper_n_text_layer(ctx);
    int n_mels = whisper_n_mels(ctx);
    bool is_multilingual = whisper_is_multilingual(ctx);

    // Create WhisperModelInfo object
    jclass model_info_class = env->FindClass("com/runanywhere/sdk/components/stt/WhisperModelInfo");
    jmethodID constructor = env->GetMethodID(model_info_class, "<init>",
        "(Ljava/lang/String;Ljava/lang/String;IIIIIIIIIIZ)V");

    return env->NewObject(model_info_class, constructor,
        string_to_jstring(env, "whisper"),  // name
        string_to_jstring(env, "base"),     // type
        n_vocab,         // vocab
        n_mels,          // nMels
        n_audio_ctx,     // nAudioCtx
        n_audio_state,   // nAudioState
        n_audio_head,    // nAudioHead
        n_audio_layer,   // nAudioLayer
        n_text_ctx,      // nTextCtx
        n_text_state,    // nTextState
        n_text_head,     // nTextHead
        n_text_layer,    // nTextLayer
        is_multilingual  // isMultilingual
    );
}

JNIEXPORT jobject JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperTranscribe
  (JNIEnv* env, jclass clazz, jlong context_handle, jfloatArray audio_data,
   jstring language, jboolean enable_timestamps, jboolean enable_translate) {

    if (context_handle == 0) return nullptr;

    struct whisper_context* ctx = reinterpret_cast<struct whisper_context*>(context_handle);

    // Get audio data
    jsize audio_len = env->GetArrayLength(audio_data);
    jfloat* audio_ptr = env->GetFloatArrayElements(audio_data, nullptr);

    // Set up whisper parameters
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    std::string lang = jstring_to_string(env, language);
    if (!lang.empty()) {
        const int lang_id = whisper_lang_id(lang.c_str());
        if (lang_id >= 0) {
            params.language = lang.c_str();
        }
    }

    params.translate = enable_translate;
    params.print_timestamps = enable_timestamps;
    params.no_timestamps = !enable_timestamps;

    LOGD("Starting transcription with %d samples", audio_len);

    // Run transcription
    int result = whisper_full(ctx, params, audio_ptr, audio_len);

    env->ReleaseFloatArrayElements(audio_data, audio_ptr, JNI_ABORT);

    if (result != 0) {
        LOGE("Whisper transcription failed with code: %d", result);
        return nullptr;
    }

    // Get results
    const int n_segments = whisper_full_n_segments(ctx);
    std::string full_text;

    // Create segments array
    jclass segment_class = env->FindClass("com/runanywhere/sdk/components/stt/WhisperSegment");
    jmethodID segment_constructor = env->GetMethodID(segment_class, "<init>",
        "(Ljava/lang/String;DDFLjava/util/List;)V");

    jobjectArray segments_array = env->NewObjectArray(n_segments, segment_class, nullptr);

    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(ctx, i);
        const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
        const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

        double start_time = t0 * 0.01; // Convert to seconds
        double end_time = t1 * 0.01;

        full_text += text;

        // Create empty token list for now
        jclass list_class = env->FindClass("java/util/ArrayList");
        jmethodID list_constructor = env->GetMethodID(list_class, "<init>", "()V");
        jobject token_list = env->NewObject(list_class, list_constructor);

        jobject segment = env->NewObject(segment_class, segment_constructor,
            string_to_jstring(env, text),
            start_time,
            end_time,
            1.0f, // confidence
            token_list
        );

        env->SetObjectArrayElement(segments_array, i, segment);
    }

    // Create result object
    jclass result_class = env->FindClass("com/runanywhere/sdk/components/stt/WhisperResult");
    jmethodID result_constructor = env->GetMethodID(result_class, "<init>",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/Map;J)V");

    // Convert segments array to list
    jclass arrays_class = env->FindClass("java/util/Arrays");
    jmethodID as_list_method = env->GetStaticMethodID(arrays_class, "asList",
        "([Ljava/lang/Object;)Ljava/util/List;");
    jobject segments_list = env->CallStaticObjectMethod(arrays_class, as_list_method, segments_array);

    // Create empty language probs map
    jclass map_class = env->FindClass("java/util/HashMap");
    jmethodID map_constructor = env->GetMethodID(map_class, "<init>", "()V");
    jobject lang_probs_map = env->NewObject(map_class, map_constructor);

    LOGI("Transcription completed: %s", full_text.substr(0, 50).c_str());

    return env->NewObject(result_class, result_constructor,
        string_to_jstring(env, full_text),
        string_to_jstring(env, lang.empty() ? "en" : lang),
        segments_list,
        lang_probs_map,
        0L // processing time
    );
}

// Stub implementations for other methods
JNIEXPORT jobject JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperTranscribeWithParams
  (JNIEnv* env, jclass clazz, jlong context_handle, jfloatArray audio_data, jobject params) {
    // For now, delegate to basic transcribe with default parameters
    return Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperTranscribe(
        env, clazz, context_handle, audio_data, nullptr, JNI_FALSE, JNI_FALSE);
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperGetLanguageCount
  (JNIEnv* env, jclass clazz, jlong context_handle) {
    return whisper_lang_max_id() + 1;
}

JNIEXPORT jobjectArray JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_whisperGetLanguageProbs
  (JNIEnv* env, jclass clazz, jlong context_handle) {
    // Return empty array for now
    jclass prob_class = env->FindClass("com/runanywhere/sdk/components/stt/WhisperLanguageProb");
    return env->NewObjectArray(0, prob_class, nullptr);
}

JNIEXPORT jfloatArray JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_convertPcmToFloat
  (JNIEnv* env, jclass clazz, jbyteArray pcm_data, jint sample_rate, jint target_rate) {

    jsize data_len = env->GetArrayLength(pcm_data);
    jbyte* data_ptr = env->GetByteArrayElements(pcm_data, nullptr);

    // Convert 16-bit PCM to float
    int sample_count = data_len / 2; // 16-bit = 2 bytes per sample
    jfloatArray result = env->NewFloatArray(sample_count);
    jfloat* result_ptr = env->GetFloatArrayElements(result, nullptr);

    const int16_t* samples = reinterpret_cast<const int16_t*>(data_ptr);

    for (int i = 0; i < sample_count; ++i) {
        result_ptr[i] = static_cast<float>(samples[i]) / 32768.0f;
    }

    env->ReleaseByteArrayElements(pcm_data, data_ptr, JNI_ABORT);
    env->ReleaseFloatArrayElements(result, result_ptr, 0);

    return result;
}

JNIEXPORT jstring JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_getVersion
  (JNIEnv* env, jclass clazz) {
    return string_to_jstring(env, "whisper.cpp-v1.5.4");
}

JNIEXPORT jboolean JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_isGpuAvailable
  (JNIEnv* env, jclass clazz) {
    return JNI_FALSE; // GPU acceleration not implemented yet
}

JNIEXPORT jboolean JNICALL Java_com_runanywhere_sdk_components_stt_WhisperJNI_setGpuAcceleration
  (JNIEnv* env, jclass clazz, jboolean enable) {
    return JNI_FALSE; // GPU acceleration not implemented yet
}

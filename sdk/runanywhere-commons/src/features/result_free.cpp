/**
 * @file result_free.cpp
 * @brief Result free function implementations
 *
 * Implements memory management for result structures.
 * These are weak symbols that can be overridden by backend implementations.
 */

#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_types.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_types.h"

// MSVC does not support __attribute__((weak)). On MSVC this whole file is
// excluded from the build via CMakeLists.txt, and each service translation
// unit provides its own strong definition of `rac_*_result_free`. On other
// compilers the weak attribute lets backend-specific .cpp files override
// these fallback definitions at link time.
#ifdef _MSC_VER
#define RAC_WEAK_SYMBOL
#else
#define RAC_WEAK_SYMBOL __attribute__((weak))
#endif

namespace {

void release_owned(char*& ptr) {
    rac_free(ptr);
    ptr = nullptr;
}

void release_owned(const char*& ptr) {
    rac_free(const_cast<char*>(ptr));
    ptr = nullptr;
}

void release_owned(void*& ptr) {
    rac_free(ptr);
    ptr = nullptr;
}

void release_owned(float*& ptr) {
    rac_free(ptr);
    ptr = nullptr;
}

void release_stt_words(rac_stt_word_t*& words, size_t& num_words) {
    if (!words) {
        num_words = 0;
        return;
    }
    for (size_t i = 0; i < num_words; i++) {
        release_owned(words[i].text);
    }
    rac_free(words);
    words = nullptr;
    num_words = 0;
}

void release_embeddings(rac_embedding_vector_t*& embeddings, size_t num_embeddings) {
    if (!embeddings) {
        return;
    }
    for (size_t i = 0; i < num_embeddings; i++) {
        release_owned(embeddings[i].data);
    }
    rac_free(embeddings);
    embeddings = nullptr;
}

}  // namespace

extern "C" {

RAC_WEAK_SYMBOL void rac_llm_result_free(rac_llm_result_t* result) {
    if (result) {
        release_owned(result->text);
    }
}

RAC_WEAK_SYMBOL void rac_stt_result_free(rac_stt_result_t* result) {
    if (result) {
        release_owned(result->text);
        release_owned(result->detected_language);
        release_stt_words(result->words, result->num_words);
    }
}

RAC_WEAK_SYMBOL void rac_tts_result_free(rac_tts_result_t* result) {
    if (result) {
        release_owned(result->audio_data);
        result->audio_size = 0;
    }
}

RAC_WEAK_SYMBOL void rac_embeddings_result_free(rac_embeddings_result_t* result) {
    if (result) {
        release_embeddings(result->embeddings, result->num_embeddings);
        result->num_embeddings = 0;
        result->dimension = 0;
    }
}

}  // extern "C"
